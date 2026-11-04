// The demo conversation: five friends planning a ski weekend in Breckenridge
// over three days while David (the demo viewer) is heads-down on a hackathon.
//
// Written to be dense with what Cetchup should pull out: plans that change
// (Friday 4pm → Saturday 6am; Hearthstone Friday → Saturday), money that
// changes ($140 each → $90 after a refund, plus gas and an old side debt),
// questions nobody answers, and several things aimed at David.
//
// Day rules (seed.ts picks real dates; see README):
//   day 0 is a Sat, Sun or Mon, day 1 the next day, day 2 the day after
//   (Mon–Wed), and the trip is the Friday–Sunday after day 2. So weekday names
//   are only used where they can't be ambiguous: day 0 names only Thursday and
//   Friday, day 1 names Wednesday–Saturday, day 2 names Thursday–Sunday.
//
// Tags mark what was planted, for the --dry-run report and the demo test
// plan. They are never sent to the database.

export const CHAT_NAME = "Breck Weekend 🎿";

/** The person who joins with the invite code and taps Catch me up. */
export const VIEWER_NAME = "David";

export const PEOPLE = {
  maya: { name: "Maya", email: "tldr.demo+maya@example.com" },
  jordan: { name: "Jordan", email: "tldr.demo+jordan@example.com" },
  priya: { name: "Priya", email: "tldr.demo+priya@example.com" },
  sam: { name: "Sam", email: "tldr.demo+sam@example.com" },
  theo: { name: "Theo", email: "tldr.demo+theo@example.com" },
} as const;

export type Sender = keyof typeof PEOPLE;

/** Maya creates the chat. */
export const CREATOR: Sender = "maya";

export type Tag =
  | "plan" //      a concrete plan, time or place
  | "change" //    a decision that replaced an earlier one
  | "money" //     who owes whom / who paid
  | "open_q" //    a question that never gets answered
  | "answered_q" // a question that does get answered (should NOT be listed as open)
  | "for_david" // aimed at the viewer
  | "side"; //     side thread / noise

export type Line = [Sender, string, ...Tag[]];

/** A run of messages starting at a local (America/Denver) wall-clock time. */
export interface Burst {
  at: string; // "HH:MM"
  lines: Line[];
}

