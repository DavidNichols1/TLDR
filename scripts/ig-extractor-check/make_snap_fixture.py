#!/usr/bin/env python3
"""Writes the synthetic Snapchat for Web chat the Snapchat reader is tested on:

    ios/Ketchup/Snapchat/Fixture/snap-thread-fixture.html
    ios/Ketchup/Snapchat/Fixture/snap-thread-fixture.expected.json

Made-up people and a made-up trip. The page copies the real page's structure
(Nov 3, 2026, from a redacted outline): a desktop layout with a chat list on
the left and the chat on the right; the chat is a scrolling <ul> of rows, each
a day pill (<time>), a notice pill, or a run of one sender's messages (a <ul>
of <li>, the first with a <header>: name, then a <time>). A message is a box
with the sender's colored left bar and dir="auto" text spans; a reply holds
the quoted message in a painted card with its own list. Class names are made
up on purpose, so the reader can't lean on Snapchat's. Older rows load in
batches when the chat is scrolled to the top, the way Snapchat fetches them.

Run from the repo root after changing it: python3 scripts/ig-extractor-check/make_snap_fixture.py
"""
import html
import json
from pathlib import Path

OUT = Path("ios/Ketchup/Snapchat/Fixture")
READER = "David"  # the harness passes readerName "David"
TITLE = "Moab Crew 🏜️"
COLORS = {"Maya": "#ff65ad", "Jordan": "#f65900", "Sam": "#00d5a0", "Priya": "#a871ff", "Me": "#0eadff"}
PIXEL = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"  # a 1x1 transparent GIF

# ("day", label) | ("notice", text) | (sender, time, [items])
# items: "text" | {"reply": (to, quoted), "t": text} | {"media": kind} | {"mention": name, "t": rest}
#        | {"link": (text, url, card title)} | {"call": True} | {"saved": text} | {"emoji": e}
CHAT = [
    ("day", "October 31"),
    ("Maya", "7:42 PM", ["ok Moab is happening", "first weekend of December, who's in"]),
    ("Jordan", "7:45 PM", ["IN", "I can drive, the 4Runner fits 5"]),
    ("Sam", "7:51 PM", ["in if we're camping and not doing a hotel"]),
    ("Me", "8:03 PM", ["in!!", "camping obviously"]),
    ("Priya", "8:10 PM", ["wait which weekend"]),
    ("Maya", "8:11 PM", [{"reply": ("Priya", "wait which weekend"), "t": "Dec 5 to 7"}]),
    ("Priya", "8:14 PM", ["ok I can do that, I'll have to leave Sunday by noon though"]),
    ("notice", "Jordan saved a chat"),
    ("Jordan", "8:20 PM", [{"media": "sticker"}]),
    ("Sam", "8:22 PM", ["who's booking the campsite"]),
    ("Me", "8:25 PM", ["I can, Devils Garden or somewhere outside the park?"]),
    ("Maya", "8:31 PM", [{"link": ("this one has showers", "example.com/moab-camp", "Up the Creek Campground")}]),
    ("Jordan", "8:33 PM", [{"emoji": "🔥"}]),
    ("day", "November 1"),
    ("Sam", "10:02 AM", ["ok I looked, Devils Garden is booked through December", "so outside the park it is"]),
    ("Me", "10:15 AM", ["Up the Creek then, it's $25 a night per site", "two sites for 5 of us?"]),
    ("Maya", "10:18 AM", ["one site holds 6 people, we just need one"]),
    ("Priya", "10:40 AM", [{"mention": "@Jordan", "t": "how early are we leaving friday"}]),
    ("Jordan", "10:44 AM", ["6am from my place, it's a 5.5 hour drive", "earlier if you want sunset at Delicate Arch"]),
    ("Maya", "10:46 AM", [{"reply": ("Jordan", "6am from my place, it's a 5.5 hour drive"), "t": "6am is brutal but fine"}]),
    ("Sam", "11:30 AM", [{"call": True}]),
    ("Sam", "11:32 AM", ["sorry pocket call"]),
    ("Priya", "12:05 PM", [{"media": "photo"}, "is this tent big enough for two"]),
    ("Me", "12:09 PM", [{"reply": ("Priya", "[photo]"), "t": "that's a 2 person, so barely"}]),
    ("Maya", "12:15 PM", ["I have a 4 person, Priya you can share with me"]),
    ("Priya", "12:16 PM", ["deal 🙏"]),
    ("Jordan", "3:40 PM", ["gas split: 4 people in my car, Sam drives separately?"]),
    ("Sam", "3:52 PM", ["yeah I'm coming from Grand Junction"]),
    ("Me", "4:01 PM", ["I'll request everyone for the campsite, $50 total for 2 nights", "so $10 each"]),
    ("Maya", "4:03 PM", ["paid"]),
    ("Jordan", "4:05 PM", ["paid 👍"]),
    ("notice", "Sam took a screenshot!"),
    ("Sam", "4:30 PM", [{"media": "video"}, "the drive in last year, the canyon road is wild"]),
    ("Priya", "4:45 PM", ["omg"]),
    ("day", "November 2"),
    ("Maya", "9:12 AM", ["food plan: I'll do breakfast burritos Saturday", "someone do dinner both nights"]),
    ("Jordan", "9:20 AM", ["I'll grill Friday, burgers and veggie burgers"]),
    ("Me", "9:31 AM", ["I've got Saturday dinner, chili"]),
    ("Priya", "9:40 AM", ["I'll bring snacks and the coffee setup"]),
    ("Sam", "10:05 AM", ["I'm on firewood, you can't bring it from out of state or something", "I'll just buy it in Moab"]),
    ("Maya", "10:07 AM", [{"reply": ("Sam", "I'll just buy it in Moab"), "t": "yes buy it there, they check"}]),
    ("Jordan", "1:15 PM", [{"media": "box"}, "Delicate Arch at sunset, that's the plan Saturday"]),
    ("Me", "1:20 PM", ["hike is 3 miles round trip, bring headlamps for the way back"]),
    ("Priya", "1:22 PM", ["noted, buying a headlamp"]),
    ("Maya", "6:45 PM", ["packing list so far:\nheadlamp\nwarm layers, it's 30 at night\nwater jugs"]),
    ("Sam", "6:50 PM", ["30 at night?? I need a better sleeping bag"]),
    ("Jordan", "6:52 PM", ["I have an extra 15 degree bag you can borrow"]),
    ("Sam", "6:53 PM", ["you're the best"]),
    ("Priya", "8:30 PM", [{"mention": "@Maya", "t": "can we stop at the Green River gas station, it has the good bathrooms"}]),
    ("Maya", "8:34 PM", ["yes, it's the halfway point anyway"]),
    ("Me", "8:40 PM", ["ok I'll make a shared list for the groceries tomorrow"]),
    ("Jordan", "8:41 PM", [{"emoji": "🏜️"}]),
    ("Maya", "9:02 PM", [{"reply": ("Me", "ok I'll make a shared list for the groceries tomorrow"), "t": "thank you David"}]),
    ("Me", "9:10 PM", [{"saved": "campsite confirmation: Up the Creek, site 4, Dec 5 to 7"}]),
    ("Priya", "9:15 PM", ["so excited"]),
]
MUST_NOT = ["DRAFT SHOULD NOT BE EXTRACTED", "SIDEBAR PREVIEW SHOULD NOT BE EXTRACTED", "saved a chat",
            "took a screenshot", "Missed voice call", "Up the Creek Campground"]
