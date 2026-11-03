package com.vibetemp.ketchup.reader

import com.vibetemp.ketchup.Fixtures
import com.vibetemp.ketchup.data.KetchupJson
import com.vibetemp.ketchup.data.TextMessage
import com.vibetemp.ketchup.data.TextSource
import com.vibetemp.ketchup.data.TextThread
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.random.Random

/**
 * The reader on synthetic threads (made-up people): who said what, quotes,
 * placeholders, what gets dropped, and pages laid together without a
 * message lost or read twice.
 */
class ThreadReaderTest {

    private val now = ZonedDateTime.of(2026, 11, 3, 10, 30, 0, 0, ZoneId.of("America/Denver"))

    private fun read(screen: FakeScreen, last: Int, source: TextSource = TextSource.INSTAGRAM): TextThread {
        val result = runBlocking { ThreadReader(source, screen, { now }, Random(1)).read(last) }
        return (result as ThreadReader.Result.Read).thread
    }

    private fun assertMessages(expected: List<TextMessage>, actual: List<TextMessage>, case: String = "") {
        assertEquals("count $case", expected.size, actual.size)
        expected.zip(actual).forEachIndexed { i, (e, a) -> assertEquals("message $i $case", e, a) }
    }

    @Test
    fun oneToOneNamesThemAfterTheTitle() {
        val t = FakeThread("Rosa Delgado")
        t.stamp("Yesterday 9:15 PM", "2026-11-03T04:15:00Z")
        t.them("Rosa", "are you still coming saturday?", expectSender = "Rosa Delgado")
        t.them("Rosa", "no pressure", expectSender = "Rosa Delgado", avatar = true)
        t.mine("yes! what time", seen = false)
        t.stamp("Today 8:02 AM", "2026-11-03T15:02:00Z")
        t.them("Rosa", "noon works", expectSender = "Rosa Delgado", avatar = true)
        t.mine("see you then", seen = true)

        val thread = read(FakeScreen(t), 30)
        assertMessages(t.expected, thread.messages)
        assertEquals("Rosa Delgado", thread.title)
        assertEquals("instagram", thread.source.id)
        // Short thread: it fits on one page, so the reader stops at the top.
        assertEquals("start", thread.stats?.stop)
        assertEquals(true, thread.stats?.reachedStart)
    }

    @Test
    fun groupLabelsNameEachRun() {
        val t = FakeThread("Trail Crew")
        t.notice("Theo named the group Trail Crew")
        t.them("Theo", "sunrise hike sunday?", label = true)
        t.them("Theo", "the ridge one", avatar = true)
        t.them("Imani", "only if there's coffee after", label = true, avatar = true)
        t.mine("I'll bring the thermos")
        t.them("Theo", "legend", label = true)
        t.them("Kai", "count me in", label = true, avatar = true)
        t.them("Kai", "😴", bigEmoji = true)

        val thread = read(FakeScreen(t), 30)
        assertMessages(t.expected, thread.messages)
        assertEquals("Trail Crew", thread.title)
    }

    @Test
    fun repliesCarryTheirQuote() {
        val t = FakeThread("Trail Crew")
        t.them("Imani", "parking fills up by 7", label = true, avatar = true)
        t.reply(
            "You replied to Imani", "parking fills up by 7", mine = true, name = "", text = "then we leave at 6",
            expectQuote = TextMessage.Quote(sender = "Imani", text = "parking fills up by 7"),
        )
        t.reply(
            "Imani replied to you", "then we leave at 6", mine = false, name = "Imani", text = "ugh fine",
            expectQuote = TextMessage.Quote(text = "then we leave at 6", isMine = true),
        )
        t.reply(
            "Theo replied to Imani", "ugh fine", mine = false, name = "Theo", text = "she says fine like it's a threat",
            expectQuote = TextMessage.Quote(sender = "Imani", text = "ugh fine"),
        )

        val thread = read(FakeScreen(t), 30)
        assertMessages(t.expected, thread.messages)
        assertEquals(
            "(replying to David: \"then we leave at 6\") ugh fine",
            thread.messages[2].wireText("David"),
        )
        assertEquals("(replying to Imani: \"ugh fine\") she says fine like it's a threat", thread.messages[3].wireText("David"))
    }

