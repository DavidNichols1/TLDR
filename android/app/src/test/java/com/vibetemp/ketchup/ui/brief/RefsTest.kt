package com.vibetemp.ketchup.ui.brief

import com.vibetemp.ketchup.Fixtures
import com.vibetemp.ketchup.data.BriefResponse
import com.vibetemp.ketchup.data.CatchUp
import com.vibetemp.ketchup.data.KetchupJson
import com.vibetemp.ketchup.data.Message
import com.vibetemp.ketchup.data.TextThread
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** Turning a brief's refs back into the messages it cites. */
class RefsTest {

    private val thread = KetchupJson.decodeFromString(TextThread.serializer(), Fixtures.asset("instagram-thread.json"))

    @Test
    fun aThreadRefIsAnIndexIntoTheThread() {
        val jordan = Refs.inThread(thread, "84")!!
        assertEquals("Jordan", jordan.name)
        assertEquals("David are you bringing the speaker?", jordan.text)
        assertFalse(jordan.isMine)
        assertNull(jordan.quote)

        val first = Refs.inThread(thread, "0")!!
        assertEquals("Maya", first.name)
        assertEquals("ok it's official", first.text)
    }

    @Test
    fun theReadersOwnMessageIsMine() {
        val mine = Refs.inThread(thread, "87")!!
        assertTrue(mine.isMine)
        assertEquals("sorry slammed at work today, will catch up on all this tonight", mine.text)
    }

    @Test
    fun aReplyKeepsWhatItQuotes() {
        val reply = Refs.inThread(thread, "64")!!
        assertEquals("perfect, 4runner gets one and priya gets the other", reply.text)
        assertEquals(Cited.Quote(name = "Maya", text = "2 spots in the garage, we're fine", isMine = false), reply.quote)
    }

    @Test
    fun aRefTheThreadDoesntHaveIsNull() {
        assertNull(Refs.inThread(thread, "88"))
        assertNull(Refs.inThread(thread, "-1"))
        assertNull(Refs.inThread(thread, "6b38f000-3939-54a8-8fb8-290471639ee2"))
    }

    @Test
    fun theHandWrittenInstagramBriefsRefsAllResolve() {
        // iOS's hand-written brief of this thread cites these.
        val refs = listOf("84", "85", "44", "75", "53", "23", "71", "0", "63", "64")
        assertTrue(refs.all { Refs.inThread(thread, it) != null })
        assertEquals(listOf("0", "23", "44", "63", "64", "71", "75", "84", "85"), Refs.inOrder(refs - "53" + "84"))
    }

    @Test
    fun aChatMessageIsNamedTheWayTheChatNamesItsSender() {
        val names = mapOf("u1" to "Maya", "me" to "David")
        val at = Instant.parse("2026-11-02T19:41:05Z")
        val maya = Refs.inChat(Message("m1", "c", "u1", "so the Airbnb is now \$540 total", at), names, me = "me")
        assertEquals(Cited("Maya", "so the Airbnb is now \$540 total", isMine = false, at = at), maya)
        val mine = Refs.inChat(Message("m2", "c", "me", "on my way", at), names, me = "me")
        assertTrue(mine.isMine)
        val left = Refs.inChat(Message("m3", "c", "gone", "bye", at), names, me = "me")
        assertEquals("Someone", left.name)
        val photo = Refs.inChat(Message("m4", "c", "u1", "", at, imagePath = "c/m4.jpg"), names, me = "me")
        assertEquals("Photo", photo.text)
    }

    @Test
    fun aChipShowsHowTheMessageStarts() {
        assertEquals("so the Airbnb is now \$540 to…", Refs.preview("so the Airbnb is now \$540 total = \$90 each"))
        assertEquals("short one", Refs.preview("short one"))
        assertEquals("two lines", Refs.preview("two\nlines"))
        // An emoji isn't cut in half.
        val cut = Refs.preview("a".repeat(27) + "🎿🎿")
        assertEquals("a".repeat(27) + "…", cut)
    }

    @Test
    fun everyBreckRefIsListedOnce() {
        val brief = KetchupJson.decodeFromString(BriefResponse.serializer(CatchUp.serializer()), Fixtures.asset("brief.json")).result!!
        val all = Refs.all(brief)
        assertEquals(all.distinct(), all)
        val each = brief.forYou.flatMap { it.refs } + brief.plans.flatMap { it.refs } + brief.owes.flatMap { it.refs } +
            brief.openQuestions.flatMap { it.refs } + brief.highlights.flatMap { it.refs }
        assertEquals(each.toSet(), all.toSet())
    }

    @Test
    fun theSkimStartsAtTheFirstUnreadMessage() {
        val base = Instant.parse("2026-11-01T00:00:00Z")
        val messages = (0 until 40).map { Message("m$it", "c", "u", "line $it", base.plusSeconds(it * 60L)) }
        // 30 read, 10 unread: reach back so the window has 12 lines.
        val window = SkimLines.window(messages, lastRead = base.plusSeconds(29 * 60L))
        assertEquals("m28", window.first().id)
        assertEquals(12, window.size)
        // 10 read, 30 unread: start at the first unread.
        assertEquals("m10", SkimLines.window(messages, lastRead = base.plusSeconds(9 * 60L)).first().id)
        // Nothing unread, or no cursor: the newest `limit` (all 40 here).
        assertEquals("m0", SkimLines.window(messages, lastRead = base.plusSeconds(3_000L)).first().id)
        assertEquals(40, SkimLines.window(messages, lastRead = null).size)
        assertEquals("m30", SkimLines.window(messages, lastRead = null, limit = 10, atLeast = 10).first().id)
    }
}
