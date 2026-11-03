// deno test supabase/functions/_shared/
// apple.ts and purchase.ts, offline. Two kinds of certificates:
// - Apple's real, public ones: the pinned Apple Root CA - G3, and the Apple
//   Worldwide Developer Relations G6 intermediate that signs StoreKit's
//   signing certificates. The chain check runs on them for real.
// - A throwaway chain made fresh in each run (keys in memory only, nothing
//   private in the repo), shaped like Apple's, to sign test transactions.
//   It only passes when a test trusts its root on purpose.

import { assert, assertEquals, assertFalse, assertRejects } from "jsr:@std/assert@1";
import {
  APPLE_INTERMEDIATE_OID, APPLE_LEAF_OID, APPLE_ROOT_CA_G3, APPLE_ROOT_CA_G3_SHA256, AppleVerifyError, fromBase64,
  issuedBy, parseCertificate, sha256Hex, verifySignedTransaction,
} from "./apple.ts";
import { checkPurchase } from "./purchase.ts";

/** Apple Worldwide Developer Relations Certification Authority, OU G6 (public;
 *  apple.com/certificateauthority). Issued by Apple Root CA - G3, valid 2021 to 2036. */
const APPLE_WWDR_G6 =
  "MIIDFjCCApygAwIBAgIUIsGhRwp0c2nvU4YSycafPTjzbNcwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAt" +
  "IEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMC" +
  "VVMwHhcNMjEwMzE3MjAzNzEwWhcNMzYwMzE5MDAwMDAwWjB1MUQwQgYDVQQDDDtBcHBsZSBXb3JsZHdpZGUgRGV2ZWxvcGVyIFJl" +
  "bGF0aW9ucyBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTELMAkGA1UECwwCRzYxEzARBgNVBAoMCkFwcGxlIEluYy4xCzAJBgNVBAYT" +
  "AlVTMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEbsQKC94PrlWmZXnXgtxzdVJL8T0SGYngDRGpngn3N6PT8JMEb7FDi4bBmPhCnZ3/" +
  "sq6PF/cGcKXWsL5vOteRhyJ45x3ASP7cOB+aao90fcpxSv/EZFbniAbNgZGhIhpIo4H6MIH3MBIGA1UdEwEB/wQIMAYBAf8CAQAw" +
  "HwYDVR0jBBgwFoAUu7DeoVgziJqkipnevr3rr9rLJKswRgYIKwYBBQUHAQEEOjA4MDYGCCsGAQUFBzABhipodHRwOi8vb2NzcC5h" +
  "cHBsZS5jb20vb2NzcDAzLWFwcGxlcm9vdGNhZzMwNwYDVR0fBDAwLjAsoCqgKIYmaHR0cDovL2NybC5hcHBsZS5jb20vYXBwbGVy" +
  "b290Y2FnMy5jcmwwHQYDVR0OBBYEFD8vlCNR01DJmig97bB85c+lkGKZMA4GA1UdDwEB/wQEAwIBBjAQBgoqhkiG92NkBgIBBAIF" +
  "ADAKBggqhkjOPQQDAwNoADBlAjBAXhSq5IyKogMCPtw490BaB677CaEGJXufQB/EqZGd6CSjiCtOnuMTbXVXmxxcxfkCMQDTSPxa" +
  "rZXvNrkxU3TkUMI33yzvFVVRT4wxWJC994OsdcZ4+RGNsYDyR5gmdr0nDGg=";

// --- A small DER writer, for the throwaway chain ------------------------------

const enc = new TextEncoder();

