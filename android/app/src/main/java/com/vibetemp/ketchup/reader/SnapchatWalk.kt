package com.vibetemp.ketchup.reader

import com.vibetemp.ketchup.data.TextMessage
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZonedDateTime

/**
 * Turns Snapchat's pieces, top to bottom, into messages ([SnapchatRows]
 * read them). Everything sits on the left, so a message's sender is the
 * last header above it. A header that says "ME", or the reader's name on
 * Snapchat (they type it once, [ReaderMemory]), case and extra spaces
 * aside, means the reader's own; nothing else does. A header's time, on
 * the last date row above it, dates its run, the way the iOS Snapchat
 * reader does (`stampOn`). A reply's quoted sender is resolved the same
 * way.
 *
 * A reply cut in two by the edge between two pages shows up as its quote
 * alone (its words were cut off) right above its words with the rest of
 * the quote: the two quotes are put back together.
 *
 * Messages above the first header the read reached have no sender yet;
 * [Walk.unnamedBefore] counts them, so the reader can scroll a little
 * further for their header. With one other person named they go under
 * that name (a 1:1 chat), else under "Someone".
 */
internal object SnapchatWalk {

    fun walk(pieces: List<Placed>, title: String, snapchatName: String?, now: ZonedDateTime): Walk {
        val me = setOfNotNull("me", snapchatName?.let(::norm)?.ifEmpty { null })
        fun isMe(name: String?) = name != null && norm(name) in me

        val units = pieces.sortedWith(compareBy<Placed>({ it.top }, { it.seq }))
        val out = mutableListOf<TextMessage>()
        var sender: String? = null
        var mine = false
        var day: LocalDate? = null
        var at: String? = null
        var headers = 0
        var stamps = 0
        var skipped = 0
        var empty = 0
        var media = 0
        var unnamedBefore = 0
        var cutQuote: TextMessage.Quote? = null

        for (u in units) {
            val p = u.piece
            val held = cutQuote
            cutQuote = null
            when {
                p.header -> {
                    sender = p.text
                    mine = isMe(p.text)
                    headers++
                    stampOn(day, p.time, now)?.let { at = it }
                }
                !p.isMessage -> {
                    val stamp = Stamps.parse(p.text, now)
                    if (stamp != null) {
                        day = stamp.atZone(now.zone).toLocalDate()
                        at = stamp.toString()
                        stamps++
                    } else {
                        skipped++ // a notice ("Maya saved a chat")
                    }
                }
                p.text.isBlank() && p.quote != null -> cutQuote = p.quote
                p.text.isBlank() -> {
                    empty++
                    skipped++
                }
                else -> {
                    if (p.media) media++
                    if (headers == 0) unnamedBefore++
                    // A quote seen alone right above these words is theirs (the row was cut between pages).
                    val quote = Quotes.merge(held, p.quote)?.let { q -> if (isMe(q.sender)) q.copy(sender = null, isMine = true) else q }
                    out += TextMessage(sender = if (mine) "" else sender.orEmpty(), text = p.text, isMine = mine, quote = quote, at = at)
                }
            }
        }

        val named = out.filter { !it.isMine && it.sender.isNotEmpty() }.map { it.sender }.toSet()
        val isGroup = named.size >= 2
        val fallback = if (isGroup) "Someone" else named.singleOrNull() ?: title.ifBlank { "Someone" }
        val messages = out.map { if (it.isMine || it.sender.isNotEmpty()) it else it.copy(sender = fallback) }
        return Walk(messages, isGroup, headers, stamps, skipped, empty, media, unnamedBefore)
    }

    /** A name as the rule compares it: case and extra spaces aside. */
    internal fun norm(s: String): String = s.trim().replace(Regex("\\s+"), " ").lowercase()

    /** A run's time: its header's time on the last date row's day (iOS `stampOn`). ISO 8601, or null. */
    private fun stampOn(day: LocalDate?, time: String?, now: ZonedDateTime): String? {
        val t = time?.let { Stamps.parse(it, now) }
        return when {
            t == null && day == null -> null
            t == null -> ZonedDateTime.of(day, LocalTime.NOON, now.zone).toInstant().toString()
            day == null -> t.toString()
            else -> ZonedDateTime.of(day, t.atZone(now.zone).toLocalTime(), now.zone).toInstant().toString()
        }
    }
}
