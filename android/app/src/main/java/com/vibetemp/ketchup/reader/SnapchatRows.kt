package com.vibetemp.ketchup.reader

import com.vibetemp.ketchup.data.TextMessage
import java.time.ZonedDateTime
import java.util.IdentityHashMap
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Reads the rows of Snapchat's chat into pieces. The shapes come from a
 * structure dump of the real app (Nov 3, 2026; class names, ids, bounds
 * and text lengths only):
 *
 * - Every message sits on the left, indented past its run's colored bar,
 *   so who sent it comes from the run's header, not from where it sits.
 * - A header row: the sender's name with a time to its right ("12:05 PM"),
 *   two text leaves side by side on one line, or the name alone at a
 *   header's left edge (further left than messages). "ME" alone is always
 *   a header. Whose run is the reader's, the walk decides ([SnapchatWalk]).
 * - A reply: `QuotedMessageView` holds the quoted sender and a time on its
 *   first line and the quoted text under them; the reply's own words sit
 *   beside it (in `plugin_content_holder`).
 * - Reactions (`chat_reactions/...` and the count beside them) are left
 *   out, and so are rows marked hidden (bound above the screen).
 * - A single line that reads as a date or time, centered or in capitals
 *   ("TODAY"), is a date row; any other centered line is a notice. Both
 *   become loose pieces the walk sorts out.
 */
internal class SnapchatRows(private val list: Bounds, private val density: Float) {
    var reactions = 0
        private set

    private class Leaf(val text: String, val media: Boolean, val bounds: Bounds)

    /** One row's leaves, outside and inside its quote. */
    private class Row(val index: Int, val own: List<Leaf>, val quoted: List<Leaf>)

    private val rows = mutableListOf<Row>()
    private val textBelow = IdentityHashMap<ReaderNode, Boolean>()

    fun read(row: ReaderNode, index: Int) {
        val quoteNode = findQuote(row)
        val own = mutableListOf<Leaf>()
        val quoted = mutableListOf<Leaf>()
        visit(row, quoteNode, inQuote = false, own, quoted)
        rows += Row(index, own.sortedWith(compareBy({ it.bounds.top }, { it.bounds.left })), quoted)
    }

    /**
     * The page's pieces. Headers sit further left than messages (which are
     * indented past the run's bar), so a lone line at a header's left edge
     * is a header too: a header cut by the list's edge can lose its time,
     * which sits a pixel lower than the name.
     */
    fun pieces(): List<Piece> {
        val headers = rows.mapNotNull { headerOf(it.own) }
        val nameLeft = headers.map { it.first.bounds.left }.sorted().getOrNull(headers.size / 2)
        val textLeft = rows.filter { it.quoted.isEmpty() && it.own.size == 1 && !it.own[0].media && headerOf(it.own) == null }
            .map { it.own[0].bounds.left }.sorted().let { it.getOrNull(it.size / 2) }
        val outdent = 4 * density
        fun atHeaderEdge(leaf: Leaf): Boolean = when {
            nameLeft != null && abs(leaf.bounds.left - nameLeft) <= 2 * density -> textLeft == null || leaf.bounds.left < textLeft - outdent
            else -> textLeft != null && leaf.bounds.left < textLeft - outdent
        }

        val out = mutableListOf<Piece>()
        for (row in rows) {
            val own = row.own
            if (row.quoted.isNotEmpty()) {
                // Placed by its own words, which every view of it shows the same way; the quote above may be cut off.
                out += message(row.index, own, quote(row.quoted), union(own.ifEmpty { row.quoted }))
                continue
            }
            if (own.isEmpty()) continue
            val header = headerOf(own)
            if (header != null) {
                out += piece(row.index, isMessage = false, text = header.first.text, media = false, box = union(own), header = true, time = header.second.text)
                continue
            }
            val only = own.singleOrNull()
            if (only != null && !only.media && '\n' !in only.text) {
                // "ME" on its own line is the reader's header with no time, never a date: unless it
                // sits where messages sit on this page (someone answering "me").
                val me = only.text.trim().equals("me", ignoreCase = true) && (atHeaderEdge(only) || (nameLeft == null && textLeft == null))
                if (!me && (centered(only.bounds) || (only.text == only.text.uppercase() && isStamp(only.text)))) {
                    // A date row ("TODAY") or a notice: the walk keeps the date and drops the rest.
                    out += piece(row.index, isMessage = false, text = only.text, media = false, box = only.bounds)
                    continue
                }
                if (me || (only.text.length <= 40 && atHeaderEdge(only))) {
                    out += piece(row.index, isMessage = false, text = only.text, media = false, box = only.bounds, header = true)
                    continue
                }
            }
            out += message(row.index, own, null, union(own))
        }
        return out
    }

    /** One message: its placeholders, then its words, line by line. */
    private fun message(index: Int, leaves: List<Leaf>, quote: TextMessage.Quote?, box: Bounds): Piece {
        val media = leaves.filter { it.media }.map { it.text }.distinct()
        val words = leaves.filter { !it.media }.joinToString("\n") { it.text }
        val text = (media + listOfNotNull(words.ifEmpty { null })).joinToString(" ")
        return piece(index, isMessage = true, text = text, media = media.isNotEmpty(), box = box, quote = quote)
    }