function concat(...parts: Uint8Array[]): Uint8Array<ArrayBuffer> {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

function length(n: number): Uint8Array {
  if (n < 128) return Uint8Array.of(n);
  const bytes: number[] = [];
  for (; n > 0; n = Math.floor(n / 256)) bytes.unshift(n & 0xff);
  return Uint8Array.of(0x80 | bytes.length, ...bytes);
}

const tlv = (tag: number, ...parts: Uint8Array[]) => {
  const body = concat(...parts);
  return concat(Uint8Array.of(tag), length(body.length), body);
};
const seq = (...parts: Uint8Array[]) => tlv(0x30, ...parts);

function base128(v: number): number[] {
  const out = [v & 0x7f];
  for (v = Math.floor(v / 128); v > 0; v = Math.floor(v / 128)) out.unshift((v & 0x7f) | 0x80);
  return out;
}

function oid(dotted: string): Uint8Array {
  const [a, b, ...rest] = dotted.split(".").map(Number);
  return tlv(0x06, Uint8Array.of(...base128(a * 40 + b), ...rest.flatMap(base128)));
}

function integer(bytes: Uint8Array): Uint8Array {
  let v = bytes;
  while (v.length > 1 && v[0] === 0) v = v.subarray(1);
  return tlv(0x02, v[0] & 0x80 ? concat(Uint8Array.of(0), v) : v);
}

function utcTime(ms: number): Uint8Array {
  const d = new Date(ms);
  const p = (n: number) => String(n).padStart(2, "0");
  return tlv(0x17, enc.encode(`${p(d.getUTCFullYear() % 100)}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}` +
    `${p(d.getUTCHours())}${p(d.getUTCMinutes())}${p(d.getUTCSeconds())}Z`));
}

const name = (cn: string) => seq(tlv(0x31, seq(oid("2.5.4.3"), tlv(0x0c, enc.encode(cn)))));
const extension = (id: string, value: Uint8Array, critical = false) =>
  seq(oid(id), ...(critical ? [tlv(0x01, Uint8Array.of(0xff))] : []), tlv(0x04, value));
const isCA = () => extension("2.5.29.19", seq(tlv(0x01, Uint8Array.of(0xff))), true);
const marker = (id: string) => extension(id, Uint8Array.of(0x05, 0x00));

interface Party {
  name: string;
  curve: "P-256" | "P-384";
  keys: CryptoKeyPair;
  der: Uint8Array<ArrayBuffer>;
}

async function party(cn: string, curve: Party["curve"]): Promise<Party> {
  const keys = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: curve }, true, ["sign", "verify"]);
  return { name: cn, curve, keys, der: new Uint8Array() };
}

async function certify(subject: Party, issuer: Party, notBefore: number, notAfter: number, extensions: Uint8Array[]) {
  const algorithm = seq(oid(issuer.curve === "P-384" ? "1.2.840.10045.4.3.3" : "1.2.840.10045.4.3.2"));
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", subject.keys.publicKey));
  const tbs = seq(
    tlv(0xa0, integer(Uint8Array.of(2))),
    integer(crypto.getRandomValues(new Uint8Array(8))),
    algorithm,
    name(issuer.name),
    seq(utcTime(notBefore), utcTime(notAfter)),
    name(subject.name),
    spki,
    tlv(0xa3, seq(...extensions)),
  );
  const hash = issuer.curve === "P-384" ? "SHA-384" : "SHA-256";
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash }, issuer.keys.privateKey, tbs));
  const half = raw.length / 2;
  subject.der = seq(tbs, algorithm, tlv(0x03, Uint8Array.of(0), seq(integer(raw.subarray(0, half)), integer(raw.subarray(half)))));
}

const DAY = 86_400_000;
const NOW = Date.now();

interface Chain { root: Party; intermediate: Party; leaf: Party }

/** Shaped like Apple's: a P-384 root and intermediate, a P-256 signing leaf. */
async function testChain(options: { leafMarker?: boolean; intermediateMarker?: boolean; leafNotAfter?: number } = {}): Promise<Chain> {
  const root = await party("Ketchup Test Root", "P-384");
  const intermediate = await party("Ketchup Test Developer Relations", "P-384");
  const leaf = await party("Ketchup Test StoreKit Signing", "P-256");
  await certify(root, root, NOW - 365 * DAY, NOW + 3650 * DAY, [isCA()]);
  await certify(intermediate, root, NOW - 365 * DAY, NOW + 3650 * DAY,
    [isCA(), ...(options.intermediateMarker === false ? [] : [marker(APPLE_INTERMEDIATE_OID)])]);
  await certify(leaf, intermediate, NOW - 30 * DAY, options.leafNotAfter ?? NOW + 365 * DAY,
    options.leafMarker === false ? [] : [marker(APPLE_LEAF_OID)]);
  return { root, intermediate, leaf };
}

const b64 = (b: Uint8Array) => btoa(String.fromCharCode(...b));
const b64url = (b: Uint8Array) => b64(b).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const part = (v: unknown) => b64url(enc.encode(JSON.stringify(v)));

async function sign(chain: Chain, payload: Record<string, unknown>, certs = [chain.leaf, chain.intermediate, chain.root],
  header: Record<string, unknown> = {}): Promise<string> {
  const signed = `${part({ alg: "ES256", x5c: certs.map((c) => b64(c.der)), ...header })}.${part(payload)}`;
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, chain.leaf.keys.privateKey, enc.encode(signed)));
  return `${signed}.${b64url(signature)}`;
}

const ME = "6f1c2c1e-7b4e-4c3a-9d55-0f2d1a8b9c01";

