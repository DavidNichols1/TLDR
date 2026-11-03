package com.vibetemp.ketchup.reader

import com.vibetemp.ketchup.data.ReaderStats
import com.vibetemp.ketchup.data.TextSource
import com.vibetemp.ketchup.data.TextThread
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.min
import kotlin.random.Random

/**
 * What the reader drives: the other app's screen. The service implements
 * it over the accessibility API; tests fake a long thread with it.
 */
interface ReaderScreen {
    /** Pixels per dp. */
    val density: Float

    /** The window as it is right now, text included. Only ever called after the person's tap. */
    suspend fun snapshot(): ReaderNode?

    /** Scrolls the list one page toward older messages. False when it can't go further right now. */
    suspend fun scrollBack(): Boolean

    /** Scrolls one page back toward the newest, to put the thread back where it was. */
    suspend fun scrollForward(): Boolean

    /** Waits until the list stops changing after a scroll, at most [timeoutMs]. True if it changed at all. */
    suspend fun awaitChange(timeoutMs: Long): Boolean

    /** A plain wait. */
    suspend fun pause(ms: Long)

    /** Milliseconds on a steady clock, for the time budget. */
    fun clock(): Long
}

/** How far a read got, for the panel. */
data class ReadProgress(val found: Int, val wanted: Int, val restoring: Boolean = false)

/**
 * Reads the newest [last][read] messages of the thread on screen: one tap,
 * one read. It scrolls back a page at a time with ACTION_SCROLL_BACKWARD,
 * waits for the list to settle, reads what's on screen, and lays the pages
 * together ([Stitcher]). At the top of what's loaded the app may fetch
 * older messages itself, the way it does for a person; the reader waits
 * for that a few times, then puts the scroll back where it was.
 *
 * Stop reasons (catch-up-text's `stop`, the same words as iOS): "enough"
 * (found the wanted count, plus two for context), "start" (the top of the
 * thread), "loads" (waited for older messages as often as it may),
 * "steps" (scrolled as often as it may), "budget" (out of time) and
 * "no-scroller" (the list doesn't scroll: what's on screen is all).
 */
