package com.vibetemp.ketchup.reader

import com.vibetemp.ketchup.data.TextMessage
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

/** A piece placed in the whole thread: [top] and [bottom] are pixels from where the first page was. */
internal class Placed(
    var piece: Piece,
    var top: Int,
    var bottom: Int,
    var clipTop: Boolean,
    var clipBottom: Boolean,
    val row: Int,
    val seq: Int,
)

/**
 * Lays the pages of a read on top of each other, oldest last, and keeps
 * every piece once. A scroll back moves what's on screen down by about a
 * page, and the list only holds the rows near the screen, so each page is
 * placed by how far its pieces moved since the page before: the shift most
 * of the shared pieces agree on (several different texts beat one repeated
 * "[photo]"). With no piece in common (the scroll moved exactly a page),
 * it moved by the list's height.
 *
 * A piece is the same as one already kept when it says the same thing at
 * the same place. A piece cut off by the list's edge has only one true
 * edge, so that's the one compared; a piece cut in half by the edge
 * between two pages is seen as its two halves meeting there. Positions,
 * not text alone, so "ok" and "ok" a minute apart stay two messages.
 *
 * The rows a duplicate was seen in are joined, so a reply's header, quote
 * and message still count as one row when the row was split across pages.
 */
internal class Stitcher(density: Float) {
    private val tolerance = max(4, (3 * density).roundToInt())

    /** Room left above everything read for a page with nothing in common: more than a walk's unread gap. */
    private val unreadGap = ((ThreadWalk.UNREAD_GAP_DP + 60) * density).roundToInt()

    /** A bubble's text sits this far inside it: less of a bubble than this on screen shows no text. */
    private val padding = max(tolerance, (16 * density).roundToInt())
    private val placed = mutableListOf<Placed>()
    private var previous: Page? = null
    private var offset = 0
    private var seq = 0
    private val rowParent = mutableListOf<Int>()

    /** Pieces seen again and not kept twice. */
    var dupes = 0
        private set

    /** Every row seen, in every page. */
    var rowsSeen = 0
        private set

    val pieces: List<Placed> get() = placed

    /** The row group [p] belongs to: rows joined by a piece seen in both. */
    fun group(p: Placed): Int = find(p.row)

    /** Adds the next (older) page. Returns how many pieces were new. */
    fun add(page: Page): Int = place(page, previous?.let { shift(it, page) } ?: 0)

    /**
     * Adds a page the person scrolled to themselves ("Until I stop
     * scrolling"); they were asked to scroll up. Placed by what it shares
     * with the last page added (two different texts must agree). A page
     * that moved back down is left out: what's there was read on the way up,
     * or was flung past, and has no place to go. More than a page from the
     * last one, it's either something already read (left out) or new and
     * older, placed just above everything read. Returns how many pieces
     * were new.
     */
    fun addFollowing(page: Page): Int {
        val before = previous ?: return place(page, 0)
        unmoved(before, page)?.let { return place(page, it) }
        followShift(before, page)?.let { moved -> return if (moved < -tolerance) 0 else place(page, moved) }
        if (realign(page) != null) return 0
        return place(page, above(page))
    }

    private fun place(page: Page, moved: Int): Int {
        val base = rowParent.size
        repeat(page.rows) { rowParent += rowParent.size }
        rowsSeen += page.rows
        offset += moved
        var added = 0
        for (p in page.pieces) {
            val next = Placed(p, p.bounds.top - offset, p.bounds.bottom - offset, p.clipTop, p.clipBottom, base + p.row, seq++)
            val same = placed.firstOrNull { isSame(it, next) }
            if (same == null) {
                placed += next
                added++
            } else {
                merge(same, next)
                dupes++
            }
        }
        previous = page
        return added
    }

    /**
     * How far the screen's content moved down from [before] to [after], in
     * pixels. Every pair of pieces that say the same thing proposes a shift;
     * a proposal only counts if the pages agree under it: every true edge
     * it puts inside the other page must meet a piece saying the same thing
     * there (a few may differ, like "Seen" arriving). A scroll back moves a
     * whole page less the list's padding, or less at the top, so one
     * agreeing text will do for those. Names and "ok" repeat all over a
     * thread, so any other shift takes two different texts. With no
     * proposal standing, it moved a whole page.
     */
    private fun shift(before: Page, after: Page): Int {
        val expected = after.list.height
        // The same pieces in the same order: the list didn't move (or less than a piece), whatever the
        // scroll said. A Snapchat page with one message on it otherwise read as a whole new page each
        // time, and that message came back over and over (Nov 3, 2026).
        unmoved(before, after)?.let { return it }
        val proposals = sortedSetOf<Int>()
        for (a in before.pieces) for (b in after.pieces) {
            // A reply's quote cut off from its words says nothing to line up on.
            if (a.key != b.key || a.text.isEmpty()) continue
            val moved = when {
                !a.clipTop && !b.clipTop -> b.bounds.top - a.bounds.top
                !a.clipBottom && !b.clipBottom -> b.bounds.bottom - a.bounds.bottom
                else -> continue
            }
            if (moved >= -tolerance && moved <= expected + tolerance) proposals += moved
        }
        var best = expected
        var bestScore = Int.MIN_VALUE
        for (moved in proposals) {
            val fit = Fit()
            check(after, before, -moved, fit)
            check(before, after, moved, fit)
            // Most of a page (a page less the list's padding) or a short last scroll at the top.
            val usual = !after.canScrollBack || moved >= expected * 0.6f
            if (fit.texts.size < (if (usual) 1 else 2) || fit.misses * 3 > fit.matches) continue
            val score = fit.matches - 2 * fit.misses
            if (score > bestScore || (score == bestScore && abs(moved - expected) < abs(best - expected))) {
                best = moved
                bestScore = score
            }
        }
        return best
    }

