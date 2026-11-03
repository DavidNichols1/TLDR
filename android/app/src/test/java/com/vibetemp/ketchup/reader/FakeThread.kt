package com.vibetemp.ketchup.reader

import com.vibetemp.ketchup.data.TextMessage
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * A synthetic DM thread laid out the way a native chat app draws one, as
 * accessibility nodes: a header with the title, a scrolling list of rows,
 * a composer with a "Message..." hint. Their bubbles hug the left past an
 * avatar gutter, mine hug the right, and every bubble is long-pressable.
 * Rows are oldest first; [expected] is what the reader should hand over.
 * Made-up people only.
 */
class FakeThread(val title: String, val density: Float = 2.625f) {
    /** One row of the list: its height, and its nodes given where its top is on screen. */
    class Row(val height: Int, val build: (top: Int) -> SnapshotNode)

    val rows = mutableListOf<Row>()
    val expected = mutableListOf<TextMessage>()
    private var at: String? = null

    val width = 1080
    private fun px(dp: Float) = (dp * density).roundToInt()
    private fun px(dp: Int) = px(dp.toFloat())

    /** A centered time stamp; [iso] is what the messages under it should carry. */
    fun stamp(label: String, iso: String?) {
        at = iso
        centered(label)
    }

    /** A centered notice ("Maya named the group"): never a message. */
    fun notice(text: String) = centered(text)

    private fun centered(text: String) {
        val w = px(24 + text.length * 7)
        val h = px(36)
        rows += Row(h) { top ->
            SnapshotNode(
                bounds = Bounds(0, top, width, top + h),
                className = "android.widget.FrameLayout",
                children = listOf(text(text, Bounds((width - w) / 2, top + px(8), (width + w) / 2, top + px(26)))),
            )
        }
    }

    /**
     * Their message. [label] puts the sender's name over the bubble (a
     * group's first message in a run), [avatar] their photo beside it (the
     * last in a run). [media] is the description of a photo or video in
     * the bubble ("Photo"), shown with [text] as its caption if any.
     */
    fun them(
        name: String,
        text: String?,
        expectSender: String = name,
        label: Boolean = false,
        avatar: Boolean = false,
        media: String? = null,
        expectText: String? = null,
        duration: String? = null,
        reaction: String? = null,
        bigEmoji: Boolean = false,
    ) = message(false, name, text, expectSender, label, avatar, media, expectText, duration, reaction, bigEmoji)

    fun mine(
        text: String?,
        media: String? = null,
        expectText: String? = null,
        seen: Boolean = false,
        bigEmoji: Boolean = false,
        reaction: String? = null,
    ) {
        message(true, "", text, "", false, false, media, expectText, null, reaction, bigEmoji)
        if (seen) receipt("Seen")
    }

    /** A loose "Seen" under the last of mine. */
    fun receipt(text: String) {
        val h = px(20)
        rows += Row(h) { top ->
            SnapshotNode(
                bounds = Bounds(0, top, width, top + h),
                className = "android.widget.FrameLayout",
                children = listOf(text(text, Bounds(width - px(12) - px(40), top + px(2), width - px(12), top + px(18)))),
            )
        }
    }

    /**
     * A reply: Instagram's header ("Jordan replied to Maya") over the quoted
     * message, then the reply's own bubble, all one row.
     */
    fun reply(
        header: String,
        quote: String,
        mine: Boolean,
        name: String,
        text: String,
        expectQuote: TextMessage.Quote,
        expectSender: String = name,
    ) {
        val quoteBubble = bubbleSize(quote, null)
        val replyBubble = bubbleSize(text, null)
        val headerH = px(18)
        val gap = px(2)
        val h = headerH + gap + quoteBubble.second + gap + replyBubble.second + px(4)
        rows += Row(h) { top ->
            val headerW = px(12 + header.length * 6)
            val headerBox = side(mine, headerW, top, top + headerH)
            val qTop = top + headerH + gap
            val qBox = side(mine, quoteBubble.first, qTop, qTop + quoteBubble.second)
            val rTop = qBox.bottom + gap
            val rBox = side(mine, replyBubble.first, rTop, rTop + replyBubble.second)
            SnapshotNode(
                bounds = Bounds(0, top, width, top + h),
                className = "android.widget.LinearLayout",
                children = listOf(
                    text(header, headerBox),
                    bubble(qBox, listOf(text(quote, inset(qBox)))),
                    bubble(rBox, listOf(text(text, inset(rBox)))),
                ),
            )
        }
        expected += TextMessage(if (mine) "" else expectSender, text, mine, expectQuote, at)
    }

