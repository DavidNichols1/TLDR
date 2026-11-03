package com.vibetemp.ketchup.reader

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
    fun add(page: Page): Int {
        val base = rowParent.size
        repeat(page.rows) { rowParent += rowParent.size }
        rowsSeen += page.rows
        previous?.let { offset += shift(it, page) }
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
        val proposals = sortedSetOf<Int>()
        for (a in before.pieces) for (b in after.pieces) {
            if (a.key != b.key) continue
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
        if (a.isMessage != b.isMessage || a.side != b.side) return false
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

    /** Keeps the fuller view of a piece seen twice. */
    private fun merge(a: Placed, b: Placed) {
        if (b.piece.text.length > a.piece.text.length) a.piece = b.piece
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
