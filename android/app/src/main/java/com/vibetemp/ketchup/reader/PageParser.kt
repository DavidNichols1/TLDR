package com.vibetemp.ketchup.reader

import com.vibetemp.ketchup.data.TextSource
import java.util.IdentityHashMap
import kotlin.math.abs
import kotlin.math.max

/** Which side of the thread a piece sits on: right is the reader's own. */
internal enum class Side { ME, THEM }

/**
 * One piece of a page: a message (everything inside one bubble, or a
 * photo on its own) or a loose line of text (a name label, a time stamp,
 * "Seen", a notice). In screen pixels, clipped to the list.
 */
internal class Piece(
    /** A message: a bubble's text and media, or media with no bubble. */
    val isMessage: Boolean,
    /** Inside a bubble (a tappable or long-pressable box that isn't the whole row). */
    val inBubble: Boolean,
    val text: String,
    /** Its text is or starts with a placeholder like "[photo]". */
    val media: Boolean,
    val side: Side,
    val centered: Boolean,
    val bounds: Bounds,
    val clipTop: Boolean,
    val clipBottom: Boolean,
    /** The row's index in its page. */
    val row: Int,
    /** At least 32 dp tall: a big emoji is a message, a reaction pill isn't. */
    val tall: Boolean,
) {
    /** Two pieces with the same key at the same place are the same piece. */
    val key: String get() = "${if (isMessage) "m" else "t"}|$side|$text"
}

/** What one look at the screen found. */
internal class Page(
    val pieces: List<Piece>,
    val list: Bounds,
    /** "scroller" for a list that scrolls, "grid" for one that doesn't (yet), catch-up-text's `root`. */
    val root: String,
    val scrollable: Boolean,
    /** The list could still scroll toward older messages when this page was read. */
    val canScrollBack: Boolean,
    val title: String,
    val rows: Int,
    val avatars: Int,
    val reactions: Int,
)

/**
 * Reads one screenful of a thread into pieces, the way the iOS readers
 * read Instagram's web page: by text and geometry, never by view ids.
 *
 * - The list is the biggest scrolling node above the composer; its
 *   children are the rows.
 * - A text leaf is the deepest node that has text; a node with no text
 *   whose description says photo, video, voice, GIF or sticker (or a big
 *   image) is a placeholder like "[photo]".
 * - A bubble is the nearest tappable or long-pressable box around a leaf
 *   that isn't the full width: chat apps open the react and reply menu on
 *   a long press. Everything in one bubble is one message.
 * - Right of center is the reader's own; centered is a time stamp or a
 *   notice.
 * - Reactions (small emoji pills on a bubble's edge, or anything described
 *   as a reaction) and avatars are dropped.
 */
internal object PageParser {

    // "Reactions", "2 reactions", "Reacted ❤️": not a bubble that says "double tap to react".
    private val REACTION = Regex("(^|\\s)reactions?(\\s|:|$)|^reacted\\b", RegexOption.IGNORE_CASE)
    private val AVATAR = Regex("profile (picture|photo|pic)|\\bavatar\\b", RegexOption.IGNORE_CASE)
    private val DURATION = Regex("^\\d{1,2}:\\d{2}$")
    private val BUBBLE_NOTE = Regex("^(edited|forwarded)$", RegexOption.IGNORE_CASE)
    private val STATUS = Regex(
        "^(active|online|offline|typing|seen|last seen|tap |view profile|\\d+ (members|people))",
        RegexOption.IGNORE_CASE,
    )

    /** The page on screen, or null when there's no message list. */
    fun parse(root: ReaderNode, source: TextSource, density: Float): Page? {
        val composer = ThreadLayout.findComposer(root, source)
        val listNode = ThreadLayout.findList(root, composer?.bounds) ?: return null
        val list = listNode.bounds
        val rows = rowsOf(listNode)
        val reading = RowReader(list, density)
        rows.forEachIndexed { i, row -> reading.read(row, i) }
        return Page(
            pieces = reading.dropReactions(),
            list = list,
            root = if (listNode.isScrollable) "scroller" else "grid",
            scrollable = listNode.isScrollable,
            canScrollBack = listNode.canScrollBack,
            title = titleOf(root, list),
            rows = rows.size,
            avatars = reading.avatars,
            reactions = reading.reactions,
        )
    }

    /** The list's rows: its visible children, under any single wrapper. */
    private fun rowsOf(list: ReaderNode): List<ReaderNode> {
        var node = list
        repeat(4) {
            val kids = node.children.filter { it.isVisibleToUser && !it.bounds.isEmpty }
            if (kids.size != 1) return kids
            node = kids.single()
        }
        return node.children.filter { it.isVisibleToUser && !it.bounds.isEmpty }
    }

