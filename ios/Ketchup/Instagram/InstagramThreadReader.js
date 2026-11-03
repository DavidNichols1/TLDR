// Ketchup's Instagram thread reader. EXPERIMENTAL, NOT RELEASED.
//
// This is the BODY of an async function, run with WKWebView's
// callAsyncJavaScript in Ketchup's own isolated JavaScript world
// (WKContentWorld.defaultClient), so the page's scripts can't see or change
// it. Arguments arrive as local variables: maxMessages, maxScrolls,
// readerName, debug. It returns a JSON string.
//
// When it runs: only after the user taps "Catch me up on this chat" on a DM
// thread (instagram.com/direct/t/...). It checks that again itself and does
// nothing anywhere else, so it never touches login pages. It never clicks,
// types or sends anything, and never reads cookies, storage or the network.
// Instagram only fills in the rows near the screen (the rest are empty
// placeholders), so it steps up through the thread a screen at a time,
// reading rows as Instagram fills them in. At the top of what's loaded
// Instagram fetches older messages itself, the way it does for a person; the
// reader lets that happen at most `maxScrolls` times, then puts the scroll
// position back.
//
// Instagram's class names are obfuscated and change often, so nothing here
// relies on them. It goes by what any browser exposes: ARIA roles and
// labels, dir="auto" text, computed styles (a bubble paints a background and
// has rounded corners) and geometry (left = them, right = me, centered =
// time stamps and notices).
//
// What it can't get:
// - Exact times. Instagram prints a time only at breaks in the conversation,
//   so each message carries the last time shown above it. English labels
//   only ("Today 3:41 PM", "Fri 8:30 PM", "Oct 28, 4:12 PM").
// - Anything older than what loads in `maxScrolls` fetches or ~28 seconds of
//   reading, and only the newest `maxMessages` are returned. No read cursor
//   either: the page has no "unread" marker, so this is the loaded thread,
//   not just what's new.
// - Media itself. Photos, videos, voice notes, GIFs and shared posts or reels
//   become placeholders like "[photo]"; a shared post keeps its caption.
//   View-once photos and videos can't be seen on the web at all
//   ("[view-once photo]").
// - Reactions, read receipts, typing, unsent messages and other notices
//   (left out on purpose), link-preview cards, and view-once or vanish-mode
//   messages that aren't rendered as text.
// - Display names, sometimes. A group shows a name label over each run of
//   messages; when a label isn't there, the sender comes from Instagram's
//   button labels ("React to message from <username>"), so it's a username.
//   With neither, it's "Someone". In a 1:1 thread the other person is named
//   after the thread title.

const MAX = Math.max(1, Math.min(Number(typeof maxMessages === "undefined" ? 300 : maxMessages) || 300, 600));
const SCROLLS = Math.max(0, Math.min(Number(typeof maxScrolls === "undefined" ? 6 : maxScrolls) || 0, 12));
const READER = typeof readerName === "string" && readerName.trim() ? readerName.trim() : "you";
const DEBUG = typeof debug !== "undefined" && debug === true;
const started = Date.now();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

if (!/(^|\.)instagram\.com$/.test(location.hostname) || !/^\/direct\/t\/[^/]+/.test(location.pathname)) {
  return JSON.stringify({ ok: false, error: "not_a_thread" });
}

// ---------------------------------------------------------------------------
// Text and time

const EMOJI_ONLY = /^(?=.*\p{Extended_Pictographic})[\p{Extended_Pictographic}\p{Emoji_Component}\u200d\ufe0f\s]+$/u;
const RECEIPT = /^(seen|sent|delivered|read)(\b|$)/i;
const REPLY_LABEL = /\breplied to\b/i;

/** Visible text of an element: <br> and block children become new lines,
 *  emoji drawn as small images keep their alt text. */
