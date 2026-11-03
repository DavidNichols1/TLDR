package com.vibetemp.ketchup.reader

import com.vibetemp.ketchup.data.TextMessage
import com.vibetemp.ketchup.data.TextSource
import com.vibetemp.ketchup.data.TextThread
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.random.Random

/**
 * "Until I stop scrolling" and "Last 10", on a fake clock with the person's
 * scrolling scripted (made-up people). No scroll of the reader's own.
 */
class FollowReaderTest {

    private val now = ZonedDateTime.of(2026, 11, 3, 10, 30, 0, 0, ZoneId.of("America/Denver"))

    /** A long group thread, every message saying something different. */
    private fun thread(count: Int): FakeThread {
        val t = FakeThread("Trail Crew")
        val names = listOf("Theo", "Imani", "Kai")
        var last = ""
        for (i in 0 until count) {
            if (i % 5 == 2) {
                t.mine("plan $i")
                last = ""
            } else {
                val name = names[(i / 3) % 3]
                t.them(name, if (i % 7 == 4) "a longer message about the weekend, number $i, so it wraps over a few lines" else "message $i", label = last != name)
                last = name
            }
        }
        return t
    }

    private fun follow(
        screen: ReaderScreen,
        source: TextSource = TextSource.INSTAGRAM,
        finishNow: () -> Boolean = { false },
        stopped: () -> Boolean = { false },
    ): ThreadReader.Result = runBlocking { ThreadReader(source, screen, { now }, Random(1)).follow({}, finishNow, stopped) }

    private fun followed(screen: ReaderScreen, source: TextSource = TextSource.INSTAGRAM): TextThread =
        (follow(screen, source) as ThreadReader.Result.Read).thread

    /**
     * One run of the thread, newest last, each message once. The oldest
     * run's sender may be unknown ("Someone"): its name sat above what the
     * person scrolled to.
     */
    private fun assertNewestRun(expected: List<TextMessage>, read: List<TextMessage>) {
        val want = expected.takeLast(read.size)
        assertEquals(want.size, read.size)
        var leading = true
        read.zip(want).forEachIndexed { i, (r, e) ->
            if (leading && r.sender == "Someone" && !e.isMine) {
                assertEquals("message $i", e.copy(sender = "Someone"), r)
            } else {
                leading = false
                assertEquals("message $i", e, r)
            }
        }
    }

    @Test
    fun followsTheScrollAndFinishesWhenTheyStop() {
        val t = thread(120)
        val firstScreen = followed(FakeScreen(t)).messages.size
        // Half a page at a time; a 2.2 s pause (under 3 s) in the middle; then they stop.
        val script = listOf(600L to 0.5f, 1_200L to 0.5f, 1_800L to 0.5f, 4_000L to 0.5f, 4_600L to 0.5f)
        val read = followed(FakeScreen(t, script = script))
        assertNewestRun(t.expected, read.messages)
        assertTrue("${read.messages.size} > $firstScreen", read.messages.size > firstScreen + 20)
        val ms = read.stats?.ms ?: 0
        assertTrue("finished at $ms", ms in 7_600..8_200)
        assertEquals("enough", read.stats?.stop)
        assertEquals(0, read.stats?.scrolls)
    }

    @Test
    fun followsOnSnapchatToo() {
        val fake = FakeSnapThread("Trail Crew")
        val people = listOf("Theo", "ME", "Imani")
        for (run in 0 until 30) {
            fake.header(people[run % 3], "8:15 AM", "2026-11-03T15:15:00Z")
            repeat(1 + run % 3) { fake.message("run $run, line $it") }
        }
        val script = (1..6).map { it * 500L to 0.45f }
        val read = followed(FakeScreen(fake.thread, snapchat = true, script = script), TextSource.SNAPCHAT)
        assertNewestRun(fake.thread.expected, read.messages)
        assertTrue(read.messages.any { it.isMine })
    }

    @Test
    fun neverScrollingFinishesAfterFiveSeconds() {
        val t = thread(120)
        val read = followed(FakeScreen(t))
        assertNewestRun(t.expected, read.messages)
        val ms = read.stats?.ms ?: 0
        assertTrue("finished at $ms", ms in 5_000..5_300)
    }

    @Test
    fun scrollingBackDownReadsNothingTwice() {
        val t = thread(120)
        val script = listOf(500L to 0.6f, 1_000L to 0.6f, 1_500L to -0.6f, 2_000L to -0.6f, 2_500L to 0.3f, 3_000L to 1.2f, 3_500L to -0.9f)
        val read = followed(FakeScreen(t, script = script))
        assertNewestRun(t.expected, read.messages)
    }

    @Test
    fun aFlingPastAPageKeepsTheOrder() {
        val t = thread(160)
        // More than a page between two looks: what was flung past is missed, nothing is read twice or out of order.
        val script = listOf(500L to 0.3f, 1_000L to 1.8f, 1_500L to 0.3f)
        val read = followed(FakeScreen(t, script = script))
        var at = 0
        for (m in read.messages) {
            val found = t.expected.subList(at, t.expected.size).indexOfFirst { it.text == m.text }
            assertTrue("in order, once: ${m.text}", found >= 0)
            val e = t.expected[at + found]
            at += found + 1
            // After a stretch nobody read, a run's name is unknown rather than carried over wrongly.
            assertEquals(e.isMine, m.isMine)
            assertTrue("${m.text}: ${m.sender}", m.sender == e.sender || m.sender == "Someone")
        }
        assertEquals(read.messages.size, read.messages.map { it.text }.toSet().size)
        assertTrue(read.messages.size < 40)
    }

    @Test
    fun stopsAtSixHundred() {
        val t = thread(720)
        val script = (1..200).map { it * 300L to 0.8f }
        val read = followed(FakeScreen(t, script = script))
        assertEquals(600, read.messages.size)
        assertNewestRun(t.expected, read.messages)
        assertEquals("enough", read.stats?.stop)
    }

    @Test
    fun catchMeUpNowFinishesAtOnce() {
        val t = thread(120)
        val screen = FakeScreen(t, script = (1..20).map { it * 400L to 0.4f })
        val result = follow(screen, finishNow = { screen.clock() >= 1_700 })
        val read = (result as ThreadReader.Result.Read).thread
        assertNewestRun(t.expected, read.messages)
        assertTrue("finished at ${read.stats?.ms}", (read.stats?.ms ?: 0) in 1_700..2_000)
    }

    @Test
    fun stopHandsOverNothing() {
        val screen = FakeScreen(thread(120), script = (1..20).map { it * 400L to 0.4f })
        assertEquals(ThreadReader.Result.Stopped, follow(screen, stopped = { screen.clock() >= 1_000 }))
    }

    @Test
    fun lastTen() {
        assertEquals(listOf(10, 30, 80, 120), ThreadReader.WINDOWS)
        val t = thread(120)
        val read = runBlocking { ThreadReader(TextSource.INSTAGRAM, FakeScreen(t), { now }, Random(1)).read(10) }
        assertEquals(t.expected.takeLast(10), (read as ThreadReader.Result.Read).thread.messages)
    }
}
