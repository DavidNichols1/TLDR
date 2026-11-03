// Seeds the Ketchup demo: five test friends, one group chat, ~300 messages
// spread over three days, so a new member who joins with the invite code
// opens the app to a wall of unread messages and taps Catch me up.
//
//   deno run --allow-net --allow-env --allow-read scripts/seed-demo/seed.ts [flags]
//
//   --dry-run          print the timeline and planted items; touches nothing
//   --reset            delete the demo friends' messages in the chat first, then reseed
//   --retime           move the whole conversation so it ends just now (default
//                      on a re-run is to keep the existing dates)
//   --end-date=YYYY-MM-DD  put the last day of the conversation on this date
//   --rearm            make the chat fully unread again for everyone who is not
//                      a demo friend (you), and clear your cached catch-ups for it
//   --photos           also add two made-up photos (photos/): Theo's dog, and Maya's
//                      photo of the cabin door code, which only the photo says
//
// Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the environment or in
// scripts/seed-demo/.env (gitignored). The service-role key bypasses Row
// Level Security; it is only for this local script and never goes in the app.
//
// Safe to re-run: message ids are derived from the chat id and the script
// line, so existing messages are skipped, not duplicated.

import { CHAT_NAME, CREATOR, DAYS, PEOPLE, type Sender, type Tag, VIEWER_NAME } from "./conversation.ts";

const TZ = "America/Denver"; // the edge function's default reading zone
const ID_NAMESPACE = "6f1c2a7e-5b9d-4c3e-9a41-2d7e8f0b1c55";
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // same as public.new_invite_code()
const INSERT_BATCH = 100;
const PATCH_CONCURRENCY = 8;

// ---------------------------------------------------------------------------
// Flags

const args = Deno.args;
const flag = (name: string) => args.includes(`--${name}`);
function flagValue(name: string): string | null {
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith(`--${name}=`)) return args[i].slice(name.length + 3);
    if (args[i] === `--${name}` && args[i + 1] && !args[i + 1].startsWith("--")) return args[i + 1];
  }
  return null;
}
if (flag("help") || flag("h")) {
  console.log(
    "usage: deno run --allow-net --allow-env --allow-read scripts/seed-demo/seed.ts [--dry-run] [--reset] [--retime] [--end-date=YYYY-MM-DD] [--rearm] [--photos]",
  );
  Deno.exit(0);
}
const DRY_RUN = flag("dry-run");
const RESET = flag("reset");
const RETIME = flag("retime");
const REARM = flag("rearm");
const PHOTOS = flag("photos");
const END_DATE = flagValue("end-date");

/**
 * --photos: two made-up photo messages on the last day, each a few minutes
 * after a script line (photos/make_photos.swift draws them). Theo's is the
 * Pickles photo he promised that morning; Maya's has the door code, which
 * the chat said would come later and which no message spells out.
 */
const PHOTO_MESSAGES: { file: string; sender: Sender; caption: string; after: string; minutes: number }[] = [
  { file: "pickles", sender: "theo", caption: "as promised. Pickles, upside down 🐶", after: "she's committing", minutes: 4 },
  { file: "door-note", sender: "maya", caption: "the host sent the door code early 🙌", after: "👍 locking that in", minutes: 9 },
];
const PHOTO_SIZE = { width: 1536, height: 1152 };

// ---------------------------------------------------------------------------
// Time helpers (America/Denver wall clock ↔ UTC, no libraries)

interface YMD {
  y: number;
  m: number;
  d: number;
}

const partsFmt = new Intl.DateTimeFormat("en-US", {
  timeZone: TZ,
  hourCycle: "h23",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
});