function textOf(el) {
  let out = "";
  const walk = (n) => {
    if (n.nodeType === Node.TEXT_NODE) { out += n.nodeValue; return; }
    if (n.nodeType !== Node.ELEMENT_NODE) return;
    const tag = n.tagName.toUpperCase();
    if (tag === "BR") { out += "\n"; return; }
    if (tag === "IMG") {
      const alt = n.getAttribute("alt") || "";
      if (alt && n.getBoundingClientRect().width <= 40) out += alt;
      return;
    }
    if (tag === "SCRIPT" || tag === "STYLE" || tag === "SVG" || tag === "VIDEO" || tag === "AUDIO") return;
    const display = getComputedStyle(n).display;
    if (display === "none") return;
    const block = display === "block" || display === "flex" || display === "list-item" || display === "grid";
    if (block && out && !out.endsWith("\n")) out += "\n";
    for (const c of n.childNodes) walk(c);
    if (block && out && !out.endsWith("\n")) out += "\n";
  };
  walk(el);
  return out.split("\n").map((l) => l.replace(/\s+/g, " ").trim()).filter(Boolean).join("\n");
}

// Every word of a separator label is one of these.
const DATE_WORD = /^(today|yesterday|at|[ap]\.?m\.?|(jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|may|june?|july?|aug(ust)?|sept?(ember)?|oct(ober)?|nov(ember)?|dec(ember)?)\.?|(sun(day)?|mon(day)?|tue(s|sday)?|wed(nesday)?|thu(r|rs|rsday)?|fri(day)?|sat(urday)?)\.?|\d{1,4}|\d{1,2}[:.]\d{2}([ap]\.?m\.?)?|\d{1,2}[ap]\.?m\.?|\d{1,2}\/\d{1,2}\/\d{2,4})$/;
const MONTHS = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11 };
const DAYS = { sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6 };

/** A time-separator label as a Date in the device's zone, or null. */
function parseStamp(raw) {
  const s = raw.toLowerCase().replace(/[,\u202f\u00a0]/g, " ").replace(/\bat\b/g, " ").replace(/\s+/g, " ").trim();
  if (!s || s.length > 40 || !s.split(" ").every((w) => DATE_WORD.test(w))) return null;
  let hour = null, minute = 0, m;
  if ((m = s.match(/\b(\d{1,2})[:.](\d{2})\s*([ap])\.?\s?m\b\.?/))) {
    hour = (+m[1] % 12) + (m[3] === "p" ? 12 : 0); minute = +m[2];
  } else if ((m = s.match(/\b(\d{1,2})\s*([ap])\.?\s?m\b\.?/))) {
    hour = (+m[1] % 12) + (m[2] === "p" ? 12 : 0);
  } else if ((m = s.match(/\b([01]?\d|2[0-3]):([0-5]\d)\b/))) {
    hour = +m[1]; minute = +m[2];
  }
  const now = new Date();
  const d = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let dated = false;
  if (/\btoday\b/.test(s)) {
    dated = true;
  } else if (/\byesterday\b/.test(s)) {
    d.setDate(d.getDate() - 1); dated = true;
  } else if ((m = s.match(/\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?![\d:.])(?:\s+(\d{4}))?\b/))) {
    d.setFullYear(m[3] ? +m[3] : now.getFullYear(), MONTHS[m[1]], +m[2]); dated = true;
    if (!m[3] && d > now) d.setFullYear(d.getFullYear() - 1);
  } else if ((m = s.match(/\b(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?(?:\s+(\d{4}))?\b/))) {
    d.setFullYear(m[3] ? +m[3] : now.getFullYear(), MONTHS[m[2]], +m[1]); dated = true;
    if (!m[3] && d > now) d.setFullYear(d.getFullYear() - 1);
  } else if ((m = s.match(/\b(\d{1,2})\/(\d{1,2})\/(\d{2}|\d{4})\b/))) {
    d.setFullYear(m[3].length === 2 ? 2000 + +m[3] : +m[3], +m[1] - 1, +m[2]); dated = true;
  } else if ((m = s.match(/\b(sun|mon|tue|wed|thu|fri|sat)[a-z]*\b/))) {
    const back = (d.getDay() - DAYS[m[1]] + 7) % 7 || 7;
    d.setDate(d.getDate() - back); dated = true;
  }
  if (!dated && hour === null) return null;
  d.setHours(hour === null ? 12 : hour, minute, 0, 0);
  return isNaN(d.getTime()) ? null : d;
}

