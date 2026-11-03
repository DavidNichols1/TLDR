// Ketchup's Snapchat chat reader. EXPERIMENTAL, NOT RELEASED.
//
// This is the BODY of an async function, run with WKWebView's
// callAsyncJavaScript in Ketchup's own isolated JavaScript world
// (WKContentWorld.defaultClient), so the page's scripts can't see or change
// it. Arguments arrive as local variables: maxMessages, maxScrolls,
// readerName, debug. It returns a JSON string, the same shape as the
// Instagram reader's.
//
// When it runs: only after the user picks how much to catch up on, on a
// Snapchat for Web chat (www.snapchat.com/web/<id>). It checks that again
// itself and does nothing anywhere else, so it never touches sign-in pages.
// It never clicks, types or sends anything, and never reads cookies,
// storage or the network. Snapchat loads older messages when the top of the
// chat is reached, the way it does for a person; the reader lets that
// happen at most `maxScrolls` times, then puts the scroll position back.
//
// Snapchat's class names are generated and change, so nothing here relies
// on them. It goes by the page's structure: the chat is a scrolling list of
// rows; a row is a day pill (a <time>), a notice (a small grey pill), or a
// run of one sender's messages (a list whose first item has a <header> with
// the sender's name and a <time>). Each message is the box with the
// sender's colored left bar, its text in dir="auto" spans. A reply holds the
// message it quotes in a painted card with a list of its own.
//
// What it can't get:
// - Exact times. Snapchat prints a time on each run of a sender's messages
//   and a pill for each day, so a message carries its run's time. English
//   labels only ("November 3", "Today", "1:07 AM").
// - Media itself. Photos, videos, stickers and voice notes become
//   placeholders like "[photo]"; a photo or video Snapchat hasn't loaded yet
//   is "[photo or video]". Snaps themselves never show on the web.
// - Reactions, notices (saved, screenshots, joins), call cards and link
//   previews, left out on purpose. Chats Snapchat already deleted are gone.
// - Anything older than what loads in `maxScrolls` fetches or ~45 seconds,
//   and only the newest `maxMessages` are returned. No read cursor either:
//   this is the loaded chat, not just what's new.

const MAX = Math.max(1, Math.min(Number(typeof maxMessages === "undefined" ? 300 : maxMessages) || 300, 600));
const SCROLLS = Math.max(0, Math.min(Number(typeof maxScrolls === "undefined" ? 6 : maxScrolls) || 0, 12));
const READER = typeof readerName === "string" && readerName.trim() ? readerName.trim() : "you";
const DEBUG = typeof debug !== "undefined" && debug === true;
const BUDGET_MS = 45000;
const started = Date.now();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

if (location.hostname !== "www.snapchat.com" || !/^\/web\/[^/]+/.test(location.pathname)) {
  return JSON.stringify({ ok: false, error: "not_a_thread" });
}

// ---------------------------------------------------------------------------
// Text and time

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

// Every word of a day or time label is one of these.
const DATE_WORD = /^(today|yesterday|at|[ap]\.?m\.?|(jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|may|june?|july?|aug(ust)?|sept?(ember)?|oct(ober)?|nov(ember)?|dec(ember)?)\.?|(sun(day)?|mon(day)?|tue(s|sday)?|wed(nesday)?|thu(r|rs|rsday)?|fri(day)?|sat(urday)?)\.?|\d{1,4}|\d{1,2}[:.]\d{2}([ap]\.?m\.?)?|\d{1,2}[ap]\.?m\.?|\d{1,2}\/\d{1,2}\/\d{2,4})$/;
const MONTHS = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11 };
const DAYS = { sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6 };

/** A day or time label as a Date in the device's zone, or null. A day with
 *  no time is noon; a time with no day is today. */
function parseStamp(raw) {
  const s = raw.toLowerCase().replace(/[,\s]+/g, " ").replace(/\bat\b/g, " ").replace(/\s+/g, " ").trim();
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
  } else if ((m = s.match(/\b(\d{1,2})\/(\d{1,2})\/(\d{2}|\d{4})\b/))) {
    d.setFullYear(m[3].length === 2 ? 2000 + +m[3] : +m[3], +m[1] - 1, +m[2]); dated = true;
  } else if ((m = s.match(/\b(sun|mon|tue|wed|thu|fri|sat)[a-z]*\b/))) {
    const back = (d.getDay() - DAYS[m[1]] + 7) % 7 || 7;
    d.setDate(d.getDate() - back); dated = true;
  }
  if (!dated && hour === null) return null;
  d.setHours(hour === null ? 12 : hour, minute, 0, 0);
  if (!dated && d > now) d.setDate(d.getDate() - 1);
  return isNaN(d.getTime()) ? null : d;
}

