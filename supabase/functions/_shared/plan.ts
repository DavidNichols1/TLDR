// Plans: how many messages Muse Spark reads for each person a day
// (migration 0010). Free 150, Plus 400, Pro 1,000; plan_limit() in SQL is
// where those numbers live. Every plan uses Meta's Standard mode
// (muse-spark-1.3), which Meta doesn't train on, so the plans differ only in
// the allowance (and Pro's voice, which runs on the phone).
//
// A call is charged the messages it sends Muse Spark (a catch-up: the
// unread ones; Ask: the messages it searches; catch-up-text: the thread the
// app sent), and at least CALL_FLOOR, because every call has a fixed cost
// (the prompt, the schema, the context lines). Only real Muse Spark calls
// get here: catch-up hands back saved and shared briefs (once.ts) first, and
// a call that fails gives its messages back.
//
// take_plan_usage checks and spends in one step, under a per-person lock, so
// two requests at once can't both squeeze in under the limit. Over it, the
// request gets a 402 the apps show as is, with the numbers for the paywall.
//
// PLANS_ENFORCED=false (a function secret, no redeploy) switches the
// allowance off: nothing is counted or refused. For emergencies only.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export type Plan = "free" | "plus" | "pro";
export type Kind = "catch_up" | "ask";

/** Every call counts as at least this many messages. */
export const CALL_FLOOR = 10;

const NAMES: Record<Plan, string> = { free: "Free", plus: "Plus", pro: "Pro" };

/** What a call costs against the allowance. */
export function charge(messages: number): number {
  return Math.max(CALL_FLOOR, Math.ceil(Number.isFinite(messages) ? messages : 0));
}

/** take_plan_usage's answer. */
export interface Taken {
  allowed: boolean;
  plan: Plan;
  used: number;
  limit: number;
  day: string;
  resets_at: string;
}

export type Usage =
  | { ok: true; plan: Plan | null; charged: number; giveBack(): Promise<void> }
  | { ok: false; response: Response };

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const count = (n: number) => n.toLocaleString("en-US");

/** The sentence a refused call shows: "You've used today's 150 free messages." */
export function limitMessage(t: Pick<Taken, "plan" | "used" | "limit">, messages: number, kind: Kind): string {
  const left = Math.max(0, t.limit - t.used);
  if (left === 0) {
    return t.plan === "free"
      ? `You've used today's ${count(t.limit)} free messages.`
      : `You've used today's ${count(t.limit)} ${NAMES[t.plan]} messages.`;
  }
  const leftToday = `you have ${count(left)} left today`;
  if (messages < CALL_FLOOR) {
    return `Each catch-up or question counts as at least ${CALL_FLOOR} messages, and ${leftToday}.`;
  }
  const what = kind === "ask" ? `This question searches ${count(messages)} messages` : `This catch-up reads ${count(messages)} messages`;
  return `${what}. ${NAMES[t.plan]} covers ${count(t.limit)} a day, and ${leftToday}.`;
}

/** Spends today's allowance for one Muse Spark call, or says why not. */
export async function takeUsage(
  db: SupabaseClient, user: string, messages: number, kind: Kind,
  env: { get(key: string): string | undefined } = Deno.env,
): Promise<Usage> {
  const charged = charge(messages);
  if (env.get("PLANS_ENFORCED") === "false") {
    return { ok: true, plan: null, charged: 0, giveBack: async () => {} };
  }
  const { data, error } = await db.rpc("take_plan_usage", { p_user: user, p_messages: charged });
  if (error || !data || typeof data !== "object") {
    console.error(JSON.stringify({ plan_error: error?.code ?? "no answer" }));
    return { ok: false, response: json(500, { error: "Couldn't check today's allowance. Try again." }) };
  }
  const taken = data as Taken;
  if (!taken.allowed) {
    console.log(JSON.stringify({ plan: taken.plan, refused: charged, used: taken.used, limit: taken.limit }));
    return {
      ok: false,
      response: json(402, {
        error: limitMessage(taken, messages, kind),
        kind: "plan_limit",
        plan: taken.plan,
        used: taken.used,
        limit: taken.limit,
        needed: charged,
        resets_at: taken.resets_at,
      }),
    };
  }
  let given = false;
  return {
    ok: true,
    plan: taken.plan,
    charged,
    giveBack: async () => {
      if (given) return;
      given = true;
      const { error } = await db.rpc("give_back_plan_usage", { p_user: user, p_day: taken.day, p_messages: charged });
      if (error) console.error(JSON.stringify({ plan_give_back_error: error.code ?? "unknown" }));
    },
  };
}
