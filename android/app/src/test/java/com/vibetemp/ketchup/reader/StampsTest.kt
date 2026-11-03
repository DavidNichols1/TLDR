package com.vibetemp.ketchup.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

/** Time separators read the way the iOS readers read them, in the phone's zone. */
class StampsTest {
    // Tuesday, November 3, 2026, 10:30 AM in Denver (MST since November 1).
    private val now = ZonedDateTime.of(2026, 11, 3, 10, 30, 0, 0, ZoneId.of("America/Denver"))

    private fun at(label: String) = Stamps.parse(label, now)?.toString()

    @Test
    fun readsInstagramsLabels() {
        assertEquals("2026-11-03T15:02:00Z", at("Today 8:02 AM"))
        assertEquals("2026-11-03T15:02:00Z", at("Today at 8:02 AM"))
        assertEquals("2026-11-03T04:15:00Z", at("Yesterday 9:15 PM"))
        // The last Friday before today, still on daylight time.
        assertEquals("2026-10-31T02:30:00Z", at("Fri 8:30 PM"))
        assertEquals("2026-10-28T22:12:00Z", at("Oct 28, 4:12 PM"))
        assertEquals("2025-10-28T22:12:00Z", at("Oct 28, 2025, 4:12 PM"))
        assertEquals("2026-10-28T22:12:00Z", at("10/28/26 4:12 PM"))
        assertEquals("2026-10-28T22:12:00Z", at("28 Oct 16:12"))
        // A day with no time is noon; a month and day still ahead is last year's.
        assertEquals("2026-11-03T19:00:00Z", at("Today"))
        assertEquals("2025-12-24T19:00:00Z", at("Dec 24"))
    }

    @Test
    fun aBareTimeIsTodayUnlessThatsAhead() {
        assertEquals("2026-11-03T16:05:00Z", at("9:05 AM"))
        assertEquals("2026-11-03T04:40:00Z", at("9:40 PM"))
    }

    @Test
    fun messagesAreNotTimes() {
        for (text in listOf("ok see you then", "lol", "3 pm tomorrow?", "at 5", "", "Seen", "Maya named the group", "25:00")) {
            assertNull(text, at(text))
        }
    }
}
