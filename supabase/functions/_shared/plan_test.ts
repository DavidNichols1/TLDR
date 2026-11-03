// deno test supabase/functions/_shared/
// plan.ts: what a call is charged, the sentences a refusal shows, the 402
// the apps get, and that only real Muse Spark calls are charged (saved and
// shared briefs from once.ts cost nothing, a failed call gives it back).
// The SQL side (the lock, the limits, the day) is in supabase/tests/rls_check.sql.

import { assert, assertEquals, assertFalse, assertMatch } from "jsr:@std/assert@1";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { CALL_FLOOR, charge, limitMessage, takeUsage, type Taken } from "./plan.ts";
import { type BriefKey, once } from "./once.ts";

type Call = { fn: string; args: Record<string, unknown> };

/** take_plan_usage and give_back_plan_usage over an in-memory day. */
class FakePlanDB {
  calls: Call[] = [];
  used = 0;
  failWith: string | null = null;
  constructor(public plan: Taken["plan"] = "free", public limit = 150) {}

  db(): SupabaseClient {
    return {
      rpc: async (fn: string, args: Record<string, unknown>) => {
        await new Promise((r) => setTimeout(r, 2));
        this.calls.push({ fn, args });
        if (this.failWith) return { data: null, error: { code: this.failWith } };
        const day = "2026-11-03";
        const resets_at = "2026-11-04T06:00:00+00:00";
        if (fn === "take_plan_usage") {
          const want = args.p_messages as number;
          if (this.used + want > this.limit) {
            return { data: { allowed: false, plan: this.plan, used: this.used, limit: this.limit, day, resets_at }, error: null };
          }
          this.used += want;
          return { data: { allowed: true, plan: this.plan, used: this.used, limit: this.limit, day, resets_at }, error: null };
        }
        if (fn === "give_back_plan_usage") {
          this.used = Math.max(0, this.used - (args.p_messages as number));
          return { data: null, error: null };
        }
        return { data: null, error: { code: "PGRST202" } };
      },
    } as unknown as SupabaseClient;
  }
}

const env = (values: Record<string, string> = {}) => ({ get: (key: string) => values[key] });

Deno.test("a call is charged its messages, and at least the floor", () => {
  assertEquals(CALL_FLOOR, 10);
  assertEquals(charge(302), 302);
  assertEquals(charge(10), 10);
  assertEquals(charge(3), 10);
  assertEquals(charge(0), 10);
  assertEquals(charge(Number.NaN), 10);
});

Deno.test("refusals say what happened, in plain words", () => {
  assertEquals(limitMessage({ plan: "free", used: 150, limit: 150 }, 40, "catch_up"),
    "You've used today's 150 free messages.");
  assertEquals(limitMessage({ plan: "plus", used: 400, limit: 400 }, 40, "ask"),
    "You've used today's 400 Plus messages.");
  assertEquals(limitMessage({ plan: "pro", used: 995, limit: 1000 }, 302, "catch_up"),
    "This catch-up reads 302 messages. Pro covers 1,000 a day, and you have 5 left today.");
  assertEquals(limitMessage({ plan: "free", used: 0, limit: 150 }, 302, "catch_up"),
    "This catch-up reads 302 messages. Free covers 150 a day, and you have 150 left today.");
  assertEquals(limitMessage({ plan: "free", used: 112, limit: 150 }, 302, "ask"),
    "This question searches 302 messages. Free covers 150 a day, and you have 38 left today.");
  assertEquals(limitMessage({ plan: "free", used: 146, limit: 150 }, 3, "ask"),
    "Each catch-up or question counts as at least 10 messages, and you have 4 left today.");
  for (const plan of ["free", "plus", "pro"] as const) {
    for (const used of [0, 140, 150, 1000]) {
      const text = limitMessage({ plan, used, limit: 150 }, 302, "catch_up");
      assertFalse(/[–—]/.test(text), text);
    }
  }
});

Deno.test("within the allowance: spent, and a failed call gives it back once", async () => {
  const fake = new FakePlanDB();
  const usage = await takeUsage(fake.db(), "u1", 112, "catch_up", env());
  assert(usage.ok);
  assertEquals(usage.plan, "free");
  assertEquals(usage.charged, 112);
  assertEquals(fake.used, 112);
  await usage.giveBack();
  await usage.giveBack();
  assertEquals(fake.used, 0);
  assertEquals(fake.calls.map((c) => c.fn), ["take_plan_usage", "give_back_plan_usage"]);
  assertEquals(fake.calls[1].args, { p_user: "u1", p_day: "2026-11-03", p_messages: 112 });
});

Deno.test("over the allowance: a 402 the apps can show and the paywall can read", async () => {
  const fake = new FakePlanDB();
  fake.used = 112;
  const usage = await takeUsage(fake.db(), "u1", 302, "catch_up", env());
  assertFalse(usage.ok);
  if (usage.ok) return;
  assertEquals(usage.response.status, 402);
  const body = await usage.response.json();
  assertEquals(body, {
    error: "This catch-up reads 302 messages. Free covers 150 a day, and you have 38 left today.",
    kind: "plan_limit",
    plan: "free",
    used: 112,
    limit: 150,
    needed: 302,
    resets_at: "2026-11-04T06:00:00+00:00",
  });
  assertEquals(fake.used, 112);
});

