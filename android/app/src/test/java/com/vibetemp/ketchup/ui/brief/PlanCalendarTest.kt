package com.vibetemp.ketchup.ui.brief

import android.provider.CalendarContract
import com.vibetemp.ketchup.Fixtures
import com.vibetemp.ketchup.data.BriefResponse
import com.vibetemp.ketchup.data.CatchUp
import com.vibetemp.ketchup.data.KetchupJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

/** "Add to calendar": the new-event screen's fields for each plan, no calendar permission. */
class PlanCalendarTest {

    private val denver = ZoneId.of("America/Denver")
    private val now = Instant.parse("2026-11-03T17:25:00Z") // 10:25 AM in Denver
    private val plans = KetchupJson.decodeFromString(BriefResponse.serializer(CatchUp.serializer()), Fixtures.asset("brief.json"))
        .result!!.plans

    private fun ms(iso: String) = Instant.parse(iso).toEpochMilli()

    @Test
    fun aConfirmedPlanWithATime() {
        val drive = plans.first { it.title == "Drive to Keystone / Breck" }
        val event = PlanCalendar.event(drive, "Breck Weekend 🎿", now = now, zone = denver)
        assertEquals("Drive to Keystone / Breck", event.title)
        assertEquals(ms("2026-11-07T13:00:00Z"), event.beginMillis) // 6:00 AM MST
        assertEquals(ms("2026-11-07T14:00:00Z"), event.endMillis) // no end: an hour
        assertFalse(event.allDay)
        assertEquals("Maya's place", event.location)
        assertEquals(
            "From “Breck Weekend 🎿” on Ketchup, found by Muse Spark.\nGoing: Maya, Priya, Theo, Jordan, Sam, David",
            event.description,
        )
    }

    @Test
    fun anEndTimeIsKept() {
        val ski = plans.first { it.title == "Ski A-Basin" }
        val event = PlanCalendar.event(ski, "Breck", now = now, zone = denver)
        assertEquals(ms("2026-11-08T15:30:00Z"), event.beginMillis)
        assertEquals(ms("2026-11-08T20:00:00Z"), event.endMillis)
    }

    @Test
    fun aProposalSaysSo() {
        val rentals = plans.first { it.title == "Rental pickup" }
        val event = PlanCalendar.event(rentals, "Breck", now = now, zone = denver)
        assertTrue(event.description.endsWith("\nStill a proposal in the chat."))
        assertEquals("Christy Sports on Colorado Blvd", event.location)
    }

    @Test
    fun noTimeStartsAtTheNextWholeHour() {
        val plan = CatchUp.Plan(title = "Game night", location = " ")
        val event = PlanCalendar.event(plan, "Breck Crew", app = "Instagram", now = now, zone = denver)
        assertEquals(ms("2026-11-03T18:00:00Z"), event.beginMillis) // 11:00 AM
        assertEquals(ms("2026-11-03T19:00:00Z"), event.endMillis)
        assertFalse(event.allDay)
        assertNull(event.location)
        assertEquals("From “Breck Crew” on Instagram, found by Muse Spark.\nStill a proposal in the chat.", event.description)
    }

    @Test
    fun aDateWithoutATimeIsAllDay() {
        val plan = CatchUp.Plan(title = "Breck weekend", startsAt = "2026-11-07", endsAt = "2026-11-08", status = "confirmed")
        val event = PlanCalendar.event(plan, "Breck", now = now, zone = denver)
        assertTrue(event.allDay)
        assertEquals(ms("2026-11-07T07:00:00Z"), event.beginMillis) // midnight in Denver
        assertEquals(ms("2026-11-09T07:00:00Z"), event.endMillis) // through the end of the 8th
    }

    @Test
    fun anAllDayPlanCoversItsDay() {
        val plan = CatchUp.Plan(title = "Ski day", startsAt = "2026-11-08T08:30:00-07:00", allDay = true)
        val event = PlanCalendar.event(plan, "Breck", now = now, zone = denver)
        assertTrue(event.allDay)
        assertEquals(ms("2026-11-08T07:00:00Z"), event.beginMillis)
        assertEquals(ms("2026-11-09T07:00:00Z"), event.endMillis)
    }

    @Test
    fun anEndBeforeTheStartIsIgnored() {
        val plan = CatchUp.Plan(title = "Dinner", startsAt = "2026-11-07T19:30:00-07:00", endsAt = "2026-11-07T18:00:00-07:00")
        val event = PlanCalendar.event(plan, "Breck", now = now, zone = denver)
        assertEquals(event.beginMillis + 3_600_000, event.endMillis)
    }

    @Test
    fun theIntentExtrasUseCalendarContractsNames() {
        val drive = plans.first { it.title == "Drive to Keystone / Breck" }
        val extras = PlanCalendar.extras(PlanCalendar.event(drive, "Breck", now = now, zone = denver))
        assertEquals("Drive to Keystone / Breck", extras[CalendarContract.Events.TITLE])
        assertEquals(ms("2026-11-07T13:00:00Z"), extras[CalendarContract.EXTRA_EVENT_BEGIN_TIME])
        assertEquals(ms("2026-11-07T14:00:00Z"), extras[CalendarContract.EXTRA_EVENT_END_TIME])
        assertEquals(false, extras[CalendarContract.EXTRA_EVENT_ALL_DAY])
        assertEquals("Maya's place", extras[CalendarContract.Events.EVENT_LOCATION])
        assertTrue((extras[CalendarContract.Events.DESCRIPTION] as String).startsWith("From "))
        // The names the calendar app reads, spelled out.
        assertEquals(setOf("title", "beginTime", "endTime", "allDay", "eventLocation", "description"), extras.keys)
    }

    @Test
    fun noLocationLeavesTheFieldOut() {
        val extras = PlanCalendar.extras(PlanCalendar.event(CatchUp.Plan(title = "Call"), "Breck", now = now, zone = denver))
        assertFalse(extras.containsKey(CalendarContract.Events.EVENT_LOCATION))
    }
}
