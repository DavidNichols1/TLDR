package com.vibetemp.ketchup.ui.chat

import com.vibetemp.ketchup.data.ApiException
import com.vibetemp.ketchup.data.ChatSummary
import com.vibetemp.ketchup.data.KetchupJson
import com.vibetemp.ketchup.data.Member
import com.vibetemp.ketchup.data.Message
import com.vibetemp.ketchup.data.Profile
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import kotlinx.serialization.builtins.ListSerializer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** Paging, merging, sending and the read cursor against a fake server. No network. */
class ChatModelTest {

    private val chatId = "c0000000-0000-4000-8000-000000000001"
    private val me = "d0000000-0000-4000-8000-000000000001"
    private val maya = "d0000000-0000-4000-8000-000000000002"
    private val t0: Instant = Instant.parse("2026-11-01T12:00:00Z")

    /** Message n from Maya at t0 + n minutes, id "m0042". */
    private fun msg(n: Int, sender: String = maya) =
        Message(id = "m%04d".format(n), chatId = chatId, sender = sender, body = "message $n", createdAt = t0.plusSeconds(60L * n))

    private fun summary(unread: Int, lastRead: Instant = t0.minusSeconds(60)) = ChatSummary(
        id = chatId, name = "Breck", inviteCode = "WQGAEA", memberCount = 2, createdAt = t0.minusSeconds(3600),
        lastMessageAt = null, lastReadAt = lastRead, unreadCount = unread,
    )

    /** The server: [all] messages, oldest first, served in pages like PostgREST. */
    private class FakeServer(var all: List<Message>, var myCursor: Instant, val me: String, val maya: String) : ChatBackend {
        val pageCalls = mutableListOf<Pair<Instant?, Int>>()
        val sent = mutableListOf<Pair<String, String>>()
        val readMarks = mutableListOf<Instant?>()
        var failSends = 0
        var sendGate: CompletableDeferred<Unit>? = null
        var membersCalls = 0

        override suspend fun messages(chatId: String, before: Instant?, limit: Int): List<Message> {
            pageCalls += before to limit
            val older = if (before == null) all else all.filter { it.createdAt < before }
            return older.takeLast(limit)
        }

        override suspend fun messagesAfter(chatId: String, after: Instant) = all.filter { it.createdAt > after }

        override suspend fun members(chatId: String): List<Member> {
            membersCalls += 1
            return listOf(
                Member(me, Instant.EPOCH, myCursor, Profile(me, "David")),
                Member(maya, Instant.EPOCH, Instant.EPOCH, Profile(maya, "Maya")),
            )
        }

        override suspend fun send(chatId: String, body: String, id: String): Message {
            sendGate?.await()
            sent += id to body
            if (failSends > 0) {
                failSends -= 1
                throw ApiException("Couldn't reach Ketchup.")
            }
            val row = Message(id = id, chatId = chatId, sender = me, body = body, createdAt = Instant.parse("2026-11-02T00:00:00Z"))
            all = all + row
            return row
        }

        override suspend fun markRead(chatId: String, at: Instant?) {
            readMarks += at
        }
    }

    @Test
    fun mergeConfirmsByIdAndKeepsInFlightLast() {
        val pending = Message("x1", chatId, me, "on my way", t0.plusSeconds(9_999), pending = true)
        val failed = Message("x2", chatId, me, "hello?", t0.plusSeconds(9_999), failed = true)
        val current = listOf(msg(1), msg(3), pending, failed)

        // A page that overlaps what's here, out of order, plus a row from another chat.
        val merged = ThreadMerge.merge(current, listOf(msg(3), msg(2), msg(1), msg(4).copy(chatId = "other")), chatId)
        assertEquals(listOf("m0001", "m0002", "m0003", "x1", "x2"), merged.map { it.id })

        // The pending bubble's echo (Realtime or the insert's reply) confirms it in place by server time.
        val echo = pending.copy(createdAt = t0.plusSeconds(150), pending = false)
        val confirmed = ThreadMerge.merge(merged, listOf(echo), chatId)
        assertEquals(listOf("m0001", "m0002", "x1", "m0003", "x2"), confirmed.map { it.id })
        assertFalse(confirmed.first { it.id == "x1" }.pending)
        assertEquals(1, confirmed.count { it.id == "x1" })
    }

