// Turns chat rows into the transcript Muse Spark reads, and maps the model's
// short message references ("m12") back to real message ids so the app can
// jump to the exact message behind every bullet.

export interface ChatMessage {
  id: string;
  sender: string;
  body: string;
  created_at: string;
}

export interface Transcript {
  text: string;
  /** "m12" → message uuid */
  refs: Map<string, string>;
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
  const line = (m: ChatMessage) => {
    n += 1;
    const ref = `m${n}`;
    refs.set(ref, m.id);
    const who = names.get(m.sender) ?? "Someone";
    const body = m.body.length > MAX_BODY ? m.body.slice(0, MAX_BODY) + "…" : m.body;
    // Keep each message on one line so a message can't pose as another.
    lines.push(`[${ref}] ${localStamp(m.created_at, timeZone)} · ${who}: ${body.replace(/\s*\n\s*/g, " / ")}`);
  };
  if (context.length) {
    lines.push("=== ALREADY READ (context only, do not summarize) ===");
    context.forEach(line);
  }
  if (fresh.length) {
    lines.push(context.length ? "=== UNREAD (summarize these) ===" : "=== MESSAGES ===");
    fresh.forEach(line);
  }
  return { text: lines.join("\n"), refs, count: context.length + fresh.length };
}

/** Keeps only refs the transcript really had, mapped to message ids. */
export function resolveRefs(raw: unknown, refs: Map<string, string>, max = 6): string[] {
  if (!Array.isArray(raw)) return [];
  const out: string[] = [];
  for (const r of raw) {
    const key = typeof r === "string" ? r.trim().replace(/^\[|\]$/g, "") : "";
    const id = refs.get(key);
    if (id && !out.includes(id)) out.push(id);
    if (out.length >= max) break;
  }
  return out;
}