/** A run's time on the last day pill above it. */
function stampOn(day, timeLabel) {
  const t = timeLabel ? parseStamp(timeLabel) : null;
  if (!day) return t;
  if (!t) return day;
  const d = new Date(day);
  d.setHours(t.getHours(), t.getMinutes(), 0, 0);
  return d;
}

// ---------------------------------------------------------------------------
// Finding the chat

function scrollable(el) {
  if (!el || el.scrollHeight <= el.clientHeight + 8) return false;
  return /(auto|scroll|overlay)/.test(getComputedStyle(el).overflowY);
}

/** The chat's list: the one whose rows hold the most sender headers, and
 *  whatever scrolls it (a short chat may not scroll at all). */
function findList() {
  let list = null, most = 0;
  for (const el of document.querySelectorAll("ul, ol")) {
    const n = el.querySelectorAll(":scope > li header").length;
    if (n > most && el.querySelector("time")) { list = el; most = n; }
  }
  if (!list) return null;
  let scroller = list;
  while (scroller && scroller !== document.body && !scrollable(scroller)) scroller = scroller.parentElement;
  return { list, scroller: scroller && scroller !== document.body ? scroller : list };
}

/** The chat's name: the boldest dir="auto" text in the bar above the list. */
function titleOf(list) {
  const box = list.getBoundingClientRect();
  for (let pane = list.parentElement; pane && pane !== document.documentElement; pane = pane.parentElement) {
    const found = [...pane.querySelectorAll('[dir="auto"]')].filter((el) => {
      const r = el.getBoundingClientRect();
      const mid = r.left + r.width / 2;
      return !list.contains(el) && r.width > 0 && r.bottom <= box.top + 2 && mid >= box.left && mid <= box.right && textOf(el);
    });
    if (found.length) {
      const weight = (el) => parseInt(getComputedStyle(el).fontWeight, 10) || 400;
      found.sort((a, b) => weight(b) - weight(a) || a.getBoundingClientRect().top - b.getBoundingClientRect().top);
      return textOf(found[0]).split("\n")[0];
    }
  }
  return "";
}

const painted = (el) => {
  const cs = getComputedStyle(el);
  return cs.backgroundImage !== "none" || !/rgba\([^)]*,\s*0\)$|transparent/.test(cs.backgroundColor);
};

/** The sender's name in a run's header: its text, minus the time. */
function senderOf(header) {
  for (const c of header.children) {
    if (c.tagName === "TIME" || c.querySelector("time")) continue;
    const t = textOf(c);
    if (t) return t.split("\n")[0];
  }
  return "";
}

/** A message's media, when it has no text of its own. */
function mediaOf(body, card) {
  const mine = (n) => !(card && card.contains(n));
  if ([...body.querySelectorAll("video")].some(mine)) return "[video]";
  if ([...body.querySelectorAll("audio")].some(mine)) return "[voice message]";
  const img = [...body.querySelectorAll("img")].filter(mine).find((i) => {
    const r = i.getBoundingClientRect();
    return r.width > 40 && r.height > 40;
  });
  if (img) {
    const r = img.getBoundingClientRect();
    return Math.max(r.width, r.height) <= 200 ? "[sticker]" : "[photo]";
  }
  // A painted box with nothing in it yet: Snapchat loads the photo or video when it's seen.
  const box = [...body.querySelectorAll("div")].filter(mine)
    .find((d) => painted(d) && d.getBoundingClientRect().height > 100 && !textOf(d));
  return box ? "[photo or video]" : null;
}

/** One message's text, or null for something that isn't one (a call card). */
function messageOf(item) {
  const body = [...item.children].find((c) => c.tagName !== "HEADER" && c.tagName !== "UL" && c.tagName !== "OL");
  if (!body) return null;
  // A reply: the quoted message sits in a painted card with a list of its own.
  let card = null, quote = null;
  const quoted = body.querySelector("ul, ol");
  if (quoted) {
    card = quoted.parentElement;
    for (let c = quoted.parentElement; c && c !== body; c = c.parentElement) {
      if (painted(c)) { card = c; break; }
    }
    let to = "";
    for (const c of card.children) {
      if (c === quoted || c.contains(quoted)) break;
      const t = textOf(c);
      if (t) { to = t.split("\n")[0]; break; }
    }
    if (/^me$/i.test(to)) to = READER;
    const spans = [...quoted.querySelectorAll('span[dir="auto"]')].filter((s) => !s.parentElement.closest('span[dir="auto"]'));
    const said = spans.map(textOf).filter(Boolean).join(" ") || mediaOf(quoted, null) || "";
    quote = { to, said: said.replace(/\s+/g, " ").slice(0, 200) };
  }
  // Its own words: the dir="auto" spans outside the quote, not inside another one.
  const own = [...body.querySelectorAll('span[dir="auto"]')]
    .filter((s) => !(card && card.contains(s)) && !s.parentElement.closest('span[dir="auto"]'));
  let text = own.map(textOf).filter(Boolean).join("\n");
  let media = false;
  if (!text) {
    text = mediaOf(body, card) || "";
    media = Boolean(text);
  }
  if (!text && !quote) return null;
  if (quote) {
    const lead = quote.said ? `(replying to ${quote.to ? `${quote.to}: ` : ""}"${quote.said}")` : `(replying to ${quote.to || "a message"})`;
    text = text ? `${lead} ${text}` : lead;
  }
  return { text, media, quote: Boolean(quote) };
}

