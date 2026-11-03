package com.vibetemp.ketchup.data.realtime

import com.vibetemp.ketchup.data.KetchupJson
import com.vibetemp.ketchup.data.Message
import com.vibetemp.ketchup.data.Previewing
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** The connection's life against a fake socket: join, live, inserts, heartbeats, a new token, a drop, stop. */
class ChatRealtimeTest {

    private val chat = "b0000000-0000-4000-8000-00000000b4ec"
    private val topic = "realtime:chat-$chat"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    @After
    fun tearDown() {
        scope.cancel()
        Previewing.active = false
    }

    /** One fake socket: what the client sent, and frames the test pushes as the server. */
    private class FakeConnection : WebSocketConnection {
        val sent = LinkedBlockingQueue<String>()
        val incoming = LinkedBlockingQueue<String>()

        @Volatile
        var closed = false

        override fun send(text: String): Boolean {
            if (closed) return false
            sent.put(text)
            return true
        }

        override fun receive(): String? {
            while (!closed) {
                val next = incoming.poll(50, TimeUnit.MILLISECONDS) ?: continue
                if (next == EOF) return null
                return next
            }
            return null
        }

        override fun close() {
            closed = true
        }

        /** The next frame the client sent, as (event, ref). */
        fun nextSent(): Pair<String, String> {
            val text = sent.poll(5, TimeUnit.SECONDS) ?: error("The client sent nothing")
            val json = KetchupJson.parseToJsonElement(text).jsonObject
            return json["event"]!!.jsonPrimitive.content to json["ref"]!!.jsonPrimitive.content
        }

        companion object {
            const val EOF = "<eof>"
        }
    }

    private class FakeConnector : WebSocketConnector {
        val opened = CopyOnWriteArrayList<FakeConnection>()
        val urls = CopyOnWriteArrayList<String>()
        override fun connect(url: String): WebSocketConnection {
            urls += url
            return FakeConnection().also { opened += it }
        }

        fun waitFor(count: Int): FakeConnection {
            val deadline = System.currentTimeMillis() + 5_000
            while (opened.size < count) {
                if (System.currentTimeMillis() > deadline) error("Only ${opened.size} connections, wanted $count")
                Thread.sleep(10)
            }
            return opened[count - 1]
        }
    }

    private fun insertFrame(id: String, body: String) =
        """{"event":"postgres_changes","payload":{"data":{"type":"INSERT","record":{"id":"$id","chat_id":"$chat",
            "sender":"d0000000-0000-4000-8000-000000000002","body":"$body","created_at":"2026-11-03 04:08:44.5+00"}},
            "ids":[1]},"ref":null,"topic":"$topic"}"""

    @Test
    fun joinsGoesLiveAndDeliversInserts() = runBlocking {
        val connector = FakeConnector()
        val inserted = LinkedBlockingQueue<Message>()
        val realtime = ChatRealtime(chat, scope, accessToken = { "access-1" }, connector = connector,
            url = "wss://example.test/realtime", heartbeatMs = 60_000, onInsert = { inserted.put(it) })
        realtime.start()
        realtime.start() // a second start while running does nothing

        val conn = connector.waitFor(1)
        assertEquals("wss://example.test/realtime", connector.urls.single())
        val (event, joinRef) = conn.nextSent()
        assertEquals("phx_join", event)
        assertFalse(realtime.isLive.value)

        conn.incoming.put("""{"event":"phx_reply","payload":{"response":{},"status":"ok"},"ref":"$joinRef","topic":"$topic"}""")
        withTimeout(5_000) { realtime.isLive.first { it } }

        conn.incoming.put(insertFrame("m1", "first"))
        conn.incoming.put(insertFrame("m2", "second"))
        assertEquals("first", inserted.poll(5, TimeUnit.SECONDS)!!.body)
        assertEquals("second", inserted.poll(5, TimeUnit.SECONDS)!!.body)

        realtime.stop()
        assertFalse(realtime.isLive.value)
        assertTrue(conn.closed)
        assertEquals(1, connector.opened.size)
    }