MEDIA = {"sticker": "[sticker]", "photo": "[photo]", "video": "[video]", "box": "[photo or video]"}

e = html.escape


def body(color, inner, saved=False):
    bg = " saved" if saved else ""
    return f'<div class="b{bg}" style="border-left-color:{color}"><div class="bi">{inner}</div></div>'


def item_html(sender, item):
    """One message's box, and what the reader should return for it (None: nothing)."""
    color = COLORS[sender]
    if isinstance(item, str):
        lines = "<br>".join(e(l) for l in item.split("\n"))
        return body(color, f'<span dir="auto" class="tx">{lines}</span>'), item
    if "reply" in item:
        to, quoted = item["reply"]
        qcolor = COLORS[to]
        said = f'<div class="mw"><img alt="" src="{PIXEL}" style="width:220px;height:300px"></div>' if quoted == "[photo]" \
            else f'<span dir="auto" class="tx">{e(quoted)}</span>'
        card = (f'<div class="qw"><div class="qc"><div class="qn"><span style="color:{qcolor}">{e(to)}</span></div>'
                f'<ul class="ql"><li style="border-left-color:{qcolor}"><div class="qb">{said}</div></li></ul></div></div>')
        name = READER if to == "Me" else to
        return body(color, card + f'<span dir="auto" class="tx">{e(item["t"])}</span>'), f'(replying to {name}: "{quoted}") {item["t"]}'
    if "media" in item:
        kind = item["media"]
        if kind == "sticker":
            inner = f'<div class="st"><img alt="" src="{PIXEL}" style="width:124px;height:136px"></div>'
        elif kind == "photo":
            inner = f'<div class="mw"><img alt="" src="{PIXEL}" style="width:280px;height:380px"></div>'
        elif kind == "video":
            inner = '<div class="mw"><video muted playsinline style="width:280px;height:380px;background:#000"></video></div>'
        else:  # a photo or video Snapchat hasn't loaded yet: an empty painted box
            inner = '<div class="mw"><div class="mb" style="width:300px;height:460px"></div></div>'
        return body(color, inner), MEDIA[kind]
    if "mention" in item:
        return body(color, f'<span dir="auto" class="tx"><span class="men">{e(item["mention"])}</span> {e(item["t"])}</span>'), \
            f'{item["mention"]} {item["t"]}'
    if "link" in item:
        text, url, card = item["link"]
        inner = (f'<span dir="auto" class="tx">{e(text)} <a class="ln" href="https://{url}">{e(url)}</a></span>'
                 f'<div class="lw"><a class="lc" href="https://{url}"><div class="li"></div>'
                 f'<div dir="auto"><div><span>{e(card)}</span></div></div></a></div>')
        return body(color, inner), f"{text} {url}"
    if "call" in item:
        inner = ('<div class="cc"><div class="ct"><span>Missed voice call</span></div>'
                 '<div class="cs"><span>Tap to call back</span></div></div>')
        return f'<div class="b" style="border-left-color:{color}">{inner}</div>', None
    if "saved" in item:
        return body(color, f'<span dir="auto" class="tx">{e(item["saved"])}</span>', saved=True), item["saved"]
    if "emoji" in item:
        return body(color, f'<span dir="auto" class="tx big">{item["emoji"]}</span>'), item["emoji"]
    raise ValueError(item)