// ---------------------------------------------------------------------------
// Finding the thread

function scrollable(el) {
  if (!el || el.scrollHeight <= el.clientHeight + 8) return false;
  return /(auto|scroll|overlay)/.test(getComputedStyle(el).overflowY);
}

function findRoot() {
  const labeled = [...document.querySelectorAll("[aria-label]")].find((el) =>
    /messages in conversation|conversation with/i.test(el.getAttribute("aria-label") || ""));
  if (labeled) return { root: labeled, how: "aria-label" };
  const grid = [...document.querySelectorAll('[role="grid"]')]
    .sort((a, b) => b.querySelectorAll('[dir="auto"]').length - a.querySelectorAll('[dir="auto"]').length)[0];
  if (grid && grid.querySelectorAll('[dir="auto"]').length >= 2) return { root: grid, how: "grid" };
  const scope = document.querySelector('[role="main"]') || document.body;
  const scrollers = [...scope.querySelectorAll("*")].filter(scrollable)
    .sort((a, b) => b.querySelectorAll('[dir="auto"]').length - a.querySelectorAll('[dir="auto"]').length);
  if (scrollers[0]) return { root: scrollers[0], how: "scroller" };
  return { root: scope, how: "main" };
}

function findScroller(root) {
  for (let n = root; n && n !== document.documentElement; n = n.parentElement) if (scrollable(n)) return n;
  const inner = [...root.querySelectorAll("*")].find(scrollable);
  if (inner) return inner;
  // Some layouts scroll the whole page instead of a list.
  const page = document.scrollingElement;
  return page && page.scrollHeight > window.innerHeight + 8 ? page : null;
}

function threadTitle(root, scroller) {
  const label = root.getAttribute("aria-label") || "";
  const m = label.match(/conversation with (.+)$/i);
  if (m && m[1].trim()) return m[1].trim();
  // The header above the message list: its biggest, boldest text.
  const top = (scroller && scroller !== document.scrollingElement ? scroller : root).getBoundingClientRect().top;
  let best = null, bestScore = 0;
  for (const el of document.querySelectorAll('h1, h2, [role="heading"], span[dir="auto"], div[dir="auto"]')) {
    if (root.contains(el) || el.closest('[contenteditable="true"], [role="textbox"]')) continue;
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.bottom > top + 2 || r.top < 0) continue;
    const t = textOf(el);
    if (!t || t.length > 80 || t.includes("\n")) continue;
    const cs = getComputedStyle(el);
    const score = parseFloat(cs.fontSize) * 10 + (parseInt(cs.fontWeight, 10) || 400) / 100;
    if (score > bestScore) { best = t; bestScore = score; }
  }
  if (best) return best;
  const doc = document.title.replace(/^\(\d+\)\s*/, "").replace(/\s*[•|·-]\s*(instagram|direct|chats?)\b.*$/i, "").trim();
  return /^(instagram|direct|chats?|inbox)$/i.test(doc) ? "" : doc;
}

// ---------------------------------------------------------------------------
// Reading what's rendered
//
// Instagram virtualizes the thread: only rows near the screen hold content,
// and every other row is an empty, invisible placeholder that keeps its
// height. So the reader steps up through the thread one screen at a time and
// keeps each row the first time it is filled in. Positions are measured up
// from the bottom of the list, which doesn't move when Instagram adds older
// messages on top, so rows read at different scroll positions line up.

