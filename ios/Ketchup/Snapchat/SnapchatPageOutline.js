// DEBUG builds only (the Snapchat page's "…" menu, Testing). A redacted
// outline of a Snapchat for Web chat page, for tuning SnapchatThreadReader.js
// against the real site: tags, roles, labels (names masked), classes, styles,
// font sizes and positions. No message text: every text becomes its length
// and a kind, except time separators. Same rules as the reader: runs only on
// tap, only on a chat page (www.snapchat.com/web/...), in Cetchup's isolated
// world.

if (location.hostname !== "www.snapchat.com" || !location.pathname.startsWith("/web")) {
  return "not a Snapchat chat page";
}

const KEEP = /^(chat|chats|snap|snaps|opened|received|delivered|sent|typing|new|me|you|your|today|yesterday|saved|save|unsave|call|called|calling|missed|video|audio|voice|note|reply|replied|replying|to|view|tap|play|pause|sticker|bitmoji|story|stories|spotlight|map|camera|send|message|messages|search|friends?|add|more|options|profile|settings|pending|screenshot|took|a|an|the|of|in|on|at|for|and|with|is|was|has|joined|left|group|members?|chat|photo|image|gif|link|shared|deleted|unsent|edited|close|open|back|menu|notifications?|ai|my)$/i;
const mask = (s) => s.split(/(\s+)/).map((w) => (/^\s+$/.test(w) || KEEP.test(w.replace(/[^\p{L}]/gu, "")) ? w : w.replace(/[\p{L}\p{N}]/gu, "x"))).join("");
// A time separator is kept only if every word is a date or time word, so a
// message like "Saturday 6am works" is never kept.
const DATE_WORD = /^(today|yesterday|at|[ap]\.?m\.?|(jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|may|june?|july?|aug(ust)?|sept?(ember)?|oct(ober)?|nov(ember)?|dec(ember)?)\.?|(sun(day)?|mon(day)?|tue(s|sday)?|wed(nesday)?|thu(r|rs|rsday)?|fri(day)?|sat(urday)?)\.?|\d{1,4}|\d{1,2}[:.]\d{2}([ap]\.?m\.?)?|\d{1,2}[ap]\.?m\.?|\d{1,2}\/\d{1,2}\/\d{2,4})$/i;
const isTime = (t) => t.length <= 40 && t.replace(/[,·•]/g, " ").trim().split(/\s+/).every((w) => DATE_WORD.test(w));
const kind = (t) => /^[\d\s:.,]+$/.test(t) ? "digits" : /^[\p{Extended_Pictographic}\p{Emoji_Component}\s]+$/u.test(t) ? "emoji" : "text";

const root = document.body;
const lines = [`page ${location.pathname.replace(/\/web\/[^/]+/, "/web/<id>")} · window ${innerWidth}x${innerHeight} · title ${JSON.stringify(mask(document.title))}`];
const pos = (r) => `x${Math.round(r.left)} y${Math.round(r.top)} ${Math.round(r.width)}x${Math.round(r.height)}`;

const walk = (el, depth) => {
  if (lines.length > 3000) return;
  const cs = getComputedStyle(el);
  if (cs.display === "none") return;
  const r = el.getBoundingClientRect();
  const tag = el.tagName.toLowerCase();
  const attrs = [];
  for (const a of ["role", "aria-label", "aria-hidden", "aria-selected", "dir", "contenteditable", "tabindex", "data-testid"]) {
    const v = el.getAttribute(a);
    if (v !== null) attrs.push(`${a}=${JSON.stringify(a === "aria-label" ? mask(v) : v.slice(0, 40))}`);
  }
  const cls = (el.getAttribute("class") || "").trim().split(/\s+/).filter(Boolean).slice(0, 3).map((c) => c.slice(0, 24));
  if (cls.length) attrs.push(`class=${JSON.stringify(cls.join(" "))}`);
  if (tag === "a") attrs.push(`href=${JSON.stringify((el.getAttribute("href") || "").replace(/[^/?=&]+/g, (p) => (/^(web|add|https?:)$/.test(p) ? p : "x")).slice(0, 40))}`);
  if (tag === "img") attrs.push(`alt=${JSON.stringify(mask(el.getAttribute("alt") || ""))}`);
  const bg = cs.backgroundImage !== "none" ? "image" : (cs.backgroundColor && !/rgba\([^)]*,\s*0\)$|transparent/.test(cs.backgroundColor) ? cs.backgroundColor : "");
  const radius = Math.round(parseFloat(cs.borderTopLeftRadius) || 0);
  const borderLeft = parseFloat(cs.borderLeftWidth) || 0;
  const style = [bg && `bg=${bg}`, radius && `r=${radius}`, cs.opacity !== "1" && `op=${cs.opacity}`,
    borderLeft > 0 && `bl=${borderLeft}px ${cs.borderLeftColor}`,
    cs.textTransform !== "none" && `tt=${cs.textTransform}`,
    /(auto|scroll)/.test(cs.overflowY) && el.scrollHeight > el.clientHeight + 8 &&
      `scroll(${el.scrollHeight}/${el.clientHeight}, top ${Math.round(el.scrollTop)}, anchor ${cs.overflowAnchor || "?"})`,
    cs.flexDirection === "column-reverse" && "column-reverse"].filter(Boolean);
  const own = [...el.childNodes].filter((n) => n.nodeType === Node.TEXT_NODE && n.nodeValue.trim()).map((n) => n.nodeValue.trim()).join(" ");
  const text = own ? (isTime(own) ? ` time=${JSON.stringify(own)}`
    : ` text(${own.length},${kind(own)},fs=${cs.fontSize},fw=${cs.fontWeight},color=${cs.color})`) : "";
  const interesting = attrs.length || style.length || text || ["img", "video", "audio", "svg", "a", "canvas", "button", "ul", "ol", "li", "h1", "h2", "h3", "h4", "h5", "h6"].includes(tag);
  if (interesting) lines.push(`${"  ".repeat(Math.min(depth, 40))}${tag} ${attrs.join(" ")} ${style.join(" ")} [${pos(r)}]${text}`.replace(/\s+\[/, " ["));
  if (tag === "svg") return;
  for (const c of el.children) walk(c, depth + (interesting ? 1 : 0));
};
walk(root, 0);
return lines.join("\n");
