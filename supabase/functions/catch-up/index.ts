// catch-up: the Muse Spark endpoint behind "Catch me up" and "Ask the chat".
//
// POST { chat_id, mode: "catch_up" | "ask", question?, time_zone? }
// Authorization: Bearer <the member's Supabase access token>
//
// 1. Reads the chat AS THE CALLER (their token, so Row Level Security decides
//    what they can see; a non-member gets nothing).
// 2. catch_up: the unread messages since their read cursor, plus a little
//    already-read context. ask: the recent history.
// 3. Sends a ref-tagged transcript to Muse Spark, with the newest photos
//    in it as images, asks for strict JSON, validates it, maps refs back to
//    message ids, and saves it to ai_briefs. A "Maya joined" line (0009) is
//    in the transcript as context, with no ref: never counted or cited.
// A repeat over the same window is served from ai_briefs, and identical
// requests that arrive together share one Muse Spark call (_shared/once.ts).

import { createClient } from "jsr:@supabase/supabase-js@2";
import { buildTranscript, type ChatMessage, isJoin, joinNote } from "../_shared/transcript.ts";
import { ASK_SCHEMA, ASK_SYSTEM, CATCH_UP_SCHEMA, CATCH_UP_SYSTEM, cleanAnswer, cleanCatchUp, parseModelJSON } from "../_shared/brief.ts";
import { museChat, MuseError, MuseNotConfigured } from "../_shared/muse.ts";
import { loadPhotos, photoImages, photoNote, type Photos, withoutPhotos } from "../_shared/photos.ts";
import { once } from "../_shared/once.ts";
import { consentRefusal } from "../_shared/consent.ts"; // Plans: Muse Spark consent
import { takeUsage } from "../_shared/plan.ts"; // Plans: the daily allowance

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const MAX_UNREAD = 600;   // newest unread messages a catch-up covers
const CONTEXT = 25;       // already-read messages shown for context
const ASK_WINDOW = 800;   // recent messages "Ask the chat" searches
const HOURLY_LIMIT = 60;  // briefs per person per hour
// Every column: rows have a kind only once 0009 is applied, and this has to
// work on either side of it. A "Maya joined" line is context, not a message.
const COLUMNS = "*";

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

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "Sign in first" });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "Bad JSON" });
  }
  const chatId = typeof body.chat_id === "string" ? body.chat_id : "";
  const mode = body.mode === "ask" ? "ask" : "catch_up";
  const question = typeof body.question === "string" ? body.question.trim().slice(0, 500) : "";
  const timeZone = validZone(body.time_zone);
  if (!/^[0-9a-f-]{36}$/i.test(chatId)) return json(400, { error: "chat_id required" });
  if (mode === "ask" && !question) return json(400, { error: "Ask a question" });

  // The caller's view of the database: RLS applies to every read below.
  const asUser = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  const { data: userData, error: userErr } = await asUser.auth.getUser();
  if (userErr || !userData.user) return json(401, { error: "Sign in first" });
  const me = userData.user.id;

  // Plans: nothing goes to Muse Spark until you've said yes, once (_shared/consent.ts).
  const noConsent = await consentRefusal(asUser, me);
  if (noConsent) return noConsent;

  const { data: membership } = await asUser
    .from("chat_members").select("last_read_at").eq("chat_id", chatId).eq("user_id", me).maybeSingle();
  if (!membership) return json(403, { error: "You're not in this chat" });

  const { count: recent } = await admin
    .from("ai_briefs").select("id", { count: "exact", head: true })
    .eq("user_id", me).gte("created_at", new Date(Date.now() - 3600_000).toISOString());
  if ((recent ?? 0) >= HOURLY_LIMIT) return json(429, { error: "That's a lot of catching up. Try again in a bit." });

  // Names of everyone in the chat.
  const { data: members } = await asUser
    .from("chat_members").select("user_id, profile:profiles(display_name)").eq("chat_id", chatId);
  const names = new Map<string, string>();
  for (const m of members ?? []) {
    // deno-lint-ignore no-explicit-any
    names.set(m.user_id, (m as any).profile?.display_name ?? "Someone");
  }
  const readerName = names.get(me) ?? "you";
  const lastRead: string = membership.last_read_at;

  let context: ChatMessage[] = [];
  let fresh: ChatMessage[] = [];

  if (mode === "catch_up") {
    const { data: unread, error } = await asUser
      .from("messages").select(COLUMNS)
      .eq("chat_id", chatId).gt("created_at", lastRead)
      .order("created_at", { ascending: false }).limit(MAX_UNREAD);
    if (error) return json(500, { error: "Couldn't load messages" });
    fresh = (unread ?? []).reverse();
    // Only join lines since the cursor: nothing to catch up on.
    if (!fresh.some((m) => !isJoin(m))) {
      return json(200, { kind: "catch_up", empty: true, message_count: 0 });
    }

    const { data: before } = await asUser
      .from("messages").select(COLUMNS)
      .eq("chat_id", chatId).lte("created_at", lastRead)
      .order("created_at", { ascending: false }).limit(CONTEXT);
    context = (before ?? []).reverse();
  } else {
    const { data: history, error } = await asUser
      .from("messages").select(COLUMNS)
      .eq("chat_id", chatId)
      .order("created_at", { ascending: false }).limit(ASK_WINDOW);
    if (error) return json(500, { error: "Couldn't load messages" });
    fresh = (history ?? []).reverse();
    if (!fresh.some((m) => !isJoin(m))) {
      return json(200, { kind: "ask", result: { answer: "There are no messages in this chat yet.", found: false, refs: [] } });
    }
  }

  // What the brief covers and counts: the messages, not the join lines.
  const said = fresh.filter((m) => !isJoin(m));

  // Made before (or being made right now) for this exact window? Use that.
  const since = mode === "catch_up" ? lastRead : said[0].created_at;
  const until = said[said.length - 1].created_at;
  const brief = await once(admin, { user: me, chat: chatId, kind: mode, since, until, question: mode === "ask" ? question : null });
  if ("cached" in brief) return json(200, { kind: mode, cached: true, brief_id: brief.cached.id, ...brief.cached });

  // Plans: today's allowance covers this read, or a 402 (_shared/plan.ts).
  // Saved and shared briefs above cost nothing.
  const usage = await takeUsage(admin, me, fresh.length, mode);
  if (!usage.ok) {
    await brief.claim.release();
    return usage.response;
  }

  // The newest unread photos (newest in the window, for Ask) go along as
  // images, downloaded as the caller (_shared/photos.ts).
  const photos = await loadPhotos(fresh, { url: SUPABASE_URL, apiKey: ANON_KEY, auth });
  const windowHasPhotos = [...context, ...fresh].some((m) => m.image_path);
  const now = new Date();
  const nowLocal = now.toLocaleString("en-US", {
    timeZone, weekday: "long", year: "numeric", month: "long", day: "numeric", hour: "numeric", minute: "2-digit",
    timeZoneName: "longOffset",
  });
  const prompt = (attached: Photos) => {
    const transcript = buildTranscript(context, fresh, names, timeZone, attached.numbers);
    const header = `Reader: ${readerName}\nNow: ${nowLocal} (time zone ${timeZone})\nMembers: ${[...names.values()].join(", ")}\n` +
      photoNote(attached, windowHasPhotos) + joinNote([...context, ...fresh]);
    const user = mode === "ask"
      ? `${header}\nTranscript:\n${transcript.text}\n\nQuestion from ${readerName}: ${question}`
      : `${header}Unread messages: ${said.length}\n\nTranscript:\n${transcript.text}`;
    return { transcript, user, images: photoImages(attached, transcript, fresh, names) };
  };

  const summarize = async (request: ReturnType<typeof prompt>) => {
    let lastError: unknown = null;
    for (let attempt = 0; attempt < 2; attempt++) {
      const reply = await museChat({
        system: mode === "ask" ? ASK_SYSTEM : CATCH_UP_SYSTEM,
        user: attempt === 0 ? request.user : `${request.user}\n\nReturn only the JSON object described, nothing else.`,
        images: request.images,
        json: true,
        schema: mode === "ask" ? ASK_SCHEMA : CATCH_UP_SCHEMA,
        temperature: 0.2,
        maxTokens: 6000, // counts reasoning tokens too
      });
      console.log(JSON.stringify({ mode, attempt, messages: said.length, photos: request.images.length, ...reply.usage }));
      try {
        const parsed = parseModelJSON(reply.text);
        const cleaned = mode === "ask" ? cleanAnswer(parsed, request.transcript.refs) : cleanCatchUp(parsed, request.transcript.refs);
        return { model: reply.model, result: cleaned as unknown };
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? new Error("No result");
  };

  const started = Date.now();
  let model = "";
  let result: unknown;
  try {
    let request = prompt(photos);
    let outcome;
    try {
      outcome = await summarize(request);
    } catch (e) {
      // Meta can refuse a photo (content policy, unreadable): once more without them.
      if (!(e instanceof MuseError) || e.status !== 400 || request.images.length === 0) throw e;
      console.warn(JSON.stringify({ mode, photos_dropped: request.images.length, code: e.code }));
      request = prompt(withoutPhotos(photos));
      outcome = await summarize(request);
    }
    model = outcome.model;
    result = outcome.result;
  } catch (e) {
    console.error("muse error", e);
    await brief.claim.release();
    await usage.giveBack(); // Plans: a failed call costs nothing
    if (e instanceof MuseNotConfigured) return json(503, { error: "Cetchup's AI isn't switched on yet." });
    return json(502, { error: "Muse Spark couldn't summarize that right now. Try again." });
  }
  const latency = Date.now() - started;

  const saved = await brief.claim.save({ message_count: said.length, model, result, latency_ms: latency });

  return json(200, {
    kind: mode,
    cached: false,
    brief_id: saved?.id ?? null,
    created_at: saved?.created_at ?? now.toISOString(),
    result,
    model,
    message_count: said.length,
    since,
    until,
    latency_ms: latency,
  });
});
