package com.vibetemp.ketchup.ui.chats

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit
import java.util.Locale

/** The times the chat screens print (iOS `Date.inboxStamp` and `daySeparator`). */
object Stamps {
    /**
     * An inbox row's time: "9:41 PM" today, "Yesterday", the weekday this
     * week ("Mon"), else "Nov 2".
     */
    fun inbox(
        at: Instant,
        yesterday: String,
        zone: ZoneId = ZoneId.systemDefault(),
        today: LocalDate = LocalDate.now(zone),
        locale: Locale = Locale.getDefault(),
    ): String {
        val local = at.atZone(zone)
        val day = local.toLocalDate()
        return when {
            day == today -> DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale).format(local)
            day == today.minusDays(1) -> yesterday
            ChronoUnit.DAYS.between(day, today) in 0..6 -> DateTimeFormatter.ofPattern("EEE", locale).format(local)
            else -> DateTimeFormatter.ofPattern("MMM d", locale).format(local)
        }
    }

    /** A thread's day line: "Today", "Yesterday", "Monday, Nov 2". */
    fun day(
        day: LocalDate,
        todayWord: String,
        yesterdayWord: String,
        today: LocalDate = LocalDate.now(),
        locale: Locale = Locale.getDefault(),
    ): String = when (day) {
        today -> todayWord
        today.minusDays(1) -> yesterdayWord
        else -> DateTimeFormatter.ofPattern("EEEE, MMM d", locale).format(day)
    }

    /** A message's full time, for its long-press menu: "Nov 2, 2026, 9:41 PM". */
    fun full(at: Instant, zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String =
        DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withLocale(locale).format(at.atZone(zone))
}