def reactions(n):
    imgs = "".join(f'<li class="rx"><button class="rb"><img alt="" src="{PIXEL}" style="width:40px;height:44px"></button></li>' for _ in range(n))
    return f'<ul class="rs">{imgs}</ul>'


rows, expected, day = [], [], None
for k, entry in enumerate(CHAT):
    if entry[0] == "day":
        day = entry[1]
        rows.append((f'<li class="r"><time class="pill"><span>{e(day)}</span></time></li>', 0))
        continue
    if entry[0] == "notice":
        rows.append((f'<li class="r"><div class="b plain"><div class="bi"><div class="np"><span>{e(entry[1])}</span></div></div></div>{reactions(0)}</li>', 0))
        continue
    sender, time, items = entry
    color = COLORS[sender]
    parts, count = [], 0
    for i, item in enumerate(items):
        box, want = item_html(sender, item)
        header = ""
        if i == 0:
            header = (f'<header class="h"><div class="hn"><div><span style="color:{color}">{e(sender)}</span></div></div>'
                      f'<span><div class="ht"><time><span>{e(time)}</span></time></div></span></header>')
        parts.append(f'<li class="m">{header}{box}{reactions(2 if k % 7 == 3 and i == 0 else 0)}</li>')
        if want is not None:
            expected.append({"sender": READER if sender == "Me" else sender, "text": want, "isMe": sender == "Me",
                             "at": None, "atLabel": f"{day}, {time}"})
            count += 1
    rows.append((f'<li class="r"><ul class="run">{"".join(parts)}</ul></li>', count))

# The newest ~25 messages are on the page at first; the rest arrive in two
# batches, newest batch first, when the chat is scrolled to the top.
shown, total = [], 0
while rows and total < 25:
    row = rows.pop()
    shown.insert(0, row[0])
    total += row[1]
half = len(rows) // 2
batches = ["".join(r[0] for r in rows[half:]), "".join(r[0] for r in rows[:half])]

sidebar = "".join(
    f'<div role="listitem" class="fr"><div class="fa"></div><div><span dir="auto" class="fn">{e(n)}</span>'
    f'<div class="fs"><span>{e(s)}</span></div></div></div>'
    for n, s in [(TITLE, "Received · 1h"), ("Maya", "SIDEBAR PREVIEW SHOULD NOT BE EXTRACTED"), ("Jordan", "Opened · 2d"),
                 ("Sam", "Received · 3d"), ("Priya", "Called"), ("Team Snapchat", "Received · 5d")])

