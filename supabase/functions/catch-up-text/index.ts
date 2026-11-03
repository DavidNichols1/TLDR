// catch-up-text: "Catch me up" and "Ask" for a conversation the app read off a
// page instead of out of Ketchup's database. Experimental and not released: an
// Instagram DM thread or a Snapchat chat the reader has open in their own
// signed-in session inside the app (ios/Ketchup/WebChat/).
//
// POST { mode: "catch_up" | "ask", question?, source: "instagram" | "snapchat", thread_title,
//        reader_name, time_zone, messages: [{ sender, text, at? }] }   (oldest first)
// Authorization: Bearer <a signed-in Ketchup user's access token>
//
// Same pipeline as catch-up: the ref-tagged transcript, the same system prompts
// and JSON schemas, the same validation. Refs come back as indexes into
// `messages`, since there is no database row to point at.
//
// Stores nothing from the conversation: no ai_briefs row, and the logs get
// counts and token usage only, never message text, names or model output.
// The one write is a usage row with no content, for the hourly cap
// (migrations 0004 and 0005).

import { createClient } from "jsr:@supabase/supabase-js@2";
import { buildTextTranscript, type TextMessage } from "../_shared/transcript.ts";
import { ASK_SCHEMA, ASK_SYSTEM, CATCH_UP_SCHEMA, CATCH_UP_SYSTEM, cleanAnswer, cleanCatchUp, parseModelJSON } from "../_shared/brief.ts";
import { museChat, MuseError, MuseNotConfigured } from "../_shared/muse.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// What each source's thread is, for the prompt. A new source also needs the
// text_brief_usage source check (a migration).
const SOURCES = new Map([
  ["instagram", "an Instagram DM thread"],
  ["snapchat", "a Snapchat chat"],
]);
const MAX_MESSAGES = 600;   // newest messages a request covers
const MAX_TEXT = 4000;      // characters kept per message (the transcript sends 600)
const MAX_BYTES = 1_000_000;
const HOURLY_LIMIT = 20;    // text catch-ups per person per hour

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function validZone(tz: unknown): string {
  if (typeof tz !== "string") return "America/Denver";
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return tz;
  } catch {
    return "America/Denver";
  }
}

/** Page text for a header line or a name: one line, no control characters. */
function oneLine(v: unknown, max: number): string {
  if (typeof v !== "string") return "";
  return v.replace(/[\u0000-\u001f\u007f\u2028\u2029]+/g, " ").replace(/\s+/g, " ").trim().slice(0, max);
}

/** Message text keeps its line breaks (the transcript flattens them). */
function messageText(v: unknown): string {
  if (typeof v !== "string") return "";
  return v.replace(/\r\n?/g, "\n").replace(/[\u0000-\u0009\u000b-\u001f\u007f]+/g, " ").trim().slice(0, MAX_TEXT);
}

/** A real, plausible time, as ISO 8601; anything else becomes null. */
function timeOrNull(v: unknown): string | null {
  if (typeof v !== "string" || v.length > 40) return null;
  const t = Date.parse(v);
  if (Number.isNaN(t) || t > Date.now() + 36 * 3600_000 || t < Date.UTC(2010, 0, 1)) return null;
  return new Date(t).toISOString();
}

// The app's reader reports how its read went (steps, loads, why it stopped).
// Only these keys, as numbers, booleans or fixed words, ever reach the log.
const READER_NUMBERS = ["scrolls", "steps", "gaps", "placeholders", "rows", "units", "found", "skipped", "empty", "dupes", "ms"];
const READER_WORDS: Record<string, string[]> = {
  root: ["aria-label", "grid", "scroller", "main"],
  stop: ["enough", "budget", "steps", "loads", "start", "no-scroller"],
};

function readerStats(v: unknown): Record<string, number | boolean | string> | undefined {
  if (!v || typeof v !== "object" || Array.isArray(v)) return undefined;
  const raw = v as Record<string, unknown>;
  const out: Record<string, number | boolean | string> = {};
  for (const key of READER_NUMBERS) {
    const n = raw[key];
    if (typeof n === "number" && Number.isFinite(n)) out[key] = Math.max(0, Math.min(10_000_000, Math.round(n)));
  }
  for (const [key, allowed] of Object.entries(READER_WORDS)) {
    const w = raw[key];
    if (typeof w === "string" && allowed.includes(w)) out[key] = w;
  }
  if (typeof raw.reachedStart === "boolean") out.reachedStart = raw.reachedStart;
  return Object.keys(out).length ? out : undefined;
}

/** A log-safe label for a failure. Never the message: a JSON parse error
 *  quotes the model's output, and an API error can echo the request. */
