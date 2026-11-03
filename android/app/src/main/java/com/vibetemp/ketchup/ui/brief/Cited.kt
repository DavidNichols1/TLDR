package com.vibetemp.ketchup.ui.brief

import com.vibetemp.ketchup.data.CatchUp
import com.vibetemp.ketchup.data.Message
import com.vibetemp.ketchup.data.TextThread
import com.vibetemp.ketchup.data.Times
import java.time.Instant

/**
 * A message a brief cites, as its source chip and the citations sheet show
 * it. [isMine] shows as "You" in ink; anyone else is [name] in their chat
 * color. Pure Kotlin (JVM tests).
 */
data class Cited(
    val name: String,
    /** The whole message, one paragraph; "Photo" for a photo without words. */
    val text: String,
    val isMine: Boolean = false,
    /** About when (a thread's times are approximate). */
    val at: Instant? = null,
    /** What it replies to, when it's a reply: who said it, and what. */
    val quote: Quote? = null,
) {
    data class Quote(val name: String?, val text: String?, val isMine: Boolean)

    /** How the chip starts: the first 28 characters, then "…" (iOS `ChatModel.preview`). */
    val preview: String get() = Refs.preview(text)
}

/** Turning a brief's refs back into messages. */
object Refs {
    private const val PREVIEW_MAX = 28

    fun preview(text: String): String {
        val flat = text.replace('\n', ' ')
        if (flat.length <= PREVIEW_MAX) return flat
        var cut = flat.take(PREVIEW_MAX)
        if (cut.last().isHighSurrogate()) cut = cut.dropLast(1)
        return "$cut…"
    }

    /**
     * A thread's ref ("12", an index into what was sent) as its message.
     * Null for a ref the thread doesn't have.
     */
    fun inThread(thread: TextThread, ref: String): Cited? = thread.message(ref)?.let { m ->
        Cited(
            name = m.sender.trim(),
            text = m.text,
            isMine = m.isMine,
            at = m.at?.let(Times::instant),
            quote = m.quote?.let { Cited.Quote(it.sender?.trim()?.takeIf(String::isNotEmpty), it.text, it.isMine) },
        )
    }

    /** A Ketchup message as a source, named the way the chat names its sender. */
    fun inChat(message: Message, names: Map<String, String>, me: String?): Cited = Cited(
        name = names[message.sender] ?: "Someone",
        text = if (message.imagePath != null && message.body.isBlank()) "Photo" else message.body,
        isMine = me != null && message.sender == me,
        at = message.createdAt,
    )

    /** Every ref in a brief, each once, in the order the page shows them. */
    fun all(brief: CatchUp): List<String> = (
        brief.forYou.flatMap { it.refs } + brief.plans.flatMap { it.refs } + brief.owes.flatMap { it.refs } +
            brief.openQuestions.flatMap { it.refs } + brief.highlights.flatMap { it.refs }
        ).distinct()

    /** A thread's refs in the order they were said. */
    fun inOrder(refs: List<String>): List<String> =
        refs.distinct().sortedWith(compareBy<String> { it.toIntOrNull() ?: Int.MAX_VALUE }.thenBy { it })
}

/** One line in the skim window while Muse Spark reads: who said it, and what. */
data class SkimLine(val name: String, val text: String, val isMine: Boolean = false)

/** What to skim while Muse Spark reads, and how many messages a catch-up reads (null when unknown). */
data class Skim(val catchUp: List<SkimLine>, val ask: List<SkimLine>, val unread: Int?)

object SkimLines {
    /**
     * Up to [limit] of a chat's messages (oldest first) for the window,
     * from the first one after [lastRead] on. A backlog shorter than
     * [atLeast] reaches back for earlier lines, so the window has enough to
     * run (iOS `SkimLine.lines`). With no [lastRead], the newest [limit].
     */
    fun window(messages: List<Message>, lastRead: Instant?, limit: Int = 200, atLeast: Int = 12): List<Message> {
        val from = lastRead?.let { read -> messages.indexOfFirst { it.createdAt > read }.takeIf { it >= 0 } }
            ?: (messages.size - limit)
        val first = maxOf(0, minOf(from, messages.size - atLeast))
        return messages.drop(first).take(limit)
    }

    fun line(cited: Cited): SkimLine = SkimLine(cited.name, cited.text.replace('\n', ' '), cited.isMine)
}
