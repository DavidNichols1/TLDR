// verify-purchase: turns an App Store subscription into a Ketchup plan.
//
// POST { jws }   (StoreKit 2's Transaction.jwsRepresentation)
// Authorization: Bearer <the signed-in user's access token>
//
// 1. Checks the transaction (_shared/purchase.ts): Apple's signature chain to
//    the pinned Apple Root CA - G3 (_shared/apple.ts), this app, one of the
//    two products, and that this account bought it (appAccountToken).
//    Production purchases become source 'app_store', Apple's sandbox
//    (TestFlight, App Review, sandbox testers) 'sandbox'. Xcode's local test
//    purchases only with STOREKIT_XCODE_TEST=true (see purchase.ts: while
//    it's on, anyone signed in could fake a day of Plus or Pro).
// 2. Records it with apply_purchase (service role; migration 0010): a newer
//    purchase replaces an older one, a refund ends the plan, and one
//    subscription unlocks one account.
// 3. Answers with what happened and my_plan(), so the app shows the new
//    plan at once.
//
// The app sends every purchase and renewal it sees (Transaction.updates,
// currentEntitlements, Restore). Not here yet: App Store Server
// Notifications, so a renewal or refund made while the app is closed shows
// up the next time it opens.
//
// Logs: the source, product and result only, never transaction ids.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { checkPurchase } from "../_shared/purchase.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const MAX_BYTES = 64_000;

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "Sign in first" });

  let jws = "";
  try {
    const raw = await req.text();
    if (raw.length > MAX_BYTES) return json(413, { error: "That purchase is too big to check" });
    const body = JSON.parse(raw);
    jws = typeof body?.jws === "string" ? body.jws.trim() : "";
  } catch {
    return json(400, { error: "Bad JSON" });
  }
  if (!jws) return json(400, { error: "jws required" });

  const asUser = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userErr } = await asUser.auth.getUser();
  if (userErr || !userData.user) return json(401, { error: "Sign in first" });
  const me = userData.user.id;

  const checked = await checkPurchase(jws, me, { xcodeTest: Deno.env.get("STOREKIT_XCODE_TEST") === "true" });
  if (!checked.ok) {
    console.warn(JSON.stringify({ fn: "verify-purchase", refused: checked.kind, reason: checked.reason ?? null }));
    return json(checked.status, { error: checked.error, kind: checked.kind });
  }

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  let result: string;
  if (!checked.revokedAt && (!checked.expiresAt || checked.expiresAt.getTime() <= Date.now())) {
    result = "expired";
  } else if (!checked.revokedAt && checked.upgraded) {
    result = "upgraded";
  } else {
    const { data, error } = await admin.rpc("apply_purchase", {
      p_user: me,
      p_plan: checked.plan,
      p_source: checked.source,
      p_product: checked.productId,
      p_original_tx: checked.originalTransactionId,
      p_tx: checked.transactionId,
      p_expires: (checked.expiresAt ?? new Date()).toISOString(),
      p_revoked_at: checked.revokedAt?.toISOString() ?? null,
    });
    if (error || typeof data !== "string") {
      console.error(JSON.stringify({ fn: "verify-purchase", apply_error: error?.code ?? "no answer" }));
      return json(500, { error: "Couldn't save your plan. Try again." });
    }
    result = data;
  }
  console.log(JSON.stringify({ fn: "verify-purchase", source: checked.source, product: checked.plan, result }));
  if (result === "taken") {
    return json(409, { error: "This App Store subscription belongs to another Cetchup account.", kind: "other_account" });
  }

  const { data: plan, error: planErr } = await asUser.rpc("my_plan");
  if (planErr) console.error(JSON.stringify({ fn: "verify-purchase", plan_error: planErr.code ?? "unknown" }));
  return json(200, { result, source: checked.source, plan: plan ?? null });
});