class ThreadReader(
    private val source: TextSource,
    private val screen: ReaderScreen,
    private val now: () -> ZonedDateTime = { ZonedDateTime.now(ZoneId.systemDefault()) },
    private val random: Random = Random.Default,
    /** Snapchat: the reader's Ketchup name and a Snapchat name learned before, for finding their own messages. */
    private val snapchatNames: SnapchatWalk.Names = SnapchatWalk.Names(),
) {
    sealed interface Result {
        /** [snap]: on Snapchat, how the reader's own messages were found (for the debug log and "Which one is you?"). */
        data class Read(val thread: TextThread, val snap: SnapchatWalk.Decision? = null) : Result

        /** No message list on screen. */
        data object NotAThread : Result

        /** A list, but nothing in it read as a message. */
        data object NothingFound : Result

        /** The person stopped it, or the thread went away mid-read. Nothing goes anywhere. */
        data object Stopped : Result
    }

    /**
     * [stopped] is checked between scrolls: when it says so, the reader puts
     * the thread back and returns [Result.Stopped].
     */
    suspend fun read(last: Int, onProgress: (ReadProgress) -> Unit = {}, stopped: () -> Boolean = { false }): Result {
        val wanted = last.coerceIn(1, MAX_MESSAGES)
        val started = screen.clock()
        val density = screen.density
        val first = screen.snapshot()?.let { PageParser.parse(it, source, density) } ?: return Result.NotAThread
        val stitcher = Stitcher(density)
        stitcher.add(first)
        val title = first.title
        fun walk() = if (source == TextSource.SNAPCHAT) {
            SnapchatWalk.walk(stitcher.pieces, title, snapchatNames, now())
        } else {
            ThreadWalk.walk(stitcher.pieces, stitcher::group, title, density, now())
        }

        // Older messages come in batches of about 20: a bigger pick may need a few more.
        val maxLoads = min(10, 2 + wanted / 20)
        var steps = 0
        var loads = 0
        var stalls = 0
        var reachedStart = false
        var gone = false
        val stop: String

        suspend fun step(): Boolean {
            if (!screen.scrollBack()) return false
            steps++
            screen.awaitChange(SETTLE_MS)
            val root = screen.snapshot()
            if (root == null) gone = true
            val page = root?.let { PageParser.parse(it, source, density) }
            if (page != null && stitcher.add(page) > 0) stalls = 0 else stalls++
            return true
        }

        if (!first.scrollable) {
            stop = "no-scroller"
        } else {
            var naming = 0
            while (true) {
                val walked = walk()
                val found = walked.messages.size
                onProgress(ReadProgress(min(found, wanted), wanted))
                if (found >= wanted + 2) {
                    // In a group, a name label sits over the first message of a run (on Snapchat,
                    // every run has a header). When the oldest one kept has none yet, its run
                    // started higher up: read a little more.
                    val oldest = walked.messages[found - wanted]
                    val unnamed = (walked.isGroup && !oldest.isMine && oldest.sender == UNNAMED) ||
                        found - wanted < walked.unnamedBefore
                    if (!unnamed || naming >= NAMING_STEPS) {
                        stop = "enough"
                        break
                    }
                    naming++
                }
                if (gone || stopped()) {
                    stop = "steps"
                    break
                }
                if (screen.clock() - started >= BUDGET_MS) {
                    stop = "budget"
                    break
                }
                if (steps >= MAX_STEPS) {
                    stop = "steps"
                    break
                }
                // Two scrolls in a row that showed nothing new: as good as the top.
                if (stalls < 2 && step()) continue
                // The top of what's loaded. The app fetches older messages on its own; wait for that.
                if (loads >= maxLoads) {
                    stop = "loads"
                    break
                }
                var grew = false
                val until = screen.clock() + LOAD_WAIT_MS
                while (!grew && !gone && !stopped() && screen.clock() < until) {
                    screen.awaitChange(LOAD_POLL_MS)
                    stalls = 0
                    grew = step() && stalls == 0
                }
                if (!grew) {
                    reachedStart = true
                    stop = "start"
                    break
                }
                loads++
                screen.pause(300L + random.nextLong(300)) // be gentle
            }
        }
        val ms = screen.clock() - started

        // Put the thread back where the person had it (unless it's gone).
        if (steps > 0 && !gone) {
            onProgress(ReadProgress(min(walk().messages.size, wanted), wanted, restoring = true))
            repeat(steps) {
                if (screen.clock() - started >= BUDGET_MS + RESTORE_MS || !screen.scrollForward()) return@repeat
                screen.awaitChange(RESTORE_SETTLE_MS)
            }
        }

        if (gone || stopped()) return Result.Stopped
        val result = walk()
        if (result.messages.isEmpty()) return Result.NothingFound
        val stats = ReaderStats(
            found = result.messages.size,
            scrolls = loads,
            ms = ms,
            reachedStart = reachedStart,
            stop = stop,
            root = first.root,
            steps = steps,
            gaps = 0,
            placeholders = result.media,
            rows = stitcher.rowsSeen,
            units = stitcher.pieces.count { it.piece.isMessage },
            skipped = result.skipped,
            empty = result.empty,
            dupes = stitcher.dupes,
        )
        return Result.Read(TextThread(source, title, result.messages.takeLast(wanted), stats), result.snap)
    }

    companion object {
        /** The three picks the panel offers, as on iOS (WebChatTab.windows). */
        val WINDOWS = listOf(30, 80, 120)

        const val MAX_MESSAGES = 600
        const val BUDGET_MS = 45_000L
        const val MAX_STEPS = 250
        private const val NAMING_STEPS = 3
        private const val UNNAMED = "Someone"
        private const val SETTLE_MS = 1_500L
        private const val LOAD_WAIT_MS = 4_000L
        private const val LOAD_POLL_MS = 700L
        private const val RESTORE_MS = 8_000L
        private const val RESTORE_SETTLE_MS = 900L
    }
}
