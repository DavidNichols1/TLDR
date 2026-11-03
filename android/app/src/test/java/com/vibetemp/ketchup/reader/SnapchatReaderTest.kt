package com.vibetemp.ketchup.reader

import com.vibetemp.ketchup.data.TextMessage
import com.vibetemp.ketchup.data.TextSource
import com.vibetemp.ketchup.data.TextThread
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.random.Random

/**
 * The reader on synthetic Snapchat chats shaped like a dump of the real
 * app (made-up people): senders from run headers, "ME" runs, replies,
 * reactions, rows bound above the screen, and overlapping pages.
 */
class SnapchatReaderTest {

    // Tuesday, November 3, 2026, 10:30 AM in Denver (MST).
    private val now = ZonedDateTime.of(2026, 11, 3, 10, 30, 0, 0, ZoneId.of("America/Denver"))

    private fun result(fake: FakeSnapThread, last: Int, fraction: Float = 0.92f, names: SnapchatWalk.Names = SnapchatWalk.Names()): ThreadReader.Result.Read {
        val screen = FakeScreen(fake.thread, pageFraction = fraction, snapchat = true)
        return runBlocking { ThreadReader(TextSource.SNAPCHAT, screen, { now }, Random(1), names).read(last) } as ThreadReader.Result.Read
    }

    private fun read(fake: FakeSnapThread, last: Int, fraction: Float = 0.92f, names: SnapchatWalk.Names = SnapchatWalk.Names()): TextThread =
        result(fake, last, fraction, names).thread

    private fun assertMessages(expected: List<TextMessage>, actual: List<TextMessage>, case: String = "") {
        assertEquals("count $case", expected.size, actual.size)
        expected.zip(actual).forEachIndexed { i, (e, a) -> assertEquals("message $i $case", e, a) }
    }

    @Test
    fun spotsTheChatByItsIdsWhateverTheHint() {
        val fake = FakeSnapThread("Rosa Delgado").apply {
            header("Rosa", "9:05 AM", null)
            message("hi")
        }
        val window = FakeScreen(fake.thread, snapchat = true).window()
        // The composer's hint ("Type a message") isn't one the Snapchat rule knows; its id is.
        val found = ThreadLayout.detect(window, TextSource.SNAPCHAT)
        assertNotNull(found)
        assertEquals(Bounds(0, 236, 1080, 2300), found!!.list)
        assertEquals("found", ThreadLayout.diagnose(window, TextSource.SNAPCHAT))
        // Instagram's rules are untouched: this isn't an Instagram thread.
        assertEquals(null, ThreadLayout.detect(window, TextSource.INSTAGRAM))
    }

    @Test
    fun oneToOneTakesSendersFromHeaders() {
        val fake = FakeSnapThread("Rosa Delgado").apply {
            date("YESTERDAY", "2026-11-02T19:00:00Z")
            header("Rosa", "11:40 PM", "2026-11-03T06:40:00Z")
            message("are you still coming saturday?")
            message("no pressure", bar = false)
            header("ME", "11:52 PM", "2026-11-03T06:52:00Z")
            message("yes! what time")
            date("TODAY", "2026-11-03T19:00:00Z")
            header("Rosa", "9:05 AM", "2026-11-03T16:05:00Z")
            message("noon works")
            header("Me", "9:12 AM", "2026-11-03T16:12:00Z")
            message("see you then")
        }
        val thread = read(fake, 30)
        assertMessages(fake.thread.expected, thread.messages)
        assertEquals("Rosa Delgado", thread.title)
        assertEquals("snapchat", thread.source.id)
        // On the wire, mine go under the reader's Ketchup name.
        assertEquals("David", thread.messages[2].wireSender("David"))
    }

    @Test
    fun groupRunsAndTheReadersKetchupName() {
        val fake = FakeSnapThread("Trail Crew").apply {
            header("Theo", "8:01 AM", "2026-11-03T15:01:00Z")
            message("sunrise hike sunday?")
            message("the ridge one")
            header("Imani", "8:03 AM", "2026-11-03T15:03:00Z")
            message("only if there's coffee after")
            // Snapchat may label the reader's run with their name: Ketchup knows it (case and spaces aside).
            header("David", "8:04 AM", "2026-11-03T15:04:00Z", isMine = true)
            message("I'll bring the thermos")
            header("Kai", "8:06 AM", "2026-11-03T15:06:00Z")
            message("count me in")
        }
        val read = result(fake, 30, names = SnapchatWalk.Names(ketchup = "  david "))
        assertMessages(fake.thread.expected, read.thread.messages)
        assertEquals(SnapchatWalk.Rule.KETCHUP_NAME, read.snap?.rule)

        // "ME" comes first: then a "David" header is a friend with the same name.
        fake.header("ME", "8:07 AM", "2026-11-03T15:07:00Z")
        fake.message("perfect")
        val withMe = read(fake, 30, names = SnapchatWalk.Names(ketchup = "David"))
        assertEquals("David", withMe.messages[3].sender)
        assertFalse(withMe.messages[3].isMine)
        assertTrue(withMe.messages[5].isMine)
    }

