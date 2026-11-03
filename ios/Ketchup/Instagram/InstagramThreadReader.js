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
// It reads what Instagram has already rendered, scrolls the thread up a few
// times (with pauses) so Instagram loads older messages the way it does for
// a person, then puts the scroll position back.
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
// - Anything older than what loads in `maxScrolls` scroll-ups, and only the
//   newest `maxMessages` are returned. No read cursor either: the page has no
//   "unread" marker, so this is the loaded thread, not just what's new.
// - Media itself. Photos, videos, voice notes, GIFs and shared posts become
//   placeholders like "[photo]"; a shared post keeps its caption.
// - Reactions, read receipts, typing, unsent messages and other notices
//   (left out on purpose), link-preview cards, and view-once or vanish-mode
//   messages that aren't rendered as text.
// - A sender's name when Instagram shows neither a name label nor an avatar
//   for a run of messages in a group ("Someone"). In a 1:1 thread the other
//   person is named after the thread title.

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

/** Reads the thread as it is on screen right now, oldest first. */
function readThread(root) {
  const box = root.getBoundingClientRect();
  const mid = box.left + box.width / 2;
  const centered = (r) => Math.abs(r.left + r.width / 2 - mid) <= Math.max(20, box.width * 0.06) && r.width < box.width * 0.9;
  const sideOf = (r) => (r.left - box.left > box.right - r.right ? "me" : "them");

  // The bubble around a text or media element: the nearest ancestor that
  // paints a background or clips, has rounded corners, and isn't full width.
  const bubbleOf = (el) => {
    for (let n = el, i = 0; n && n !== root && i < 12; n = n.parentElement, i++) {
      const r = n.getBoundingClientRect();
      if (r.width > box.width * 0.92) return null;
      const cs = getComputedStyle(n);
      if (radius(cs) >= 6 && (paints(cs) || cs.overflow === "hidden" || cs.overflowX === "hidden")) return n;
    }
    return null;
  };
  const opacityOf = (el) => {
    let o = 1;
    for (let n = el, i = 0; n && n !== root && i < 10; n = n.parentElement, i++) o *= parseFloat(getComputedStyle(n).opacity) || 1;
    return o;
  };
  const isReaction = (el) => {
    const b = el.closest('[role="button"]');
    return !!b && root.contains(b) && /react/i.test(b.getAttribute("aria-label") || "");
  };

  // 1. Leaves: outermost dir="auto" text, plus media and avatars.
  const leaves = [];
  // A row-sized wrapper that is itself dir="auto" mustn't swallow the messages inside it.
  let texts = [];
  const take = (els) => {
    for (const el of els) {
      const wide = el.getBoundingClientRect().width > box.width * 0.92 && el.querySelector('[dir="auto"]');
      if (wide) take([...el.querySelectorAll('[dir="auto"]')].filter((c) => c.parentElement.closest('[dir="auto"]') === el));
      else texts.push(el);
    }
  };
  take([...root.querySelectorAll('[dir="auto"]')].filter((el) => {
    const outer = el.parentElement.closest('[dir="auto"]');
    return !outer || outer === root || !root.contains(outer);
  }));
  if (texts.length < 2) {
    // No dir="auto" markup: fall back to any element that holds text itself.
    texts = [...root.querySelectorAll("*")].filter((el) =>
      [...el.childNodes].some((c) => c.nodeType === Node.TEXT_NODE && c.nodeValue.trim()));
  }
  for (const el of texts) {
    if (skipZone(el) || isReaction(el)) continue;
    const text = textOf(el);
    const r = textRect(el);
    if (!text || r.width === 0 || r.height === 0) continue;
    if (/^edited$/i.test(text)) continue;
    leaves.push({ kind: "text", el, text, r, bubble: bubbleOf(el), size: parseFloat(getComputedStyle(el).fontSize) || 15 });
  }
  for (const el of root.querySelectorAll("img, video, audio, [role='button'][aria-label]")) {
    if (skipZone(el) || isReaction(el)) continue;
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) continue;
    const tag = el.tagName.toUpperCase();
    if (tag === "IMG") {
      const alt = el.getAttribute("alt") || "";
      const round = parseFloat(getComputedStyle(el).borderTopLeftRadius) >= r.width * 0.4;
      if (/profile picture/i.test(alt) || (r.width <= 48 && round)) {
        leaves.push({ kind: "avatar", el, r, name: alt.replace(/'s profile picture$/i, "").trim() });
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

  // 2. Messages: everything inside one bubble is one message.
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
    const post = u.el.querySelector('a[href*="/p/"], a[href*="/reel/"]') || u.el.closest('a[href*="/p/"], a[href*="/reel/"]');
    if (post) {
      const caption = u.texts.filter((t, i) => !(i === 0 && /^[a-z0-9._]{1,30}$/i.test(t)));
      u.media = [/\/reel\//.test(post.getAttribute("href")) ? "[shared reel]" : "[shared post]"];
      u.texts = caption;
    }
    if (u.media.includes("[video]")) u.media = u.media.filter((x) => x !== "[voice message]");
    u.text = [...new Set(u.media)].concat(u.texts.length ? [u.texts.join("\n")] : []).join(" ").trim();
    u.small = u.leaves.some((l) => l.kind === "text") && Math.max(...u.leaves.filter((l) => l.kind === "text").map((l) => l.size)) < 14;
  }

  // 3. Walk top to bottom.
  const order = new Map(units.map((u, i) => [u, i]));
  units.sort((a, b) => (a.r.top - b.r.top) || (order.get(a) - order.get(b)));
  const out = [];
  const stats = { separators: 0, labels: 0, avatars: 0, media: 0, skipped: 0 };
  let at = null, atLabel = null, sender = null, reply = null;

  const nextMessage = (i) => {
    for (let j = i + 1; j < units.length; j++) if (units[j].kind === "message" || units[j].kind === "text") return units[j];
    return null;
  };

  for (let i = 0; i < units.length; i++) {
    const u = units[i];
    if (u.kind === "avatar") { stats.avatars++; continue; }
    let msg = null;
    if (u.kind === "text") {
      const t = u.text;
      const stamp = centered(u.r) ? parseStamp(t) : null;
      if (stamp) { at = stamp.toISOString(); atLabel = t; stats.separators++; reply = null; continue; }
      if (RECEIPT.test(t) && t.length < 80) { stats.skipped++; continue; }
      if (REPLY_LABEL.test(t) && t.length < 120) {
        // "You replied to Maya", "Maya replied to you", "Jordan replied to Maya", "Replied to your story".
        const you = t.match(/^you replied to (.+)$/i);
        const by = t.match(/^(.+?) replied to (.+)$/i);
        const to = you ? you[1] : by ? by[2] : /your story/i.test(t) ? "your story" : "";
        reply = { to: /^you$/i.test(to) ? READER : to, quote: null };
        // Who is replying names the next message (not a group signal: 1:1 threads say it too).
        if (!you && by) sender = by[1].trim();
        continue;
      }
      if (EMOJI_ONLY.test(t) && u.size >= 24) {
        msg = { side: sideOf(u.r), text: t, small: false, el: u.el };
      } else if (centered(u.r)) {
        stats.skipped++; // a notice ("Maya named the group"), or the thread-start header
        continue;
      } else {
        const next = nextMessage(i);
        const nextSide = next ? sideOf(next.r) : null;
        if (u.size <= 13.5 && t.length <= 50 && sideOf(u.r) === "them" && nextSide === "them" && next.r.top - u.r.bottom < 40) {
          sender = t; stats.labels++; reply = null;
          continue;
        }
        if (u.size <= 13.5) { stats.skipped++; continue; } // small loose text: a status line, not a message
        msg = { side: sideOf(u.r), text: t, small: false, el: u.el }; // a message whose bubble we couldn't see
      }
    } else {
      if (!u.text) { stats.skipped++; continue; }
      if (u.media.length) stats.media++;
      msg = { side: sideOf(u.r), text: u.text, small: u.small || opacityOf(u.el) < 0.9, el: u.el };
    }

    if (reply && reply.quote === null && msg.small) { reply.quote = msg.text; continue; }
    let text = msg.text;
    if (reply) {
      const quote = reply.quote && reply.quote.length > 80 ? reply.quote.slice(0, 79) + "…" : reply.quote;
      text = quote === null ? `(replying to ${reply.to || "a message"}) ${text}`
        : `(replying to ${reply.to ? `${reply.to}: ` : ""}"${quote}") ${text}`;
      reply = null;
    }
    if (msg.side === "me") sender = null;
    out.push({ sender: msg.side === "me" ? "" : sender, text, isMe: msg.side === "me", at, atLabel, el: msg.el, r: u.r });
  }

  // 4. Runs of their messages with no name label: take the avatar next to the run.
  const avatars = units.filter((u) => u.kind === "avatar" && u.name && sideOf(u.r) === "them");
  for (let i = 0; i < out.length;) {
    if (out[i].isMe || out[i].sender) { i++; continue; }
    let j = i;
    while (j + 1 < out.length && !out[j + 1].isMe && !out[j + 1].sender) j++;
    const top = out[i].r.top, bottom = out[j].r.bottom;
    const near = avatars.find((a) => a.r.top < bottom + 30 && a.r.bottom > top - 4);
    if (near) for (let k = i; k <= j; k++) out[k].sender = near.name;
    i = j + 1;
  }
  stats.distinctAvatars = new Set(avatars.map((a) => a.name)).size;
  return { messages: out, stats };
}

// ---------------------------------------------------------------------------
// Scroll up for older messages, then put the thread back where it was.

try {
  const { root, how } = findRoot();
  const scroller = findScroller(root);
  const title = threadTitle(root, scroller);
  let snapshot = readThread(root);
  const firstEls = snapshot.messages.map((m) => m.el);
  const snapshots = [snapshot];
  let scrolls = 0, reachedStart = false, reversed = false;

  if (scroller && SCROLLS > 0) {
    reversed = scroller.scrollTop < 0 || getComputedStyle(scroller).flexDirection === "column-reverse";
    const fromBottom = reversed ? -scroller.scrollTop : scroller.scrollHeight - scroller.clientHeight - scroller.scrollTop;
    const size = () => scroller.scrollHeight + root.querySelectorAll('[dir="auto"], img, video').length;
    while (scrolls < SCROLLS && snapshot.messages.length < MAX) {
      const before = size();
      scroller.scrollTop = -1e9; // the oldest end, for top-down and bottom-up (column-reverse) lists alike
      if (scroller.scrollTop < 0) reversed = true;
      scrolls++;
      let grew = false;
      for (let waited = 0; waited < 3000 && !grew; waited += 150) {
        await sleep(150);
        grew = size() > before;
      }
      if (!grew) { reachedStart = true; break; }
      await sleep(500 + Math.floor(Math.random() * 300)); // let it settle; be gentle
      snapshot = readThread(root);
      snapshots.push(snapshot);
    }
    scroller.scrollTop = reversed ? -fromBottom : scroller.scrollHeight - scroller.clientHeight - fromBottom;
  }

  // A list that unmounts what scrolled away (virtualized) loses the newest
  // messages from the last read: stitch the reads together instead.
  let messages = snapshots[snapshots.length - 1].messages;
  const virtualized = firstEls.some((el) => !el.isConnected);
  if (virtualized) {
    const seen = new Set();
    messages = [];
    for (const snap of [...snapshots].reverse()) {
      for (const m of snap.messages) if (!seen.has(m.el)) { seen.add(m.el); messages.push(m); }
    }
  }

  const stats = snapshots[snapshots.length - 1].stats;
  const named = messages.filter((m) => !m.isMe && m.sender);
  const isGroup = stats.labels > 0 || stats.distinctAvatars >= 2;
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
    stats: { root: how, scrolls, reachedStart, reversed, virtualized, found: messages.length, named: named.length,
             separators: stats.separators, labels: stats.labels, avatars: stats.avatars, media: stats.media,
             skipped: stats.skipped, ms: Date.now() - started },
  });
} catch (e) {
  return JSON.stringify({ ok: false, error: "read_failed", detail: String(e && e.name || e) });
}