function paints(cs) {
  const bg = cs.backgroundColor;
  const color = bg && bg !== "transparent" && !/rgba\([^)]*,\s*0(\.0+)?\)$/.test(bg);
  return color || (cs.backgroundImage && cs.backgroundImage !== "none");
}
const radius = (cs) => Math.max(parseFloat(cs.borderTopLeftRadius) || 0, parseFloat(cs.borderTopRightRadius) || 0,
  parseFloat(cs.borderBottomLeftRadius) || 0, parseFloat(cs.borderBottomRightRadius) || 0);
/** Where the text itself is drawn (a centered label in a full-width block is still centered). */
function textRect(el) {
  const range = document.createRange();
  range.selectNodeContents(el);
  const r = range.getBoundingClientRect();
  return r.width > 0 ? r : el.getBoundingClientRect();
}
const skipZone = (el) => el.closest('[contenteditable="true"], [role="textbox"], textarea, input, select, [role="progressbar"]');
const opacity = (el) => {
  const v = parseFloat(getComputedStyle(el).opacity);
  return isNaN(v) ? 1 : v;
};

/** The element whose children are the rows (one message or time stamp each). */
function findList(root) {
  let n = root;
  for (let depth = 0; depth < 12; depth++) {
    const kids = [...n.children].filter((c) => getComputedStyle(c).display !== "none");
    if (kids.length >= 6) return n;
    const next = kids.sort((a, b) => b.getElementsByTagName("*").length - a.getElementsByTagName("*").length)[0];
    if (!next || next.getElementsByTagName("*").length === 0) return n;
    n = next;
  }
  return n;
}

const rowsOf = (list) => (list.children.length >= 2 ? [...list.children] : [list]);
const filled = (row) => !!row.firstElementChild && opacity(row) > 0;

/** Who wrote a row, from Instagram's button labels ("React to message from
 *  <username>", "Open the profile page of <username>"). A username, not a
 *  display name. */
function userIn(row) {
  for (const el of [row, ...row.querySelectorAll("[aria-label]")]) {
    const m = (el.getAttribute("aria-label") || "").match(/\bmessage\s+\S+\s+(\S+)\s*$|\bprofile\s+\S+\s+of\s+(\S+)\s*$/i);
    if (m) return (m[1] || m[2]).trim();
  }
  return null;
}

/** The pieces of one row: loose text (labels, time stamps), bubbles (one
 *  message each) and avatars, with where they sit. */