    @Test
    fun meHeadersWithAndWithoutATime() {
        val fake = FakeSnapThread("Rosa").apply {
            header("Rosa", "9:05 AM", "2026-11-03T16:05:00Z")
            message("are you up")
            message("me")
            header("ME", null, "2026-11-03T16:05:00Z")
            message("barely")
            message("coffee first")
            header("Rosa", "9:20 AM", "2026-11-03T16:20:00Z")
            message("same")
            header("ME", "9:21 AM", "2026-11-03T16:21:00Z")
            message("see you at 10")
        }
        val read = result(fake, 30)
        // "me" from Rosa sits where messages sit: a message, not a header.
        assertMessages(fake.thread.expected, read.thread.messages)
        assertEquals(SnapchatWalk.Rule.ME, read.snap?.rule)
        assertEquals("snap headers: [len 4, title, time, 3 msgs] [len 2, me, time 1 of 2, 3 msgs]; mine by me", SnapchatWalk.describe(read.snap!!))
    }

    @Test
    fun oneToOneLearnsTheReadersDisplayName() {
        val fake = FakeSnapThread("Rosa Delgado 🌵").apply {
            header("Rosa Delgado", "8:40 AM", "2026-11-03T15:40:00Z")
            message("are you still coming saturday?")
            header("Dave N", "8:45 AM", "2026-11-03T15:45:00Z", isMine = true)
            message("yes! what time")
            header("Rosa Delgado", "8:46 AM", "2026-11-03T15:46:00Z")
            reply("Dave N", "yes! what time", "noon", TextMessage.Quote(text = "yes! what time", isMine = true))
        }
        val read = result(fake, 30)
        assertMessages(fake.thread.expected, read.thread.messages)
        assertEquals(SnapchatWalk.Rule.ONE_TO_ONE, read.snap?.rule)
        assertEquals("Dave N", read.snap?.learned)
        // A one-to-one chat never needs to ask.
        assertEquals(emptyList<String>(), SnapchatWalk.askAmong(read.thread, read.snap))
        assertEquals("snap headers: [len 12, title, time, 2 msgs] [len 6, time, 1 msgs]; mine by one-to-one", SnapchatWalk.describe(read.snap!!))
    }

    private fun group(): FakeSnapThread = FakeSnapThread("Trail Crew").apply {
        header("Theo", "8:01 AM", "2026-11-03T15:01:00Z")
        message("sunrise hike sunday?")
        message("the ridge one")
        header("Dave N", "8:02 AM", "2026-11-03T15:02:00Z", isMine = true)
        message("I'll bring the thermos")
        header("Kai", "8:06 AM", "2026-11-03T15:06:00Z")
        reply("Dave N", "I'll bring the thermos", "legend", TextMessage.Quote(text = "I'll bring the thermos", isMine = true))
        header("Theo", "8:07 AM", "2026-11-03T15:07:00Z")
        message("5:45 then")
    }

    @Test
    fun aGroupUsesTheRememberedName() {
        val fake = group()
        val read = result(fake, 30, names = SnapchatWalk.Names(ketchup = "David", remembered = " dave  n"))
        assertMessages(fake.thread.expected, read.thread.messages)
        assertEquals(SnapchatWalk.Rule.REMEMBERED, read.snap?.rule)
        assertEquals(null, read.snap?.learned)
    }

    @Test
    fun aGroupAsksWhichOneIsYou() {
        val fake = group()
        val read = result(fake, 30)
        assertEquals(SnapchatWalk.Rule.NONE, read.snap?.rule)
        assertEquals(0, read.thread.messages.count { it.isMine })
        // Most messages first.
        val ask = SnapchatWalk.askAmong(read.thread, read.snap)
        assertEquals(listOf("Theo", "Dave N", "Kai"), ask)
        assertEquals("snap headers: [len 4, time, 3 msgs] [len 6, time, 1 msgs] [len 3, time, 1 msgs]; mine by none", SnapchatWalk.describe(read.snap!!))
        // The answer applies to this read: their runs, and quotes of them, are the reader's.
        assertMessages(fake.thread.expected, SnapchatWalk.relabel(read.thread, "Dave N").messages)
    }

    @Test
    fun noneOfTheseLeavesTheReadAsItWas() {
        val read = result(group(), 30)
        assertEquals(3, SnapchatWalk.askAmong(read.thread, read.snap).size)
        // "None of these" hands the read over unchanged: nobody's messages are the reader's.
        assertTrue(read.thread.messages.none { it.isMine })
        assertEquals(listOf("Theo", "Theo", "Dave N", "Kai", "Theo"), read.thread.messages.map { it.sender })
        assertEquals("Dave N", read.thread.messages[3].quote?.sender)
        // Fewer than two people: nothing to ask.
        val alone = FakeSnapThread("Theo").apply {
            header("Theo", "8:01 AM", null)
            message("anyone up")
        }
        val one = result(alone, 30)
        assertEquals(emptyList<String>(), SnapchatWalk.askAmong(one.thread, one.snap))
    }

