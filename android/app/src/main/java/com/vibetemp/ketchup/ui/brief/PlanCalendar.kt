package com.vibetemp.ketchup.ui.brief

import android.content.Intent
import android.provider.CalendarContract
import com.vibetemp.ketchup.data.CatchUp
import com.vibetemp.ketchup.data.Times
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** An event as "Add to calendar" hands it to the phone's calendar app. */
data class CalendarEvent(
    val title: String,
    val beginMillis: Long,
    val endMillis: Long,
    val allDay: Boolean,
    val location: String?,
    val description: String,
)

/**
 * "Add to calendar" for a plan: the system's new-event screen, prefilled
 * with the title, the time and the place, for the reader to check and save
 * (`Intent.ACTION_INSERT` on the Events table). Ketchup never writes to the
 * calendar itself and asks for no calendar permission. Port of iOS
 * AI/EventEditor.swift; the mapping is pure Kotlin (JVM tests).
 */
object PlanCalendar {

    /**
     * The event for [plan]. [chatName] and [app] say where it came from in
     * the notes ("From “Breck Weekend” on Ketchup"). A plan with no time
     * starts at the next whole hour, for the reader to set; one with a date
     * but no time is all day on that date.
     */
    fun event(
        plan: CatchUp.Plan,
        chatName: String,
        app: String = "Ketchup",
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): CalendarEvent {
        val start = plan.startsAt?.let { Times.planTime(it, zone) }
        val end = plan.endsAt?.let { Times.planTime(it, zone) }
        val allDay = start != null && (plan.allDay || !hasTime(plan))
        val begin: Instant
        val until: Instant
        if (start != null && allDay) {
            begin = start.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()
            val lastDay = (end?.takeIf { it > start } ?: start).atZone(zone).toLocalDate()
            until = lastDay.plusDays(1).atStartOfDay(zone).toInstant()
        } else {
            begin = start ?: now.atZone(zone).truncatedTo(ChronoUnit.HOURS).plusHours(1).toInstant()
            until = end?.takeIf { it > begin } ?: begin.plus(Duration.ofHours(1))
        }
        val notes = buildList {
            add("From “$chatName” on $app, found by Muse Spark.")
            if (plan.who.isNotEmpty()) add("Going: ${plan.who.joinToString(", ")}")
            if (!plan.confirmed) add("Still a proposal in the chat.")
        }
        return CalendarEvent(
            title = plan.title.trim(),
            beginMillis = begin.toEpochMilli(),
            endMillis = until.toEpochMilli(),
            allDay = allDay,
            location = plan.location?.trim()?.takeIf { it.isNotEmpty() },
            description = notes.joinToString("\n"),
        )
    }

    /** A bare date ("2026-11-07") means the chat never said what time. */
    fun hasTime(plan: CatchUp.Plan): Boolean = (plan.startsAt?.trim()?.length ?: 0) > 10

    /** The new-event screen's extras, by CalendarContract's names. */
    fun extras(event: CalendarEvent): Map<String, Any> = buildMap {
        put(CalendarContract.Events.TITLE, event.title)
        put(CalendarContract.EXTRA_EVENT_BEGIN_TIME, event.beginMillis)
        put(CalendarContract.EXTRA_EVENT_END_TIME, event.endMillis)
        put(CalendarContract.EXTRA_EVENT_ALL_DAY, event.allDay)
        event.location?.let { put(CalendarContract.Events.EVENT_LOCATION, it) }
        put(CalendarContract.Events.DESCRIPTION, event.description)
    }

    /** The Intent that opens the phone's calendar on [event]. */
    fun intent(event: CalendarEvent): Intent =
        Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI).apply {
            for ((key, value) in extras(event)) {
                when (value) {
                    is String -> putExtra(key, value)
                    is Long -> putExtra(key, value)
                    is Boolean -> putExtra(key, value)
                }
            }
        }
}