    @Test
    fun mediaBecomesPlaceholders() {
        val t = FakeThread("Kai Moreno")
        t.them("Kai", null, expectSender = "Kai Moreno", media = "Photo", expectText = "[photo]")
        t.them("Kai", "the view from the top", expectSender = "Kai Moreno", media = "Shared post", expectText = "[shared post] the view from the top")
        t.them("Kai", null, expectSender = "Kai Moreno", media = "Voice message", duration = "0:12", expectText = "[voice message]")
        t.them("Kai", null, expectSender = "Kai Moreno", media = "Video", duration = "0:31", expectText = "[video]", avatar = true)
        t.mine(null, media = "GIF", expectText = "[GIF]")
        t.mine(null, media = "Sticker", expectText = "[sticker]")

        val thread = read(FakeScreen(t), 30)
        assertMessages(t.expected, thread.messages)
        assertEquals(6, thread.stats?.placeholders)
    }

    @Test
    fun timesNoticesReceiptsAndReactionsAreNotMessages() {
        val t = FakeThread("Trail Crew")
        t.notice("Imani created the group")
        t.stamp("Fri 8:30 PM", "2026-10-31T02:30:00Z")
        t.them("Theo", "who's driving", label = true, reaction = "❤️")
        t.them("Imani", "not me, my car is in the shop", label = true, avatar = true)
        t.stamp("Oct 31, 9:10 AM", "2026-10-31T15:10:00Z")
        t.mine("I can drive", reaction = "👍2", seen = true)
        t.receipt("Seen by Theo")
        t.them("Theo", "🙏", label = true, bigEmoji = true)

        val thread = read(FakeScreen(t), 30)
        assertMessages(t.expected, thread.messages)
        assertEquals("2026-10-31T15:10:00Z", thread.messages.last().at)
    }

    @Test
    fun overlappingPagesKeepEveryMessageOnce() {
        // Repeated words on purpose: "ok" twice in a row is two messages, not a duplicate.
        val t = FakeThread("Trail Crew")
        val names = listOf("Theo", "Imani", "Kai")
        var last = ""
        for (i in 0 until 160) {
            val words = when (i % 9) {
                0 -> "ok"
                1 -> "ok"
                2 -> "lol"
                4 -> "this is a longer message about the plan for the weekend, number $i, so it wraps over a few lines"
                else -> "message $i"
            }
            if (i % 7 == 3) {
                t.mine(words)
                last = ""
            } else if (i % 11 == 5) {
                t.them(names[i % 3], null, media = "Photo", expectText = "[photo]", label = last != names[i % 3])
                last = names[i % 3]
            } else {
                val name = names[(i / 4) % 3]
                t.them(name, words, label = last != name)
                last = name
            }
        }
        // A whole page, nearly a page (a list with padding), and much less.
        for (fraction in listOf(1f, 0.95f, 0.7f, 0.45f, 0.25f)) {
            val screen = FakeScreen(t, pageFraction = fraction)
            val thread = read(screen, 120)
            assertMessages(t.expected.takeLast(120), thread.messages, "at $fraction")
            assertEquals("enough at $fraction", "enough", thread.stats?.stop)
            assertTrue("put back at $fraction", screen.atBottom)
        }
        // The whole thing, read to the top.
        val all = read(FakeScreen(t, pageFraction = 0.8f), 600)
        assertMessages(t.expected, all.messages)
        assertEquals("start", all.stats?.stop)
        assertTrue((all.stats?.dupes ?: 0) > 0)
    }