function failureKind(e: unknown): string {
  if (e instanceof MuseNotConfigured) return "not_configured";
  if (e instanceof MuseError) return `muse_${e.status}${e.code ? `_${e.code}` : ""}`;
  return e instanceof Error ? e.name : "unknown";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "Sign in first" });

  if (Number(req.headers.get("Content-Length") ?? 0) > MAX_BYTES) return json(413, { error: "That chat is too long to send" });
  let body: Record<string, unknown>;
  try {
    const raw = await req.text();
    if (raw.length > MAX_BYTES) return json(413, { error: "That chat is too long to send" });
    body = JSON.parse(raw);
    if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error("not an object");
  } catch {
    return json(400, { error: "Bad JSON" });
  }

  const mode = body.mode === "ask" ? "ask" : "catch_up";
  const question = typeof body.question === "string" ? body.question.trim().slice(0, 500) : "";
  const source = typeof body.source === "string" ? body.source : "";
  const timeZone = validZone(body.time_zone);
  const readerName = oneLine(body.reader_name, 40) || "you";
  const title = oneLine(body.thread_title, 80);
  const reader = readerStats(body.reader);
  if (!SOURCES.has(source)) return json(400, { error: "Unknown source" });
  if (mode === "ask" && !question) return json(400, { error: "Ask a question" });
  if (!Array.isArray(body.messages)) return json(400, { error: "messages required" });

  // The newest MAX_MESSAGES; refs still point at indexes in the full list.
  const all = body.messages as unknown[];
  const first = Math.max(0, all.length - MAX_MESSAGES);
  const messages: TextMessage[] = [];
  for (const m of all.slice(first)) {
    if (!m || typeof m !== "object" || Array.isArray(m)) return json(400, { error: "Each message needs a sender and text" });
    const row = m as Record<string, unknown>;
    messages.push({
      sender: oneLine(row.sender, 60) || "Someone",
      // Kept even when empty, so every index still lines up with the app's list.
      text: messageText(row.text) || "[empty]",
      at: timeOrNull(row.at),
    });
  }

  const asUser = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userErr } = await asUser.auth.getUser();
  if (userErr || !userData.user) return json(401, { error: "Sign in first" });
  const me = userData.user.id;

  if (messages.length === 0) {
    return mode === "ask"
      ? json(200, { kind: "ask", source, result: { answer: "There are no messages in this chat yet.", found: false, refs: [] } })
      : json(200, { kind: "catch_up", source, empty: true, message_count: 0 });
  }

  // Checks the cap and records this use in one step (no content is stored).
  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const { data: allowed, error: quotaErr } = await admin.rpc("take_text_brief", {
    p_user: me, p_source: source, p_mode: mode, p_messages: messages.length, p_limit: HOURLY_LIMIT,
  });
  if (quotaErr) {
    console.error(JSON.stringify({ fn: "catch-up-text", quota_error: quotaErr.code ?? "unknown" }));
    return json(500, { error: "Couldn't check your catch-up limit. Try again." });
  }
  if (allowed !== true) return json(429, { error: "That's a lot of catching up. Try again in a bit." });

  const transcript = buildTextTranscript(messages, timeZone, first);
  const now = new Date();
  const nowLocal = now.toLocaleString("en-US", {
    timeZone, weekday: "long", year: "numeric", month: "long", day: "numeric", hour: "numeric", minute: "2-digit",
    timeZoneName: "longOffset",
  });
  const senders = [...new Set(messages.map((m) => m.sender))].filter((s) => s !== readerName);
  const header = `Reader: ${readerName}\nNow: ${nowLocal} (time zone ${timeZone})\n` +
    `Chat: ${title ? `"${title}", ` : ""}${SOURCES.get(source)} the reader has open\n` +
    `Members: ${[readerName, ...senders].join(", ")}\n` +
    (messages.some((m) => m.at) ? "Times are approximate: the page only shows one at breaks in the conversation.\n" : "");
  const userPrompt = mode === "ask"
    ? `${header}\nTranscript:\n${transcript.text}\n\nQuestion from ${readerName}: ${question}`
    : `${header}Messages: ${messages.length}\n\nTranscript:\n${transcript.text}`;

  const started = Date.now();
  let model = "";
  let result: unknown;
  try {
    let lastError: unknown = null;
    for (let attempt = 0; attempt < 2 && result === undefined; attempt++) {
      const reply = await museChat({
        system: mode === "ask" ? ASK_SYSTEM : CATCH_UP_SYSTEM,
        user: attempt === 0 ? userPrompt : `${userPrompt}\n\nReturn only the JSON object described, nothing else.`,
        json: true,
        schema: mode === "ask" ? ASK_SCHEMA : CATCH_UP_SCHEMA,
        temperature: 0.2,
        maxTokens: 6000, // counts reasoning tokens too
        quiet: true,
      });
      model = reply.model;
      // Counts only: never the messages, the names or what the model wrote.
      console.log(JSON.stringify({ fn: "catch-up-text", source, mode, attempt, messages: messages.length, ...reply.usage, reader }));
      try {
        const parsed = parseModelJSON(reply.text);
        result = mode === "ask" ? cleanAnswer(parsed, transcript.refs) : cleanCatchUp(parsed, transcript.refs);
      } catch (e) {
        lastError = e;
      }
    }
    if (result === undefined) throw lastError ?? new Error("No result");
  } catch (e) {
    console.error(JSON.stringify({ fn: "catch-up-text", source, mode, failed: failureKind(e) }));
    if (e instanceof MuseNotConfigured) return json(503, { error: "Ketchup's AI isn't switched on yet." });
    return json(502, { error: "Muse Spark couldn't summarize that right now. Try again." });
  }

  return json(200, {
    kind: mode,
    source,
    cached: false,
    result,
    model,
    message_count: messages.length,
    truncated: first > 0,
    latency_ms: Date.now() - started,
  });
});