Deno.test("the database not answering is a 500, never a free pass", async () => {
  const fake = new FakePlanDB();
  fake.failWith = "PGRST202";
  const usage = await takeUsage(fake.db(), "u1", 20, "ask", env());
  assertFalse(usage.ok);
  if (usage.ok) return;
  assertEquals(usage.response.status, 500);
  assertMatch((await usage.response.json()).error, /allowance/);
});

Deno.test("PLANS_ENFORCED=false switches the allowance off", async () => {
  const fake = new FakePlanDB();
  fake.used = 150;
  const usage = await takeUsage(fake.db(), "u1", 302, "catch_up", env({ PLANS_ENFORCED: "false" }));
  assert(usage.ok);
  assertEquals(fake.calls.length, 0);
});

// --- Only real Muse Spark calls are charged --------------------------------

type Row = Record<string, unknown>;

/** Just enough of an ai_briefs table for once.ts (as in once_test.ts). */
class FakeBriefs {
  rows = new Map<string, Row>();
  db(): SupabaseClient {
    return { from: () => new BriefQuery(this) } as unknown as SupabaseClient;
  }
}

class BriefQuery {
  private op: "select" | "insert" | "update" | "delete" = "select";
  private payload: Row = {};
  private filters: ((r: Row) => boolean)[] = [];
  constructor(private table: FakeBriefs) {}
  select(_columns: string) { return this; }
  insert(row: Row) { this.op = "insert"; this.payload = row; return this; }
  update(fields: Row) { this.op = "update"; this.payload = fields; return this; }
  delete() { this.op = "delete"; return this; }
  eq(c: string, v: unknown) { this.filters.push((r) => r[c] === v); return this; }
  neq(c: string, v: unknown) { this.filters.push((r) => r[c] !== v); return this; }
  is(c: string, v: unknown) { this.filters.push((r) => (r[c] ?? null) === v); return this; }
  lt(c: string, v: string) { this.filters.push((r) => String(r[c]) < v); return this; }
  order() { return this; }
  limit() { return this; }
  maybeSingle() { return this.run(); }
  single() { return this.run(); }
  then(ok?: (v: unknown) => unknown, no?: (e: unknown) => unknown) { return this.run().then(ok, no); }
  private async run(): Promise<{ data: unknown; error: { code: string } | null }> {
    await new Promise((r) => setTimeout(r, 5));
    const hit = [...this.table.rows.values()].filter((r) => this.filters.every((f) => f(r)));
    switch (this.op) {
      case "insert": {
        const id = (this.payload.id as string) ?? crypto.randomUUID();
        if (this.table.rows.has(id)) return { data: null, error: { code: "23505" } };
        const row = { created_at: new Date().toISOString(), ...this.payload, id };
        this.table.rows.set(id, row);
        return { data: row, error: null };
      }
      case "update":
        for (const r of hit) Object.assign(r, this.payload);
        return { data: hit[0] ?? null, error: null };
      case "delete":
        for (const r of hit) this.table.rows.delete(r.id as string);
        return { data: null, error: null };
      default:
        return { data: hit[0] ?? null, error: null };
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

/** catch-up's order: a saved or shared brief first, then the allowance, then Muse Spark. */
async function catchUp(briefs: FakeBriefs, plans: FakePlanDB, muse: { calls: number }, fail = false): Promise<number> {
  const brief = await once(briefs.db(), key);
  if ("cached" in brief) return 200;
  const usage = await takeUsage(plans.db(), key.user, 302, "catch_up", env());
  if (!usage.ok) {
    await brief.claim.release();
    return usage.response.status;
  }
  muse.calls++;
  await new Promise((r) => setTimeout(r, 200));
  if (fail) {
    await brief.claim.release();
    await usage.giveBack();
    return 502;
  }
  await brief.claim.save({ message_count: 302, model: "muse-spark-1.3", result: { tldr: "ok" }, latency_ms: 200 });
  return 200;
}

Deno.test("two identical catch-ups at once are charged once, and the saved one is free", async () => {
  const briefs = new FakeBriefs();
  const plans = new FakePlanDB("plus", 400);
  const muse = { calls: 0 };
  assertEquals(await Promise.all([catchUp(briefs, plans, muse), catchUp(briefs, plans, muse)]), [200, 200]);
  assertEquals(await catchUp(briefs, plans, muse), 200);
  assertEquals(muse.calls, 1);
  assertEquals(plans.used, 302);
  assertEquals(plans.calls.filter((c) => c.fn === "take_plan_usage").length, 1);
});

Deno.test("a refused catch-up lets go of its claim, and a failed one costs nothing", async () => {
  const briefs = new FakeBriefs();
  const free = new FakePlanDB("free", 150);
  const muse = { calls: 0 };
  assertEquals(await catchUp(briefs, free, muse), 402);
  assertEquals(briefs.rows.size, 0);
  assertEquals(muse.calls, 0);

  const pro = new FakePlanDB("pro", 1000);
  assertEquals(await catchUp(briefs, pro, muse, true), 502);
  assertEquals(pro.used, 0);
  assertEquals(briefs.rows.size, 0);
});