    /** The thread's name: the topmost line of text above the list that isn't a status ("Active now"). */
    fun titleOf(root: ReaderNode, list: Bounds): String {
        var best: Pair<Bounds, String>? = null
        root.walkTree { node, _ ->
            if (node.isEditable || !node.isVisibleToUser) return@walkTree
            val b = node.bounds
            val t = clean(node.text)
            if (t.isEmpty() || b.isEmpty || b.bottom > list.top + 2 || t.length > 80 || '\n' in t || STATUS.containsMatchIn(t)) return@walkTree
            val current = best
            if (current == null || b.top < current.first.top || (b.top == current.first.top && b.left < current.first.left)) best = b to t
        }
        return best?.second.orEmpty()
    }

    /** Text as it reads: each line trimmed, runs of spaces as one, empty lines dropped. */
    fun clean(raw: CharSequence?): String {
        if (raw.isNullOrBlank()) return ""
        return raw.toString().split('\n').map { it.replace(Regex("\\s+"), " ").trim() }.filter(String::isNotEmpty).joinToString("\n")
    }

    /** What a node shows when it has no text: a placeholder like "[photo]", or null. */
    fun placeholder(description: String, className: String?, bounds: Bounds, density: Float): String? {
        val d = description.lowercase()
        if (d.isNotEmpty()) {
            return when {
                Regex("view.?once").containsMatchIn(d) -> if ("video" in d) "[view-once video]" else "[view-once photo]"
                Regex("\\bgifs?\\b").containsMatchIn(d) -> "[GIF]"
                "sticker" in d -> "[sticker]"
                Regex("\\b(voice|audio)\\b").containsMatchIn(d) -> "[voice message]"
                Regex("\\breels?\\b").containsMatchIn(d) -> "[shared reel]"
                Regex("\\bposts?\\b").containsMatchIn(d) -> "[shared post]"
                "video" in d -> "[video]"
                Regex("\\b(photo|image|picture)s?\\b").containsMatchIn(d) -> "[photo]"
                Regex("^(play|pause)\\b").containsMatchIn(d) -> "[voice message]"
                else -> null
            }
        }
        val big = bounds.width >= 72 * density && bounds.height >= 72 * density
        return if (big && className?.contains("Image") == true) "[photo]" else null
    }

    /** Reads rows into pieces; one per page. */
    private class RowReader(private val list: Bounds, private val density: Float) {
        val pieces = mutableListOf<Piece>()
        var avatars = 0
        var reactions = 0
        private val textBelow = IdentityHashMap<ReaderNode, Boolean>()

        private class Leaf(val text: String, val media: Boolean, val bounds: Bounds, val bubble: ReaderNode?)

        fun read(row: ReaderNode, index: Int) {
            val leaves = mutableListOf<Leaf>()
            visit(row, emptyList(), leaves)
            // Everything inside one bubble is one message, in the order it was drawn.
            val bubbles = IdentityHashMap<ReaderNode, MutableList<Leaf>>()
            val order = mutableListOf<Any>()
            for (leaf in leaves) {
                val bubble = leaf.bubble
                if (bubble == null) {
                    order += leaf
                } else {
                    bubbles.getOrPut(bubble) { mutableListOf<Leaf>().also { order += bubble } }.add(leaf)
                }
            }
            for (item in order) {
                if (item is Leaf) {
                    val box = item.bounds.clippedTo(list)
                    // A big photo centered at the top of a thread is its header, not a message.
                    if (item.media && isCentered(box)) continue
                    pieces += piece(isMessage = item.media, inBubble = false, text = item.text, media = item.media, box = box, row = index)
                } else {
                    val bubble = item as ReaderNode
                    val inside = bubbles.getValue(bubble)
                    var media = inside.filter { it.media }.map { it.text }.distinct()
                    if ("[video]" in media) media = media - "[voice message]"
                    val timed = "[video]" in media || "[voice message]" in media
                    val words = inside.filter { !it.media }.map { it.text }
                        .filterNot { BUBBLE_NOTE.matches(it) || (timed && DURATION.matches(it)) }
                    val text = (media + listOfNotNull(words.joinToString("\n").ifEmpty { null })).joinToString(" ")
                    pieces += piece(isMessage = true, inBubble = true, text = text, media = media.isNotEmpty(), box = bubble.bounds.clippedTo(list), row = index)
                }
            }
        }