    @Test
    fun waitsForOlderMessagesAtTheTop() {
        fun batch(from: Int, to: Int) = FakeThread("Trail Crew").apply {
            for (i in from until to) if (i % 5 == 0) mine("plan $i") else them("Theo", "idea $i", label = i % 5 == 1)
        }
        val newest = batch(60, 90)
        val older = listOf(batch(30, 60), batch(0, 30))
        val expected = (older.reversed() + newest).flatMap { it.expected }
        val thread = read(FakeScreen(newest, older = older), 80)
        assertMessages(expected.takeLast(80), thread.messages)
        assertEquals("enough", thread.stats?.stop)
        assertEquals(2, thread.stats?.scrolls)

        // It may wait for older messages only so often (2 + 30 / 20 = 3 times for "Last 30").
        val many = (0 until 10).map { b -> batch(b * 5, b * 5 + 5) }.reversed()
        val capped = read(FakeScreen(batch(50, 54), older = many), 30)
        assertEquals("loads", capped.stats?.stop)
        assertEquals(3, capped.stats?.scrolls)
    }

    @Test
    fun aSlowThreadStopsAtTheBudget() {
        val t = FakeThread("Trail Crew")
        for (i in 0 until 400) t.them("Theo", "slow $i", label = i == 0)
        val thread = read(FakeScreen(t, pageFraction = 0.1f, waitMs = 2_000), 120)
        assertEquals("budget", thread.stats?.stop)
        assertTrue(thread.messages.isNotEmpty())
    }

    @Test
    fun readsTheInstagramFixtureExactly() {
        // instagram-thread.json drawn the way Instagram's app draws a group, then read back: 88 of 88.
        val fixture = KetchupJson.decodeFromString(TextThread.serializer(), Fixtures.asset("instagram-thread.json"))
        val t = drawFixture(fixture)
        for (fraction in listOf(1f, 0.93f, 0.6f)) {
            val thread = read(FakeScreen(t, pageFraction = fraction), 120)
            assertEquals(fixture.messages.size, thread.messages.size)
            fixture.messages.zip(thread.messages).forEachIndexed { i, (e, a) ->
                assertEquals("message $i", e.copy(at = null), a)
                assertEquals("wire $i", e.wireText("David"), a.wireText("David"))
            }
            assertEquals("Breck Crew 🎿", thread.title)
        }
        // "Last 30" is the newest 30.
        assertEquals(fixture.messages.takeLast(30), read(FakeScreen(t), 30).messages)
    }

    @Test
    fun stopPutsTheThreadBackAndHandsNothingOver() {
        val t = FakeThread("Trail Crew")
        for (i in 0 until 200) t.them("Theo", "plan $i", label = i == 0)
        val screen = FakeScreen(t)
        var checks = 0
        val result = runBlocking { ThreadReader(TextSource.INSTAGRAM, screen, { now }).read(120, {}, { ++checks > 3 }) }
        assertEquals(ThreadReader.Result.Stopped, result)
        assertTrue(screen.scrollsBack > 0)
        assertTrue(screen.atBottom)

        // The thread went away mid-read (the person left the app): nothing goes anywhere.
        val real = FakeScreen(t)
        var looks = 0
        val leaving = object : ReaderScreen by real {
            override suspend fun snapshot(): ReaderNode? = if (++looks > 2) null else real.window()
        }
        assertEquals(ThreadReader.Result.Stopped, runBlocking { ThreadReader(TextSource.INSTAGRAM, leaving, { now }).read(120) })
    }

    @Test
    fun notAThreadWithoutAList() {
        val screen = object : ReaderScreen by FakeScreen(FakeThread("x")) {
            override suspend fun snapshot(): ReaderNode =
                SnapshotNode(bounds = Bounds(0, 0, 1080, 2400), children = listOf(SnapshotNode(bounds = Bounds(0, 100, 1080, 200), text = "Home")))
        }
        val result = runBlocking { ThreadReader(TextSource.INSTAGRAM, screen, { now }).read(30) }
        assertEquals(ThreadReader.Result.NotAThread, result)
    }

