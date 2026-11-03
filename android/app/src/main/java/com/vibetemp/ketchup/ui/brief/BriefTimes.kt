package com.vibetemp.ketchup.ui.brief

import android.text.format.DateFormat
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalContext
import com.vibetemp.ketchup.data.CatchUp
import com.vibetemp.ketchup.data.Times
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

// Times as the brief shows them, in the phone's zone, language and 12 or
// 24 hour setting.

/** "6:00 AM", or "06:00" when the phone is set to 24-hour time. */
@Composable
@ReadOnlyComposable
fun timeText(time: LocalTime): String {
    val pattern = if (DateFormat.is24HourFormat(LocalContext.current)) "HH:mm" else "h:mm a"
    return DateTimeFormatter.ofPattern(pattern, Locale.getDefault()).format(time)
}

/** A plan's start and end in [zone] (null when Muse Spark gave none it could read). */
class PlanTimes(plan: CatchUp.Plan, val zone: ZoneId = ZoneId.systemDefault()) {
    val start: ZonedDateTime? = plan.startsAt?.let { Times.planTime(it, zone) }?.atZone(zone)
    private val endRaw: ZonedDateTime? = plan.endsAt?.let { Times.planTime(it, zone) }?.atZone(zone)
    val allDay: Boolean = plan.allDay
    val hasTime: Boolean = PlanCalendar.hasTime(plan)

    /** The end, when it's a real one: a time, after the start, on a plan with a time. */
    val end: ZonedDateTime? get() {
        val s = start ?: return null
        return endRaw?.takeIf { !allDay && hasTime && it.isAfter(s) }
    }

    val endsSameDay: Boolean get() = end?.toLocalDate() == start?.toLocalDate()

    fun weekday(style: TextStyle = TextStyle.SHORT): String? = start?.dayOfWeek?.getDisplayName(style, Locale.getDefault())

    /** "Nov 7". */
    fun monthDay(): String? = start?.let { DateTimeFormatter.ofPattern("MMM d", Locale.getDefault()).format(it) }

    /** "Saturday, November 7". */
    fun spokenDay(): String? = start?.let { DateTimeFormatter.ofPattern("EEEE, MMMM d", Locale.getDefault()).format(it) }

    companion object {
        /** Soonest first; plans with no time go last, in Muse Spark's order. */
        fun soonestFirst(plans: List<CatchUp.Plan>, zone: ZoneId = ZoneId.systemDefault()): List<CatchUp.Plan> {
            val starts: List<Instant?> = plans.map { p -> p.startsAt?.let { Times.planTime(it, zone) } }
            return plans.indices.sortedWith { a, b ->
                val x = starts[a]
                val y = starts[b]
                when {
                    x != null && y != null -> if (x != y) x.compareTo(y) else a.compareTo(b)
                    x != null -> -1
                    y != null -> 1
                    else -> a.compareTo(b)
                }
            }.map { plans[it] }
        }
    }
}
