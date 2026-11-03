package com.vibetemp.ketchup.ui.brief

// Muse Spark's sentences, marked up for skimming: money and times get the
// mustard marker on their own, the reader's name stands out in a question,
// a first sentence can stand as a headline. Pure Kotlin (JVM tests). Port of
// iOS AI/BriefText.swift and the split in AI/AskSheet.swift.

/** Where the marker goes in a sentence, as ranges into it. Show with `MarkedText`. */
object BriefMarks {

    private const val DAY = "(?:mon|tues|wednes|thurs|fri|satur|sun)day"
    private const val CLOCK = """\d{1,2}(?::\d{2})?\s?(?:am|pm|a\.m\.|p\.m\.)(?![a-z])|\d{1,2}:\d{2}"""
    private const val TIME = "(?:$CLOCK|noon|midnight)"

    /**
     * Money and times: "$90", "$1,200.50", "Saturday 6am", "Thursday noon",
     * "7:30", "5:45am", and a bare day after "by", "before" or "until"
     * ("confirm by Thursday"). Other day names stay plain ("the Friday
     * storm"), and so does an old amount ("down from $140", "instead of
     * $140", "was $140").
     */
    private val moneyAndTimesPattern = Regex(
        listOf(
            """(?<!\bfrom )(?<!\binstead of )(?<!\bwas )[${'$'}€£]\d+(?:,\d{3})*(?:\.\d{1,2})?""",
            """\b$DAY\s+(?:at\s+)?$TIME""",
            """(?<=\b(?:by|before|until) )$DAY""",
            """\b$TIME""",
        ).joinToString("|"),
        RegexOption.IGNORE_CASE,
    )

    fun moneyAndTimes(text: String): List<IntRange> = moneyAndTimesPattern.findAll(text).map { it.range }.toList()

    /** Every mention of [name] as a name: the reader, in someone's question. */
    fun name(name: String, text: String): List<IntRange> =
        namePattern(name)?.findAll(text)?.map { it.range }?.toList().orEmpty()

    /** Whether [text] mentions [name] as a name. */
    fun mentions(name: String, text: String): Boolean = namePattern(name)?.containsMatchIn(text) == true

    /**
     * The whole word, capitalized the way Muse Spark writes names, so a
     * reader called Will doesn't light up every "will".
     */
    private fun namePattern(name: String): Regex? {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return null
        val capitalized = trimmed.substring(0, 1).uppercase() + trimmed.substring(1)
        return Regex("""\b${Regex.escape(capitalized)}\b""")
    }
}

object Sentences {
    /**
     * "Muse Spark is busy right now. Try again in a moment." gives the first
     * sentence, to set as a headline, and the rest, to go under it.
     */
    fun first(text: String): Pair<String, String?> {
        val trimmed = text.trim()
        val stop = Regex("""[.?!]\s+""").find(trimmed) ?: return trimmed to null
        val first = trimmed.substring(0, stop.range.last + 1).trim()
        val rest = trimmed.substring(stop.range.last + 1).trim()
        return first to rest.ifEmpty { null }
    }
}

/** An answer split for the card that shows it (iOS `AnswerCard.split`). */
data class AnswerParts(val headline: String, val rest: String?, val saysNotFound: Boolean) {
    companion object {
        private const val OPENER = "the chat doesn't say"

        /**
         * "The chat doesn't say. Sam asked twice." splits after "say."; any
         * other answer after its own first sentence ("The chat doesn't say
         * whether the house has a hot tub."), so nothing is cut mid-sentence.
         * [saysNotFound] is false for an answer that only lacked a source.
         */
        fun of(answer: String): AnswerParts {
            val text = answer.trim()
            val saysNotFound = text.replace('’', '\'').lowercase().startsWith(OPENER)
            if (saysNotFound) {
                val after = text.substring(OPENER.length)
                if (after.isEmpty() || after.first() in ".:;!") {
                    val rest = after.dropWhile { it in " .:;!" }.trim()
                    return AnswerParts(
                        "The chat doesn't say.",
                        rest.ifEmpty { null }?.let { it.substring(0, 1).uppercase() + it.substring(1) },
                        true,
                    )
                }
            }
            val (first, rest) = Sentences.first(text)
            return AnswerParts(first, rest, saysNotFound)
        }
    }
}

/** The reader's first name, to greet and to mark ("David"), or null when they have none worth using. */
fun firstName(readerName: String): String? =
    readerName.trim().split(' ').firstOrNull()?.takeIf { it.isNotEmpty() && it.lowercase() !in NOT_NAMES }

/** What the app sends or shows when it doesn't know the reader's name. */
private val NOT_NAMES = setOf("me", "you", "someone")
