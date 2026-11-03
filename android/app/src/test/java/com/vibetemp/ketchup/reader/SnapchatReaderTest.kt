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

    private fun read(fake: FakeSnapThread, last: Int, fraction: Float = 0.92f, readerName: String? = null): TextThread {
        val screen = FakeScreen(fake.thread, pageFraction = fraction, snapchat = true)
        val result = runBlocking { ThreadReader(TextSource.SNAPCHAT, screen, { now }, Random(1), readerName).read(last) }
        return (result as ThreadReader.Result.Read).thread
    }

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
    fun groupRunsAndTheReadersOwnName() {
        val fake = FakeSnapThread("Trail Crew").apply {
            header("Theo", "8:01 AM", "2026-11-03T15:01:00Z")
            message("sunrise hike sunday?")
            message("the ridge one")
            header("Imani", "8:03 AM", "2026-11-03T15:03:00Z")
            message("only if there's coffee after")
            // Snapchat may label the reader's run with their name: Ketchup knows it.
            header("David", "8:04 AM", "2026-11-03T15:04:00Z", isMine = true)
            message("I'll bring the thermos")
            header("Kai", "8:06 AM", "2026-11-03T15:06:00Z")
            message("count me in")
            header("ME", "8:07 AM", "2026-11-03T15:07:00Z")
            message("perfect")
        }
        assertMessages(fake.thread.expected, read(fake, 30, readerName = "David").messages)
        // Without the name, only "ME" runs are the reader's.
        val anonymous = read(fake, 30)
        assertEquals("David", anonymous.messages[3].sender)
        assertFalse(anonymous.messages[3].isMine)
        assertTrue(anonymous.messages[5].isMine)
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
