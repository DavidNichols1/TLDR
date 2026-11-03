package com.vibetemp.ketchup.reader

import com.vibetemp.ketchup.data.TextMessage
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * A synthetic Snapchat chat, row for row the shapes a structure dump of the
 * real app showed (Nov 3, 2026): every message on the left, indented past
 * its run's colored bar, under a header with the sender's name and a time
 * ("ME" for the reader's own); replies holding a `QuotedMessageView`;
 * reactions (`chat_reactions/...`) with their count; centered date rows.
 * Text leaves are the app's own `javaClass` nodes. Made-up people only.
 * Show it with `FakeScreen(fake.thread, snapchat = true)`.
 */
class FakeSnapThread(title: String, density: Float = 2.625f) {
    val thread = FakeThread(title, density)
    private val d = density
    private val w = thread.width
    private var sender = ""
    private var mine = false
    private var at: String? = null

    private fun px(dp: Float) = (dp * d).roundToInt()
    private fun px(dp: Int) = px(dp.toFloat())

    /** A centered date row ("TODAY"); [iso] is what the messages under it carry until a header's time. */
    fun date(label: String, iso: String?) {
        at = iso
        centered(label)
    }

    /** A centered notice ("Kai saved a message in Chat"): never a message. */
    fun notice(text: String) = centered(text)

    /** A run's header: the sender's name and a time. "ME" (or [isMine]) is the reader's own run. */
    fun header(name: String, time: String, iso: String?, isMine: Boolean = name.equals("ME", ignoreCase = true)) {
        sender = name
        mine = isMine
        at = iso
        val h = px(20)
        val nameW = px(8 + name.length * 7)
        thread.rows += FakeThread.Row(h) { top ->
            SnapshotNode(
                bounds = Bounds(0, top, w, top + h),
                className = "android.widget.LinearLayout",
                children = listOf(
                    SnapshotNode(
                        bounds = Bounds(px(8), top, px(8) + nameW, top + h), className = "android.view.View",
                        children = listOf(leaf(name, Bounds(px(8), top, px(8) + nameW, top + h))),
                    ),
                    SnapshotNode(
                        bounds = Bounds(px(8) + nameW, top + 1, w - px(10), top + h), className = "android.view.View",
                        children = listOf(leaf(time, Bounds(px(8) + nameW, top + 1, w - px(10), top + h))),
                    ),
                ),
            )
        }
    }

    /** A message in the current run, with the run's bar beside it and [reactions] under it if any. */
    fun message(text: String, bar: Boolean = true, reactions: Int = 0) {
        val textH = height(text)
        val reactH = if (reactions > 0) px(30) else 0
        val h = textH + reactH + px(2)
        thread.rows += FakeThread.Row(h) { top ->
            val kids = mutableListOf(content(top, textH, bar, listOf(textBox(text, top, textH))))
            if (reactions > 0) kids += reactionBox(top + textH + px(2), reactions)
            SnapshotNode(bounds = Bounds(0, top, w, top + h), className = "android.widget.LinearLayout", children = kids)
        }
        thread.expected += TextMessage(if (mine) "" else sender, text, mine, null, at)
    }

    /**
     * A reply in the current run: the quoted message ([quoteSender] as the
     * app shows it, a time, [quoteText]) in a `QuotedMessageView`, and the
     * reply's own words in `plugin_content_holder`.
     */
    fun reply(quoteSender: String, quoteText: String, text: String, expectQuote: TextMessage.Quote) {
        val quoteH = px(56)
        val textH = height(text)
        val h = quoteH + px(6) + textH + px(2)
        thread.rows += FakeThread.Row(h) { top ->
            val quoteBox = Bounds(px(15), top + px(3), w * 6 / 10, top + quoteH)
            val quoted = SnapshotNode(
                bounds = quoteBox,
                className = "android.view.View",
                viewId = "com.snapchat.android:id/QuotedMessageView",
                children = listOf(
                    SnapshotNode(bounds = Bounds(quoteBox.left + px(8), quoteBox.top + px(4), quoteBox.left + px(8 + quoteSender.length * 7), quoteBox.top + px(22)), className = "android.widget.TextView", viewId = "com.snapchat.android:id/", text = quoteSender),
                    SnapshotNode(bounds = Bounds(quoteBox.right - px(48), quoteBox.top + px(4), quoteBox.right - px(8), quoteBox.top + px(22)), className = "android.widget.TextView", viewId = "com.snapchat.android:id/", text = "9:01 AM"),
                    SnapshotNode(bounds = Bounds(quoteBox.left + px(16), quoteBox.top + px(26), quoteBox.right - px(8), quoteBox.bottom - px(6)), className = "android.widget.TextView", viewId = "com.snapchat.android:id/", text = quoteText),
                ),
            )
            val ownTop = quoteBox.bottom + px(6)
            val own = SnapshotNode(
                bounds = Bounds(px(12), ownTop, w - px(8), ownTop + textH),
                className = "android.widget.FrameLayout",
                viewId = "com.snapchat.android:id/plugin_content_holder",
                children = listOf(
                    SnapshotNode(
                        bounds = Bounds(px(19), ownTop, w - px(8), ownTop + textH), className = "android.view.View",
                        children = listOf(SnapshotNode(bounds = Bounds(px(19), ownTop, w - px(8), ownTop + textH), className = "android.widget.TextView", viewId = "com.snapchat.android:id/", text = text)),
                    ),
                ),
            )
            SnapshotNode(
                bounds = Bounds(0, top, w, top + h),
                className = "android.widget.LinearLayout",
                children = listOf(content(top, h - px(2), bar = true, inner = listOf(SnapshotNode(bounds = quoteBox, className = "android.view.View", children = listOf(quoted)), own))),
            )
        }
        thread.expected += TextMessage(if (mine) "" else sender, text, mine, expectQuote, at)
    }

    private fun centered(text: String) {
        val tw = px(24 + text.length * 7)
        val h = px(34)
        thread.rows += FakeThread.Row(h) { top ->
            SnapshotNode(
                bounds = Bounds(0, top, w, top + h),
                className = "android.widget.FrameLayout",
                children = listOf(leaf(text, Bounds((w - tw) / 2, top + px(8), (w + tw) / 2, top + px(26)))),
            )
        }
    }

    /** The row's content: the run's 3 px bar (when it shows) and what the message holds. */
    private fun content(top: Int, h: Int, bar: Boolean, inner: List<SnapshotNode>): SnapshotNode {
        val kids = mutableListOf<SnapshotNode>()
        if (bar) kids += SnapshotNode(bounds = Bounds(px(8), top, px(8) + 3, top + h), className = "android.view.View")
        kids += SnapshotNode(
            bounds = Bounds(px(12), top, w - px(8), top + h), className = "android.widget.LinearLayout",
            children = listOf(SnapshotNode(bounds = Bounds(px(12), top, w - px(8), top + h), className = "android.view.ViewGroup", children = inner)),
        )
        return SnapshotNode(bounds = Bounds(px(8), top, w - px(8), top + h), className = "android.widget.LinearLayout", children = kids)
    }

    private fun textBox(text: String, top: Int, h: Int) = SnapshotNode(
        bounds = Bounds(px(12), top, w - px(8), top + h), className = "android.view.View",
        children = listOf(leaf(text, Bounds(px(19), top, w - px(8), top + h))),
    )

    private fun reactionBox(top: Int, count: Int): SnapshotNode {
        val b = Bounds(px(8), top, w, top + px(30))
        return SnapshotNode(
            bounds = b, className = "android.widget.FrameLayout",
            children = listOf(
                SnapshotNode(
                    bounds = b, className = "android.view.View",
                    children = listOf(
                        SnapshotNode(bounds = Bounds(px(22), top + px(2), px(50), top + px(28)), className = "android.view.View", viewId = "com.snapchat.android:id/chat_reactions/reaction-2-4417_74-s5"),
                        SnapshotNode(bounds = Bounds(px(52), top + px(6), px(60), top + px(24)), className = "android.widget.TextView", viewId = "com.snapchat.android:id/", text = count.toString()),
                    ),
                ),
            ),
        )
    }

    /** Snapchat's text node: class `javaClass`, as the dump showed it. */
    private fun leaf(text: String, b: Bounds) = SnapshotNode(bounds = b, className = "javaClass", text = text)

    /** About 34 characters a line, 20 dp each, plus padding. */
    private fun height(text: String): Int {
        val lines = text.split('\n').sumOf { max(1, (it.length + 33) / 34) }
        return px(min(400, 8 + lines * 20))
    }
}
