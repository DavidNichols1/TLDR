// What verify-purchase accepts as a Ketchup subscription, apart from the
// database write. Apple's signature (apple.ts) first, then the payload:
// this app's bundle ID, one of the two products, an auto-renewable
// subscription, bought by this account (appAccountToken), and its
// environment, which decides the plan's source.
//
// Xcode's local StoreKit test ("Xcode" environment) isn't signed by Apple,
// so nothing proves it was really bought. With STOREKIT_XCODE_TEST=true it's
// accepted anyway, as source 'xcode-test', for 24 hours at most (apply_purchase
// and a check constraint both cap it). While that flag is on, ANYONE signed
// in can make one up and get Plus or Pro for a day: turn it on only while
// recording or testing, then unset it. Off (the default), an Xcode purchase
// gets a 403 that says so, and the plan doesn't change.

import { AppleVerifyError, decodeUnsigned, verifySignedTransaction, type VerifyOptions } from "./apple.ts";
import type { Plan } from "./plan.ts";

export const BUNDLE_ID = "com.vibetemp.ketchup";

export const PRODUCTS: Record<string, Exclude<Plan, "free">> = {
  "com.vibetemp.ketchup.plus.monthly": "plus",
  "com.vibetemp.ketchup.pro.monthly": "pro",
};

export type Source = "app_store" | "sandbox" | "xcode-test";

export type Checked =
  | {
    ok: true;
    plan: Exclude<Plan, "free">;
    source: Source;
    productId: string;
    originalTransactionId: string;
    transactionId: string;
    expiresAt: Date | null;
    revokedAt: Date | null;
    /** A newer purchase in the group replaced it (Plus before an upgrade to Pro). */
    upgraded: boolean;
  }
  | { ok: false; status: number; error: string; kind: string; reason?: string };

const refuse = (status: number, kind: string, error: string, reason?: string): Checked =>
  ({ ok: false, status, kind, error, reason });

const date = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? new Date(v) : null);
const text = (v: unknown) => (typeof v === "string" && v.length > 0 && v.length <= 64 ? v : null);

export async function checkPurchase(
  jws: string, user: string, options: VerifyOptions & { xcodeTest: boolean },
): Promise<Checked> {
  let tx: Record<string, unknown>;
  let source: Source;
  try {
    const unsigned = decodeUnsigned(jws);
    if (unsigned.environment === "Xcode") {
      if (!options.xcodeTest) {
        return refuse(403, "xcode_test_off",
          "This is an Xcode test purchase. Apple doesn't sign those, so Cetchup can't check it, and your plan stays as it is.");
      }
      tx = unsigned;
      source = "xcode-test";
    } else {
      tx = await verifySignedTransaction(jws, options);
      if (tx.environment === "Production") source = "app_store";
      else if (tx.environment === "Sandbox") source = "sandbox";
      else return refuse(400, "unverified", "Cetchup couldn't confirm this purchase with Apple.", "environment");
    }
  } catch (e) {
    const reason = e instanceof AppleVerifyError ? e.reason : "unknown";
    return refuse(400, "unverified", "Cetchup couldn't confirm this purchase with Apple.", reason);
  }

  if (tx.bundleId !== BUNDLE_ID) return refuse(400, "wrong_app", "That purchase is for a different app.");
  const productId = text(tx.productId);
  const plan = productId ? PRODUCTS[productId] : undefined;
  if (!productId || !plan) return refuse(400, "unknown_product", "Cetchup doesn't sell that.");
  if (tx.type !== "Auto-Renewable Subscription") return refuse(400, "unknown_product", "Cetchup doesn't sell that.");

  // Bought from this account (the app passes the user id as appAccountToken).
  const token = typeof tx.appAccountToken === "string" ? tx.appAccountToken.toLowerCase() : null;
  if (token && token !== user.toLowerCase()) {
    return refuse(409, "other_account", "This App Store subscription belongs to another Cetchup account.");
  }

  const originalTransactionId = text(tx.originalTransactionId);
  const transactionId = text(tx.transactionId);
  if (!originalTransactionId || !transactionId) {
    return refuse(400, "unverified", "Cetchup couldn't confirm this purchase with Apple.", "ids");
  }

  return {
    ok: true,
    plan,
    source,
    productId,
    originalTransactionId,
    transactionId,
    expiresAt: date(tx.expiresDate),
    revokedAt: date(tx.revocationDate),
    upgraded: tx.isUpgraded === true,
  };
}
