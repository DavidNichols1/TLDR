// Turns chat rows into the transcript Muse Spark reads, and maps the model's
// short message references ("m12") back to real message ids so the app can
// jump to the exact message behind every bullet.
//
// The same transcript is built for a conversation the app read off a page
// (catch-up-text): there the refs map back to each message's index in the
// request instead of a database id.

export interface ChatMessage {
  id: string;
  sender: string;
  body: string;
  created_at: string;
}

/** A message the app read off a page, not out of Ketchup's database. */
export interface TextMessage {
  sender: string;
  text: string;
  /** ISO 8601, when the page showed a time for it. */
  at: string | null;
}

export interface Transcript<Ref = string> {
  text: string;
  /** "m12" → message uuid (text transcripts: the message's index) */
  refs: Map<string, Ref>;
  /** messages included, in order */
  count: number;
}

const MAX_BODY = 600; // characters per message sent to the model

/** Local, human wall-clock time ("Mon Nov 2, 7:41 PM") in the reader's zone. */
export function localStamp(iso: string, timeZone: string): string {
  return new Date(iso).toLocaleString("en-US", {
    timeZone,
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

/** One message: "[m12] Mon Nov 2, 7:41 PM · Maya: …". Kept on one line so a
 *  message can't pose as another. With no time it is "[m12] Maya: …". */
function line(ref: string, stamp: string | null, who: string, body: string): string {
  const clipped = body.length > MAX_BODY ? body.slice(0, MAX_BODY) + "…" : body;
  return `[${ref}] ${stamp === null ? "" : `${stamp} · `}${who}: ${clipped.replace(/\s*\n\s*/g, " / ")}`;
}

/**
 * context: messages the reader has already seen (shown so the model knows
 * what "that" refers to, but never summarized); fresh: the unread ones.
 */
export function buildTranscript(
  context: ChatMessage[],
  fresh: ChatMessage[],
  names: Map<string, string>,
  timeZone: string,
): Transcript {
  const refs = new Map<string, string>();
  const lines: string[] = [];
  let n = 0;
  const add = (m: ChatMessage) => {
    n += 1;
    const ref = `m${n}`;
    refs.set(ref, m.id);
    lines.push(line(ref, localStamp(m.created_at, timeZone), names.get(m.sender) ?? "Someone", m.body));
  };
  if (context.length) {
    lines.push("=== ALREADY READ (context only, do not summarize) ===");
    context.forEach(add);
  }
  if (fresh.length) {
    lines.push(context.length ? "=== UNREAD (summarize these) ===" : "=== MESSAGES ===");
    fresh.forEach(add);
  }
  return { text: lines.join("\n"), refs, count: context.length + fresh.length };
}

/**
 * The same transcript for messages read off a page. There is no read cursor
 * there, so every message is in one MESSAGES block. Refs map to
 * `firstIndex + position`, the message's index in the app's request.
 */
export function buildTextTranscript(messages: TextMessage[], timeZone: string, firstIndex = 0): Transcript<number> {
  const refs = new Map<string, number>();
  const lines: string[] = [];
  if (messages.length) lines.push("=== MESSAGES ===");
  messages.forEach((m, i) => {
    const ref = `m${i + 1}`;
    refs.set(ref, firstIndex + i);
    lines.push(line(ref, m.at === null ? null : localStamp(m.at, timeZone), m.sender, m.text));
  });
  return { text: lines.join("\n"), refs, count: messages.length };
}

/** Keeps only refs the transcript really had, mapped to message ids (or indexes). */
export function resolveRefs<Ref>(raw: unknown, refs: Map<string, Ref>, max = 6): Ref[] {
  if (!Array.isArray(raw)) return [];
  const out: Ref[] = [];
  for (const r of raw) {
    const key = typeof r === "string" ? r.trim().replace(/^\[|\]$/g, "") : "";
    const id = refs.get(key);
    // Not a truthiness check: index 0 is a real ref.
    if (id !== undefined && !out.includes(id)) out.push(id);
    if (out.length >= max) break;
  }
  return out;
}