export const DAYS: Burst[][] = [
  // ---------------------------------------------------------------- day 0
  [
    {
      at: "10:14",
      lines: [
        ["maya", "ok it's official, the Breck house is BOOKED 🎿🏔️", "plan"],
        ["maya", "two nights, Friday + the night after. 3 bedrooms and a bunk room, 10 min walk to the gondola", "plan"],
        ["priya", "AHHH yes"],
        ["priya", "is it the one with the green door??"],
        ["maya", "the green door one 💚"],
        ["sam", "wait is this the one with the hot tub"],
        ["maya", "lol it's the one we all voted on"],
        ["jordan", "nice. who's actually confirmed"],
      ],
    },
    {
      at: "10:31",
      lines: [
        ["maya", "me, Priya, Jordan, Sam, Theo, David = 6"],
        ["maya", "David said yes last week right before he disappeared into his hackathon cave 😂", "for_david"],
        ["theo", "classic David"],
        ["sam", "someone check on him he hasn't replied to anything in days"],
        ["priya", "he's probably building an app that reads this chat for him"],
        ["jordan", "honestly that would be useful for this chat"],
        ["sam", "lmao"],
      ],
    },
    {
      at: "10:48",
      lines: [
        ["maya", "ok money. the Airbnb was $840 total with fees, I put it on my card", "money"],
        ["maya", "that's $140 each for 6 of us. Venmo me whenever, before Friday ideally", "money"],
        ["jordan", "sent ✅", "money"],
        ["priya", "sending now"],
        ["priya", "done!", "money"],
        ["sam", "my bank app is being weird, i'll venmo you tomorrow morning", "money"],
        ["theo", "I'll send mine after I get paid Friday if that's cool"],
        ["maya", "totally fine"],
        ["maya", "David that means you too when you resurface 💸", "for_david", "money"],
      ],
    },
    {
      at: "12:05",
      lines: [
        ["maya", "plan for getting up there: leave Friday at 4 from my place?", "plan"],
        ["maya", "two cars. I can take 3, Jordan can you take 3?"],
        ["jordan", "yeah the Subaru fits 3 plus skis on the rack"],
        ["jordan", "I'll grab the rack from my brother's this week"],
        ["theo", "4 works, I can leave work early"],
        ["priya", "4 is perfect"],
        ["sam", "4 is ambitious for me but i'll make it work 🫡"],
        ["maya", "ok cars: Maya car = me, Priya, Theo. Jordan car = Jordan, Sam, David", "plan", "for_david"],
        ["jordan", "David is going to love sitting next to Sam for 2 hours"],
        ["sam", "rude. accurate, but rude"],
      ],
    },
    {
      at: "12:40",
      lines: [
        ["priya", "I'm going to call Hearthstone for Friday dinner, they do big groups"],
        ["priya", "7:30 Friday? gives us time to get up there and check in", "plan"],
        ["maya", "perfect"],
        ["jordan", "👍"],
        ["sam", "is hearthstone the fancy one"],
        ["priya", "medium fancy. they have elk"],
        ["sam", "say less"],
      ],
    },
    {
      at: "13:02",
      lines: [
        ["priya", "booked! Hearthstone, Friday 7:30, table for 6 under Priya", "plan"],
        ["maya", "queen 👑"],
        ["theo", "elk friday let's goooo"],
      ],
    },
    {
      at: "15:20",
      lines: [
        ["theo", "unrelated but does anyone know a dog sitter, my usual one is out of town that week", "side"],
        ["priya", "my neighbor does it! she's great with big dogs", "side"],
        ["theo", "Pickles is 70 lbs of anxiety lol", "side"],
        ["priya", "she had a great dane last month, she can handle Pickles", "side"],
        ["theo", "can you send me her number?", "side", "answered_q"],
        ["priya", "texting it to you now", "side"],
        ["theo", "legend, thank you 🙏", "side"],
      ],
    },
    {
      at: "16:30",
      lines: [
        ["theo", "fyi Breck itself won't be open yet, it's early season. Keystone and A-Basin are open though"],
        ["jordan", "Keystone is like 25 min from the house, that's fine"],
        ["priya", "I have the Epic pass so Keystone works for me"],
        ["sam", "i have nothing. how much is a day ticket"],
        ["theo", "like $180 at the window, cheaper if you buy online a few days ahead"],
        ["sam", "$180 to slide down a hill 💀"],
        ["maya", "you'll survive"],
        ["sam", "barely"],
        ["theo", "buy it online Sam. not at the window. I'm begging you"],
      ],
    },
    {
      at: "17:45",
      lines: [
        ["theo", "gear check: who needs rentals?"],
        ["sam", "me. i sold my skis in 2023 like an idiot"],
        ["theo", "Christy Sports on Colorado Blvd has good weekend rates, I'll reserve for whoever needs them"],
        ["theo", "I need height, weight and boot size from each of you"],
        ["sam", "5'11, 170, boot 10.5"],
        ["sam", "wait is that too much info for the group chat"],
        ["jordan", "we've seen worse in here"],
        ["theo", "David do you still need rentals or did you end up buying skis?", "for_david", "open_q"],
        ["maya", "he was talking about buying some last spring, no idea if he did"],
      ],
    },
    {
      at: "19:30",
      lines: [
        ["priya", "food plan: I'll do a grocery run before we leave and we cook breakfast both mornings"],
        ["priya", "anyone vegetarian or allergic to anything?", "answered_q"],
        ["theo", "no tree nuts for me, otherwise anything"],
        ["maya", "I'm good with anything"],
        ["jordan", "same"],
        ["sam", "i'm allergic to vegetables"],
        ["priya", "noted, extra spinach for Sam 🥬"],
        ["sam", "betrayal"],
        ["priya", "and David eats literally everything so we're good there"],
      ],
    },
    {
      at: "21:10",
      lines: [
        ["sam", "ok who's making the playlist for the drive", "side"],
        ["priya", "not you. last time it was 40 minutes of sea shanties", "side"],
        ["sam", "those were BANGERS", "side"],
        ["jordan", "I'm driving so I'm DJ. rules are rules", "side"],
        ["sam", "tyranny", "side"],
        ["maya", "driver picks the music, shotgun holds the snacks. ancient law", "side"],
        ["theo", "lmao", "side"],
        ["sam", "fine but i'm making a collaborative playlist anyway and you can't stop me", "side"],
        ["sam", "it's called 'shred or be shredded'", "side"],
        ["priya", "I'm leaving this group", "side"],
      ],
    },
    {
      at: "22:34",
      lines: [
        ["jordan", "got the ski rack from my brother btw. fits 4 pairs"],
        ["maya", "amazing"],
        ["sam", "jordan you're the dad of this group and i mean that with love"],
        ["jordan", "go to bed Sam"],
      ],
    },
  ],

  // ---------------------------------------------------------------- day 1
  [
    {
      at: "07:52",
      lines: [
        ["jordan", "uh have you guys seen the forecast"],
        ["jordan", "winter storm warning for the mountains Friday noon through early Saturday"],
        ["jordan", "8–14 inches above 9,000 ft and the I-70 traction law is going to be on"],
        ["theo", "that's amazing for skiing and terrible for driving"],
        ["sam", "POWDER DAY"],
        ["jordan", "powder day for people who are already up there"],
        ["maya", "ugh ok let's think about this"],
      ],
    },
    {
      at: "08:30",
      lines: [
        ["jordan", "also my boss just moved a client thing to Friday 4:30, so I can't leave before 6 anyway"],
        ["maya", "so Friday at 4 is out regardless", "change"],
        ["priya", "what about leaving Friday at 8pm after the worst of it?"],
        ["jordan", "the storm runs overnight. 8pm Friday on I-70 in a storm is a no from me"],
        ["theo", "agree, the Eisenhower tunnel at night in a storm is sketchy"],
        ["sam", "what if we just leave saturday super early and get first chair"],
        ["maya", "honestly that might be the move"],
        ["priya", "we'd lose the first night at the house though"],
        ["maya", "let me see what the host says before we panic"],
      ],
    },
    {
      at: "09:15",
      lines: [
        ["maya", "proposal: leave SATURDAY 5:30am from my place, ski Keystone as soon as we get up there", "change", "plan"],
        ["sam", "5:30 is a crime"],
        ["sam", "i will be legally asleep"],
        ["jordan", "5:30 gets us to Keystone by 7:30, way ahead of traffic"],
        ["priya", "can we do 6? 5:30 means waking up at 4:45"],
        ["theo", "6 is fine, still beats the traffic"],
        ["jordan", "6 works, but 6 means 6. not 6:20 Sam"],
        ["sam", "i have never been late in my life"],
        ["maya", "lol"],
        ["priya", "Sam you were 50 minutes late to my birthday"],
        ["sam", "that was a parking situation"],
        ["maya", "ok FINAL: we leave Saturday at 6:00am from my place. be there at 5:45 with your stuff in the car", "change", "plan"],
        ["jordan", "👍"],
        ["theo", "✅"],
        ["priya", "✅"],
        ["sam", "✅ (under protest)"],
        ["maya", "same cars as before. David you're still in Jordan's car 🚗", "for_david", "plan"],
      ],
    },
    {
      at: "09:41",
      lines: [
        ["priya", "wait what about Hearthstone Friday night then"],
        ["maya", "oh no"],
        ["priya", "I'll call them when they open at 11 and see if they can do Saturday instead"],
        ["maya", "and I'm messaging the Airbnb host about Friday night now"],
      ],
    },
    {
      at: "11:22",
      lines: [
        ["priya", "Hearthstone moved us!! SATURDAY 7:30 now, still 6 people", "change", "plan"],
        ["priya", "but they need a final headcount by Thursday at noon or they'll drop us to 4", "plan"],
        ["maya", "amazing"],
        ["jordan", "nice work"],
        ["priya", "so David please confirm you're actually coming 🙏", "for_david", "open_q"],
      ],
    },
    {
      at: "12:45",
      lines: [
        ["maya", "good news: the host is letting us cancel Friday night because of the storm and refunding $300", "money", "change"],
        ["maya", "so the Airbnb is now $540 total = $90 each", "money", "change"],
        ["maya", "Jordan + Priya you already sent $140, I'll send you each $50 back tonight", "money"],
        ["jordan", "oh nice, thanks"],
        ["priya", "yay host 🙌"],
        ["maya", "Sam, Theo, David: just send $90 instead of $140", "money", "for_david"],
        ["theo", "even better"],
        ["sam", "see, waiting paid off"],
        ["maya", "that is NOT the lesson"],
      ],
    },
    {
      at: "13:10",
      lines: [
        ["theo", "what time can we check in Saturday then?", "answered_q"],
        ["maya", "normally 4pm but the host is going to try for noon since the place is empty the night before"],
        ["maya", "I'll confirm Thursday. door code comes the morning of"],
        ["sam", "so where does our stuff go while we ski"],
        ["jordan", "it stays in the cars. it's fine"],
        ["sam", "also does the house actually have a hot tub or was that one photo of someone else's hot tub", "open_q"],
        ["theo", "Jordan does the Subaru have snow tires or all-seasons? traction law means you need one or the other plus AWD", "open_q"],
        ["jordan", "more important question: is Keystone parking free on Saturdays?", "answered_q"],
        ["theo", "free in the River Run lots if you're there before 8, otherwise $25"],
        ["jordan", "we'll be there before 8 so free 😎"],
      ],
    },
    {
      at: "15:30",
      lines: [
        ["theo", "@Sam also you still owe me $45 for the Mission Ballroom tickets from October 😇", "money", "side"],
        ["sam", "I KNOW. i'm going to venmo you so hard", "side"],
        ["theo", "you can do it softly, just do it", "side"],
        ["sam", "adding it to my list. Maya $90, Theo $45. i am a man of debts", "money", "side"],
        ["priya", "put it in your notes app Sam", "side"],
        ["sam", "my notes app is just a picture of a raccoon", "side"],
        ["jordan", "that tracks", "side"],
      ],
    },
    {
      at: "17:10",
      lines: [
        ["theo", "rentals update: Christy Sports on Colorado Blvd, reserved skis + boots for Sam and me", "plan"],
        ["theo", "pickup is Friday at 6pm, they close at 8", "plan"],
        ["jordan", "I'm done at 6, I can drive you both. there by 6:15", "plan"],
        ["theo", "perfect"],
        ["theo", "David if you need rentals I need your height, weight and boot size by Wednesday night or they won't hold a set for you", "for_david", "open_q"],
        ["sam", "do they do snowboards too or just skis"],
        ["theo", "both, but you said skis Sam"],
        ["sam", "i'm keeping my options open"],
        ["theo", "you're getting skis"],
      ],
    },
    {
      at: "18:40",
      lines: [
        ["priya", "grocery run is now Friday at 7pm since nobody's driving up Friday. King Soopers on Colorado Blvd", "plan", "change"],
        ["priya", "Maya want to come? then we load your car Friday night and you're ready to go Saturday"],
        ["maya", "yes! I'll meet you there at 7", "plan"],
        ["priya", "list so far: eggs, bacon, pancake mix, coffee, oat milk for Theo, sandwich stuff, a frankly irresponsible amount of chips"],
        ["sam", "and the good salsa"],
        ["priya", "and the good salsa"],
        ["theo", "bagels pls"],
        ["jordan", "beer. a reasonable amount"],
        ["sam", "an unreasonable amount"],
        ["priya", "I'll pay for it and we split it after", "money"],
        ["maya", "send the receipt in here so we can split it"],
      ],
    },
    {
      at: "20:55",
      lines: [
        ["sam", "is David bringing the speaker? his is the only one that isn't trash"],
        ["maya", "David you're on speaker + Catan duty 🫡", "for_david"],
        ["jordan", "no Catan. last time Priya and Sam didn't talk for 2 days"],
        ["priya", "he traded me a sheep for nothing and then took my road"],
        ["sam", "it was a strategic sheep"],
        ["maya", "Catan is coming. it builds character"],
        ["jordan", "I'm bringing a shovel and jumper cables, that's my contribution to character"],
      ],
    },
    {
      at: "21:30",
      lines: [
        ["maya", "also what if we do dinner Thursday at Root Down to sort out gear + money before the trip? 7:30?", "plan"],
        ["priya", "I'm in!"],
        ["theo", "might have a work thing Thursday, I'll know tomorrow"],
        ["jordan", "maybe. depends how late my client stuff runs"],
        ["sam", "root down has the sweet potato fries right? then yes"],
        ["maya", "ok tentatively Thursday 7:30 at Root Down, I'll book for 4 and adjust", "plan"],
        ["maya", "David you in? 👀", "for_david", "open_q"],
      ],
    },
    {
      at: "22:15",
      lines: [
        ["priya", "who's sleeping where btw? 3 bedrooms + the bunk room", "open_q"],
        ["sam", "is the bunk room the one with 4 beds"],
        ["sam", "because i would like the top bunk for spiritual reasons"],
        ["theo", "I'm a top bunk guy too"],
        ["sam", "then we fight"],
        ["jordan", "someone remind me to charge my boot heaters"],
        ["sam", "your boots have HEATERS??"],
        ["jordan", "my feet are 33 years old. they need heaters"],
        ["sam", "lmaooo"],
        ["maya", "ok goodnight you weirdos"],
      ],
    },
  ],

  // ---------------------------------------------------------------- day 2
  [
    {
      at: "07:40",
      lines: [
        ["theo", "Pickles officially has a sitter for the weekend 🐶 Priya your neighbor is the best", "side"],
        ["priya", "told you!!", "side"],
        ["theo", "she has a fenced yard. Pickles is going to think he's the one on vacation", "side"],
        ["maya", "send a pic of Pickles", "side"],
        ["theo", "he's asleep upside down on the couch, I'll get one later", "side"],
      ],
    },
    {
      at: "08:15",
      lines: [
        ["jordan", "forecast update: storm now looks like Friday 1pm to Saturday 3am, roads should be plowed by morning"],
        ["jordan", "CDOT says traction law for cars, possible chain law for trucks"],
        ["theo", "so Saturday is a powder day. we made the right call"],
        ["sam", "POWDER DAY (for real this time)"],
        ["maya", "the 6am decision has been vindicated"],
        ["theo", "Jordan still curious about the tires btw 👀", "open_q"],
        ["sam", "jordan is ignoring the tire question which is the most jordan thing ever"],
      ],
    },
    {
      at: "09:30",
      lines: [
        ["jordan", "gas plan: I'll fill up Friday night. $20 each for gas, pay whoever drives you", "money"],
        ["jordan", "so Sam + David → me, Priya + Theo → Maya", "money", "for_david"],
        ["maya", "works for me"],
        ["priya", "👍"],
        ["theo", "fair"],
      ],
    },
    {
      at: "10:05",
      lines: [
        ["priya", "random but I passed my certification exam this morning!!! 🎉", "side"],
        ["maya", "PRIYA", "side"],
        ["theo", "let's gooo", "side"],
        ["jordan", "congrats, huge", "side"],
        ["sam", "first round at Hearthstone is on us", "side"],
        ["priya", "I'm holding you to that Sam", "side"],
        ["sam", "the debt list grows", "side"],
      ],
    },
    {
      at: "11:02",
      lines: [
        ["sam", "has anyone actually heard from David"],
        ["jordan", "he liked a message at 3am so he's alive"],
        ["maya", "his hackathon ends this week I think. he'll surface"],
        ["priya", "he's buying the first round when he's back"],
        ["sam", "the debt list welcomes a new member"],
        ["theo", "lol"],
      ],
    },
    {
      at: "12:10",
      lines: [
        ["sam", "lunch break, just watched a guy ski down a mountain in a banana costume and i've made a decision", "side"],
        ["priya", "no", "side"],
        ["sam", "you don't even know what it is", "side"],
        ["priya", "it's a costume. no", "side"],
        ["sam", "SATURDAY IS COSTUME DAY", "side"],
        ["jordan", "I'm not driving 2 hours in a costume", "side"],
        ["sam", "you put it on in the parking lot like a professional", "side"],
        ["theo", "I'll do it if it's warm", "side"],
        ["maya", "I do still have a dinosaur onesie", "side"],
        ["sam", "MAYA 🦖", "side"],
        ["maya", "I'm not committing to anything", "side"],
        ["sam", "she's committing", "side"],
      ],
    },
    {
      at: "13:40",
      lines: [
        ["theo", "sent you $90 Maya ✅", "money"],
        ["maya", "got it, thank you!"],
        ["maya", "and Jordan + Priya, I sent your $50 back last night. check your Venmo", "money"],
        ["jordan", "got it 👍"],
        ["priya", "yep got it!"],
        ["maya", "so still waiting on Sam ($90) and David ($90)", "money", "for_david"],
        ["sam", "tonight. on my life"],
        ["maya", "you said that two days ago"],
        ["sam", "and i meant it then too"],
      ],
    },
    {
      at: "15:05",
      lines: [
        ["theo", "update: my work thing Thursday got cancelled, I'm in for Root Down"],
        ["jordan", "I'm out for Thursday, client dinner. have fun"],
        ["maya", "ok Root Down Thursday 7:30 is me, Priya, Theo, Sam. booked for 4", "plan"],
        ["maya", "David if you want in I can bump it to 5, just say so by tomorrow", "for_david"],
        ["sam", "sweet potato fries 🍠"],
      ],
    },
    {
      at: "16:30",
      lines: [
        ["theo", "Sunday plan: A-Basin, first chair is 8:30. ski till about 1?", "plan"],
        ["maya", "checkout is 11 Sunday so we'd have to pack the cars before we go", "plan"],
        ["jordan", "so: cars packed by 8, ski A-Basin 8:30 to 1, leave by 2 to beat the traffic home", "plan"],
        ["priya", "and the Broncos game is Sunday afternoon so Sam will want to be home anyway", "side"],
        ["sam", "i will listen on the radio in the car like a 1950s dad", "side"],
        ["jordan", "leave A-Basin by 2pm Sunday, home around 4 if I-70 cooperates", "plan"],
        ["maya", "👍 locking that in"],
      ],
    },
    {
      at: "18:20",
      lines: [
        ["maya", "packing list for Saturday: skis/board, boots, helmet, goggles, layers, chargers, swimsuit just in case"],
        ["sam", "swimsuit just in case of WHAT. is there a hot tub or not"],
        ["jordan", "I've got the ski rack, a shovel and the jumper cables"],
        ["theo", "I'll bring my wax kit and tuning stuff"],
        ["priya", "I'll bring the cooler and the waffle maker"],
        ["sam", "i'll bring the vibes"],
        ["maya", "Sam bring a helmet. you don't own one"],
        ["sam", "i'll rent one"],
        ["sam", "wait does Christy rent helmets?", "answered_q"],
        ["theo", "they don't include them in the weekend package, but I have a spare you can borrow"],
        ["sam", "theo you're the goat 🐐"],
      ],
    },
    {
      at: "19:05",
      lines: [
        ["priya", "reminder: Hearthstone needs the final headcount by Thursday noon. I have 6 but David still hasn't confirmed 😬", "for_david", "plan"],
        ["maya", "I'll text him directly too"],
        ["sam", "someone go to his apartment and knock"],
        ["jordan", "he's probably asleep on his keyboard"],
        ["theo", "if he's out my coworker Alex has been begging to come, he'd take the spot", "side"],
        ["priya", "let's give David until Thursday morning, then we ask Alex", "for_david", "plan"],
        ["maya", "agreed"],
      ],
    },
    {
      at: "20:30",
      lines: [
        ["jordan", "playlist update: I made one. it's called 'I-70 at 6am' and there are no sea shanties", "side"],
        ["sam", "i added three sea shanties", "side"],
        ["jordan", "how", "side"],
        ["sam", "it's collaborative jordan. that's the beauty of it", "side"],
        ["jordan", "I'm removing your access", "side"],
        ["sam", "you can't remove the human spirit", "side"],
      ],
    },
    {
      at: "21:45",
      lines: [
        ["sam", "maya check your venmo 😤", "money"],
        ["maya", "WOW. a miracle. got it, $90 ✅", "money"],
        ["theo", "and my $45? 👀", "money", "side"],
        ["sam", "next paycheck. it's on the list", "money", "side"],
        ["theo", "the raccoon list", "side"],
        ["sam", "the raccoon list is sacred", "side"],
      ],
    },
    {
      at: "22:20",
      lines: [
        ["maya", "David when you finally come up for air, read this chat. there's a lot in here for you 😂", "for_david"],
        ["jordan", "alarm is set for 5:15 Saturday. see everyone at Maya's at 5:45", "plan"],
        ["sam", "5:45 is a made up time"],
        ["priya", "goodnight!! 🌙"],
        ["maya", "goodnight losers 💙"],
      ],
    },
  ],
];