    private fun message(
        mine: Boolean,
        name: String,
        text: String?,
        expectSender: String,
        label: Boolean,
        avatar: Boolean,
        media: String?,
        expectText: String?,
        duration: String?,
        reaction: String?,
        bigEmoji: Boolean,
    ) {
        val (bw, bh) = if (bigEmoji) px(56) to px(52) else bubbleSize(text, media)
        val labelH = if (label) px(16) + px(4) else 0
        val reactionH = if (reaction != null) px(14) else 0
        val h = labelH + bh + reactionH + px(4)
        rows += Row(h) { top ->
            val kids = mutableListOf<SnapshotNode>()
            if (label) kids += text(name, Bounds(px(52) + px(12), top, px(52) + px(12) + px(8 + name.length * 7), top + px(16)))
            val bTop = top + labelH
            val box = side(mine, bw, bTop, bTop + bh)
            if (bigEmoji) {
                kids += SnapshotNode(bounds = box, className = "android.widget.TextView", text = text, isLongClickable = true, isClickable = true)
            } else {
                val inner = mutableListOf<SnapshotNode>()
                var y = box.top + px(10)
                if (media != null) {
                    val m = Bounds(box.left + px(4), box.top + px(4), box.right - px(4), box.top + px(4) + px(170))
                    inner += SnapshotNode(bounds = m, className = "android.widget.ImageView", contentDescription = media)
                    y = m.bottom + px(6)
                }
                if (duration != null) inner += text(duration, Bounds(box.right - px(60), box.bottom - px(28), box.right - px(12), box.bottom - px(10)))
                if (text != null) inner += text(text, Bounds(box.left + px(12), y, box.right - px(12), box.bottom - px(10)))
                kids += bubble(box, inner)
            }
            if (avatar) kids += SnapshotNode(bounds = Bounds(px(10), box.bottom - px(32), px(42), box.bottom), className = "android.widget.ImageView")
            if (reaction != null) {
                val pill = Bounds(box.left + px(8), box.bottom - px(8), box.left + px(44), box.bottom + px(14))
                kids += SnapshotNode(bounds = pill, className = "android.widget.TextView", text = reaction, isClickable = true)
            }
            SnapshotNode(bounds = Bounds(0, top, width, top + h), className = "android.widget.LinearLayout", children = kids)
        }
        expected += TextMessage(expectSender, expectText ?: text.orEmpty(), mine, null, at)
    }

    /** A bubble's width and height: about 7.5 dp a character, 32 characters a line. */
    private fun bubbleSize(text: String?, media: String?): Pair<Int, Int> {
        val lines = text?.split('\n')?.sumOf { max(1, (it.length + 31) / 32) } ?: 0
        val longest = text?.split('\n')?.maxOf { min(it.length, 32) } ?: 0
        val w = if (media != null) px(220) else min(px(262), px(24) + px(longest * 7.5f))
        val h = (if (media != null) px(178) else 0) + (if (lines > 0) px(20) + lines * px(20) else px(4))
        return w to h
    }

    private fun side(mine: Boolean, w: Int, top: Int, bottom: Int) =
        if (mine) Bounds(width - px(12) - w, top, width - px(12), bottom) else Bounds(px(52), top, px(52) + w, bottom)

    private fun inset(b: Bounds) = Bounds(b.left + px(12), b.top + px(10), b.right - px(12), b.bottom - px(10))

    private fun text(text: String, b: Bounds) = SnapshotNode(bounds = b, className = "android.widget.TextView", text = text)

    private fun bubble(b: Bounds, kids: List<SnapshotNode>) =
        SnapshotNode(bounds = b, className = "android.widget.FrameLayout", isClickable = true, isLongClickable = true, children = kids)
}

/**
 * The phone's screen showing a [FakeThread], scrolled to its newest
 * message. A scroll moves [pageFraction] of the list's height, rows only
 * exist while they're on screen (like a RecyclerView), and nodes are
 * clipped to the list the way getBoundsInScreen clips them. At the top it
 * fetches [older] batches one at a time, like Instagram loading history.
 * The clock is virtual: nothing here sleeps.
 */