        private fun piece(isMessage: Boolean, inBubble: Boolean, text: String, media: Boolean, box: Bounds, row: Int) = Piece(
            isMessage = isMessage,
            inBubble = inBubble,
            text = text,
            media = media,
            side = if (box.left - list.left > list.right - box.right) Side.ME else Side.THEM,
            centered = isCentered(box),
            bounds = box,
            clipTop = box.top <= list.top + 1,
            clipBottom = box.bottom >= list.bottom - 1,
            row = row,
            tall = box.height >= 32 * density,
        )

        private fun isCentered(b: Bounds): Boolean =
            abs(b.centerX - list.centerX) <= max(8 * density, list.width * 0.06f) && b.width < list.width * 0.9f

        private fun visit(node: ReaderNode, path: List<ReaderNode>, out: MutableList<Leaf>) {
            val b = node.bounds
            if (!node.isVisibleToUser || b.isEmpty || !b.intersects(list) || node.isEditable) return
            val description = clean(node.contentDescription)
            if (REACTION.containsMatchIn(description) && b.height <= 44 * density) {
                reactions++
                return
            }
            val text = clean(node.text)
            val below = hasTextBelow(node)
            if (text.isNotEmpty() && !below) {
                out += Leaf(text, media = false, bounds = b, bubble = bubbleOf(node, path))
                return
            }
            if (text.isEmpty() && !below) {
                if (isAvatar(node, description)) {
                    avatars++
                    return
                }
                val media = placeholder(description, node.className, b, density)
                if (media != null) {
                    out += Leaf(media, media = true, bounds = b, bubble = bubbleOf(node, path))
                    return
                }
            }
            val inner = path + node
            node.children.forEach { visit(it, inner, out) }
        }

        /** The nearest tappable box around [node] (itself included) that isn't the full width. */
        private fun bubbleOf(node: ReaderNode, path: List<ReaderNode>): ReaderNode? {
            val narrow = list.width * 0.92f
            if ((node.isClickable || node.isLongClickable) && node.bounds.width <= narrow) return node
            return path.asReversed().firstOrNull { (it.isClickable || it.isLongClickable) && it.bounds.width <= narrow }
        }

        private fun isAvatar(node: ReaderNode, description: String): Boolean {
            if (AVATAR.containsMatchIn(description)) return true
            if (description.isNotEmpty() || node.className?.contains("Image") != true) return false
            val b = node.bounds
            val square = abs(b.width - b.height) <= max(b.width, b.height) * 0.2f
            return square && b.width <= 48 * density && b.centerX - list.left < list.width * 0.2f
        }

        private fun hasTextBelow(node: ReaderNode): Boolean = textBelow.getOrPut(node) {
            node.children.any { child ->
                child.isVisibleToUser && !child.isEditable && (clean(child.text).isNotEmpty() || hasTextBelow(child))
            }
        }

        /**
         * Reaction pills: small emoji (and a count) on a bubble's edge. A big
         * emoji on its own is a message and stays.
         */
        fun dropReactions(): List<Piece> {
            val near = 8 * density
            return pieces.filter { p ->
                val pill = !p.tall && p.text.isNotEmpty() && Emoji.only(p.text.filterNot(Char::isDigit)) &&
                    pieces.any { other ->
                        other !== p && other.row == p.row && other.isMessage && other.text != p.text &&
                            p.bounds.top <= other.bounds.bottom + near && p.bounds.bottom >= other.bounds.top - near
                    }
                if (pill) reactions++
                !pill
            }
        }
    }
}

/** Emoji-only text ("🙌", "❤️❤️"), checked by code point so it works the same on a phone and the JVM. */
internal object Emoji {
    fun only(s: String): Boolean {
        var pictographs = 0
        var i = 0
        while (i < s.length) {
            val cp = s.codePointAt(i)
            i += Character.charCount(cp)
            when {
                Character.isWhitespace(cp) -> Unit
                cp == 0x200D || cp == 0xFE0F || cp == 0xFE0E || cp == 0x20E3 || cp in 0x1F3FB..0x1F3FF || cp in 0xE0020..0xE007F -> Unit
                isPictograph(cp) -> pictographs++
                else -> return false
            }
        }
        return pictographs > 0
    }

    private fun isPictograph(cp: Int): Boolean =
        cp in 0x1F000..0x1FAFF || cp in 0x2600..0x27BF || cp in 0x2300..0x23FF || cp in 0x2B00..0x2BFF ||
            cp in 0x2190..0x21FF || cp == 0x00A9 || cp == 0x00AE || cp == 0x203C || cp == 0x2049 || cp == 0x2122 ||
            cp == 0x2139 || cp == 0x3030 || cp == 0x303D || cp == 0x3297 || cp == 0x3299
}
