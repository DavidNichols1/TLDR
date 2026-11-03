// Checks a StoreKit 2 signed transaction (Transaction.jwsRepresentation, a
// JWS signed with ES256) the way Apple's App Store Server Library does, with
// no dependencies:
//
// 1. The header's x5c holds three certificates: Apple's signing leaf, the
//    Apple Worldwide Developer Relations intermediate, and the root.
// 2. The root must be exactly Apple Root CA - G3, pinned below. It's public:
//    https://www.apple.com/certificateauthority/ (SHA-256 fingerprint
//    63343ABF B89A6A03 EBB57E9B 3F5FA7BE 7C4F5C75 6F3017B3 A8C488C3 653E9179,
//    the same as macOS's system root store).
// 3. The intermediate is signed by the root and carries Apple's OID
//    1.2.840.113635.100.6.2.1; the leaf is signed by the intermediate and
//    carries 1.2.840.113635.100.6.11.1. All three are valid on the date
//    Apple signed the transaction.
// 4. The JWS signature checks out with the leaf's key.
//
// No online revocation check (OCSP), as with the library's offline mode.
// Xcode's local StoreKit test signs with a certificate Xcode makes on the
// Mac, so its purchases never pass this; verify-purchase decides what to do
// with those (decodeUnsigned).

export const APPLE_ROOT_CA_G3 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQL" +
  "DB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMw" +
  "MTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRp" +
  "ZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IA" +
  "BJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqX" +
  "l5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8w" +
  "DgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWT" +
  "xnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

export const APPLE_ROOT_CA_G3_SHA256 = "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

export const APPLE_INTERMEDIATE_OID = "1.2.840.113635.100.6.2.1";
export const APPLE_LEAF_OID = "1.2.840.113635.100.6.11.1";

const ECDSA_SHA256 = "1.2.840.10045.4.3.2";
const ECDSA_SHA384 = "1.2.840.10045.4.3.3";
const EC_PUBLIC_KEY = "1.2.840.10045.2.1";
const CURVES: Record<string, "P-256" | "P-384"> = { "1.2.840.10045.3.1.7": "P-256", "1.3.132.0.34": "P-384" };
const BASIC_CONSTRAINTS = "2.5.29.19";

/** Why a transaction didn't check out. The reason is a fixed word, safe to log. */
export class AppleVerifyError extends Error {
  constructor(readonly reason: string) {
    super(`Apple signature check failed: ${reason}`);
  }
}

const fail = (reason: string): never => {
  throw new AppleVerifyError(reason);
};

// --- Bytes ------------------------------------------------------------------

export function fromBase64(text: string): Uint8Array<ArrayBuffer> {
  try {
    return Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
  } catch {
    return fail("base64");
  }
}

export function fromBase64Url(text: string): Uint8Array<ArrayBuffer> {
  const plain = text.replace(/-/g, "+").replace(/_/g, "/");
  return fromBase64(plain + "=".repeat((4 - (plain.length % 4)) % 4));
}

function sameBytes(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((x, i) => x === b[i]);
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)));
  return [...digest].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// --- DER ----------------------------------------------------------------------

interface Node {
  tag: number;
  /** Where the header starts. */
  start: number;
  /** Where the value starts. */
  value: number;
  end: number;
}

function node(der: Uint8Array, at: number): Node {
  if (at + 2 > der.length) fail("der");
  const tag = der[at];
  if ((tag & 0x1f) === 0x1f) fail("der");
  let length = der[at + 1];
  let value = at + 2;
  if (length & 0x80) {
    const bytes = length & 0x7f;
    if (bytes === 0 || bytes > 4 || value + bytes > der.length) fail("der");
    length = 0;
    for (let i = 0; i < bytes; i++) length = length * 256 + der[value + i];
    value += bytes;
  }
  const end = value + length;
  if (end > der.length) fail("der");
  return { tag, start: at, value, end };
}

function inside(der: Uint8Array, parent: Node): Node[] {
  const out: Node[] = [];
  for (let at = parent.value; at < parent.end;) {
    const child = node(der, at);
    out.push(child);
    at = child.end;
  }
  return out;
}

function expect(n: Node | undefined, tag: number): Node {
  if (!n || n.tag !== tag) fail("der");
  return n as Node;
}