const transaction = (fields: Record<string, unknown> = {}) => ({
  transactionId: "2000000812345678",
  originalTransactionId: "2000000812340000",
  bundleId: "com.vibetemp.ketchup",
  productId: "com.vibetemp.ketchup.plus.monthly",
  purchaseDate: NOW - DAY,
  originalPurchaseDate: NOW - DAY,
  expiresDate: NOW + 30 * DAY,
  type: "Auto-Renewable Subscription",
  appAccountToken: ME,
  inAppOwnershipType: "PURCHASED",
  signedDate: NOW - 60_000,
  environment: "Sandbox",
  ...fields,
});

async function reason(promise: Promise<unknown>): Promise<string> {
  const e = await assertRejects(() => promise, AppleVerifyError);
  return (e as AppleVerifyError).reason;
}

// --- Apple's real certificates ----------------------------------------------

Deno.test("the pinned root is Apple Root CA - G3, signed by itself", async () => {
  const der = fromBase64(APPLE_ROOT_CA_G3);
  assertEquals(await sha256Hex(der), APPLE_ROOT_CA_G3_SHA256);
  const root = parseCertificate(der);
  assert(new TextDecoder().decode(root.subject).includes("Apple Root CA - G3"));
  assertEquals(root.curve, "P-384");
  assert(root.isCA);
  assertEquals(new Date(root.notBefore).toISOString(), "2014-04-30T18:19:06.000Z");
  assertEquals(new Date(root.notAfter).toISOString(), "2039-04-30T18:19:06.000Z");
  assert(await issuedBy(root, root));
});

Deno.test("Apple's G6 intermediate checks out against the pinned root, and only it", async () => {
  const root = parseCertificate(fromBase64(APPLE_ROOT_CA_G3));
  const g6 = parseCertificate(fromBase64(APPLE_WWDR_G6));
  assert(g6.isCA);
  assert(g6.extensions.has(APPLE_INTERMEDIATE_OID));
  assertEquals(g6.curve, "P-384");
  assert(await issuedBy(g6, root));
  // One changed byte inside what Apple signed (in the validity dates).
  const changed = fromBase64(APPLE_WWDR_G6);
  const at = changed.indexOf(0x17) + 4;
  changed[at] ^= 0x01;
  assertFalse(await issuedBy(parseCertificate(changed), root));
  // And a stranger's root doesn't vouch for it.
  const stranger = await testChain();
  assertFalse(await issuedBy(g6, parseCertificate(stranger.root.der)));
});

// --- The chain check, on a throwaway chain ------------------------------------

Deno.test("a transaction signed through a chain checks out against that chain's root", async () => {
  const chain = await testChain();
  const payload = transaction();
  assertEquals(await verifySignedTransaction(await sign(chain, payload), { roots: [chain.root.der] }), payload);
});

Deno.test("the same transaction fails against Apple's root: only Apple's chain counts", async () => {
  const chain = await testChain();
  assertEquals(await reason(verifySignedTransaction(await sign(chain, transaction()))), "root");
});

Deno.test("a changed payload fails the signature", async () => {
  const chain = await testChain();
  const [head, , signature] = (await sign(chain, transaction())).split(".");
  const forged = `${head}.${part(transaction({ productId: "com.vibetemp.ketchup.pro.monthly" }))}.${signature}`;
  assertEquals(await reason(verifySignedTransaction(forged, { roots: [chain.root.der] })), "signature");
});

Deno.test("Apple's OIDs are required on the leaf and the intermediate", async () => {
  const noLeaf = await testChain({ leafMarker: false });
  assertEquals(await reason(verifySignedTransaction(await sign(noLeaf, transaction()), { roots: [noLeaf.root.der] })), "leaf");
  const noIntermediate = await testChain({ intermediateMarker: false });
  assertEquals(await reason(verifySignedTransaction(await sign(noIntermediate, transaction()),
    { roots: [noIntermediate.root.der] })), "intermediate");
});

Deno.test("a certificate that had expired when the transaction was signed fails", async () => {
  const chain = await testChain({ leafNotAfter: NOW - 2 * DAY });
  assertEquals(await reason(verifySignedTransaction(await sign(chain, transaction()), { roots: [chain.root.der] })),
    "expired certificate");
});

Deno.test("a leaf from another chain fails, even with the same names", async () => {
  const a = await testChain();
  const b = await testChain();
  const jws = await sign(a, transaction(), [a.leaf, b.intermediate, a.root]);
  assertEquals(await reason(verifySignedTransaction(jws, { roots: [a.root.der] })), "chain");
});