    @Test
    fun firstPageReachesBackToTheUnreadAndCountsExactly() = runBlocking {
        val server = FakeServer((1..450).map { msg(it) }, myCursor = t0.plusSeconds(60L * 240), me = me, maya = maya)
        val model = ChatModel(summary(unread = 300), me, server, this)
        model.open()
        val s = model.state.value

        // 300 unread + 25 of context; then it pages back to the server's cursor (message 240).
        assertEquals(null to 325, server.pageCalls.first())
        assertTrue(s.synced)
        assertTrue(s.loaded)
        assertEquals(210, s.unreadCount)
        assertEquals(210, s.unreadAtOpen)
        assertEquals("m0241", s.firstUnreadId)
        assertEquals((126..450).map { "m%04d".format(it) }, s.messages.map { it.id })
        assertEquals("Maya", model.name(maya))
        assertEquals("You", model.name(me))
    }

    @Test
    fun aJoinLineStartsTheNewPartButIsNeverCounted() = runBlocking {
        // Maya joins (a "Maya joined" line, migration 0009), then says two things, all after your cursor.
        val joined = Message("j0001", chatId, maya, "joined", t0.plusSeconds(30), kind = Message.JOINED)
        val server = FakeServer(listOf(joined, msg(1), msg(2)), myCursor = t0, me = me, maya = maya)
        val model = ChatModel(summary(unread = 2, lastRead = t0), me, server, this)
        model.open()
        val s = model.state.value
        assertEquals(2, s.unreadCount)
        assertEquals(2, s.unreadAtOpen)
        assertEquals("j0001", s.firstUnreadId)

        // Only a join line since your cursor: nothing new, and no "N new" line.
        val quiet = FakeServer(listOf(msg(1), joined.copy(createdAt = t0.plusSeconds(90))), myCursor = t0.plusSeconds(60), me = me, maya = maya)
        val other = ChatModel(summary(unread = 0, lastRead = t0.plusSeconds(60)), me, quiet, this)
        other.open()
        assertEquals(0, other.state.value.unreadCount)
        assertNull(other.state.value.firstUnreadId)
    }

    @Test
    fun rowsFromBeforeKindReadAsText() {
        val rows = KetchupJson.decodeFromString(
            ListSerializer(Message.serializer()),
            """[
              {"id":"a","chat_id":"c","sender":"s","body":"hi","created_at":"2026-11-01T12:00:00Z"},
              {"id":"b","chat_id":"c","sender":"s","body":"joined","created_at":"2026-11-01T12:01:00Z","kind":"joined"},
              {"id":"c","chat_id":"c","sender":"s","body":"yo","created_at":"2026-11-01T12:02:00Z","kind":"text"}
            ]""",
        )
        assertEquals(listOf(Message.TEXT, Message.JOINED, Message.TEXT), rows.map { it.kind })
        assertEquals(listOf(false, true, false), rows.map { it.isJoin })
    }

    @Test
    fun olderPagesAndRealtimeRowsNeverDuplicate() = runBlocking {
        val server = FakeServer((1..590).map { msg(it) }, myCursor = t0.plusSeconds(60L * 590), me = me, maya = maya)
        val model = ChatModel(summary(unread = 0, lastRead = t0.plusSeconds(60L * 590)), me, server, this)
        model.open()
        assertEquals((391..590).map { "m%04d".format(it) }, model.state.value.messages.map { it.id })
        assertTrue(model.state.value.hasOlder)

        // Realtime delivers a new row, and an old one that a page also returns.
        server.all = server.all + msg(591)
        model.merge(listOf(msg(591), msg(391)))
        // The polling fallback finds nothing newer, and the older pages overlap nothing twice.
        model.poll()
        model.loadOlder()
        model.loadOlder()
        val ids = model.state.value.messages.map { it.id }
        assertEquals(ids.distinct(), ids)
        assertEquals((1..591).map { "m%04d".format(it) }, ids)
        assertFalse(model.state.value.hasOlder)
        assertEquals(0, model.state.value.unreadCount)
    }

    @Test
    fun aJumpPagesBackUntilTheMessageIsHere() = runBlocking {
        val server = FakeServer((1..1000).map { msg(it) }, myCursor = t0.plusSeconds(60L * 1000), me = me, maya = maya)
        val model = ChatModel(summary(unread = 0, lastRead = t0.plusSeconds(60L * 1000)), me, server, this)
        model.open()
        assertTrue(model.ensureLoaded("m0350"))
        assertTrue(model.state.value.messages.any { it.id == "m0350" })
        assertEquals(listOf(null, t0.plusSeconds(60L * 801), t0.plusSeconds(60L * 601), t0.plusSeconds(60L * 401)), server.pageCalls.map { it.first })
        assertFalse(model.ensureLoaded("not-a-message"))
    }