function unitsIn(row, g) {
  const { box, base, centered, sideOf } = g;
  const user = userIn(row);
  const stop = row.parentElement;

  // The bubble around a text or media element: the nearest ancestor that
  // paints a background or clips, has rounded corners, and isn't full width.
  const bubbleOf = (el) => {
    for (let n = el, i = 0; n && n !== stop && i < 14; n = n.parentElement, i++) {
      const r = n.getBoundingClientRect();
      if (r.width > box.width * 0.92) return null;
      const cs = getComputedStyle(n);
      if (radius(cs) >= 6 && (paints(cs) || cs.overflow === "hidden" || cs.overflowX === "hidden")) return n;
    }
    return null;
  };
  const fadedOf = (el) => {
    let o = 1;
    for (let n = el, i = 0; n && n !== stop && i < 10; n = n.parentElement, i++) o *= opacity(n);
    return o < 0.9;
  };
  const isReaction = (el) => {
    const b = el.closest('[role="button"]');
    return !!b && row.contains(b) && /react/i.test(b.getAttribute("aria-label") || "");
  };

  // Leaves: outermost dir="auto" text (a row-sized dir="auto" wrapper mustn't
  // swallow what's inside it), media, avatars.
  const texts = [];
  const take = (els) => {
    for (const el of els) {
      const wide = el.getBoundingClientRect().width > box.width * 0.92 && el.querySelector('[dir="auto"]');
      if (wide) take([...el.querySelectorAll('[dir="auto"]')].filter((c) => c.parentElement.closest('[dir="auto"]') === el));
      else texts.push(el);
    }
  };
  if (g.plainText) {
    // A page without dir="auto": any element that holds text itself.
    texts.push(...[row, ...row.querySelectorAll("*")].filter((el) =>
      [...el.childNodes].some((c) => c.nodeType === Node.TEXT_NODE && c.nodeValue.trim())));
  } else if (row.matches('[dir="auto"]')) {
    take([row]);
  } else {
    take([...row.querySelectorAll('[dir="auto"]')].filter((el) => {
      const outer = el.parentElement.closest('[dir="auto"]');
      return !outer || !row.contains(outer);
    }));
  }

  const leaves = [];
  for (const el of texts) {
    if (skipZone(el) || isReaction(el)) continue;
    const text = textOf(el);
    const r = textRect(el);
    if (!text || r.width === 0 || r.height === 0) continue;
    if (/^edited$/i.test(text)) continue;
    leaves.push({ kind: "text", el, text, r, bubble: bubbleOf(el), size: parseFloat(getComputedStyle(el).fontSize) || 15 });
  }
  for (const el of row.querySelectorAll("img, video, audio, [role='button'][aria-label]")) {
    if (skipZone(el) || isReaction(el)) continue;
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) continue;
    const tag = el.tagName.toUpperCase();
    if (tag === "IMG") {
      const alt = el.getAttribute("alt") || "";
      const link = el.closest("a[aria-label]");
      const linked = link && row.contains(link) ? (link.getAttribute("aria-label") || "").match(/\bprofile\s+\S+\s+of\s+(\S+)\s*$/i) : null;
      const round = (n) => !!n && parseFloat(getComputedStyle(n).borderTopLeftRadius) >= r.width * 0.4;
      if (/profile[\s_-]?pic/i.test(alt) || linked || (r.width <= 48 && (round(el) || round(el.parentElement)))) {
        const name = linked ? linked[1] : /'s profile picture$/i.test(alt) ? alt.replace(/'s profile picture$/i, "").trim() : "";
        leaves.push({ kind: "avatar", el, r, name });
        continue;
      }
      if (r.width <= 40) continue; // inline emoji, read as text
      leaves.push({ kind: "media", el, r, bubble: bubbleOf(el), media: /\bgif\b/i.test(alt) ? "[GIF]" : /sticker/i.test(alt) ? "[sticker]" : "[photo]" });
    } else if (tag === "VIDEO") {
      leaves.push({ kind: "media", el, r, bubble: bubbleOf(el), media: "[video]" });
    } else if (tag === "AUDIO" || /^(play|pause)\b/i.test(el.getAttribute("aria-label") || "")) {
      leaves.push({ kind: "media", el, r, bubble: bubbleOf(el), media: "[voice message]" });
    }
  }

  // Everything inside one bubble is one message.
  const units = [];
  const byBubble = new Map();
  for (const leaf of leaves) {
    if (leaf.kind === "avatar") { units.push(leaf); continue; }
    if (!leaf.bubble) {
      if (leaf.kind === "media" && centered(leaf.r)) continue; // the big avatar atop a thread
      units.push(leaf.kind === "media" ? { kind: "message", el: leaf.el, r: leaf.r, texts: [], media: [leaf.media], leaves: [leaf] } : leaf);
      continue;
    }
    let u = byBubble.get(leaf.bubble);
    if (!u) {
      u = { kind: "message", el: leaf.bubble, r: leaf.bubble.getBoundingClientRect(), texts: [], media: [], leaves: [] };
      byBubble.set(leaf.bubble, u);
      units.push(u);
    }
    u.leaves.push(leaf);
    if (leaf.kind === "text") u.texts.push(leaf.text); else u.media.push(leaf.media);
  }
  for (const u of units) {
    if (u.kind !== "message") continue;
    const icons = [...u.el.querySelectorAll("svg[aria-label]")].map((s) => s.getAttribute("aria-label") || "");
    const once = icons.map((l) => l.match(/^this (photo|video)\b/i)).find(Boolean);
    const post = u.el.querySelector('a[href*="/p/"], a[href*="/reel/"]') || u.el.closest('a[href*="/p/"], a[href*="/reel/"]');
    if (once) {
      // "This photo/video can only be viewed once..." is Instagram's note, not the message.
      u.media = [`[view-once ${once[1].toLowerCase()}]`];
      u.texts = [];
    } else if (post || icons.some((l) => /^(clip|reel)$/i.test(l))) {
      u.media = [post && !/\/reel\//.test(post.getAttribute("href")) ? "[shared post]" : "[shared reel]"];
      u.texts = u.texts.filter((t, i) => !(i === 0 && /^[a-z0-9._]{1,30}$/i.test(t))); // the poster's username
    }
    if (u.media.includes("[video]")) u.media = u.media.filter((x) => x !== "[voice message]");
    u.text = [...new Set(u.media)].concat(u.texts.length ? [u.texts.join("\n")] : []).join(" ").trim();
    const sizes = u.leaves.filter((l) => l.kind === "text").map((l) => l.size);
    u.small = sizes.length > 0 && Math.max(...sizes) < 14;
    u.faded = fadedOf(u.el);
  }

  return units.map((u) => ({
    kind: u.kind,
    text: u.text,
    media: u.kind === "message" && u.media.length > 0,
    name: u.name,
    size: u.size,
    small: !!u.small,
    faded: !!u.faded,
    side: sideOf(u.r),
    centered: centered(u.r),
    topY: base - u.r.top,
    bottomY: base - u.r.bottom,
    user,
    order: g.order(),
  }));
}

