// DEBUG builds only (InstagramCatchUpScreen's "…" menu). A redacted outline of
// an Instagram DM thread page, for tuning InstagramThreadReader.js against the
// real site: tags, roles, labels (names masked), dir, bubble styles, font
// sizes and positions. No message text: every text becomes its length and a
// kind, except time separators. Same rules as the reader: runs only on tap,
// only on instagram.com/direct/, in Ketchup's isolated world.

if (!/(^|\.)instagram\.com$/.test(location.hostname) || !location.pathname.startsWith("/direct/")) {
  return "not an Instagram DM page";
}

const KEEP = /^(messages?|conversation|in|with|seen|by|sent|delivered|like|liked|reply|replied|react|reactions?|see|who|reacted|to|this|play|pause|video|audio|photo|call|back|more|options|typing|information|send|voice|clip|emoji|gif|sticker|unsend|forward|copy|edit|edited|load|loading|older|new|you|your|the|a|an|and|of|on|at|for|open|close|view|profile|picture|today|yesterday)$/i;
const mask = (s) => s.split(/(\s+)/).map((w) => (/^\s+$/.test(w) || KEEP.test(w.replace(/[^\p{L}]/gu, "")) ? w : w.replace(/[\p{L}\p{N}]/gu, "x"))).join("");
// A time separator is kept only if every word is a date or time word and it
// sits centered, so a message like "Saturday 6am works" is never kept.
const DATE_WORD = /^(today|yesterday|at|[ap]\.?m\.?|(jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|may|june?|july?|aug(ust)?|sept?(ember)?|oct(ober)?|nov(ember)?|dec(ember)?)\.?|(sun(day)?|mon(day)?|tue(s|sday)?|wed(nesday)?|thu(r|rs|rsday)?|fri(day)?|sat(urday)?)\.?|\d{1,4}|\d{1,2}[:.]\d{2}([ap]\.?m\.?)?|\d{1,2}[ap]\.?m\.?|\d{1,2}\/\d{1,2}\/\d{2,4})$/i;
const isTime = (t, r) => t.length <= 40 && Math.abs(r.left + r.width / 2 - (box.left + box.width / 2)) < box.width * 0.06 &&
  t.replace(/,/g, " ").trim().split(/\s+/).every((w) => DATE_WORD.test(w));
const kind = (t) => /^[\d\s:.,]+$/.test(t) ? "digits" : /^[\p{Extended_Pictographic}\p{Emoji_Component}\s]+$/u.test(t) ? "emoji" : "text";

const main = document.querySelector('[role="main"]') || document.body;
const box = main.getBoundingClientRect();
const lines = [`page ${location.pathname.replace(/\/t\/[^/]+/, "/t/<id>")} · main ${Math.round(box.width)}x${Math.round(box.height)} · title ${JSON.stringify(mask(document.title))}`];
const pos = (r) => {
  const c = r.left + r.width / 2 - (box.left + box.width / 2);
  const side = Math.abs(c) < box.width * 0.06 ? "C" : c < 0 ? "L" : "R";
  return `${side} x${Math.round(r.left - box.left)} y${Math.round(r.top - box.top)} ${Math.round(r.width)}x${Math.round(r.height)}`;
};

const walk = (el, depth) => {
  if (lines.length > 2500) return;
  const cs = getComputedStyle(el);
  if (cs.display === "none") return;
  const tag = el.tagName.toLowerCase();
  const attrs = [];
  for (const a of ["role", "aria-label", "aria-hidden", "dir", "contenteditable", "tabindex", "data-scope", "data-testid"]) {
    const v = el.getAttribute(a);
    if (v !== null) attrs.push(`${a}=${JSON.stringify(a === "aria-label" ? mask(v) : v.slice(0, 40))}`);
  }
  if (tag === "a") attrs.push(`href=${JSON.stringify((el.getAttribute("href") || "").replace(/[^/?=&]+/g, (p) => (/^(p|reel|stories|direct|t)$/.test(p) ? p : "x")).slice(0, 40))}`);
  if (tag === "img") attrs.push(`alt=${JSON.stringify(mask(el.getAttribute("alt") || ""))}`);
  const bg = cs.backgroundImage !== "none" ? "gradient" : (cs.backgroundColor && !/rgba\([^)]*,\s*0\)$|transparent/.test(cs.backgroundColor) ? cs.backgroundColor : "");
  const radius = Math.round(parseFloat(cs.borderTopLeftRadius) || 0);
  const style = [bg && `bg=${bg}`, radius && `r=${radius}`, cs.opacity !== "1" && `op=${cs.opacity}`,
    /(auto|scroll)/.test(cs.overflowY) && el.scrollHeight > el.clientHeight + 8 && `scroll(${el.scrollHeight}/${el.clientHeight}, top ${Math.round(el.scrollTop)})`,
    cs.flexDirection === "column-reverse" && "column-reverse"].filter(Boolean);
  const own = [...el.childNodes].filter((n) => n.nodeType === Node.TEXT_NODE && n.nodeValue.trim()).map((n) => n.nodeValue.trim()).join(" ");
  const range = document.createRange();
  range.selectNodeContents(el);
  const text = own ? (isTime(own, range.getBoundingClientRect()) ? ` time=${JSON.stringify(own)}` : ` text(${own.length},${kind(own)},fs=${cs.fontSize},fw=${cs.fontWeight})`) : "";
  const interesting = attrs.length || style.length || text || ["img", "video", "audio", "svg", "a", "canvas", "h1", "h2", "h3", "h4", "h5", "h6"].includes(tag);
  if (interesting) lines.push(`${"  ".repeat(Math.min(depth, 40))}${tag} ${attrs.join(" ")} ${style.join(" ")} [${pos(el.getBoundingClientRect())}]${text}`.replace(/\s+\[/, " ["));
  if (tag === "svg") return;
  for (const c of el.children) walk(c, depth + (interesting ? 1 : 0));
};
walk(main, 0);
return lines.join("\n");
