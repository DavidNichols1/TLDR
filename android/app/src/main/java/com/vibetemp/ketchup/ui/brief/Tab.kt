package com.vibetemp.ketchup.ui.brief

import com.vibetemp.ketchup.data.CatchUp
import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Locale

/**
 * "Who owes what", sorted the way a diner check reads: the reader's lines
 * first (what they owe, then what's owed to them) with the totals, money
 * between other people, then the things to bring. Muse Spark writes each
 * amount into a phrase ("$90 for Airbnb"); the amount and the item are read
 * back out of it here. Pure Kotlin (JVM tests). Port of iOS AI/OwesCheck.swift.
 */
class Tab(owes: List<CatchUp.Owe>, reader: String) {

    /** One line on the check. [fromReader] and [toReader] mean "You". */
    data class Line(
        val from: String,
        val fromReader: Boolean,
        val to: String?,
        val toReader: Boolean,
        /** "Airbnb", "Speaker and Catan". */
        val label: String,
        val amount: BigDecimal?,
        val symbol: String,
        val refs: List<String>,
    )

    /** What the reader owes, then what's owed to them. */
    val yours: List<Line>
    /** Money between other people. */
    val others: List<Line>
    /** No amount: things to bring or do (the reader's first). */
    val toBring: List<Line>
    val youOwe: BigDecimal
    val owedToYou: BigDecimal
    /** The currency each total is in, from the lines that make it up. */
    val youOweSymbol: String
    val owedSymbol: String

    init {
        val owing = mutableListOf<Line>()
        val owed = mutableListOf<Line>()
        val others = mutableListOf<Line>()
        val mineToBring = mutableListOf<Line>()
        val toBring = mutableListOf<Line>()
        var youOwe = BigDecimal.ZERO
        var owedToYou = BigDecimal.ZERO
        var youOweSymbol = "$"
        var owedSymbol = "$"
        for (owe in owes) {
            val fromReader = isReader(owe.who, reader)
            val toReader = isReader(owe.owesWhom, reader)
            val parsed = parse(owe.what)
            val line = Line(
                from = owe.who.trim(),
                fromReader = fromReader,
                to = owe.owesWhom?.trim()?.takeIf { it.isNotEmpty() },
                toReader = toReader,
                label = parsed.label,
                amount = parsed.amount,
                symbol = parsed.symbol,
                refs = owe.refs,
            )
            val amount = parsed.amount
            when {
                amount == null -> if (fromReader) mineToBring += line else toBring += line
                fromReader -> {
                    owing += line
                    youOwe += amount
                    youOweSymbol = parsed.symbol
                }
                toReader -> {
                    owed += line
                    owedToYou += amount
                    owedSymbol = parsed.symbol
                }
                else -> others += line
            }
        }
        this.yours = owing + owed
        this.others = others
        this.toBring = mineToBring + toBring
        this.youOwe = youOwe
        this.owedToYou = owedToYou
        this.youOweSymbol = youOweSymbol
        this.owedSymbol = owedSymbol
    }

    /** An amount, its currency symbol and the item it's for. */
    data class Parsed(val amount: BigDecimal?, val symbol: String, val label: String)

    companion object {
        /** An amount: "$90", "$1,200.50", "€45" (and not the comma in "$540, so"). */
        private val money = Regex("""([${'$'}€£])\s?(\d+(?:,\d{3})*(?:\.\d{1,2})?)""")

        /**
         * The model names the reader the way the chat does ("David"), and now
         * and then "you". A thread read off another app with no Ketchup name
         * sends "Me".
         */
        fun isReader(name: String?, reader: String): Boolean {
            val n = name?.trim()?.lowercase().orEmpty()
            if (n.isEmpty()) return false
            if (n == "you" || n == "me") return true
            val r = reader.trim().lowercase()
            if (r.isEmpty()) return false
            return n == r || n == r.split(' ').first()
        }

        /**
         * "$90 for Airbnb" gives (90, "$", "Airbnb"); "Bring the speaker and
         * Catan" gives no amount and "Speaker and Catan".
         */
        fun parse(what: String): Parsed {
            val match = money.find(what)
                ?: return Parsed(null, "$", label(what, dropping = listOf("bring ", "brings "), afterFor = false))
            val amount = match.groupValues[2].replace(",", "").toBigDecimalOrNull()
            val rest = what.replaceRange(match.range, " ")
            return Parsed(amount, match.groupValues[1], label(rest, dropping = emptyList(), afterFor = true))
        }

        /** "$90.00", in the reader's number format. */
        fun format(amount: BigDecimal, symbol: String, locale: Locale = Locale.getDefault()): String {
            val number = NumberFormat.getNumberInstance(locale).apply {
                minimumFractionDigits = 2
                maximumFractionDigits = 2
            }
            return symbol + number.format(amount)
        }

        /**
         * What's left of the phrase once the amount is out, as an item: what
         * follows "for" when money has one ("Send Maya $90 for the Airbnb"),
         * no "the", a capital letter.
         */
        private fun label(raw: String, dropping: List<String>, afterFor: Boolean): String {
            var text = raw.split(Regex("""\s+""")).filter(String::isNotEmpty).joinToString(" ")
            if (afterFor) {
                val at = text.indexOf(" for ", ignoreCase = true)
                if (at >= 0) text = text.substring(at + " for ".length)
            }
            text = text.trim { it.isWhitespace() || it.isPunctuation() }
            for (prefix in dropping + listOf("for ", "the ")) {
                if (text.lowercase().startsWith(prefix)) text = text.substring(prefix.length).trim()
            }
            return if (text.isEmpty()) text else text.substring(0, 1).uppercase() + text.substring(1)
        }

        private fun Char.isPunctuation(): Boolean = when (Character.getType(this).toByte()) {
            Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION,
            Character.END_PUNCTUATION, Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION,
            Character.OTHER_PUNCTUATION,
            -> true
            else -> false
        }
    }
}
