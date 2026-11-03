package com.vibetemp.ketchup.ui.chat

import com.vibetemp.ketchup.data.Message
import com.vibetemp.ketchup.ui.chats.InviteCode
import com.vibetemp.ketchup.ui.chats.Stamps
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

/** The thread's rows (with "Maya joined" lines), invite codes as pasted, and the times the screens print. */
class ThreadRowsTest {

    private val zone = ZoneId.of("America/Denver")

    private fun msg(id: String, sender: String, at: String, kind: String = Message.TEXT) =
        Message(id = id, chatId = "c", sender = sender, body = id, createdAt = Instant.parse(at), kind = kind)

    private fun shape(rows: List<ThreadRow>) = rows.map {
        when (it) {
            is ThreadRow.Day -> "day ${it.day}"
            is ThreadRow.Unread -> "${it.count} new"
            is ThreadRow.Joined -> "${it.message.sender} joined"
            is ThreadRow.Bubble -> "${it.message.id}${if (it.startsRun) "<" else ""}${if (it.endsRun) ">" else ""}"
        }
    }

    @Test
    fun daysUnreadLineAndRuns() {
        val messages = listOf(
            msg("a", "maya", "2026-11-01T18:00:00Z"),
            msg("b", "maya", "2026-11-01T18:01:00Z"),
            msg("c", "theo", "2026-11-01T18:02:00Z"),
            msg("d", "theo", "2026-11-02T18:00:00Z"), // a new day breaks the run
            msg("e", "theo", "2026-11-02T18:01:00Z"), // the unread line breaks it too
            msg("f", "theo", "2026-11-02T18:02:00Z"),
        )
        val rows = threadRows(messages, firstUnreadId = "e", unreadAtOpen = 2, zone = zone)
        assertEquals(
            listOf("day 2026-11-01", "a<", "b>", "c<>", "day 2026-11-02", "d<>", "2 new", "e<", "f>"),
            shape(rows),
        )
        // Keys are unique, so the list can keep its place.
        assertEquals(rows.size, rows.map { it.key }.toSet().size)
        // Nothing unread: no line.
        assertEquals(0, threadRows(messages, null, 0, zone).count { it is ThreadRow.Unread })
    }

    @Test
    fun joinLines() {
        val messages = listOf(
            msg("a", "maya", "2026-11-01T18:00:00Z"),
            msg("j1", "rowan", "2026-11-01T18:01:00Z", Message.JOINED), // Rowan left and came back: this one goes
            msg("b", "maya", "2026-11-01T18:02:00Z"),
            msg("j2", "rowan", "2026-11-01T18:03:00Z", Message.JOINED),
            msg("c", "rowan", "2026-11-01T18:04:00Z"),
            msg("d", "maya", "2026-11-01T18:05:00Z"),
            msg("j3", "sam", "2026-11-01T18:06:00Z", Message.JOINED),
            msg("e", "maya", "2026-11-01T18:07:00Z"),
        )
        // The new part starts at a join line; a join line ends a run, and only someone's newest shows.
        val rows = threadRows(messages, firstUnreadId = "j2", unreadAtOpen = 3, zone = zone)
        assertEquals(
            listOf("day 2026-11-01", "a<", "b>", "3 new", "rowan joined", "c<>", "d<>", "sam joined", "e<>"),
            shape(rows),
        )
        assertEquals(rows.size, rows.map { it.key }.toSet().size)
        // An older line that's left out still gets its "N new" line, on the next row shown.
        assertEquals(
            listOf("day 2026-11-01", "a<>", "4 new", "b<>", "rowan joined", "c<>", "d<>", "sam joined", "e<>"),
            shape(threadRows(messages, firstUnreadId = "j1", unreadAtOpen = 4, zone = zone)),
        )
    }

    @Test
    fun inviteCodesFromWhatPeoplePaste() {
        assertEquals("WQGAEA", InviteCode.clean("wqgaea"))
        assertEquals("WQG", InviteCode.clean("wq g"))
        assertEquals("WQGAEA", InviteCode.clean("Join “Breck Weekend 🎿” on Ketchup with code WQGAEA"))
        assertEquals("RM8T2Q", InviteCode.clean("the code: RM8T2Q, thanks!"))
        assertEquals("ABCDEF", InviteCode.clean("abcdefghij"))
    }

    @Test
    fun inboxAndDayStamps() {
        val today = LocalDate.of(2026, 11, 3)
        val at = { s: String -> Instant.parse(s) }
        assertEquals("Yesterday", Stamps.inbox(at("2026-11-02T20:00:00Z"), "Yesterday", zone, today, Locale.US))
        assertEquals("Sun", Stamps.inbox(at("2026-11-01T20:00:00Z"), "Yesterday", zone, today, Locale.US))
        assertEquals("Oct 20", Stamps.inbox(at("2026-10-20T20:00:00Z"), "Yesterday", zone, today, Locale.US))
        assertEquals("Today", Stamps.day(today, "Today", "Yesterday", today, Locale.US))
        assertEquals("Monday, Nov 2", Stamps.day(LocalDate.of(2026, 11, 2), "Today", "Yest", LocalDate.of(2026, 11, 5), Locale.US))
    }
}
