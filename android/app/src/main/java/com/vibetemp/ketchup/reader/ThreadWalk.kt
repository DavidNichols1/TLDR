package com.vibetemp.ketchup.reader

import com.vibetemp.ketchup.data.TextMessage
import java.time.ZonedDateTime

/** The thread's messages, oldest first, and counts of what wasn't one. */
internal class Walk(
    val messages: List<TextMessage>,
    val isGroup: Boolean,
    val labels: Int,
    val stamps: Int,
    val skipped: Int,
    val empty: Int,
    val media: Int,
    /** Snapchat: how many of the oldest messages came before any sender's header (their sender is a guess). */
    val unnamedBefore: Int = 0,
)

/**
 * Turns the pieces, top to bottom, into messages with senders, quotes and
 * times: the iOS Instagram reader's `walk()`.
 *
 * - A centered line that reads as a time is a separator: the messages
 *   under it carry that time. Any other centered line is a notice
 *   ("Maya named the group") and is dropped.
 * - "Seen", "Sent", "Delivered", "Edited" and typing lines are dropped.
 * - "You replied to Maya", "Maya replied to you": the next message in that
 *   row is the quote and the one after it is the reply. "Maya replied to
 *   ..." also names the sender.
 * - In a group, a short loose line right above their bubble is the
 *   sender's name; it covers the run until a message of the reader's or
 *   the next name. A name of "Me" (Snapchat's) means the run is the reader's.
 * - A loose line that's none of these, when the thread has bubbles, is a
 *   status line and is dropped. With no bubbles anywhere, loose text is
 *   the messages.
 * - With no name labels and one other person, it's a 1:1: their messages
 *   go under the thread's title. Otherwise an unnamed message is "Someone".
 */
internal object ThreadWalk {
    private val RECEIPT = Regex("^(seen|sent|delivered|read|edited|typing)(\\b|$)", RegexOption.IGNORE_CASE)
    private val REPLY = Regex("^(?:(.+?)\\s+)?replied to (.+)$", RegexOption.IGNORE_CASE)
    private val SELF = Regex("^(him|her|them)sel(f|ves)$|^themself$", RegexOption.IGNORE_CASE)
    private val STORY = Regex("^(your|their|his|her|my) story$", RegexOption.IGNORE_CASE)
    /** Empty space this tall between two pieces is a stretch nobody read, not a layout gap ([Stitcher.addFollowing]). */
    internal const val UNREAD_GAP_DP = 180

    private val LABEL_TAIL = Regex("\\s*[·•]\\s*(pinned|edited|forwarded)\\s*$", RegexOption.IGNORE_CASE)

    private class Reply(val group: Int, val to: String?, val toMine: Boolean) {
        var quote: String? = null
    }

    fun walk(pieces: List<Placed>, group: (Placed) -> Int, title: String, density: Float, now: ZonedDateTime): Walk {
        val units = pieces.sortedWith(compareBy<Placed>({ it.top }, { it.seq }))
        val hasBubbles = units.any { it.piece.inBubble }
        fun isMessage(u: Placed) = u.piece.isMessage || (!hasBubbles && !u.piece.centered)

        val out = mutableListOf<TextMessage>()
        var at: String? = null
        var label: String? = null
        var labelMine = false
        var reply: Reply? = null
        var labels = 0
        var stamps = 0
        var skipped = 0
        var empty = 0
        var media = 0
        var below: Int? = null

        for ((i, u) in units.withIndex()) {
            val p = u.piece
            // A stretch nobody read (the person flung past it): whose run continues after it is unknown.
            if (below != null && u.top - below > UNREAD_GAP_DP * density) {
                label = null
                labelMine = false
                reply = null
            }
            below = maxOf(below ?: u.bottom, u.bottom)
            if (!p.isMessage) {
                val t = p.text
                if (p.centered) {
                    val stamp = Stamps.parse(t, now)
                    if (stamp != null) {
                        at = stamp.toString()
                        stamps++
                        reply = null
                        continue
                    }
                }
                if (t.length < 80 && RECEIPT.containsMatchIn(t)) {
                    skipped++
                    continue
                }
                val replied = if (t.length < 120 && '\n' !in t) REPLY.find(t) else null
                if (replied != null) {
                    val by = replied.groups[1]?.value?.trim()
                    val byMe = by.equals("you", ignoreCase = true)
                    val to = replied.groupValues[2].trim()
                    reply = when {
                        STORY.matches(to) -> Reply(group(u), to.lowercase(), toMine = false)
                        to.equals("you", true) || to.equals("yourself", true) -> Reply(group(u), null, toMine = true)
                        SELF.matches(to) -> Reply(group(u), if (byMe) null else by, toMine = byMe)
                        else -> Reply(group(u), to, toMine = false)
                    }
                    // Who's replying names the message (1:1 threads say it too, so it isn't a group's label).
                    if (by != null && !byMe) {
                        label = by
                        labelMine = false
                    }
                    continue
                }
                val bigEmoji = Emoji.only(t) && p.tall
                if (!bigEmoji) {
                    if (p.centered) {
                        skipped++
                        continue
                    }
                    if (hasBubbles && isLabel(units, i, density)) {
                        label = t.replace(LABEL_TAIL, "").ifEmpty { t }
                        labelMine = label.equals("me", ignoreCase = true)
                        labels++
                        reply = null
                        continue
                    }
                    if (hasBubbles) {
                        skipped++
                        continue
                    }
                }
            } else if (p.text.isBlank()) {
                empty++
                skipped++
                continue
            }

            // A message. Right after a reply's header, the first of two in its row is the quote.
            val open = reply
            if (open != null && open.quote == null && group(u) == open.group &&
                units.drop(i + 1).takeWhile { group(it) == open.group }.any(::isMessage)
            ) {
                open.quote = p.text
                continue
            }
            if (p.media) media++
            val mine = p.side == Side.ME || (labelMine && label != null)
            if (p.side == Side.ME) {
                label = null
                labelMine = false
            }
            val quote = open?.let { TextMessage.Quote(sender = it.to, text = it.quote, isMine = it.toMine) }
            reply = null
            out += TextMessage(sender = if (mine) "" else label.orEmpty(), text = p.text, isMine = mine, quote = quote, at = at)
        }

        val named = out.filter { !it.isMine && it.sender.isNotEmpty() }.map { it.sender }.toSet()
        val isGroup = labels > 0 || named.size >= 2
        val messages = out.map { m ->
            when {
                m.isMine -> m
                !isGroup && title.isNotBlank() -> m.copy(sender = title)
                m.sender.isEmpty() -> m.copy(sender = "Someone")
                else -> m
            }
        }
        return Walk(messages, isGroup, labels, stamps, skipped, empty, media)
    }

    /** A short loose line sitting right on top of their bubble. */
    private fun isLabel(units: List<Placed>, i: Int, density: Float): Boolean {
        val u = units[i]
        val t = u.piece.text
        if (u.piece.side != Side.THEM || t.length > 50 || '\n' in t) return false
        val next = units.getOrNull(i + 1) ?: return false
        if (!next.piece.isMessage || next.piece.side != Side.THEM) return false
        val gap = next.top - u.bottom
        return gap >= -2 * density && gap <= 24 * density
    }
}