    @Test
    fun repliesCarryTheirQuote() {
        val fake = FakeSnapThread("Trail Crew").apply {
            header("Imani", "8:10 AM", "2026-11-03T15:10:00Z")
            message("parking fills up by 7")
            header("ME", "8:12 AM", "2026-11-03T15:12:00Z")
            reply("Imani", "parking fills up by 7", "then we leave at 6", TextMessage.Quote(sender = "Imani", text = "parking fills up by 7"))
            header("Theo", "8:15 AM", "2026-11-03T15:15:00Z")
            reply("ME", "then we leave at 6", "6?? ok fine", TextMessage.Quote(text = "then we leave at 6", isMine = true))
        }
        val thread = read(fake, 30)
        assertMessages(fake.thread.expected, thread.messages)
        assertEquals("(replying to David: \"then we leave at 6\") 6?? ok fine", thread.messages[2].wireText("David"))
    }

    @Test
    fun reactionsNoticesAndHiddenRowsAreNotMessages() {
        val fake = FakeSnapThread("Trail Crew").apply {
            notice("Kai saved a message in Chat")
            header("Theo", "8:20 AM", "2026-11-03T15:20:00Z")
            message("who's driving", reactions = 2)
            message("not me", reactions = 1)
            header("ME", "8:21 AM", "2026-11-03T15:21:00Z")
            message("I can drive")
        }
        val thread = read(fake, 30)
        assertMessages(fake.thread.expected, thread.messages)
        val said = thread.messages.joinToString { it.text + (it.quote?.text ?: "") }
        for (absent in listOf("Off screen", "never read", "saved a message", "2", "1")) assertFalse(absent, absent in said.split(", "))
    }

    @Test
    fun overlappingPagesKeepEveryMessageOnce() {
        val fake = FakeSnapThread("Trail Crew")
        val people = listOf("Theo", "ME", "Imani", "Kai")
        fake.date("YESTERDAY", "2026-11-02T19:00:00Z")
        var run = 0
        var i = 0
        while (i < 150) {
            if (i == 70) fake.date("TODAY", "2026-11-03T19:00:00Z")
            val name = people[run % people.size]
            fake.header(name, "8:15 AM", if (i < 70) "2026-11-02T15:15:00Z" else "2026-11-03T15:15:00Z")
            repeat(1 + run % 4) {
                val words = when (i % 9) {
                    0, 1 -> "ok"
                    2 -> "lol"
                    4 -> "this is a longer message about the plan for the weekend, number $i, so it wraps over a few lines"
                    else -> "message $i"
                }
                when {
                    i % 13 == 6 -> fake.reply("Kai", "earlier thing $i", words, TextMessage.Quote(sender = "Kai", text = "earlier thing $i"))
                    else -> fake.message(words, bar = it == 0, reactions = if (i % 7 == 3) 2 else 0)
                }
                i++
            }
            run++
        }
        val all = fake.thread.expected
        // A whole page, a page less the input bar, and much less.
        for (fraction in listOf(1f, 0.92f, 0.6f, 0.35f)) {
            for (last in listOf(30, 80)) {
                assertMessages(all.takeLast(last), read(fake, last, fraction).messages, "last $last at $fraction")
            }
            val whole = read(fake, 600, fraction)
            assertMessages(all, whole.messages, "all at $fraction")
            assertEquals("start", whole.stats?.stop)
        }
    }

    @Test
    fun saysWhyThereIsNoThreadWithoutText() {
        fun screen(vararg kids: SnapshotNode) = SnapshotNode(bounds = Bounds(0, 0, 1080, 2400), children = kids.toList())
        val list = SnapshotNode(bounds = Bounds(0, 236, 1080, 2300), className = "androidx.recyclerview.widget.RecyclerView", viewId = "com.snapchat.android:id/chat_message_list", isScrollable = true)
        val field = SnapshotNode(bounds = Bounds(150, 2180, 800, 2280), viewId = "com.snapchat.android:id/chat_input_bar_search", hint = "Search for a GIF", isEditable = true)
        val noComposer = ThreadLayout.diagnose(screen(list, field), TextSource.SNAPCHAT)
        assertEquals("no composer (chat_input_bar_search h=16)", noComposer)
        val composer = SnapshotNode(bounds = Bounds(150, 2180, 800, 2280), viewId = "com.snapchat.android:id/chat_input_text_field", hint = "Type a message", isEditable = true)
        val noList = ThreadLayout.diagnose(screen(composer), TextSource.SNAPCHAT)
        assertEquals("no list (composer chat_input_text_field; scrollers: none)", noList)
        assertFalse("Search" in noComposer + noList)
    }
}