function oid(der: Uint8Array, n: Node): string {
  expect(n, 0x06);
  const values: number[] = [];
  let v = 0;
  for (let i = n.value; i < n.end; i++) {
    v = v * 128 + (der[i] & 0x7f);
    if (!(der[i] & 0x80)) {
      values.push(v);
      v = 0;
    }
  }
  if (values.length === 0) fail("der");
  const first = values[0];
  const head = first < 40 ? [0, first] : first < 80 ? [1, first - 40] : [2, first - 80];
  return [...head, ...values.slice(1)].join(".");
}

function time(der: Uint8Array, n: Node): number {
  const text = new TextDecoder().decode(der.subarray(n.value, n.end));
  const short = /^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(text);
  const long = /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(text);
  let parts: number[];
  if (n.tag === 0x17 && short) {
    const yy = Number(short[1]);
    parts = [yy < 50 ? 2000 + yy : 1900 + yy, ...short.slice(2).map(Number)];
  } else if (n.tag === 0x18 && long) {
    parts = long.slice(1).map(Number);
  } else {
    return fail("der");
  }
  const [y, mo, d, h, mi, s] = parts;
  return Date.UTC(y, mo - 1, d, h, mi, s);
}

// --- X.509 ------------------------------------------------------------------

export interface Certificate {
  der: Uint8Array<ArrayBuffer>;
  /** The signed part, header included. */
  tbs: Uint8Array<ArrayBuffer>;
  signatureAlgorithm: string;
  /** DER: SEQUENCE { r, s }. */
  signature: Uint8Array<ArrayBuffer>;
  issuer: Uint8Array<ArrayBuffer>;
  subject: Uint8Array<ArrayBuffer>;
  notBefore: number;
  notAfter: number;
  /** SubjectPublicKeyInfo, ready for crypto.subtle.importKey("spki"). */
  spki: Uint8Array<ArrayBuffer>;
  curve: "P-256" | "P-384" | null;
  /** Extension OIDs, with their values. */
  extensions: Map<string, Uint8Array<ArrayBuffer>>;
  isCA: boolean;
}

export function parseCertificate(der: Uint8Array<ArrayBuffer>): Certificate {
  const top = expect(node(der, 0), 0x30);
  if (top.end !== der.length) fail("der");
  const [tbsNode, algNode, sigNode] = inside(der, top);
  expect(tbsNode, 0x30);
  const signatureAlgorithm = oid(der, inside(der, expect(algNode, 0x30))[0]);
  expect(sigNode, 0x03);
  if (der[sigNode.value] !== 0) fail("der");

  const fields = inside(der, tbsNode);
  let i = fields[0]?.tag === 0xa0 ? 1 : 0; // version
  expect(fields[i++], 0x02); // serial number
  const innerAlg = oid(der, inside(der, expect(fields[i++], 0x30))[0]);
  if (innerAlg !== signatureAlgorithm) fail("der");
  const issuer = expect(fields[i++], 0x30);
  const [notBefore, notAfter] = inside(der, expect(fields[i++], 0x30)).map((t) => time(der, t));
  const subject = expect(fields[i++], 0x30);
  const spki = expect(fields[i++], 0x30);

  const [keyAlg] = inside(der, spki);
  const keyAlgParts = inside(der, expect(keyAlg, 0x30));
  const curve = oid(der, keyAlgParts[0]) === EC_PUBLIC_KEY && keyAlgParts[1]?.tag === 0x06
    ? CURVES[oid(der, keyAlgParts[1])] ?? null
    : null;

  const extensions = new Map<string, Uint8Array<ArrayBuffer>>();
  let isCA = false;
  const wrapper = fields.slice(i).find((f) => f.tag === 0xa3);
  if (wrapper) {
    for (const ext of inside(der, expect(inside(der, wrapper)[0], 0x30))) {
      const parts = inside(der, expect(ext, 0x30));
      const id = oid(der, parts[0]);
      const value = expect(parts[parts.length - 1], 0x04);
      extensions.set(id, der.slice(value.value, value.end));
      if (id === BASIC_CONSTRAINTS) {
        const constraints = inside(der, expect(node(der, value.value), 0x30));
        isCA = constraints[0]?.tag === 0x01 && der[constraints[0].value] !== 0;
      }
    }
  }

  return {
    der,
    tbs: der.slice(tbsNode.start, tbsNode.end),
    signatureAlgorithm,
    signature: der.slice(sigNode.value + 1, sigNode.end),
    issuer: der.slice(issuer.start, issuer.end),
    subject: der.slice(subject.start, subject.end),
    notBefore: notBefore ?? fail("der"),
    notAfter: notAfter ?? fail("der"),
    spki: der.slice(spki.start, spki.end),
    curve,
    extensions,
    isCA,
  };
}