    @Test
    fun heartbeatsAndANewTokenGoOut() = runBlocking {
        val connector = FakeConnector()
        val token = AtomicReference("access-1")
        val realtime = ChatRealtime(chat, scope, accessToken = { token.get() }, connector = connector,
            url = "wss://example.test/realtime", heartbeatMs = 40, onInsert = {})
        realtime.start()
        val conn = connector.waitFor(1)
        val (_, joinRef) = conn.nextSent()

        val beat = KetchupJson.parseToJsonElement(conn.sent.poll(5, TimeUnit.SECONDS)!!).jsonObject
        assertEquals("heartbeat", beat["event"]!!.jsonPrimitive.content)
        assertEquals("phoenix", beat["topic"]!!.jsonPrimitive.content)

        // The next beat notices the refreshed token and hands it to the channel, under the join's ref.
        token.set("access-2")
        val pushed = (1..6).asSequence()
            .mapNotNull { conn.sent.poll(5, TimeUnit.SECONDS) }
            .map { KetchupJson.parseToJsonElement(it).jsonObject }
            .first { it["event"]!!.jsonPrimitive.content == "access_token" }
        assertEquals(topic, pushed["topic"]!!.jsonPrimitive.content)
        assertEquals(joinRef, pushed["join_ref"]!!.jsonPrimitive.content)
        assertEquals("access-2", pushed["payload"]!!.jsonObject["access_token"]!!.jsonPrimitive.content)
        realtime.stop()
    }

    @Test
    fun aDroppedChannelReconnectsWithTheFreshToken() = runBlocking {
        val connector = FakeConnector()
        val tokens = listOf("access-1", "access-2").iterator()
        val realtime = ChatRealtime(chat, scope, accessToken = { if (tokens.hasNext()) tokens.next() else "access-2" },
            connector = connector, url = "wss://example.test/realtime", heartbeatMs = 60_000,
            backoffMs = { 20 }, onInsert = {})
        realtime.start()
        val first = connector.waitFor(1)
        val (_, joinRef) = first.nextSent()
        first.incoming.put("""{"event":"phx_reply","payload":{"response":{},"status":"ok"},"ref":"$joinRef","topic":"$topic"}""")
        withTimeout(5_000) { realtime.isLive.first { it } }

        // The channel errors (an expired token, a server restart): not live, then a new socket.
        first.incoming.put("""{"event":"phx_error","payload":{},"ref":"$joinRef","topic":"$topic"}""")
        withTimeout(5_000) { realtime.isLive.first { !it } }
        val second = connector.waitFor(2)
        assertTrue(first.closed)
        val join = second.sent.poll(5, TimeUnit.SECONDS)!!
        assertTrue(join, join.contains("\"access_token\":\"access-2\""))
        realtime.stop()
    }

    @Test
    fun aClosedSocketAlsoReconnects() = runBlocking {
        val connector = FakeConnector()
        val realtime = ChatRealtime(chat, scope, accessToken = { "access-1" }, connector = connector,
            url = "wss://example.test/realtime", heartbeatMs = 60_000, backoffMs = { 20 }, onInsert = {})
        realtime.start()
        val first = connector.waitFor(1)
        first.nextSent()
        first.incoming.put(FakeConnection.EOF)
        connector.waitFor(2)
        realtime.stop()
    }

    @Test
    fun signedOutOrPreviewingNeverConnects() = runBlocking {
        val connector = FakeConnector()
        val signedOut = ChatRealtime(chat, scope, accessToken = { null }, connector = connector, onInsert = {})
        signedOut.start()
        Thread.sleep(100)
        assertEquals(0, connector.opened.size)

        Previewing.active = true
        val previewing = ChatRealtime(chat, scope, accessToken = { "access-1" }, connector = connector, onInsert = {})
        previewing.start()
        Thread.sleep(100)
        assertEquals(0, connector.opened.size)
    }
}