page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Snapchat</title>
<style>
html, body {{ margin: 0; height: 100%; background: #121212; color: #dedede; font: 16px -apple-system, Helvetica, sans-serif; }}
.app {{ display: flex; height: 100%; }}
.side {{ width: 340px; flex: none; background: #1e1e1e; display: flex; flex-direction: column; }}
.side .top {{ height: 60px; flex: none; }}
.flist {{ overflow-y: auto; flex: 1; }}
.fr {{ display: flex; gap: 10px; padding: 10px 16px; align-items: center; }}
.fa {{ width: 40px; height: 40px; border-radius: 20px; background: #444; flex: none; }}
.fn {{ font-size: 15px; }}
.fs {{ font-size: 11px; color: #999; }}
.pane {{ flex: 1; display: flex; flex-direction: column; margin: 0 10px 10px; min-width: 0; }}
.bar {{ height: 60px; flex: none; display: flex; align-items: center; gap: 12px; }}
.bk {{ width: 36px; height: 36px; border-radius: 18px; background: #2b2b2b; border: 0; color: #ddd; }}
.av {{ width: 36px; height: 36px; border-radius: 18px; background: #555; }}
.tt {{ font-size: 16px; font-weight: 600; }}
.chat {{ flex: 1; display: flex; flex-direction: column; background: #1e1e1e; border-radius: 12px; min-height: 0; }}
.list {{ list-style: none; margin: 0; padding: 0 12px; overflow-y: auto; flex: 1; }}
.list ul {{ list-style: none; margin: 0; padding: 0; }}
.r {{ margin: 14px 0; }}
.pill {{ display: block; width: max-content; margin: 0 auto; padding: 6px 12px; border-radius: 15px; background: #1e1e1e;
        text-transform: uppercase; font-size: 11px; color: #999; }}
.h {{ display: flex; justify-content: space-between; text-transform: uppercase; font-size: 12px; font-weight: 600; max-width: 380px; }}
.ht {{ font-weight: 400; color: #999; }}
.b {{ border-left: 2px solid; padding-left: 8px; margin: 2px 0; border-radius: 2px; }}
.b.saved {{ background: #333232; }}
.b.plain {{ border-left: 0; }}
.tx {{ font-size: 16px; line-height: 1.3; }}
.tx.big {{ font-size: 32px; }}
.men {{ font-weight: 600; color: #a871ff; }}
.ln {{ color: #dedede; font-weight: 600; }}
.qc {{ background: #1e1e1e; border-radius: 10px; border: 1px solid rgba(255,255,255,0.1); padding: 8px; margin: 4px 0; }}
.qn {{ text-transform: uppercase; font-size: 14px; }}
.ql li {{ border-left: 2px solid; padding-left: 6px; }}
.mb {{ background: #292929; border-radius: 8px; }}
.lc {{ display: flex; gap: 10px; background: #1e1e1e; border-radius: 10px; padding: 10px; margin-top: 6px; color: #dedede; text-decoration: none; width: 420px; }}
.li {{ width: 40px; height: 40px; border-radius: 8px; background: #333; }}
.cc {{ background: #1e1e1e; border-radius: 10px; padding: 10px 12px; width: 260px; color: #999; }}
.cs {{ font-size: 12px; }}
.np {{ width: max-content; margin: 0 auto; padding: 2px 10px; border-radius: 15px; background: #1e1e1e;
      text-transform: uppercase; font-size: 9.5px; color: #999; }}
.rs {{ display: flex; gap: 4px; }}
.rb {{ border: 0; background: none; padding: 0; }}
.compose {{ flex: none; display: flex; padding: 10px 12px; }}
.input {{ flex: 1; background: #2b2b2b; border-radius: 18px; padding: 8px 14px; color: #999; font-size: 14px; }}
</style></head>
<body>
<div class="app">
  <div class="side"><div class="top"></div><div role="list" aria-label="Friends list" class="flist">{sidebar}</div></div>
  <div class="pane">
    <div class="bar"><button class="bk" aria-label="Back">&lt;</button><div class="av"></div>
      <div class="tw"><span class="tn"><span dir="auto" class="tt">{e(TITLE)}</span></span></div></div>
    <div class="chat">
      <ul class="list" id="chat"><li class="r" style="height:0;margin:0"></li>{"".join(shown)}</ul>
      <div class="compose"><div role="textbox" contenteditable="true" class="input">DRAFT SHOULD NOT BE EXTRACTED</div></div>
    </div>
  </div>
</div>
<script>
// Older rows arrive when the chat is scrolled to the top, newest batch first,
// and the view stays put, the way Snapchat loads history.
const batches = {json.dumps(batches)};
const chat = document.getElementById("chat");
let loading = false;
chat.addEventListener("scroll", () => {{
  if (chat.scrollTop > 40 || loading || !batches.length) return;
  loading = true;
  setTimeout(() => {{
    const before = chat.scrollHeight;
    chat.firstElementChild.insertAdjacentHTML("afterend", batches.shift());
    chat.scrollTop += chat.scrollHeight - before;
    loading = false;
  }}, 400);
}});
chat.scrollTop = chat.scrollHeight;
</script>
</body></html>
"""

OUT.mkdir(parents=True, exist_ok=True)
(OUT / "snap-thread-fixture.html").write_text(page)
(OUT / "snap-thread-fixture.expected.json").write_text(json.dumps(
    {"title": TITLE, "isGroup": True, "mustNotContain": MUST_NOT, "messages": expected}, indent=1, ensure_ascii=False) + "\n")
print(f"{len(expected)} messages; {total} on the page at first, the rest in {len(batches)} batches")