function localParts(ms: number) {
  const p = Object.fromEntries(partsFmt.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  return { y: +p.year, m: +p.month, d: +p.day, h: +p.hour, mi: +p.minute, s: +p.second };
}

function offsetMs(utcMs: number): number {
  const p = localParts(utcMs);
  return Date.UTC(p.y, p.m - 1, p.d, p.h, p.mi, p.s) - Math.floor(utcMs / 1000) * 1000;
}

/** UTC ms for a wall-clock time in TZ (handles the DST switch). */
function zoned(day: YMD, h: number, mi: number, s = 0): number {
  const guess = Date.UTC(day.y, day.m - 1, day.d, h, mi, s);
  const first = guess - offsetMs(guess);
  const second = guess - offsetMs(first);
  return second;
}

const addDays = (day: YMD, n: number): YMD => {
  const t = new Date(Date.UTC(day.y, day.m - 1, day.d + n));
  return { y: t.getUTCFullYear(), m: t.getUTCMonth() + 1, d: t.getUTCDate() };
};
const weekday = (day: YMD) => new Date(Date.UTC(day.y, day.m - 1, day.d)).getUTCDay(); // 0 = Sun
const ymdOf = (ms: number): YMD => {
  const p = localParts(ms);
  return { y: p.y, m: p.m, d: p.d };
};
const ymdStr = (d: YMD) => `${d.y}-${String(d.m).padStart(2, "0")}-${String(d.d).padStart(2, "0")}`;
const DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const dayLabel = (d: YMD) =>
  new Date(Date.UTC(d.y, d.m - 1, d.d)).toLocaleDateString("en-US", {
    timeZone: "UTC",
    weekday: "short",
    month: "short",
    day: "numeric",
  });
const stamp = (ms: number) =>
  new Date(ms).toLocaleString("en-US", {
    timeZone: TZ,
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });

// ---------------------------------------------------------------------------
// Deterministic ids and jitter

function fnv1a(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

const nsBytes = new Uint8Array(ID_NAMESPACE.replace(/-/g, "").match(/../g)!.map((b) => parseInt(b, 16)));

/** RFC 4122 version-5 UUID, so the same script line always gets the same id. */
async function uuidv5(name: string): Promise<string> {
  const nameBytes = new TextEncoder().encode(name);
  const data = new Uint8Array(nsBytes.length + nameBytes.length);
  data.set(nsBytes);
  data.set(nameBytes, nsBytes.length);
  const h = new Uint8Array(await crypto.subtle.digest("SHA-1", data)).slice(0, 16);
  h[6] = (h[6] & 0x0f) | 0x50;
  h[8] = (h[8] & 0x3f) | 0x80;
  const hex = [...h].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

// ---------------------------------------------------------------------------
// The planned conversation

interface Planned {
  index: number;
  day: number;
  sender: Sender;
  body: string;
  tags: Tag[];
  at: number; // UTC ms
}

const SCRIPT = DAYS.flatMap((bursts, day) =>
  bursts.flatMap((b) => b.lines.map((l, i) => ({ day, at: b.at, first: i === 0, line: l })))
);

/**
 * Where the conversation sits: its last day, and how far the whole thing is
 * pulled earlier (at most MAX_SHIFT) so it can end "today" before the
 * scripted late-evening messages have actually happened.
 */
interface Placement {
  lastDay: YMD;
  shiftMs: number;
}
const MAX_SHIFT = 3 * 3600_000;
const SETTLE = 15 * 60_000; // the last message lands at least this long before now

/** Lays the script out on real dates. */
function timeline({ lastDay, shiftMs }: Placement): Planned[] {
  const firstDay = addDays(lastDay, -(DAYS.length - 1));
  const out: Planned[] = [];
  let prev = -Infinity;
  SCRIPT.forEach((s, index) => {
    const [sender, body, ...tags] = s.line;
    const key = `${index}:${body}`;
    let at: number;
    if (s.first) {
      const [h, mi] = s.at.split(":").map(Number);
      at = zoned(addDays(firstDay, s.day), h, mi, fnv1a(key) % 40);
      if (at <= prev) throw new Error(`Burst at day ${s.day} ${s.at} starts before the previous one ends`);
    } else {
      // Typing time: short replies land fast, long ones take a bit.
      at = prev + (6 + Math.min(55, Math.round(body.length * 0.3)) + (fnv1a(key) % 22)) * 1000;
    }
    out.push({ index, day: s.day, sender, body, tags, at });
    prev = at;
  });
  return shiftMs ? out.map((p) => ({ ...p, at: p.at - shiftMs })) : out;
}

/** The pull-back needed for `lastDay` to end before now, or null if over MAX_SHIFT. */
function placeOn(lastDay: YMD, now: number): Placement | null {
  const t = timeline({ lastDay, shiftMs: 0 });
  const shiftMs = Math.max(0, t[t.length - 1].at - (now - SETTLE));
  return shiftMs <= MAX_SHIFT ? { lastDay, shiftMs: Math.ceil(shiftMs / 60_000) * 60_000 } : null;
}

/** Last day = the latest Mon–Wed the conversation can end on before now. */
function autoPlacement(now: number): Placement {
  const today = ymdOf(now);
  for (let back = 0; back < 10; back++) {
    const cand = addDays(today, -back);
    if (![1, 2, 3].includes(weekday(cand))) continue;
    const p = placeOn(cand, now);
    if (p) return p;
  }
  throw new Error("could not place the conversation");
}

function endDatePlacement(s: string, now: number): Placement {
  const p = placeOn(parseYMD(s), now);
  if (!p) throw new Error(`--end-date ${s} would put messages in the future. Pick an earlier date.`);
  return p;
}

function validate(plan: Planned[], now: number) {
  for (const p of plan) {
    if (p.body !== p.body.trim() || p.body.length < 1 || p.body.length > 2000) {
      throw new Error(`Line ${p.index} breaks the body rules (trimmed, 1–2000 chars)`);
    }
    if (!(p.sender in PEOPLE)) throw new Error(`Line ${p.index} has unknown sender ${p.sender}`);
  }
  const last = plan[plan.length - 1].at;
  if (last > now) throw new Error(`The last message (${stamp(last)}) would be in the future. Pick an earlier --end-date.`);
}

function tripDates(lastDay: YMD) {
  let fri = addDays(lastDay, 1);
  while (weekday(fri) !== 5) fri = addDays(fri, 1);
  return { fri, sat: addDays(fri, 1), sun: addDays(fri, 2), thu: addDays(fri, -1) };
}

function report(plan: Planned[], { lastDay, shiftMs }: Placement, now: number) {
  const first = plan[0].at;
  const last = plan[plan.length - 1].at;
  const firstDay = addDays(lastDay, -(DAYS.length - 1));
  console.log(`\nConversation: "${CHAT_NAME}": ${plan.length} messages`);
  console.log(`  days:  ${[0, 1, 2].map((i) => dayLabel(addDays(firstDay, i))).join(", ")}  (${TZ})`);
  console.log(`  span:  ${stamp(first)} → ${stamp(last)}  (${((last - first) / 3600_000).toFixed(1)} h)`);
  console.log(
    `  ends:  ${Math.round((now - last) / 60_000)} min before now  (last day ${ymdStr(lastDay)}` +
      (shiftMs ? `, pulled ${Math.round(shiftMs / 60_000)} min earlier so it's already over)` : ")"),
  );
  const trip = tripDates(lastDay);
  console.log(
    `  trip:  ${dayLabel(trip.thu)} Root Down · ${dayLabel(trip.fri)} rentals + groceries · ` +
      `${dayLabel(trip.sat)} leave 6am, Hearthstone 7:30pm · ${dayLabel(trip.sun)} A-Basin, leave by 2pm`,
  );
  if (![1, 2, 3].includes(weekday(lastDay))) {
    console.warn(`  WARNING: the last day is a ${DAY_NAMES[weekday(lastDay)]}; the script reads best ending Mon–Wed.`);
  }
  if (zoned(trip.fri, 18, 0) < now) {
    console.warn(`  WARNING: the trip Friday (${dayLabel(trip.fri)}) is already past. Seed Mon–Thu, or use --end-date.`);
  }

  console.log("\nMessages per sender:");
  for (const s of Object.keys(PEOPLE) as Sender[]) {
    const n = plan.filter((p) => p.sender === s).length;
    console.log(`  ${PEOPLE[s].name.padEnd(7)} ${String(n).padStart(3)}`);
  }
  console.log("\nMessages per day:");
  for (let d = 0; d < DAYS.length; d++) {
    console.log(`  ${dayLabel(addDays(firstDay, d)).padEnd(12)} ${String(plan.filter((p) => p.day === d).length).padStart(3)}`);
  }
  const tags: Tag[] = ["plan", "change", "money", "open_q", "answered_q", "for_david", "side"];
  console.log("\nPlanted (tagged lines):");
  for (const t of tags) console.log(`  ${t.padEnd(11)} ${String(plan.filter((p) => p.tags.includes(t)).length).padStart(3)}`);
  const untagged = plan.filter((p) => p.tags.length === 0).length;
  console.log(`  ${"untagged".padEnd(11)} ${String(untagged).padStart(3)}  (banter and replies)`);

  for (const t of tags.filter((t) => t !== "side")) {
    console.log(`\n[${t}]`);
    for (const p of plan.filter((p) => p.tags.includes(t))) {
      console.log(`  ${stamp(p.at).padEnd(22)} ${PEOPLE[p.sender].name}: ${p.body}`);
    }
  }
}

// ---------------------------------------------------------------------------
// Supabase (plain fetch; the service-role key goes in both headers, like supabase-js)

async function loadDotEnv() {
  try {
    const text = await Deno.readTextFile(new URL("./.env", import.meta.url));
    for (const raw of text.split("\n")) {
      const line = raw.trim();
      if (!line || line.startsWith("#") || !line.includes("=")) continue;
      const i = line.indexOf("=");
      const k = line.slice(0, i).trim();
      const v = line.slice(i + 1).trim().replace(/^["']|["']$/g, "");
      if (k && Deno.env.get(k) === undefined) Deno.env.set(k, v);
    }
  } catch (e) {
    if (!(e instanceof Deno.errors.NotFound)) throw e;
  }
}

function checkServiceKey(key: string) {
  if (key.startsWith("sb_publishable_")) throw new Error("That's the publishable key. Use the secret / service_role key.");
  if (key.startsWith("sb_secret_")) return;
  const parts = key.split(".");
  if (parts.length === 3) {
    try {
      const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
      if (payload.role !== "service_role") throw new Error(`That key's role is "${payload.role}", not service_role.`);
      return;
    } catch (e) {
      if (e instanceof Error && e.message.startsWith("That key")) throw e;
    }
  }
  throw new Error("SUPABASE_SERVICE_ROLE_KEY doesn't look like a Supabase secret or service_role key.");
}

class Api {
  constructor(private url: string, private key: string) {}

  async req<T = unknown>(method: string, path: string, body?: unknown, prefer?: string): Promise<T> {
    const res = await fetch(this.url + path, {
      method,
      headers: {
        apikey: this.key,
        Authorization: `Bearer ${this.key}`,
        "Content-Type": "application/json",
        ...(prefer ? { Prefer: prefer } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    if (!res.ok) {
      const err = new Error(`${method} ${path.split("?")[0]} → ${res.status}: ${text.slice(0, 300)}`);
      (err as Error & { status?: number }).status = res.status;
      throw err;
    }
    return (text ? JSON.parse(text) : null) as T;
  }

  async count(table: string, filter: string): Promise<number> {
    const res = await fetch(`${this.url}/rest/v1/${table}?select=id&${filter}`, {
      method: "HEAD",
      headers: { apikey: this.key, Authorization: `Bearer ${this.key}`, Prefer: "count=exact" },
    });
    if (!res.ok) throw new Error(`count ${table} → ${res.status}`);
    const range = res.headers.get("content-range") ?? "*/0";
    return Number(range.split("/")[1] ?? 0);
  }
}

const enc = encodeURIComponent;

async function pool<T>(items: T[], n: number, fn: (x: T) => Promise<void>) {
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
    while (i < items.length) await fn(items[i++]);
  }));
}

function newInviteCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(6));
  return [...bytes].map((b) => ALPHABET[b % 32]).join("");
}

interface AuthUser {
  id: string;
  email?: string;
}

async function ensureUsers(api: Api): Promise<Record<Sender, string>> {
  const existing = new Map<string, string>();
  for (let page = 1; page < 50; page++) {
    const res = await api.req<{ users: AuthUser[] }>("GET", `/auth/v1/admin/users?page=${page}&per_page=200`);
    for (const u of res.users ?? []) if (u.email) existing.set(u.email.toLowerCase(), u.id);
    if ((res.users ?? []).length < 200) break;
  }
  const ids = {} as Record<Sender, string>;
  for (const s of Object.keys(PEOPLE) as Sender[]) {
    const { email, name } = PEOPLE[s];
    let id = existing.get(email.toLowerCase());
    if (id) {
      console.log(`  user ${name.padEnd(7)} ${email}  (exists)`);
    } else {
      const u = await api.req<AuthUser>("POST", "/auth/v1/admin/users", {
        email,
        email_confirm: true,
        user_metadata: { display_name: name, tldr_demo: true },
      });
      id = u.id;
      console.log(`  user ${name.padEnd(7)} ${email}  (created)`);
    }
    ids[s] = id;
  }
  // The sign-up trigger made a profile named after the email; give it the real name.
  await api.req(
    "POST",
    "/rest/v1/profiles?on_conflict=id",
    (Object.keys(ids) as Sender[]).map((s) => ({ id: ids[s], display_name: PEOPLE[s].name })),
    "resolution=merge-duplicates,return=minimal",
  );
  return ids;
}

interface ChatRow {
  id: string;
  name: string;
  invite_code: string;
  created_at: string;
}

async function ensureChat(api: Api, creator: string): Promise<{ chat: ChatRow; created: boolean }> {
  const found = await api.req<ChatRow[]>(
    "GET",
    `/rest/v1/chats?select=id,name,invite_code,created_at&name=eq.${enc(CHAT_NAME)}&created_by=eq.${creator}&order=created_at.asc&limit=1`,
  );
  if (found.length) return { chat: found[0], created: false };
  // create_chat() needs auth.uid(), so do what it does: chat row + creator membership.
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const rows = await api.req<ChatRow[]>(
        "POST",
        "/rest/v1/chats?select=id,name,invite_code,created_at",
        { name: CHAT_NAME, invite_code: newInviteCode(), created_by: creator },
        "return=representation",
      );
      return { chat: rows[0], created: true };
    } catch (e) {
      if ((e as { status?: number }).status !== 409) throw e; // 409 = invite code taken, try another
    }
  }
  throw new Error("Couldn't find a free invite code");
}

// ---------------------------------------------------------------------------

async function main() {
  const now = Date.now();

  if (DRY_RUN) {
    const place = END_DATE ? endDatePlacement(END_DATE, now) : autoPlacement(now);
    const plan = timeline(place);
    validate(plan, now);
    const ids = new Set(await Promise.all(plan.map((p) => uuidv5(`dry-run/${p.index}/${p.sender}/${p.body}`))));
    console.log(`DRY RUN. Nothing is written. ${ids.size} distinct message ids for ${plan.length} lines.`);
    report(plan, place, now);
    console.log(`\nAccounts it would create/reuse:`);
    for (const s of Object.keys(PEOPLE) as Sender[]) console.log(`  ${PEOPLE[s].name.padEnd(7)} ${PEOPLE[s].email}`);
    if (PHOTOS) {
      console.log(`\nPhotos it would add:`);
      for (const p of photoTimes(plan)) console.log(`  ${stamp(p.at).padEnd(22)} ${PEOPLE[p.sender].name}: [photo ${p.file}] ${p.caption}`);
    }
    console.log(`\nViewer: join with the invite code from an account whose display name is "${VIEWER_NAME}".`);
    return;
  }

  await loadDotEnv();
  const url = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/+$/, "");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !key) {
    console.error("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (or put them in scripts/seed-demo/.env).");
    Deno.exit(1);
  }
  checkServiceKey(key);
  const api = new Api(url, key);

  console.log(`Seeding ${url}`);
  const users = await ensureUsers(api);
  const seedIds = Object.values(users);
  const seedList = `(${seedIds.join(",")})`;

  const { chat, created } = await ensureChat(api, users[CREATOR]);
  console.log(`  chat "${chat.name}" ${chat.id}  (${created ? "created" : "exists"})`);

  const members = await api.req<{ user_id: string; last_read_at: string }[]>(
    "GET",
    `/rest/v1/chat_members?select=user_id,last_read_at&chat_id=eq.${chat.id}`,
  );
  const memberSet = new Set(members.map((m) => m.user_id));
  const missing = seedIds.filter((id) => !memberSet.has(id));
  if (missing.length) {
    await api.req(
      "POST",
      "/rest/v1/chat_members?on_conflict=chat_id,user_id",
      missing.map((user_id) => ({ chat_id: chat.id, user_id })),
      "resolution=ignore-duplicates,return=minimal",
    );
  }
  console.log(`  members: ${seedIds.length} demo friends (${missing.length} added), ${members.filter((m) => !seedIds.includes(m.user_id)).length} others`);

  const before = await api.count("messages", `chat_id=eq.${chat.id}`);

  if (RESET) {
    await api.req("DELETE", `/rest/v1/messages?chat_id=eq.${chat.id}&sender=in.${seedList}`, undefined, "return=minimal");
    console.log(`  --reset: deleted the demo friends' messages`);
  }

  // Ids first: they don't depend on dates.
  const idFor = (p: { index: number; sender: Sender; body: string }) => uuidv5(`${chat.id}/${p.index}/${p.sender}/${p.body}`);
  const scriptIds = await Promise.all(SCRIPT.map((s, index) => idFor({ index, sender: s.line[0], body: s.line[1] })));

  const existing = await api.req<{ id: string; sender: string; created_at: string }[]>(
    "GET",
    `/rest/v1/messages?select=id,sender,created_at&chat_id=eq.${chat.id}&order=created_at.asc&limit=5000`,
  );
  const existingAt = new Map(existing.map((m) => [m.id, Date.parse(m.created_at)]));

  // Which dates? Keep the existing ones on a re-run unless asked to move them.
  let place: Placement;
  const lastId = scriptIds[scriptIds.length - 1];
  const keptLast = existingAt.get(lastId);
  if (END_DATE) place = endDatePlacement(END_DATE, now);
  else if (!RETIME && keptLast !== undefined) {
    const lastDay = ymdOf(keptLast);
    const unshifted = timeline({ lastDay, shiftMs: 0 });
    place = { lastDay, shiftMs: Math.max(0, unshifted[unshifted.length - 1].at - keptLast) };
  } else place = autoPlacement(now);
  const plan = timeline(place);
  validate(plan, now);

  const rows = plan.map((p, i) => ({ ...p, id: scriptIds[i] }));
  const scriptSet = new Set(scriptIds);
  const stale = existing.filter((m) => seedIds.includes(m.sender) && !scriptSet.has(m.id));
  if (stale.length) {
    console.warn(`  note: ${stale.length} older demo messages don't match conversation.ts (it was edited). Run with --reset to clear them.`);
  }

  // Insert what's missing. The hygiene trigger stamps created_at = now(), so
  // the real dates are set in a second pass below.
  const toInsert = rows.filter((r) => !existingAt.has(r.id));
  for (let i = 0; i < toInsert.length; i += INSERT_BATCH) {
    await api.req(
      "POST",
      "/rest/v1/messages?on_conflict=id",
      toInsert.slice(i, i + INSERT_BATCH).map((r) => ({ id: r.id, chat_id: chat.id, sender: users[r.sender], body: r.body })),
      "resolution=ignore-duplicates,return=minimal",
    );
  }
  console.log(`  inserted ${toInsert.length} messages (${rows.length - toInsert.length} already there)`);

  const toRetime = rows.filter((r) => existingAt.get(r.id) !== r.at);
  await pool(toRetime, PATCH_CONCURRENCY, async (r) => {
    await api.req("PATCH", `/rest/v1/messages?id=eq.${r.id}`, { created_at: new Date(r.at).toISOString() }, "return=minimal");
  });
  console.log(`  dated ${toRetime.length} messages`);

  if (PHOTOS) await addPhotos(api, url, key, chat.id, users, plan);

  // The chat must look older than its first message: a new member's read
  // cursor starts at chats.created_at, so this is what makes it all unread.
  const chatCreated = new Date(rows[0].at - 25 * 60_000).toISOString();
  const latest = await api.req<{ body: string; sender: string; created_at: string }[]>(
    "GET",
    `/rest/v1/messages?select=body,sender,created_at&chat_id=eq.${chat.id}&order=created_at.desc&limit=1`,
  );
  await api.req("PATCH", `/rest/v1/chats?id=eq.${chat.id}`, {
    created_at: chatCreated,
    last_message_at: latest[0]?.created_at ?? null,
    last_message_preview: latest[0] ? latest[0].body.slice(0, 140) : null,
    last_message_sender: latest[0]?.sender ?? null,
  }, "return=minimal");
  await api.req(
    "PATCH",
    `/rest/v1/chat_members?chat_id=eq.${chat.id}&user_id=in.${seedList}`,
    { joined_at: chatCreated, last_read_at: new Date(rows[rows.length - 1].at).toISOString() },
    "return=minimal",
  );

  // Anyone else in the chat (you): show, and optionally reset, their unread state.
  const others = members.filter((m) => !seedIds.includes(m.user_id));
  if (others.length) {
    const profiles = await api.req<{ id: string; display_name: string }[]>(
      "GET",
      `/rest/v1/profiles?select=id,display_name&id=in.(${others.map((o) => o.user_id).join(",")})`,
    );
    const nameOf = new Map(profiles.map((p) => [p.id, p.display_name]));
    const unreadFrom = REARM ? new Date(Date.parse(chatCreated) - 1).toISOString() : null;
    for (const o of others) {
      if (unreadFrom) {
        await api.req("PATCH", `/rest/v1/chat_members?chat_id=eq.${chat.id}&user_id=eq.${o.user_id}`, { last_read_at: unreadFrom }, "return=minimal");
        await api.req("DELETE", `/rest/v1/ai_briefs?chat_id=eq.${chat.id}&user_id=eq.${o.user_id}&kind=eq.catch_up`, undefined, "return=minimal");
      }
      const cursor = unreadFrom ?? o.last_read_at;
      const unread = await api.count("messages", `chat_id=eq.${chat.id}&created_at=gt.${enc(cursor)}&sender=neq.${o.user_id}`);
      const nm = nameOf.get(o.user_id) ?? o.user_id;
      const hint = unread === 0 && !REARM ? "  ← run with --rearm to make it unread again" : "";
      const nameHint = nm === VIEWER_NAME ? "" : `  (display name isn't "${VIEWER_NAME}", so "for you" items won't match)`;
      console.log(`  ${REARM ? "rearmed" : "member"} ${nm}: ${unread} unread${hint}${nameHint}`);
    }
  } else if (REARM) {
    console.log("  --rearm: nobody besides the demo friends has joined yet");
  }

  const after = await api.count("messages", `chat_id=eq.${chat.id}`);
  report(plan, place, now);
  console.log(`\nMessages in chat: ${before} → ${after}`);
  console.log(`\n  INVITE CODE:  ${chat.invite_code}\n`);
  console.log(`In the app: set your display name to "${VIEWER_NAME}", tap Join, enter ${chat.invite_code}, then Catch me up.`);
}