    /** The same pieces in the same order: how far they moved (0 when the list didn't move), or null. */
    private fun unmoved(before: Page, after: Page): Int? {
        if (before.pieces.isEmpty() || before.pieces.map { it.key } != after.pieces.map { it.key }) return null
        val moves = before.pieces.zip(after.pieces).mapNotNull { (a, b) ->
            when {
                !a.clipTop && !b.clipTop -> b.bounds.top - a.bounds.top
                !a.clipBottom && !b.clipBottom -> b.bounds.bottom - a.bounds.bottom
                else -> null
            }
        }.sorted()
        return moves.getOrNull(moves.size / 2) ?: 0
    }

    /**
     * The person's own scroll since [before]: either way, up to a page.
     * Every shift two pieces that say the same thing propose must leave the
     * pages agreeing, with two different texts (one, when a page holds just
     * one), the smallest standing shift winning a tie.
     */
    private fun followShift(before: Page, after: Page): Int? {
        val reach = after.list.height + tolerance
        val proposals = sortedSetOf<Int>()
        for (a in before.pieces) for (b in after.pieces) {
            if (a.key != b.key || a.text.isEmpty()) continue
            val moved = when {
                !a.clipTop && !b.clipTop -> b.bounds.top - a.bounds.top
                !a.clipBottom && !b.clipBottom -> b.bounds.bottom - a.bounds.bottom
                else -> continue
            }
            if (abs(moved) <= reach) proposals += moved
        }
        val needed = if (before.pieces.map { it.key }.distinct().size <= 1 || after.pieces.map { it.key }.distinct().size <= 1) 1 else 2
        var best: Int? = null
        var bestScore = Int.MIN_VALUE
        for (moved in proposals) {
            val fit = Fit()
            check(after, before, -moved, fit)
            check(before, after, moved, fit)
            if (fit.texts.size < needed || fit.misses * 3 > fit.matches) continue
            val score = fit.matches - 2 * fit.misses
            val current = best
            if (score > bestScore || (score == bestScore && current != null && abs(moved) < abs(current))) {
                best = moved
                bestScore = score
            }
        }
        return best
    }

    /**
     * Lines [page] up with everything read so far (the person scrolled back
     * to something seen before, past the page before). Each offset two
     * messages propose must hold up: wherever the page would land on
     * something already read, it must say the same thing there. Two
     * different messages must agree (names repeat in every run), with few
     * misses. Null when nothing holds.
     */
    private fun realign(page: Page): Int? {
        val proposals = sortedSetOf<Int>()
        for (b in page.pieces) {
            if (!b.isMessage || b.text.isEmpty()) continue
            for (a in placed) {
                if (!says(a.piece, b)) continue
                // The offset that puts b where a is: abs = screen - offset.
                proposals += when {
                    !a.clipTop && !b.clipTop -> b.bounds.top - a.top
                    !a.clipBottom && !b.clipBottom -> b.bounds.bottom - a.bottom
                    else -> continue
                }
            }
        }
        var best: Int? = null
        var bestScore = Int.MIN_VALUE
        for (o in proposals) {
            var matches = 0
            var misses = 0
            val texts = HashSet<String>()
            for (b in page.pieces) {
                if (b.text.isEmpty()) continue
                val top = b.bounds.top - o
                val bottom = b.bounds.bottom - o
                val there = placed.filter { minOf(it.bottom, bottom) - maxOf(it.top, top) > tolerance }
                if (there.isEmpty()) continue // not read yet: no evidence either way
                val same = there.any { a ->
                    says(a.piece, b) && ((!a.clipTop && !b.clipTop && abs(a.top - top) <= tolerance) ||
                        (!a.clipBottom && !b.clipBottom && abs(a.bottom - bottom) <= tolerance) ||
                        a.clipTop || a.clipBottom || b.clipTop || b.clipBottom)
                }
                if (same) {
                    matches++
                    if (b.isMessage) texts += b.key
                } else {
                    misses++
                }
            }
            if (texts.size < 2 || misses * 3 > matches) continue
            val score = matches - 2 * misses
            if (score > bestScore) {
                best = o
                bestScore = score
            }
        }
        return best?.let { it - offset }
    }