/** Everything on the page, oldest first, with counts. */
function readAll(list) {
  const messages = [];
  const stats = { rows: 0, units: 0, separators: 0, runs: 0, notices: 0, skipped: 0, empty: 0, media: 0, quotes: 0 };
  let day = null, dayLabel = null;
  for (const row of list.children) {
    stats.rows++;
    if (row.getBoundingClientRect().height < 1) continue;
    const headers = [...row.querySelectorAll("header")];
    if (!headers.length) {
      // A day pill: a <time> that reads as a date. Anything else is a notice.
      const time = row.querySelector("time");
      const label = time ? textOf(time) : "";
      const d = label ? parseStamp(label) : null;
      if (d) { day = d; dayLabel = label; stats.separators++; }
      else if (textOf(row)) stats.notices++;
      continue;
    }
    for (const header of headers) {
      const first = header.parentElement; // the run's first item
      if (!first) continue;
      stats.runs++;
      const name = senderOf(header);
      const isMe = /^me$/i.test(name);
      const timeEl = header.querySelector("time");
      const timeLabel = timeEl ? textOf(timeEl) : "";
      const stamp = stampOn(day, timeLabel);
      const atLabel = [dayLabel, timeLabel].filter(Boolean).join(", ") || null;
      for (let item = first; item; item = item.nextElementSibling) {
        if (item !== first && item.querySelector("header")) break; // the next sender's run
        stats.units++;
        const msg = messageOf(item);
        if (!msg) { stats.skipped++; continue; }
        if (!msg.text.trim()) { stats.empty++; continue; }
        if (msg.media) stats.media++;
        if (msg.quote) stats.quotes++;
        messages.push({ sender: isMe ? READER : name, text: msg.text, isMe, at: stamp ? stamp.toISOString() : null, atLabel });
      }
    }
  }
  return { messages, stats };
}

// ---------------------------------------------------------------------------
// Reading

try {
  const found = findList();
  if (!found) return JSON.stringify({ ok: false, error: "read_failed", detail: "no-list" });
  const { scroller, list } = found;
  const title = titleOf(list);
  let loads = 0, steps = 0, reachedStart = false, stop = "enough";
  const fromBottom = scroller.scrollHeight - scroller.clientHeight - scroller.scrollTop;
  for (;;) {
    if (readAll(list).messages.length >= MAX + 2) { stop = "enough"; break; }
    if (!scrollable(scroller)) { reachedStart = true; stop = "start"; break; }
    if (Date.now() - started >= BUDGET_MS) { stop = "budget"; break; }
    if (loads >= SCROLLS) { stop = "loads"; break; }
    // The top of what's loaded: Snapchat fetches older messages itself.
    const height = scroller.scrollHeight, rows = list.children.length;
    scroller.scrollTop = 0;
    steps++;
    let grew = false;
    for (let waited = 0; waited < 5000 && !grew; waited += 150) {
      await sleep(150);
      grew = scroller.scrollHeight > height + 4 || list.children.length > rows;
    }
    if (!grew) { reachedStart = true; stop = "start"; break; }
    loads++;
    await sleep(300 + Math.floor(Math.random() * 300)); // be gentle
  }
  if (steps) scroller.scrollTop = scroller.scrollHeight - scroller.clientHeight - fromBottom;

  const { messages, stats } = readAll(list);
  const named = new Set(messages.filter((m) => !m.isMe && m.sender).map((m) => m.sender));
  const isGroup = named.size >= 2;
  for (const m of messages) if (!m.isMe && !m.sender) m.sender = isGroup || !title ? "Someone" : title;
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
    stats: { root: "scroller", stop, scrolls: loads, steps, gaps: 0, reachedStart, placeholders: 0, rows: stats.rows,
             units: stats.units, found: messages.length, named: named.size, separators: stats.separators,
             runs: stats.runs, notices: stats.notices, media: stats.media, quotes: stats.quotes,
             skipped: stats.skipped, empty: stats.empty, dupes: 0, ms: Date.now() - started },
  });
} catch (e) {
  return JSON.stringify({ ok: false, error: "read_failed", detail: String(e && e.name || e) });
}