/** Reads the rows filled in right now and keeps the ones not seen yet. */
function collect(ctx) {
  const box = ctx.root.getBoundingClientRect();
  const mid = box.left + box.width / 2;
  const g = {
    box,
    base: ctx.list.getBoundingClientRect().bottom,
    centered: (r) => Math.abs(r.left + r.width / 2 - mid) <= Math.max(20, box.width * 0.06) && r.width < box.width * 0.9,
    sideOf: (r) => (r.left - box.left > box.right - r.right ? "me" : "them"),
    plainText: ctx.plainText,
    order: () => ctx.order++,
  };
  for (const row of rowsOf(ctx.list)) {
    if (ctx.rows.has(row) || !filled(row)) continue;
    const units = unitsIn(row, g);
    if (units.length) ctx.rows.set(row, units);
  }
}

const isMessageUnit = (u) => u.kind === "message" || (u.kind === "text" && !u.centered && u.size > 13.5);
const messageCount = (ctx) => {
  let n = 0;
  for (const units of ctx.rows.values()) for (const u of units) if (isMessageUnit(u)) n++;
  return n;
};

/** Waits until every row on screen has been filled in (or gives up). */
async function settle(ctx, scroller) {
  for (let t = 0; t < 1500; t += 50) {
    await sleep(50);
    const view = scroller === document.scrollingElement
      ? { top: 0, bottom: window.innerHeight } : scroller.getBoundingClientRect();
    let pending = 0;
    for (const row of rowsOf(ctx.list)) {
      const b = row.getBoundingClientRect();
      if (b.height === 0 || b.bottom < view.top || b.top > view.bottom) continue;
      if (!filled(row)) pending++;
    }
    if (pending === 0) return;
  }
}

