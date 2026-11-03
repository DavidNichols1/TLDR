package com.vibetemp.ketchup.data

import com.vibetemp.ketchup.ui.theme.People
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class TimesAndPeopleTest {

    @Test
    fun postgresTimesParse() {
        // Postgres's microseconds survive, so a read cursor set to a message's own time covers it.
        assertEquals(Instant.parse("2026-11-02T19:41:05.123456Z"), Times.instant("2026-11-02T19:41:05.123456+00:00"))
        assertEquals("2026-11-02T19:41:05.123456Z", Times.iso(Times.instant("2026-11-02T19:41:05.123456+00:00")!!))
        assertEquals(Instant.parse("2026-11-02T19:41:05.123Z"), Times.instant("2026-11-02 19:41:05.123+00"))
        assertEquals(Instant.parse("2026-11-03T04:08:44Z"), Times.instant("2026-11-03T04:08:44Z"))
        assertEquals(Instant.parse("2026-11-07T13:00:00Z"), Times.instant("2026-11-07T06:00:00-07:00"))
        assertNull(Times.instant("Saturday"))
    }

    @Test
    fun planTimesTakeWhatJavaScriptWould() {
        val denver = ZoneId.of("America/Denver")
        assertEquals(Instant.parse("2026-11-06T07:00:00Z"), Times.planTime("2026-11-06", denver))
        assertEquals(Instant.parse("2026-11-07T02:00:00Z"), Times.planTime("2026-11-06T19:00", denver))
    }

    @Test
    fun theDemoChatsSixPeopleGetSixColors() {
        // Same hash as iOS Theme.personColor(name:), whose salt was picked for exactly this.
        val names = listOf("David", "Maya", "Jordan", "Priya", "Sam", "Theo")
        assertEquals(6, names.map(People::colorIndex).toSet().size)
        assertEquals(People.colorIndex("Maya"), People.colorIndex(" maya "))
    }

    @Test
    fun initials() {
        assertEquals("MC", People.initials("Maya Chen"))
        assertEquals("S", People.initials("sam"))
        assertEquals("GJ", People.initials("Grandma June"))
        assertEquals("?", People.initials(""))
    }
}