    @Test
    fun aSendShowsAtOnceAndSettlesInPlace() = runBlocking {
        val server = FakeServer((1..3).map { msg(it) }, myCursor = t0, me = me, maya = maya)
        val model = ChatModel(summary(unread = 3, lastRead = t0), me, server, this)
        model.open()
        assertEquals(3, model.state.value.unreadCount)

        val gate = CompletableDeferred<Unit>()
        server.sendGate = gate
        val job = model.send("on my way")
        yield() // the insert is on its way, waiting on the server
        val bubble = model.state.value.messages.last()
        assertTrue(bubble.pending)
        assertEquals("on my way", bubble.body)
        assertEquals(me, bubble.sender)
        // Sending catches you up: the server moves the sender's cursor.
        assertEquals(0, model.state.value.unreadCount)

        // The Realtime echo lands before the insert's reply: one bubble, confirmed.
        val echo = bubble.copy(pending = false, createdAt = Instant.parse("2026-11-02T00:00:00Z"))
        model.merge(listOf(echo))
        gate.complete(Unit)
        job.join()
        val mine = model.state.value.messages.filter { it.id == bubble.id }
        assertEquals(1, mine.size)
        assertFalse(mine.single().pending)
        assertFalse(mine.single().failed)
        assertEquals(listOf(bubble.id to "on my way"), server.sent)
    }

    @Test
    fun aFailedSendCanBeRetried() = runBlocking {
        val server = FakeServer(listOf(msg(1)), myCursor = t0, me = me, maya = maya)
        server.failSends = 1
        val model = ChatModel(summary(unread = 0), me, server, this)
        model.open()
        model.send("hello?").join()
        val failed = model.state.value.messages.last()
        assertTrue(failed.failed)
        assertFalse(failed.pending)

        model.retry(failed.id)!!.join()
        val sent = model.state.value.messages.last()
        assertEquals(failed.id, sent.id)
        assertFalse(sent.failed)
        assertFalse(sent.pending)
        // Same id both times, so a lost reply can never make two rows.
        assertEquals(listOf(failed.id, failed.id), server.sent.map { it.first })
        assertNull(model.retry(sent.id))
    }

    @Test
    fun aDuplicateKeyMeansItLanded() = runBlocking {
        val server = object : ChatBackend by FakeServer(listOf(msg(1)), t0, me, maya) {
            override suspend fun send(chatId: String, body: String, id: String): Message =
                throw ApiException("duplicate key value violates unique constraint \"messages_pkey\"", 409, "23505")
        }
        val model = ChatModel(summary(unread = 0), me, server, this)
        model.open()
        model.send("hi").join()
        val m = model.state.value.messages.last()
        assertFalse(m.pending)
        assertFalse(m.failed)
    }

    @Test
    fun scrollingToTheBottomMarksRead() = runBlocking {
        val server = FakeServer((1..5).map { msg(it) }, myCursor = t0, me = me, maya = maya)
        val model = ChatModel(summary(unread = 5, lastRead = t0), me, server, this)
        model.open()
        assertEquals(5, model.state.value.unreadCount)
        model.reachedBottomByScrolling()
        yield()
        assertEquals(0, model.state.value.unreadCount)
        assertEquals(listOf<Instant?>(null), server.readMarks)
        // The divider stays where it was.
        assertEquals("m0001", model.state.value.firstUnreadId)
    }

    @Test
    fun aBriefThatMovedTheCursorClearsTheCount() = runBlocking {
        val server = FakeServer((1..20).map { msg(it) }, myCursor = t0, me = me, maya = maya)
        val model = ChatModel(summary(unread = 20, lastRead = t0), me, server, this)
        model.open()
        assertEquals(20, model.state.value.unreadCount)
        // The brief read through message 15 and moved the cursor there.
        server.myCursor = t0.plusSeconds(60L * 15)
        model.refreshCursor()
        assertEquals(5, model.state.value.unreadCount)
        assertEquals(20, model.state.value.unreadAtOpen)
    }

    @Test
    fun aFailedFirstLoadSaysWhyAndPollTriesAgain() = runBlocking {
        var down = true
        val real = FakeServer((1..3).map { msg(it) }, myCursor = t0, me = me, maya = maya)
        val server = object : ChatBackend by real {
            override suspend fun messages(chatId: String, before: Instant?, limit: Int): List<Message> {
                if (down) throw java.io.IOException("no route to host")
                return real.messages(chatId, before, limit)
            }
        }
        val model = ChatModel(summary(unread = 3), me, server, this)
        model.open()
        assertFalse(model.state.value.loaded)
        assertEquals("Couldn't reach Ketchup. Check your connection and try again.", model.state.value.loadError)
        down = false
        model.poll()
        assertTrue(model.state.value.synced)
        assertNull(model.state.value.loadError)
        assertEquals(3, model.state.value.messages.size)
    }
}
