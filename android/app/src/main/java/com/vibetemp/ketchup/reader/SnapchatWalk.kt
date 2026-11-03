package com.vibetemp.ketchup.reader

import com.vibetemp.ketchup.data.TextMessage
import com.vibetemp.ketchup.data.TextThread
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZonedDateTime

/**
 * Turns Snapchat's pieces, top to bottom, into messages ([SnapchatRows]
 * read them). Everything sits on the left, so a message's sender is the
 * last header above it. A header's time, on the last date row above it,
 * dates its run, the way the iOS Snapchat reader does (`stampOn`).
 *
 * Which headers are the reader's own is decided after the walk, by the
 * first of these rules that names anyone ([Rule]):
 *
 * 1. A header that says "ME", in any case.
 * 2. The reader's Ketchup display name (case and extra spaces aside).
 * 3. A Snapchat name remembered from an earlier read on this phone.
 * 4. A one-to-one chat: exactly two people, one of them the thread's title;
 *    the other is the reader, and that name is worth remembering.
 *
 * When none applies and two or more people are in the read, the panel
 * asks "Which one is you?" ([askAmong], [relabel]). A reply's quoted
 * sender is resolved the same way.
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
object SnapchatWalk {

    /** What Ketchup knows about the reader's name: their Ketchup display name, and a Snapchat name learned before. */
    data class Names(val ketchup: String? = null, val remembered: String? = null)

    /** Which rule found the reader's own messages. */
    enum class Rule(val word: String) {
        ME("me"),
        KETCHUP_NAME("ketchup name"),
        REMEMBERED("remembered"),
        ONE_TO_ONE("one-to-one"),
        NONE("none"),
    }

    /** One header label: how often it headed a run, how many of those showed a time, and how many messages it headed. */
    class Label(val name: String, val runs: Int, val timed: Int, val messages: Int)

    /** How a read's "mine" was decided. Held in memory for one catch-up, like the thread. */
    class Decision(
        val rule: Rule,
        /** The header label that's the reader's own, when a rule found one. */
        val mine: String?,
        /** A Snapchat name worth remembering (the one-to-one rule found it). */
        val learned: String?,
        val labels: List<Label>,
        val title: String,
        val names: Names,
    )

    private class Raw(val label: String?, val text: String, val quote: TextMessage.Quote?, val at: String?)

    internal fun walk(pieces: List<Placed>, title: String, names: Names, now: ZonedDateTime): Walk {
        val units = pieces.sortedWith(compareBy<Placed>({ it.top }, { it.seq }))
        val raw = mutableListOf<Raw>()
        val runs = LinkedHashMap<String, IntArray>() // normalized label -> [runs, timed, messages]
        val shown = HashMap<String, String>() // normalized label -> as first shown
        var sender: String? = null
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
                    headers++
                    val key = norm(p.text)
                    shown.getOrPut(key) { p.text }
                    val counts = runs.getOrPut(key) { IntArray(3) }
                    counts[0]++
                    if (p.time != null) counts[1]++
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
                    sender?.let { runs[norm(it)]?.let { counts -> counts[2]++ } }
                    // A quote seen alone right above these words is theirs (the row was cut between pages).
                    raw += Raw(sender, p.text, Quotes.merge(held, p.quote), at)
                }
            }
        }

        val labels = runs.map { (key, c) -> Label(shown.getValue(key), c[0], c[1], c[2]) }
        val decision = decide(labels, title, names)
        val mineKey = decision.mine?.let(::norm)
        fun isMine(label: String?) = label != null && (norm(label) == mineKey || norm(label) == ME)

        val out = raw.map { r ->
            val mine = r.label != null && norm(r.label) == mineKey
            val quote = r.quote?.let { q -> if (isMine(q.sender)) q.copy(sender = null, isMine = true) else q }
            TextMessage(sender = if (mine) "" else r.label.orEmpty(), text = r.text, isMine = mine, quote = quote, at = r.at)
        }
        val named = out.filter { !it.isMine && it.sender.isNotEmpty() }.map { it.sender }.toSet()
        val isGroup = named.size >= 2
        val fallback = if (isGroup) UNNAMED else named.singleOrNull() ?: title.ifBlank { UNNAMED }
        val messages = out.map { if (it.isMine || it.sender.isNotEmpty()) it else it.copy(sender = fallback) }
        return Walk(messages, isGroup, headers, stamps, skipped, empty, media, unnamedBefore, decision)
    }

    /** The first rule that names the reader, in order. */
    private fun decide(labels: List<Label>, title: String, names: Names): Decision {
        fun found(rule: Rule, label: Label?, learned: String? = null) =
            Decision(rule, label?.name, learned, labels, title, names)
        labels.firstOrNull { norm(it.name) == ME }?.let { return found(Rule.ME, it) }
        names.ketchup?.let(::norm)?.takeIf(String::isNotEmpty)?.let { k ->
            labels.firstOrNull { norm(it.name) == k }?.let { return found(Rule.KETCHUP_NAME, it) }
        }
        names.remembered?.let(::norm)?.takeIf(String::isNotEmpty)?.let { r ->
            labels.firstOrNull { norm(it.name) == r }?.let { return found(Rule.REMEMBERED, it) }
        }
        if (labels.size == 2) {
            val (a, b) = labels
            val aTitle = isTitle(a.name, title)
            val bTitle = isTitle(b.name, title)
            if (aTitle != bTitle) {
                val me = if (aTitle) b else a
                return found(Rule.ONE_TO_ONE, me, learned = me.name)
            }
        }
        return found(Rule.NONE, null)
    }

    /**
     * Who to ask about, when no rule found the reader: the people in the
     * kept messages, most messages first. Empty when there's nothing to ask
     * (a rule decided, or fewer than two people).
     */
    fun askAmong(thread: TextThread, decision: Decision?): List<String> {
        if (decision == null || decision.rule != Rule.NONE) return emptyList()
        val people = thread.messages.filter { !it.isMine && it.sender.isNotBlank() && it.sender != UNNAMED }
            .groupingBy { it.sender }.eachCount()
            .entries.sortedByDescending { it.value }.map { it.key }
        return if (people.size >= 2) people else emptyList()
    }

    /** [thread] with [mine]'s messages (and quotes of them) as the reader's own: the answer to "Which one is you?". */
    fun relabel(thread: TextThread, mine: String): TextThread {
        val key = norm(mine)
        return thread.copy(
            messages = thread.messages.map { m ->
                val quote = m.quote?.let { q -> if (q.sender != null && norm(q.sender) == key) q.copy(sender = null, isMine = true) else q }
                if (!m.isMine && norm(m.sender) == key) m.copy(sender = "", isMine = true, quote = quote) else m.copy(quote = quote)
            },
        )
    }

    /**
     * The debug log's line about a read, never text: each header label's
     * length, which name it matches, whether its header showed a time, and
     * how many messages it headed; then the rule that decided.
     *
     *     snap headers: [len 2, me, no time, 6 msgs] [len 11, title, time, 14 msgs]; mine by me
     */
    fun describe(decision: Decision): String {
        val k = decision.names.ketchup?.let(::norm)
        val r = decision.names.remembered?.let(::norm)
        val labels = decision.labels.joinToString(" ") { l ->
            val n = norm(l.name)
            val flags = listOfNotNull(
                "me".takeIf { n == ME },
                "ketchup name".takeIf { k != null && n == k },
                "remembered".takeIf { r != null && n == r },
                "title".takeIf { isTitle(l.name, decision.title) },
            )
            val time = when (l.timed) {
                0 -> "no time"
                l.runs -> "time"
                else -> "time ${l.timed} of ${l.runs}"
            }
            "[" + (listOf("len ${l.name.length}") + flags + listOf(time, "${l.messages} msgs")).joinToString(", ") + "]"
        }
        return "snap headers: ${labels.ifEmpty { "none" }}; mine by ${decision.rule.word}"
    }

    /** A label as the rules compare it: case and extra spaces aside. */
    internal fun norm(s: String): String = s.trim().replace(Regex("\\s+"), " ").lowercase()

    /** The thread's title names this person (it may carry more words, like a last name, or an emoji). */
    private fun isTitle(name: String, title: String): Boolean {
        val n = bare(name)
        val t = bare(title)
        if (n.isEmpty() || t.isEmpty()) return false
        return n == t || t.startsWith("$n ") || n.startsWith("$t ")
    }

    /** Letters, digits and single spaces only, lowercase: emoji and punctuation in a title don't count. */
    private fun bare(s: String): String =
        s.lowercase().map { if (it.isLetterOrDigit()) it else ' ' }.joinToString("").trim().replace(Regex("\\s+"), " ")

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

    private const val ME = "me"
    private const val UNNAMED = "Someone"
}
