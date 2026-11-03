// One Muse Spark call per brief. Identical requests that arrive together
// (a double tap, the app's prefetch racing a tap, two of your devices)
// would each pay for the same catch-up; here the first claims it and the
// others wait for its result.
//
// The claim is a pending ai_briefs row whose id is derived from what the
// brief covers (user, chat, kind, the unread window, the question), so the
// primary key lets only one insert win: no lock and no new table. The
// winner fills that row in when Muse Spark answers, or deletes it if the
// call fails so the next request can try; the others poll it and send it
// back as a saved brief. A claim left by a request that died goes stale
// after two minutes. Ask gets the same treatment: the same question over
// the same messages is answered once.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export interface BriefKey {
  user: string;
  chat: string;
  kind: "catch_up" | "ask";
  /** catch_up: the reader's cursor; ask: the oldest message searched. */
  since: string;
  /** The newest message covered. */
  until: string;
  question: string | null;
}

/** The columns a saved brief goes back with (the app's BriefResponse). */
export const BRIEF_COLUMNS = "id, result, model, message_count, since, until, latency_ms, created_at";

export const PENDING = "pending";
const POLL_MS = 800;
const WAIT_MS = 100_000;
const STALE_MS = 120_000;

export interface Saved {
  id: string;
  created_at: string;
}

/** This request makes the brief: save() fills the claim in, release() gives it up. */
export class Claim {
  constructor(
    private readonly db: SupabaseClient,
    /** null: no claim (the database refused it, or waiting ran out), so save() inserts. */
    readonly id: string | null,
    private readonly key: BriefKey,
  ) {}

  async save(fields: { message_count: number; model: string; result: unknown; latency_ms: number }): Promise<Saved | null> {
    if (this.id) {
      const { data } = await this.db.from("ai_briefs").update(fields)
        .eq("id", this.id).eq("model", PENDING).select("id, created_at").maybeSingle();
      if (data) return data as Saved;
    }
    // Unclaimed, or the claim went stale and was cleared: keep it anyway.
    const { data, error } = await this.db.from("ai_briefs").insert({ ...columns(this.key), ...fields })
      .select("id, created_at").single();
    if (error) console.error("save error", error);
    return (data as Saved) ?? null;
  }

  async release(): Promise<void> {
    if (!this.id) return;
    await this.db.from("ai_briefs").delete().eq("id", this.id).eq("model", PENDING);
  }
}

export type Once = { cached: Record<string, unknown> } | { claim: Claim };

/** The finished brief for `key` if there is one, else this request's claim
 * on making it, after waiting out a request that's already making it. */
export async function once(db: SupabaseClient, key: BriefKey): Promise<Once> {
  const id = await briefId(key);
  const deadline = Date.now() + WAIT_MS;
  for (;;) {
    const done = await finished(db, key);
    if (done) return { cached: done };
    const { error } = await db.from("ai_briefs")
      .insert({ id, ...columns(key), model: PENDING, result: {}, message_count: 0 });
    if (!error) return { claim: new Claim(db, id, key) };
    if (error.code !== "23505") {
      // Not a duplicate: the database is having trouble. Make it anyway.
      console.error("claim error", error);
      return { claim: new Claim(db, null, key) };
    }
    const waited = await waitFor(db, id, deadline);
    if (waited === "timeout") {
      console.warn(JSON.stringify({ claim: "timed out", kind: key.kind }));
      return { claim: new Claim(db, null, key) };
    }
    // "done": the next finished() finds it. "gone": released or stale, so claim it.
  }
}

/** A finished brief over exactly this window (and question). */
async function finished(db: SupabaseClient, key: BriefKey): Promise<Record<string, unknown> | null> {
  const query = db.from("ai_briefs").select(BRIEF_COLUMNS)
    .eq("user_id", key.user).eq("chat_id", key.chat).eq("kind", key.kind)
    .eq("since", key.since).eq("until", key.until).neq("model", PENDING);
  const { data } = await (key.question === null ? query.is("question", null) : query.eq("question", key.question))
    .order("created_at", { ascending: false }).limit(1).maybeSingle();
  return (data as Record<string, unknown>) ?? null;
}

/** Polls someone else's claim until it's finished, given up, or stale. */
async function waitFor(db: SupabaseClient, id: string, deadline: number): Promise<"done" | "gone" | "timeout"> {
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, POLL_MS));
    const { data } = await db.from("ai_briefs").select("model, created_at").eq("id", id).maybeSingle();
    if (!data) return "gone";
    if (data.model !== PENDING) return "done";
    if (Date.now() - Date.parse(data.created_at as string) > STALE_MS) {
      await db.from("ai_briefs").delete().eq("id", id).eq("model", PENDING)
        .lt("created_at", new Date(Date.now() - STALE_MS).toISOString());
      return "gone";
    }
  }
  return "timeout";
}

function columns(key: BriefKey) {
  return {
    user_id: key.user,
    chat_id: key.chat,
    kind: key.kind,
    question: key.question,
    since: key.since,
    until: key.until,
  };
}

/** A UUID from a hash of the key, so identical requests name the same row. */
export async function briefId(key: BriefKey): Promise<string> {
  const text = [key.user, key.chat, key.kind, key.since, key.until, key.question ?? ""].join("\n");
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  hash[6] = (hash[6] & 0x0f) | 0x80; // version 8: made by us
  hash[8] = (hash[8] & 0x3f) | 0x80; // the usual variant
  const hex = [...hash.subarray(0, 16)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