    /** Nothing in common with anything read: just above everything, since the person scrolls up. */
    private fun above(page: Page): Int {
        if (page.pieces.isEmpty() || placed.isEmpty()) return 0
        val topmost = placed.minOf { it.top }
        val lowest = page.pieces.maxOf { it.bounds.bottom }
        return lowest - (topmost - unreadGap) - offset
    }

    private class Fit {
        var matches = 0
        var misses = 0
        val texts = HashSet<String>()
    }

    /**
     * Moves [from]'s true edges by [dy] and counts which land on a matching
     * piece of [onto]. An edge only counts where enough of the piece would
     * be on [onto] to show: a bubble's last few dp at the list's edge hold
     * no text, so there's no piece there to meet.
     */
    private fun check(from: Page, onto: Page, dy: Int, fit: Fit) {
        val list = onto.list
        for (p in from.pieces) {
            if (p.text.isEmpty()) continue
            val top = p.bounds.top + dy
            val bottom = p.bounds.bottom + dy
            val shows = if (p.isMessage) padding else tolerance
            val useTop = !p.clipTop && top >= list.top + tolerance && top <= list.bottom - shows
            val useBottom = !p.clipBottom && bottom >= list.top + shows && bottom <= list.bottom - tolerance
            if (!useTop && !useBottom) continue
            val hit = onto.pieces.any { o ->
                says(o, p) && ((useTop && !o.clipTop && abs(o.bounds.top - top) <= tolerance) ||
                    (useBottom && !o.clipBottom && abs(o.bounds.bottom - bottom) <= tolerance))
            }
            if (hit) {
                fit.matches++
                fit.texts += p.key
            } else {
                fit.misses++
            }
        }
    }

    /**
     * The two say the same thing. A bubble cut off by the list's edge may be
     * missing a line (a photo's caption), so a cut-off one only has to be
     * part of the other.
     */
    private fun says(a: Piece, b: Piece): Boolean {
        if (a.isMessage != b.isMessage || a.side != b.side || a.header != b.header) return false
        // A reply's quote cut off from its words: only the same quote is the same piece.
        if (a.text.isEmpty() || b.text.isEmpty()) return a.text == b.text && a.quote != null && a.quote == b.quote
        if (a.text == b.text) return true
        val clipped = a.clipTop || a.clipBottom || b.clipTop || b.clipBottom
        return clipped && a.text.isNotEmpty() && b.text.isNotEmpty() && (a.text in b.text || b.text in a.text)
    }

    /** [b] (just read) is [a] (kept) seen again. */
    private fun isSame(a: Placed, b: Placed): Boolean {
        if (!says(a.piece, b.piece)) return false
        // Two pieces of a list never overlap: saying the same thing in the same place, it's one.
        if (minOf(a.bottom, b.bottom) - maxOf(a.top, b.top) > tolerance) return true
        return (!a.clipTop && !b.clipTop && abs(a.top - b.top) <= tolerance) ||
            (!a.clipBottom && !b.clipBottom && abs(a.bottom - b.bottom) <= tolerance) ||
            // Cut by the edge between two pages: the newer page saw its bottom half, the older one its top.
            (a.clipTop && b.clipBottom && abs(a.top - b.bottom) <= tolerance * 2)
    }

    /** Keeps the fuller view of a piece seen twice (a reply cut off by the edge may have lost part of its quote). */
    private fun merge(a: Placed, b: Placed) {
        val keep = if (b.piece.text.length > a.piece.text.length) b.piece else a.piece
        val quote = Quotes.merge(a.piece.quote, b.piece.quote)
        a.piece = if (quote == keep.quote) keep else keep.copy(quote = quote)
        if (a.clipTop && !b.clipTop) {
            a.top = b.top
            a.clipTop = false
        } else if (a.clipTop && b.clipTop) {
            a.top = minOf(a.top, b.top)
        }
        if (a.clipBottom && !b.clipBottom) {
            a.bottom = b.bottom
            a.clipBottom = false
        } else if (a.clipBottom && b.clipBottom) {
            a.bottom = maxOf(a.bottom, b.bottom)
        }
        union(a.row, b.row)
    }

    private fun find(x: Int): Int {
        var r = x
        while (rowParent[r] != r) r = rowParent[r]
        var n = x
        while (rowParent[n] != r) {
            val up = rowParent[n]
            rowParent[n] = r
            n = up
        }
        return r
    }

    private fun union(a: Int, b: Int) {
        val ra = find(a)
        val rb = find(b)
        if (ra != rb) rowParent[rb] = ra
    }
}

/** Two views of the same quote (each may be cut off by the list's edge) as one: the sender from either, the longer text. */
internal object Quotes {
    fun merge(x: TextMessage.Quote?, y: TextMessage.Quote?): TextMessage.Quote? = when {
        x == null -> y
        y == null -> x
        else -> TextMessage.Quote(
            sender = x.sender ?: y.sender,
            text = listOfNotNull(x.text, y.text).maxByOrNull { it.length },
            isMine = x.isMine || y.isMine,
        )
    }
}