/** Turns the pieces, top to bottom, into messages with senders and times. */
function walk(all) {
  // A row Instagram re-created while we scrolled is read twice: same text, same place.
  const seen = new Set();
  const units = all.filter((u) => {
    const key = `${u.kind}|${u.text || u.name || ""}|${Math.round(u.topY / 3)}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }).sort((a, b) => (b.topY - a.topY) || (a.order - b.order));

  const out = [];
  const stats = { separators: 0, labels: 0, avatars: 0, media: 0, skipped: 0 };
  const names = new Map(); // username → the display name its label showed
  let at = null, atLabel = null, label = null, labelUser, reply = null;
  const after = (i) => {
    for (let j = i + 1; j < units.length; j++) if (units[j].kind !== "avatar") return units[j];
    return null;
  };

  for (let i = 0; i < units.length; i++) {
    const u = units[i];
    if (u.kind === "avatar") { stats.avatars++; continue; }
    let msg = null;
    if (u.kind === "text") {
      const t = u.text;
      const stamp = u.centered ? parseStamp(t) : null;
      if (stamp) { at = stamp.toISOString(); atLabel = t; stats.separators++; reply = null; continue; }
      if (RECEIPT.test(t) && t.length < 80) { stats.skipped++; continue; }
      if (REPLY_LABEL.test(t) && t.length < 120) {
        // "You replied to Maya", "Maya replied to you", "Jordan replied to Maya", "Replied to your story".
        const you = t.match(/^you replied to (.+)$/i);
        const by = t.match(/^(.+?) replied to (.+)$/i);
        const to = you ? you[1] : by ? by[2] : /your story/i.test(t) ? "your story" : "";
        reply = { to: /^you$/i.test(to) ? READER : to, quote: null };
        // Who is replying names the next message (not a group signal: 1:1 threads say it too).
        if (!you && by) { label = by[1].trim(); labelUser = undefined; }
        continue;
      }
      if (EMOJI_ONLY.test(t) && u.size >= 24) {
        msg = { side: u.side, text: t, small: false, user: u.user };
      } else if (u.centered) {
        stats.skipped++; // a notice ("Maya named the group"), or the thread-start header
        continue;
      } else {
        const next = after(i);
        if (u.size <= 13.5 && t.length <= 50 && u.side === "them" && next && next.side === "them" && u.bottomY - next.topY < 40) {
          label = t; labelUser = undefined; stats.labels++; reply = null;
          continue;
        }
        if (u.size <= 13.5) { stats.skipped++; continue; } // small loose text: a status line, not a message
        msg = { side: u.side, text: t, small: false, user: u.user }; // a message whose bubble we couldn't see
      }
    } else {
      if (!u.text) { stats.skipped++; continue; }
      if (u.media) stats.media++;
      msg = { side: u.side, text: u.text, small: u.small || u.faded, user: u.user };
    }

    if (reply && reply.quote === null && msg.small) { reply.quote = msg.text; continue; }
    let text = msg.text;
    if (reply) {
      const quote = reply.quote && reply.quote.length > 80 ? reply.quote.slice(0, 79) + "…" : reply.quote;
      text = quote === null ? `(replying to ${reply.to || "a message"}) ${text}`
        : `(replying to ${reply.to ? `${reply.to}: ` : ""}"${quote}") ${text}`;
      reply = null;
    }
    let sender = "";
    if (msg.side === "me") {
      label = null; labelUser = undefined;
    } else {
      // A name label covers its run. A different username without a new label means the run ended.
      if (label !== null && labelUser === undefined) {
        labelUser = msg.user || null;
        if (msg.user) names.set(msg.user, label);
      } else if (label !== null && msg.user && labelUser && msg.user !== labelUser) {
        label = null; labelUser = undefined;
      }
      sender = label !== null ? label : msg.user;
    }
    out.push({ sender, text, isMe: msg.side === "me", at, atLabel, user: msg.user, topY: u.topY, bottomY: u.bottomY });
  }

  // Usernames that a label later named get that display name everywhere.
  for (const m of out) if (!m.isMe && m.sender && m.sender === m.user && names.has(m.user)) m.sender = names.get(m.user);

  // Runs of their messages still unnamed: take the avatar next to the run.
  const avatars = units.filter((u) => u.kind === "avatar" && u.name && u.side === "them");
  for (let i = 0; i < out.length;) {
    if (out[i].isMe || out[i].sender) { i++; continue; }
    let j = i;
    while (j + 1 < out.length && !out[j + 1].isMe && !out[j + 1].sender) j++;
    const near = avatars.find((a) => a.topY > out[j].bottomY - 30 && a.bottomY < out[i].topY + 4);
    if (near) for (let k = i; k <= j; k++) out[k].sender = names.get(near.name) || near.name;
    i = j + 1;
  }
  stats.distinctAvatars = new Set(avatars.map((a) => a.name)).size;
  return { messages: out, stats };
}

// ---------------------------------------------------------------------------
// Step up through the thread (Instagram loads older messages when the top is
// reached), then put the scroll back where it was.

const BUDGET_MS = 28000;

try {
  const { root, how } = findRoot();
  const scroller = findScroller(root);
  const list = findList(root);
  const title = threadTitle(root, scroller);
  const ctx = { root, list, rows: new Map(), order: 0, plainText: !root.querySelector('[dir="auto"]') };
  const placeholders = rowsOf(list).filter((row) => !filled(row)).length;
  collect(ctx);
  let loads = 0, steps = 0, reachedStart = false, reversed = false;

  if (scroller) {
    reversed = scroller.scrollTop < 0 || getComputedStyle(scroller).flexDirection === "column-reverse";
    const fromBottom = reversed ? -scroller.scrollTop : scroller.scrollHeight - scroller.clientHeight - scroller.scrollTop;
    const step = Math.max(120, Math.round(scroller.clientHeight * 0.9));
    while (messageCount(ctx) < MAX && Date.now() - started < BUDGET_MS && steps < 250) {
      const before = scroller.scrollTop;
      scroller.scrollTop = before - step;
      if (scroller.scrollTop < 0) reversed = true;
      steps++;
      await settle(ctx, scroller);
      collect(ctx);
      if (Math.abs(scroller.scrollTop - before) >= 1) continue;
      // The top of what's loaded. Instagram fetches older messages on its own
      // when the top is reached; wait for that, at most `maxScrolls` times.
      if (loads >= SCROLLS) break;
      const height = scroller.scrollHeight;
      let grew = false;
      for (let waited = 0; waited < 3500 && !grew; waited += 150) {
        await sleep(150);
        grew = scroller.scrollHeight > height + 4;
      }
      if (!grew) { reachedStart = true; break; }
      loads++;
      await sleep(300 + Math.floor(Math.random() * 300)); // be gentle
      await settle(ctx, scroller);
      collect(ctx);
    }
    scroller.scrollTop = reversed ? -fromBottom : scroller.scrollHeight - scroller.clientHeight - fromBottom;
  }

  const { messages, stats } = walk([...ctx.rows.values()].flat());
  const named = new Set(messages.filter((m) => !m.isMe && m.sender).map((m) => m.sender));
  // Only group threads show name labels. A thread with none and only one
  // other person in it is 1:1: that person is named after the thread.
  const isGroup = stats.labels > 0 || named.size >= 2;
  for (const m of messages) {
    if (m.isMe) continue;
    if (!isGroup && title) m.sender = title;
    else if (!m.sender) m.sender = "Someone";
  }
  const truncated = messages.length > MAX;
  const kept = messages.slice(-MAX).map((m) => {
    const o = { sender: m.sender, text: m.text, isMe: m.isMe, at: m.at };
    if (DEBUG) o.atLabel = m.atLabel;
    return o;
  });

  return JSON.stringify({
    ok: true,
    title,
    isGroup,
    messages: kept,
    truncated,
    // Counts only, safe to log.
    stats: { root: how, scrolls: loads, steps, reachedStart, reversed, placeholders, rows: ctx.rows.size,
             found: messages.length, named: named.size, separators: stats.separators, labels: stats.labels,
             avatars: stats.avatars, media: stats.media, skipped: stats.skipped, ms: Date.now() - started },
  });
} catch (e) {
  return JSON.stringify({ ok: false, error: "read_failed", detail: String(e && e.name || e) });
}