    /**
     * The quoted message: its first line holds the sender (leftmost) and a
     * time; what's under that line is what it said.
     */
    private fun quote(leaves: List<Leaf>): TextMessage.Quote {
        val sorted = leaves.sortedWith(compareBy({ it.bounds.top }, { it.bounds.left }))
        if (sorted.size == 1) return TextMessage.Quote(text = sorted.single().text)
        val first = sorted.first()
        val line = sorted.filter { sameLine(it.bounds, first.bounds) }
        val said = (sorted - line.toSet()).joinToString(" ") { it.text }.replace(Regex("\\s+"), " ").trim()
        val sender = line.minBy { it.bounds.left }.text
        return if (said.isEmpty() && line.size == 1) TextMessage.Quote(text = sender) else TextMessage.Quote(sender = sender, text = said.ifEmpty { null })
    }

    /** A header: two short single-line leaves side by side, the name on the left and a time after it. */
    private fun headerOf(leaves: List<Leaf>): Pair<Leaf, Leaf>? {
        if (leaves.size != 2 || leaves.any { it.media || '\n' in it.text }) return null
        val (name, time) = leaves.sortedBy { it.bounds.left }
        if (name.text.length > 40 || time.text.length > 16) return null
        if (!sameLine(name.bounds, time.bounds) || time.bounds.left < name.bounds.right - 2 * density) return null
        return name to time
    }

    private fun visit(node: ReaderNode, quoteNode: ReaderNode?, inQuote: Boolean, own: MutableList<Leaf>, quoted: MutableList<Leaf>) {
        val b = node.bounds
        if (!node.isVisibleToUser || b.isEmpty || !b.intersects(list) || node.isEditable) return
        if (isReactions(node)) {
            reactions++
            return
        }
        val quoting = inQuote || node === quoteNode
        val out = if (quoting) quoted else own
        val text = PageParser.clean(node.text)
        val below = hasTextBelow(node)
        if (text.isNotEmpty() && !below) {
            out += Leaf(text, media = false, bounds = b)
            return
        }
        if (text.isEmpty() && !below) {
            val media = PageParser.placeholder(PageParser.clean(node.contentDescription), node.className, b, density)
            if (media != null) {
                out += Leaf(media, media = true, bounds = b)
                return
            }
        }
        node.children.forEach { visit(it, quoteNode, quoting, own, quoted) }
    }

    /** A reaction, or the box holding a reaction and its count. */
    private fun isReactions(node: ReaderNode): Boolean =
        idName(node)?.contains(REACTIONS) == true || node.children.any { idName(it)?.contains(REACTIONS) == true }

    private fun findQuote(row: ReaderNode): ReaderNode? {
        var found: ReaderNode? = null
        row.walkTree { node, _ -> if (found == null && idName(node) == QUOTE) found = node }
        return found
    }

    private fun hasTextBelow(node: ReaderNode): Boolean = textBelow.getOrPut(node) {
        node.children.any { child ->
            child.isVisibleToUser && !child.isEditable && (PageParser.clean(child.text).isNotEmpty() || hasTextBelow(child))
        }
    }

    private fun piece(
        row: Int,
        isMessage: Boolean,
        text: String,
        media: Boolean,
        box: Bounds,
        header: Boolean = false,
        time: String? = null,
        quote: TextMessage.Quote? = null,
    ): Piece {
        val b = box.clippedTo(list)
        return Piece(
            isMessage = isMessage,
            inBubble = false,
            text = text,
            media = media,
            side = if (b.left - list.left > list.right - b.right) Side.ME else Side.THEM,
            centered = centered(b),
            bounds = b,
            clipTop = b.top <= list.top + 1,
            clipBottom = b.bottom >= list.bottom - 1,
            row = row,
            tall = b.height >= 32 * density,
            header = header,
            time = time,
            quote = quote,
        )
    }

    private fun centered(b: Bounds): Boolean =
        abs(b.centerX - list.centerX) <= max(8 * density, list.width * 0.06f) && b.width < list.width * 0.9f

    private fun sameLine(a: Bounds, b: Bounds): Boolean = min(a.bottom, b.bottom) - max(a.top, b.top) >= min(a.height, b.height) / 2

    private fun union(leaves: List<Leaf>): Bounds = leaves.map { it.bounds }.reduce { a, b ->
        Bounds(min(a.left, b.left), min(a.top, b.top), max(a.right, b.right), max(a.bottom, b.bottom))
    }

    private fun idName(node: ReaderNode): String? = ThreadLayout.idName(node)

    private fun isStamp(text: String): Boolean = Stamps.parse(text, ZonedDateTime.now()) != null

    private companion object {
        const val QUOTE = "QuotedMessageView"
        const val REACTIONS = "chat_reactions"
    }
}