    @Test
    fun spotsAThreadButNotTheInboxOrComments() {
        val thread = FakeScreen(FakeThread("Rosa").apply { them("Rosa", "hi") }).window()
        assertTrue(ThreadLayout.detect(thread, TextSource.INSTAGRAM) != null)
        assertNull(ThreadLayout.detect(thread, TextSource.SNAPCHAT))

        fun screen(field: SnapshotNode) = SnapshotNode(
            bounds = Bounds(0, 0, 1080, 2400),
            children = listOf(
                SnapshotNode(bounds = Bounds(0, 300, 1080, 2100), className = "androidx.recyclerview.widget.RecyclerView", isScrollable = true),
                field,
            ),
        )
        // The inbox: a search field at the top.
        assertNull(ThreadLayout.detect(screen(SnapshotNode(bounds = Bounds(40, 240, 1040, 290), hint = "Search", isEditable = true)), TextSource.INSTAGRAM))
        // A post's comments: a composer, but not a message one.
        assertNull(ThreadLayout.detect(screen(SnapshotNode(bounds = Bounds(40, 2200, 1040, 2300), hint = "Add a comment for rosa...", isEditable = true)), TextSource.INSTAGRAM))
        // Snapchat's chat.
        assertTrue(ThreadLayout.detect(screen(SnapshotNode(bounds = Bounds(40, 2200, 1040, 2300), hint = "Send a chat", isEditable = true)), TextSource.SNAPCHAT) != null)
    }

    @Test
    fun structureDumpHasNoText() {
        val t = FakeThread("Rosa Delgado").apply {
            them("Rosa", "the secret is the sauce")
            mine("never telling anyone")
        }
        val lines = StructureDump.lines(FakeScreen(t).window())
        val all = lines.joinToString("\n")
        for (word in listOf("Rosa", "secret", "sauce", "telling", "Message", "Active")) assertFalse(word, word in all)
        assertTrue(all, lines.any { "RecyclerView" in it && "scroll" in it })
        assertTrue(all, lines.any { "t=23" in it })
        assertTrue(all, lines.any { "EditText" in it && "edit" in it && "h=10" in it })
    }

    /** The fixture as Instagram's app would draw it: names over each run of theirs, avatars at its end. */
    private fun drawFixture(fixture: TextThread): FakeThread {
        val t = FakeThread(fixture.title)
        t.notice("Maya named the group ${fixture.title}")
        val m = fixture.messages
        for ((i, msg) in m.withIndex()) {
            val prev = m.getOrNull(i - 1)
            val next = m.getOrNull(i + 1)
            val first = prev == null || prev.isMine || prev.sender != msg.sender
            val lastOfRun = next == null || next.isMine || next.sender != msg.sender
            val q = msg.quote
            val media = when {
                msg.text.startsWith("[photo]") -> "Photo"
                msg.text.startsWith("[video]") -> "Video"
                msg.text.startsWith("[GIF]") -> "GIF"
                msg.text.startsWith("[voice message]") -> "Voice message"
                msg.text.startsWith("[shared post]") -> "Shared post"
                else -> null
            }
            val caption = if (media != null) msg.text.substringAfter("] ", "").ifEmpty { null } else msg.text
            val bigEmoji = media == null && Emoji.only(msg.text)
            when {
                q != null -> t.reply(
                    "${msg.sender} replied to ${q.sender}", q.text.orEmpty(), mine = false, name = msg.sender, text = msg.text,
                    expectQuote = q,
                )
                msg.isMine -> t.mine(caption, media = media, expectText = msg.text, bigEmoji = bigEmoji)
                else -> t.them(
                    msg.sender, caption, label = first, avatar = lastOfRun, media = media, expectText = msg.text,
                    duration = if (media == "Voice message") "0:07" else null, bigEmoji = bigEmoji,
                )
            }
        }
        return t
    }
}