/** A DER ECDSA signature as WebCrypto wants it: r and s, each `size` bytes. */
function rawSignature(der: Uint8Array, size: number): Uint8Array<ArrayBuffer> {
  const top = expect(node(der, 0), 0x30);
  const [r, s] = inside(der, top);
  const out = new Uint8Array(size * 2);
  [expect(r, 0x02), expect(s, 0x02)].forEach((n, k) => {
    let v = der.subarray(n.value, n.end);
    while (v.length > 0 && v[0] === 0) v = v.subarray(1);
    if (v.length > size) fail("signature");
    out.set(v, (k + 1) * size - v.length);
  });
  return out;
}

function publicKey(cert: Certificate): Promise<CryptoKey> {
  if (!cert.curve) return Promise.reject(new AppleVerifyError("key"));
  return crypto.subtle.importKey("spki", cert.spki, { name: "ECDSA", namedCurve: cert.curve }, false, ["verify"]);
}

/** True when `issuer` signed `child` (its name and its key). */
export async function issuedBy(child: Certificate, issuer: Certificate): Promise<boolean> {
  if (!sameBytes(child.issuer, issuer.subject) || !issuer.curve) return false;
  const hash = child.signatureAlgorithm === ECDSA_SHA384 ? "SHA-384"
    : child.signatureAlgorithm === ECDSA_SHA256 ? "SHA-256" : null;
  if (!hash) return false;
  const size = issuer.curve === "P-384" ? 48 : 32;
  return crypto.subtle.verify({ name: "ECDSA", hash }, await publicKey(issuer), rawSignature(child.signature, size), child.tbs);
}

// --- JWS --------------------------------------------------------------------

function decodePart(part: string | undefined): Record<string, unknown> {
  if (!part) return fail("malformed");
  try {
    const value = JSON.parse(new TextDecoder().decode(fromBase64Url(part)));
    if (value && typeof value === "object" && !Array.isArray(value)) return value;
  } catch { /* below */ }
  return fail("malformed");
}

/** The payload, with nothing checked. Only for Xcode's local test purchases. */
export function decodeUnsigned(jws: string): Record<string, unknown> {
  const parts = jws.split(".");
  if (parts.length !== 3) fail("malformed");
  return decodePart(parts[1]);
}

export interface VerifyOptions {
  /** Trusted roots, DER. Apple Root CA - G3 unless a test passes its own. */
  roots?: Uint8Array[];
  /** Milliseconds; the default is now. */
  now?: number;
}

/** The payload of a transaction Apple signed, or an AppleVerifyError. */
export async function verifySignedTransaction(jws: string, options: VerifyOptions = {}): Promise<Record<string, unknown>> {
  const parts = jws.split(".");
  if (parts.length !== 3) fail("malformed");
  const header = decodePart(parts[0]);
  const payload = decodePart(parts[1]);
  if (header.alg !== "ES256") fail("alg");
  const x5c = header.x5c;
  if (!Array.isArray(x5c) || x5c.length !== 3 || !x5c.every((c) => typeof c === "string")) fail("x5c");
  const [leaf, intermediate, root] = (x5c as string[]).map((c) => parseCertificate(fromBase64(c)));

  const roots = options.roots ?? [fromBase64(APPLE_ROOT_CA_G3)];
  if (!roots.some((r) => sameBytes(r, root.der))) fail("root");

  // Checked on the day Apple signed it, so an old purchase still checks out.
  const now = options.now ?? Date.now();
  const signed = typeof payload.signedDate === "number" ? Math.min(payload.signedDate, now) : now;
  for (const cert of [leaf, intermediate, root]) {
    if (signed < cert.notBefore || signed > cert.notAfter) fail("expired certificate");
  }
  if (!intermediate.isCA || !intermediate.extensions.has(APPLE_INTERMEDIATE_OID)) fail("intermediate");
  if (!leaf.extensions.has(APPLE_LEAF_OID)) fail("leaf");
  if (!(await issuedBy(intermediate, root))) fail("chain");
  if (!(await issuedBy(leaf, intermediate))) fail("chain");
  if (leaf.curve !== "P-256") fail("leaf key");

  const signature = fromBase64Url(parts[2]);
  if (signature.length !== 64) fail("signature");
  const signedPart = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, await publicKey(leaf), signature, signedPart);
  if (!ok) fail("signature");
  return payload;
}
