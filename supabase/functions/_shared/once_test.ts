// deno test supabase/functions/_shared/
// once.ts against a small in-memory stand-in for the ai_briefs table, with
// a pretend Muse Spark call: identical requests together pay once.

import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { type BriefKey, briefId, once, PENDING } from "./once.ts";

type Row = Record<string, unknown>;

/** Just enough of supabase-js's query builder for once.ts. */
class FakeTable {
  rows = new Map<string, Row>();
  db(): SupabaseClient {
    return { from: () => new Query(this) } as unknown as SupabaseClient;
  }
}

type Result = { data: unknown; error: { code: string } | null };

class Query {
  private op: "select" | "insert" | "update" | "delete" = "select";
  private payload: Row = {};
  private filters: ((r: Row) => boolean)[] = [];
  private returning = false;
  constructor(private table: FakeTable) {}

  select(_columns: string) { this.returning = this.op !== "select"; return this; }
  insert(row: Row) { this.op = "insert"; this.payload = row; return this; }
  update(fields: Row) { this.op = "update"; this.payload = fields; return this; }
  delete() { this.op = "delete"; return this; }
  eq(c: string, v: unknown) { this.filters.push((r) => r[c] === v); return this; }
  neq(c: string, v: unknown) { this.filters.push((r) => r[c] !== v); return this; }
  is(c: string, v: unknown) { this.filters.push((r) => (r[c] ?? null) === v); return this; }
  lt(c: string, v: string) { this.filters.push((r) => String(r[c]) < v); return this; }
  order() { return this; }
  limit() { return this; }
  maybeSingle() { return this.run(true); }
  single() { return this.run(true); }
  /** Awaiting the builder runs it, as supabase-js does. */
  then(ok?: (v: Result) => unknown, no?: (e: unknown) => unknown) {
    return this.run(false).then(ok, no);
  }

  private async run(one: boolean): Promise<Result> {
    await new Promise((r) => setTimeout(r, 5)); // a round trip
    const matches = () => [...this.table.rows.values()].filter((r) => this.filters.every((f) => f(r)));
    switch (this.op) {
      case "insert": {
        const id = (this.payload.id as string) ?? crypto.randomUUID();
        if (this.table.rows.has(id)) return { data: null, error: { code: "23505" } };
        const row = { created_at: new Date().toISOString(), ...this.payload, id };
        this.table.rows.set(id, row);
        return { data: this.returning ? row : null, error: null };
      }
      case "update": {
        const hit = matches();
        for (const r of hit) Object.assign(r, this.payload);
        return { data: one ? hit[0] ?? null : hit, error: null };
      }
      case "delete": {
        for (const r of matches()) this.table.rows.delete(r.id as string);
        return { data: null, error: null };
      }
      default: {
        const hit = matches();
        return { data: one ? hit[0] ?? null : hit, error: null };
      }
    }
  }
}

const key: BriefKey = {
  user: "00000000-0000-0000-0000-0000000000d1",
  chat: "b0000000-0000-4000-8000-00000000b4ec",
  kind: "catch_up",
  since: "2026-10-28T18:00:00+00:00",
  until: "2026-11-03T05:12:00.123456+00:00",
  question: null,
};

/** What catch-up does with once(): the brief's id, and whether it paid for a Muse call. */
async function request(table: FakeTable, muse: { calls: number }, fail = false): Promise<string> {
  const brief = await once(table.db(), key);
  if ("cached" in brief) return brief.cached.id as string;
  muse.calls++;
  await new Promise((r) => setTimeout(r, 300)); // Muse Spark thinking
  if (fail) {
    await brief.claim.release();
    throw new Error("Muse Spark failed");
  }
  const saved = await brief.claim.save({ message_count: 302, model: "muse-spark-1.3", result: { tldr: "ok" }, latency_ms: 300 });
  return saved!.id;
}

Deno.test("two identical requests together pay Muse Spark once", async () => {
  const table = new FakeTable();
  const muse = { calls: 0 };
  const [a, b] = await Promise.all([request(table, muse), request(table, muse)]);
  assertEquals(muse.calls, 1);
  assertEquals(a, b);
  assertEquals(a, await briefId(key));
  const row = table.rows.get(a)!;
  assertEquals(row.model, "muse-spark-1.3");
  assertEquals(table.rows.size, 1);
});

Deno.test("a later identical request is served the saved brief", async () => {
  const table = new FakeTable();
  const muse = { calls: 0 };
  const first = await request(table, muse);
  const again = await request(table, muse);
  assertEquals(muse.calls, 1);
  assertEquals(first, again);
});

Deno.test("a failed call is released, and the request waiting on it makes the brief", async () => {
  const table = new FakeTable();
  const muse = { calls: 0 };
  const [a, b] = await Promise.allSettled([request(table, muse, true), request(table, muse)]);
  assertEquals(a.status, "rejected");
  assertEquals(b.status, "fulfilled");
  assertEquals(muse.calls, 2);
  assertEquals((b as PromiseFulfilledResult<string>).value, await briefId(key));
  assertEquals([...table.rows.values()].filter((r) => r.model === PENDING).length, 0);
});

Deno.test("a stale claim from a request that died is taken over", async () => {
  const table = new FakeTable();
  const id = await briefId(key);
  table.rows.set(id, {
    id, user_id: key.user, chat_id: key.chat, kind: key.kind, question: null, since: key.since, until: key.until,
    model: PENDING, result: {}, message_count: 0, created_at: new Date(Date.now() - 180_000).toISOString(),
  });
  const muse = { calls: 0 };
  assertEquals(await request(table, muse), id);
  assertEquals(muse.calls, 1);
  assertEquals(table.rows.get(id)!.model, "muse-spark-1.3");
});

Deno.test("the claim's id follows the key", async () => {
  const id = await briefId(key);
  assertEquals(id, await briefId({ ...key }));
  assert(/^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(id));
  assertNotEquals(id, await briefId({ ...key, until: "2026-11-03T05:13:00+00:00" }));
  assertNotEquals(await briefId({ ...key, kind: "ask", question: "when do we leave?" }),
    await briefId({ ...key, kind: "ask", question: "who owes me?" }));
});