/** Where each photo goes: a few minutes after its script line. */
function photoTimes(plan: Planned[]) {
  return PHOTO_MESSAGES.map((p) => {
    const anchor = plan.findLast((line) => line.body === p.after);
    if (!anchor) throw new Error(`--photos: no script line "${p.after}" to put ${p.file} after`);
    return { ...p, at: anchor.at + p.minutes * 60_000 };
  });
}

/**
 * --photos: uploads each photo (full and small copy, named as the app names
 * them) to the private chat-media bucket, then adds its message and dates
 * it. Re-runs overwrite the files and skip the messages.
 */
async function addPhotos(api: Api, url: string, key: string, chatId: string, users: Record<Sender, string>, plan: Planned[]) {
  for (const p of photoTimes(plan)) {
    const id = await uuidv5(`${chatId}/photo/${p.file}`);
    const path = `${chatId}/${id}.jpg`;
    for (const [suffix, name] of [["", path], ["_small", `${chatId}/${id}_small.jpg`]]) {
      const bytes = await Deno.readFile(new URL(`./photos/${p.file}${suffix}.jpg`, import.meta.url));
      const res = await fetch(`${url}/storage/v1/object/chat-media/${name}`, {
        method: "POST",
        headers: {
          apikey: key,
          Authorization: `Bearer ${key}`,
          "Content-Type": "image/jpeg",
          "Cache-Control": "max-age=31536000, immutable",
          "x-upsert": "true",
        },
        body: bytes,
      });
      if (!res.ok) throw new Error(`upload ${p.file}${suffix} → ${res.status}: ${(await res.text()).slice(0, 200)}`);
      await res.body?.cancel();
    }
    await api.req(
      "POST",
      "/rest/v1/messages?on_conflict=id",
      [{ id, chat_id: chatId, sender: users[p.sender], body: p.caption, image_path: path,
         image_width: PHOTO_SIZE.width, image_height: PHOTO_SIZE.height }],
      "resolution=ignore-duplicates,return=minimal",
    );
    await api.req("PATCH", `/rest/v1/messages?id=eq.${id}`, { created_at: new Date(p.at).toISOString() }, "return=minimal");
    console.log(`  photo ${p.file.padEnd(9)} ${stamp(p.at)} from ${PEOPLE[p.sender].name}`);
  }
}

function parseYMD(s: string): YMD {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) throw new Error(`--end-date must be YYYY-MM-DD, got "${s}"`);
  return { y: +m[1], m: +m[2], d: +m[3] };
}

if (import.meta.main) {
  try {
    await main();
  } catch (e) {
    console.error(`\nSeed failed: ${e instanceof Error ? e.message : e}`);
    Deno.exit(1);
  }
}