Deno.test("only ES256 with exactly three certificates, and garbage is refused", async () => {
  const chain = await testChain();
  const roots = [chain.root.der];
  assertEquals(await reason(verifySignedTransaction(await sign(chain, transaction(), undefined, { alg: "HS256" }), { roots })), "alg");
  assertEquals(await reason(verifySignedTransaction(await sign(chain, transaction(), [chain.leaf, chain.root]), { roots })), "x5c");
  assertEquals(await reason(verifySignedTransaction("not a jws", { roots })), "malformed");
  assertEquals(await reason(verifySignedTransaction("a.b.c", { roots })), "malformed");
});

// --- What verify-purchase accepts (purchase.ts) -------------------------------

const check = async (jws: string, chain: Chain, xcodeTest = false, user = ME) =>
  await checkPurchase(jws, user, { roots: [chain.root.der], xcodeTest });

Deno.test("a sandbox Plus purchase by this account is Plus from the sandbox", async () => {
  const chain = await testChain();
  const checked = await check(await sign(chain, transaction()), chain);
  assert(checked.ok);
  assertEquals(checked.plan, "plus");
  assertEquals(checked.source, "sandbox");
  assertEquals(checked.originalTransactionId, "2000000812340000");
  assertEquals(checked.expiresAt?.getTime(), NOW + 30 * DAY);
  assertEquals(checked.revokedAt, null);

  const pro = await check(await sign(chain, transaction({
    environment: "Production", productId: "com.vibetemp.ketchup.pro.monthly", appAccountToken: ME.toUpperCase(),
  })), chain);
  assert(pro.ok);
  assertEquals([pro.plan, pro.source], ["pro", "app_store"]);
});

Deno.test("another account's purchase, another app or another product is refused", async () => {
  const chain = await testChain();
  const other = await check(await sign(chain, transaction()), chain, false, "11111111-2222-4333-8444-555555555555");
  assertFalse(other.ok);
  if (!other.ok) assertEquals([other.status, other.kind], [409, "other_account"]);
  const app = await check(await sign(chain, transaction({ bundleId: "com.example.other" })), chain);
  assertFalse(app.ok);
  if (!app.ok) assertEquals([app.status, app.kind], [400, "wrong_app"]);
  const product = await check(await sign(chain, transaction({ productId: "com.vibetemp.ketchup.lifetime" })), chain);
  assertFalse(product.ok);
  if (!product.ok) assertEquals([product.status, product.kind], [400, "unknown_product"]);
});

Deno.test("refunds and upgrades come through for apply_purchase to act on", async () => {
  const chain = await testChain();
  const refunded = await check(await sign(chain, transaction({ revocationDate: NOW - 1000, revocationReason: 0 })), chain);
  assert(refunded.ok);
  assertEquals(refunded.revokedAt?.getTime(), NOW - 1000);
  const upgraded = await check(await sign(chain, transaction({ isUpgraded: true })), chain);
  assert(upgraded.ok);
  assert(upgraded.upgraded);
});

/** Xcode's local test purchases have Apple's shape but aren't signed by Apple. */
const xcodePurchase = (fields: Record<string, unknown> = {}) =>
  `${part({ alg: "ES256", kid: "Apple_Xcode_Key" })}.${part(transaction({
    environment: "Xcode", transactionId: "0", originalTransactionId: "0", ...fields,
  }))}.not-signed-by-apple`;

Deno.test("an Xcode test purchase is refused unless STOREKIT_XCODE_TEST is on", async () => {
  const chain = await testChain();
  const off = await check(xcodePurchase(), chain, false);
  assertFalse(off.ok);
  if (!off.ok) {
    assertEquals([off.status, off.kind], [403, "xcode_test_off"]);
    assertFalse(/[–—]/.test(off.error));
  }
  const on = await check(xcodePurchase(), chain, true);
  assert(on.ok);
  assertEquals([on.plan, on.source], ["plus", "xcode-test"]);
});

Deno.test("why the flag stays off: while it's on, a made-up Xcode purchase passes", async () => {
  const chain = await testChain();
  const madeUp = await check(xcodePurchase({ productId: "com.vibetemp.ketchup.pro.monthly", appAccountToken: undefined }), chain, true);
  assert(madeUp.ok);
  assertEquals(madeUp.plan, "pro");
  // Only "Xcode" skips the check: a made-up sandbox or App Store purchase never does.
  const fakeSandbox = await check(xcodePurchase({ environment: "Sandbox" }), chain, true);
  assertFalse(fakeSandbox.ok);
  if (!fakeSandbox.ok) assertEquals([fakeSandbox.status, fakeSandbox.kind], [400, "unverified"]);
});
