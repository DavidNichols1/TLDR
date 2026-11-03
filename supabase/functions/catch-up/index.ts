// catch-up: the Muse Spark endpoint behind "Catch me up" and "Ask the chat".
//
// POST { chat_id, mode: "catch_up" | "ask", question?, time_zone? }
// Authorization: Bearer <the member's Supabase access token>
//
// 1. Reads the chat AS THE CALLER (their token, so Row Level Security decides
//    what they can see; a non-member gets nothing).
// 2. catch_up: the unread messages since their read cursor, plus a little
//    already-read context. ask: the recent history.
// 3. Sends a ref-tagged transcript to Muse Spark, asks for strict JSON,
//    validates it, maps refs back to message ids, and saves it to ai_briefs.
// A repeat catch-up over the same unread window is served from ai_briefs.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { buildTranscript, type ChatMessage } from "../_shared/transcript.ts";
import { ASK_SCHEMA, ASK_SYSTEM, CATCH_UP_SCHEMA, CATCH_UP_SYSTEM, cleanAnswer, cleanCatchUp, parseModelJSON } from "../_shared/brief.ts";
import { museChat, MuseNotConfigured } from "../_shared/muse.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const MAX_UNREAD = 600;   // newest unread messages a catch-up covers
const CONTEXT = 25;       // already-read messages shown for context
const ASK_WINDOW = 800;   // recent messages "Ask the chat" searches
const HOURLY_LIMIT = 60;  // briefs per person per hour

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
      .from("messages").select("id, sender, body, created_at, image_path")
      .eq("chat_id", chatId).gt("created_at", lastRead)
      .order("created_at", { ascending: false }).limit(MAX_UNREAD);
    if (error) return json(500, { error: "Couldn't load messages" });
    fresh = (unread ?? []).reverse();
    if (fresh.length === 0) {
      return json(200, { kind: "catch_up", empty: true, message_count: 0 });
    }
    const until = fresh[fresh.length - 1].created_at;

    // Same unread window as last time? Serve the saved brief.
    const { data: cached } = await admin
      .from("ai_briefs").select("id, result, model, message_count, since, until, latency_ms, created_at")
      .eq("user_id", me).eq("chat_id", chatId).eq("kind", "catch_up")
      .eq("since", lastRead).eq("until", until)
      .order("created_at", { ascending: false }).limit(1).maybeSingle();
    if (cached) return json(200, { kind: "catch_up", cached: true, brief_id: cached.id, ...cached });

    const { data: before } = await asUser
      .from("messages").select("id, sender, body, created_at, image_path")
      .eq("chat_id", chatId).lte("created_at", lastRead)
      .order("created_at", { ascending: false }).limit(CONTEXT);
    context = (before ?? []).reverse();
  } else {
    const { data: history, error } = await asUser
      .from("messages").select("id, sender, body, created_at, image_path")
      .eq("chat_id", chatId)
      .order("created_at", { ascending: false }).limit(ASK_WINDOW);
    if (error) return json(500, { error: "Couldn't load messages" });
    fresh = (history ?? []).reverse();
    if (fresh.length === 0) {
      return json(200, { kind: "ask", result: { answer: "There are no messages in this chat yet.", found: false, refs: [] } });
    }
  }

  const transcript = buildTranscript(context, fresh, names, timeZone);
  const now = new Date();
  const nowLocal = now.toLocaleString("en-US", {
    timeZone, weekday: "long", year: "numeric", month: "long", day: "numeric", hour: "numeric", minute: "2-digit",
    timeZoneName: "longOffset",
  });
  // Photos show as "[photo]" lines; the model sees only their captions.
  const photoNote = [...context, ...fresh].some((m) => m.image_path)
    ? `Photos: "[photo]" marks a photo someone sent. You can't see it; any words after it are its caption.\n`
    : "";
  const header = `Reader: ${readerName}\nNow: ${nowLocal} (time zone ${timeZone})\nMembers: ${[...names.values()].join(", ")}\n${photoNote}`;
  const userPrompt = mode === "ask"
    ? `${header}\nTranscript:\n${transcript.text}\n\nQuestion from ${readerName}: ${question}`
    : `${header}Unread messages: ${fresh.length}\n\nTranscript:\n${transcript.text}`;

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
      });
      model = reply.model;
      console.log(JSON.stringify({ mode, attempt, messages: fresh.length, ...reply.usage }));
      try {
        const parsed = parseModelJSON(reply.text);
        result = mode === "ask" ? cleanAnswer(parsed, transcript.refs) : cleanCatchUp(parsed, transcript.refs);
      } catch (e) {
        lastError = e;
      }
    }
    if (result === undefined) throw lastError ?? new Error("No result");
  } catch (e) {
    console.error("muse error", e);
    if (e instanceof MuseNotConfigured) return json(503, { error: "Ketchup's AI isn't switched on yet." });
    return json(502, { error: "Muse Spark couldn't summarize that right now. Try again." });
  }
  const latency = Date.now() - started;

  const since = mode === "catch_up" ? lastRead : fresh[0].created_at;
  const until = fresh[fresh.length - 1].created_at;
  const { data: saved, error: saveErr } = await admin.from("ai_briefs").insert({
    chat_id: chatId,
    user_id: me,
    kind: mode,
    question: mode === "ask" ? question : null,
    since,
    until,
    message_count: fresh.length,
    model,
    result,
    latency_ms: latency,
  }).select("id, created_at").single();
  if (saveErr) console.error("save error", saveErr);

  return json(200, {
    kind: mode,
    cached: false,
    brief_id: saved?.id ?? null,
    created_at: saved?.created_at ?? now.toISOString(),
    result,
    model,
    message_count: fresh.length,
    since,
    until,
    latency_ms: latency,
  });
});
