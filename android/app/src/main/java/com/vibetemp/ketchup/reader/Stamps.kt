package com.vibetemp.ketchup.reader

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZonedDateTime

/**
 * Time separators ("Today 3:41 PM", "Fri 8:30 PM", "Oct 28, 4:12 PM"), a
 * port of the iOS readers' `parseStamp`. English labels only, read in the
 * phone's time zone. A day with no time is noon; a time with no day is
 * today, or yesterday if that would be in the future; a weekday is the
 * last one before today.
 */
object Stamps {
    // Every word of a separator label is one of these.
    private val DATE_WORD = Regex(
        "^(today|yesterday|at|[ap]\\.?m\\.?|(jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|may|june?|july?|aug(ust)?|" +
            "sept?(ember)?|oct(ober)?|nov(ember)?|dec(ember)?)\\.?|(sun(day)?|mon(day)?|tue(s|sday)?|wed(nesday)?|" +
            "thu(r|rs|rsday)?|fri(day)?|sat(urday)?)\\.?|\\d{1,4}|\\d{1,2}[:.]\\d{2}([ap]\\.?m\\.?)?|\\d{1,2}[ap]\\.?m\\.?|" +
            "\\d{1,2}/\\d{1,2}/\\d{2,4})$",
    )
    private val CLOCK_12 = Regex("\\b(\\d{1,2})[:.](\\d{2})\\s*([ap])\\.?\\s?m\\b\\.?")
    private val HOUR_12 = Regex("\\b(\\d{1,2})\\s*([ap])\\.?\\s?m\\b\\.?")
    private val CLOCK_24 = Regex("\\b([01]?\\d|2[0-3]):([0-5]\\d)\\b")
    private val MONTH_DAY = Regex("\\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.?\\s+(\\d{1,2})(?![\\d:.])(?:\\s+(\\d{4}))?\\b")
    private val DAY_MONTH = Regex("\\b(\\d{1,2})\\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.?(?:\\s+(\\d{4}))?\\b")
    private val NUMERIC = Regex("\\b(\\d{1,2})/(\\d{1,2})/(\\d{2}|\\d{4})\\b")
    private val WEEKDAY = Regex("\\b(sun|mon|tue|wed|thu|fri|sat)[a-z]*\\b")
    private val MONTHS = listOf("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")
    private val DAYS = mapOf(
        "mon" to DayOfWeek.MONDAY, "tue" to DayOfWeek.TUESDAY, "wed" to DayOfWeek.WEDNESDAY, "thu" to DayOfWeek.THURSDAY,
        "fri" to DayOfWeek.FRIDAY, "sat" to DayOfWeek.SATURDAY, "sun" to DayOfWeek.SUNDAY,
    )

    /** [raw] as an instant, or null when it isn't a time label. */
    fun parse(raw: String, now: ZonedDateTime): Instant? {
        val s = raw.lowercase()
            .replace(Regex("[,  ]"), " ")
            .replace(Regex("\\bat\\b"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
        if (s.isEmpty() || s.length > 40 || !s.split(" ").all(DATE_WORD::matches)) return null

        var hour: Int? = null
        var minute = 0
        val clock12 = CLOCK_12.find(s)
        val hour12 = if (clock12 == null) HOUR_12.find(s) else null
        val clock24 = if (clock12 == null && hour12 == null) CLOCK_24.find(s) else null
        when {
            clock12 != null -> {
                hour = clock12.groupValues[1].toInt() % 12 + if (clock12.groupValues[3] == "p") 12 else 0
                minute = clock12.groupValues[2].toInt()
            }
            hour12 != null -> hour = hour12.groupValues[1].toInt() % 12 + if (hour12.groupValues[2] == "p") 12 else 0
            clock24 != null -> {
                hour = clock24.groupValues[1].toInt()
                minute = clock24.groupValues[2].toInt()
            }
        }
        if (minute > 59 || (hour != null && hour > 23)) return null

        val today = now.toLocalDate()
        var day: LocalDate? = null
        runCatching {
            val monthDay = MONTH_DAY.find(s)
            val dayMonth = DAY_MONTH.find(s)
            val numeric = NUMERIC.find(s)
            val weekday = WEEKDAY.find(s)
            day = when {
                Regex("\\btoday\\b").containsMatchIn(s) -> today
                Regex("\\byesterday\\b").containsMatchIn(s) -> today.minusDays(1)
                monthDay != null -> dated(today, monthDay.groupValues[3], MONTHS.indexOf(monthDay.groupValues[1]) + 1, monthDay.groupValues[2].toInt())
                dayMonth != null -> dated(today, dayMonth.groupValues[3], MONTHS.indexOf(dayMonth.groupValues[2]) + 1, dayMonth.groupValues[1].toInt())
                numeric != null -> {
                    val y = numeric.groupValues[3].toInt().let { if (numeric.groupValues[3].length == 2) 2000 + it else it }
                    LocalDate.of(y, numeric.groupValues[1].toInt(), numeric.groupValues[2].toInt())
                }
                weekday != null -> {
                    val target = DAYS.getValue(weekday.groupValues[1])
                    val back = ((today.dayOfWeek.value - target.value + 7) % 7).let { if (it == 0) 7 else it }
                    today.minusDays(back.toLong())
                }
                else -> null
            }
        }.onFailure { return null }

        if (day == null && hour == null) return null
        var at = ZonedDateTime.of(day ?: today, LocalTime.of(hour ?: 12, minute), now.zone)
        if (day == null && at.isAfter(now)) at = at.minusDays(1)
        return at.toInstant()
    }

    /** A month and day, this year unless that's still ahead (then last year). */
    private fun dated(today: LocalDate, year: String, month: Int, dayOfMonth: Int): LocalDate {
        if (year.isNotEmpty()) return LocalDate.of(year.toInt(), month, dayOfMonth)
        val date = LocalDate.of(today.year, month, dayOfMonth)
        return if (date.isAfter(today)) date.minusYears(1) else date
    }
}