class FakeScreen(
    private val thread: FakeThread,
    private val pageFraction: Float = 1f,
    older: List<FakeThread> = emptyList(),
    /** How long each wait takes, on the virtual clock. */
    private val waitMs: Long = 250,
) : ReaderScreen {
    override val density = thread.density
    val list = Bounds(0, 236, thread.width, 2148)
    private val rows = thread.rows.toMutableList()
    private val pending = older.map { it.rows.toList() }.toMutableList()
    private var loadAsked = false
    private var y: Int
    private var now = 0L
    var scrollsBack = 0
        private set
    var scrollsForward = 0
        private set

    private val contentHeight get() = rows.sumOf { it.height }
    private val page get() = (list.height * pageFraction).roundToInt()
    private val bottomY get() = max(0, contentHeight - list.height)

    init {
        y = bottomY
    }

    /** Where the list is scrolled to, from its top. */
    val scrolledTo: Int get() = y
    val atBottom: Boolean get() = y == bottomY

    override suspend fun snapshot(): ReaderNode = window()

    override suspend fun scrollBack(): Boolean {
        if (y <= 0) {
            loadAsked = pending.isNotEmpty()
            return false
        }
        y = max(0, y - page)
        scrollsBack++
        return true
    }

    override suspend fun scrollForward(): Boolean {
        if (y >= bottomY) return false
        y = min(bottomY, y + page)
        scrollsForward++
        return true
    }

    override suspend fun awaitChange(timeoutMs: Long): Boolean {
        now += min(timeoutMs, waitMs)
        if (loadAsked && pending.isNotEmpty()) {
            // Older messages arrive above; the list keeps what's on screen where it was.
            val batch = pending.removeAt(0)
            rows.addAll(0, batch)
            y += batch.sumOf { it.height }
            loadAsked = false
        }
        return true
    }

    override suspend fun pause(ms: Long) {
        now += ms
    }

    override fun clock(): Long = now

    fun window(): SnapshotNode {
        val kids = mutableListOf<SnapshotNode>()
        var contentTop = 0
        for (row in rows) {
            val top = list.top + contentTop - y
            if (top < list.bottom && top + row.height > list.top) kids += clip(row.build(top), list)
            contentTop += row.height
        }
        val header = SnapshotNode(
            bounds = Bounds(0, 84, thread.width, list.top),
            className = "android.widget.LinearLayout",
            children = listOf(
                SnapshotNode(bounds = Bounds(20, 120, 130, 200), className = "android.widget.ImageButton", contentDescription = "Back", isClickable = true),
                SnapshotNode(bounds = Bounds(160, 110, 700, 160), className = "android.widget.TextView", text = thread.title),
                SnapshotNode(bounds = Bounds(160, 162, 500, 200), className = "android.widget.TextView", text = "Active now"),
                SnapshotNode(bounds = Bounds(820, 120, 920, 200), className = "android.widget.ImageButton", contentDescription = "Audio call", isClickable = true),
            ),
        )
        val listNode = SnapshotNode(
            bounds = list,
            className = "androidx.recyclerview.widget.RecyclerView",
            isScrollable = true,
            canScrollBack = y > 0,
            children = kids,
        )
        val composer = SnapshotNode(
            bounds = Bounds(0, list.bottom, thread.width, 2400),
            className = "android.widget.LinearLayout",
            children = listOf(
                SnapshotNode(bounds = Bounds(150, 2180, 900, 2300), className = "android.widget.EditText", hint = "Message...", isEditable = true, isClickable = true),
            ),
        )
        return SnapshotNode(bounds = Bounds(0, 0, thread.width, 2400), className = "android.widget.FrameLayout", children = listOf(header, listNode, composer))
    }

    private fun clip(node: SnapshotNode, to: Bounds): SnapshotNode {
        val b = node.bounds.clippedTo(to)
        val visible = !b.isEmpty
        return node.copy(
            bounds = if (visible) b else Bounds(0, 0, 0, 0),
            isVisibleToUser = visible,
            children = node.children.map { clip(it, if (visible) b else to) },
        )
    }
}
