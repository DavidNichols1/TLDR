package com.vibetemp.ketchup.data.realtime

import com.vibetemp.ketchup.data.KetchupJson
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** Realtime's frames as iOS `Net/Realtime.swift` sends and reads them. No network. */
class RealtimeProtocolTest {

    private val chat = "B0000000-0000-4000-8000-00000000B4EC"
    private val topic = "realtime:chat-b0000000-0000-4000-8000-00000000b4ec"

    private fun json(text: String): JsonObject = KetchupJson.parseToJsonElement(text).jsonObject
    private fun JsonObject.str(key: String) = this[key]!!.jsonPrimitive.content
    private fun JsonObject.obj(key: String) = this[key]!!.jsonObject

    @Test
    fun joinSubscribesToThisChatsInsertsWithTheToken() {
        val frame = json(RealtimeProtocol.join(chat, "access-1", "7"))
        assertEquals(topic, frame.str("topic"))
        assertEquals("phx_join", frame.str("event"))
        assertEquals("7", frame.str("ref"))
        assertEquals("7", frame.str("join_ref"))

        val payload = frame.obj("payload")
        assertEquals("access-1", payload.str("access_token"))
        val config = payload.obj("config")
        assertEquals(false, config["private"]!!.jsonPrimitive.boolean)
        assertEquals(false, config.obj("broadcast")["self"]!!.jsonPrimitive.boolean)
        assertEquals(false, config.obj("presence")["enabled"]!!.jsonPrimitive.boolean)
        val changes = config["postgres_changes"] as JsonArray
        assertEquals(1, changes.size)
        val change = changes[0].jsonObject
        assertEquals("INSERT", change.str("event"))
        assertEquals("public", change.str("schema"))
        assertEquals("messages", change.str("table"))
        assertEquals("chat_id=eq.b0000000-0000-4000-8000-00000000b4ec", change.str("filter"))
    }

    @Test
    fun heartbeatAndTokenFrames() {
        val beat = json(RealtimeProtocol.heartbeat("12"))
        assertEquals("phoenix", beat.str("topic"))
        assertEquals("heartbeat", beat.str("event"))
        assertEquals("12", beat.str("ref"))
        assertEquals(JsonObject(emptyMap()), beat.obj("payload"))

        val token = json(RealtimeProtocol.accessToken(chat, "access-2", "13", "7"))
        assertEquals(topic, token.str("topic"))
        assertEquals("access_token", token.str("event"))
        assertEquals("access-2", token.obj("payload").str("access_token"))
        assertEquals("13", token.str("ref"))
        assertEquals("7", token.str("join_ref"))

        val leave = json(RealtimeProtocol.leave(chat, "14", "7"))
        assertEquals("phx_leave", leave.str("event"))
        assertEquals(topic, leave.str("topic"))
    }

    @Test
    fun joinRepliesCountOnlyForOurJoin() {
        val ok = """{"event":"phx_reply","payload":{"response":{"postgres_changes":[{"id":31,"event":"INSERT",
            "filter":"chat_id=eq.b0000000-0000-4000-8000-00000000b4ec","schema":"public","table":"messages"}]},
            "status":"ok"},"ref":"7","topic":"$topic"}"""
        assertEquals(RealtimeProtocol.Event.Joined, RealtimeProtocol.parse(ok, chat, "7"))
        // The same reply to another ref (an access_token push) isn't the join.
        assertEquals(RealtimeProtocol.Event.Ignored, RealtimeProtocol.parse(ok, chat, "8"))

        val refused = """{"event":"phx_reply","payload":{"response":{"reason":"Invalid JWT"},"status":"error"},"ref":"7","topic":"$topic"}"""
        assertTrue(RealtimeProtocol.parse(refused, chat, "7") is RealtimeProtocol.Event.Down)

        // Heartbeat replies come back on the phoenix topic.
        val beat = """{"event":"phx_reply","payload":{"response":{},"status":"ok"},"ref":"12","topic":"phoenix"}"""
        assertEquals(RealtimeProtocol.Event.Ignored, RealtimeProtocol.parse(beat, chat, "7"))
    }

    @Test
    fun aNewMessagePayloadBecomesAMessage() {
        // As Realtime sends it: the row under data.record, times in Postgres's text form.
        val frame = """{"event":"postgres_changes","payload":{"data":{"columns":[{"name":"id","type":"uuid"}],
            "commit_timestamp":"2026-11-03T04:08:44.123Z","errors":null,"record":{"body":"on my way 🎿",
            "chat_id":"b0000000-0000-4000-8000-00000000b4ec","created_at":"2026-11-03 04:08:44.123456+00",
            "id":"6fe6a3cc-7a99-5aa3-a3dd-be8a6a18adb5","image_height":null,"image_path":null,"image_width":null,
            "sender":"d0000000-0000-4000-8000-000000000002","edited_at":null},"schema":"public","table":"messages",
            "type":"INSERT"},"ids":[31]},"ref":null,"topic":"$topic"}"""
        val event = RealtimeProtocol.parse(frame, chat, "7")
        val message = (event as RealtimeProtocol.Event.Insert).message
        assertEquals("6fe6a3cc-7a99-5aa3-a3dd-be8a6a18adb5", message.id)
        assertEquals("b0000000-0000-4000-8000-00000000b4ec", message.chatId)
        assertEquals("d0000000-0000-4000-8000-000000000002", message.sender)
        assertEquals("on my way 🎿", message.body)
        assertEquals(Instant.parse("2026-11-03T04:08:44.123456Z"), message.createdAt)
        assertEquals(null, message.imagePath)
        assertEquals(false, message.pending)
    }

    @Test
    fun aPhotoMessageKeepsItsImage() {
        val frame = """{"event":"postgres_changes","payload":{"data":{"record":{"body":"",
            "chat_id":"b0000000-0000-4000-8000-00000000b4ec","created_at":"2026-11-03 04:08:44+00",
            "id":"m-photo","image_height":768,"image_path":"b0000000-0000-4000-8000-00000000b4ec/m-photo.jpg",
            "image_width":1024,"sender":"d0000000-0000-4000-8000-000000000002"},"type":"INSERT"}},"ref":null,"topic":"$topic"}"""
        val message = (RealtimeProtocol.parse(frame, chat, "7") as RealtimeProtocol.Event.Insert).message
        assertEquals("", message.body)
        assertEquals(1024, message.imageWidth)
        assertEquals(768, message.imageHeight)
    }

    @Test
    fun everythingElseIsIgnoredOrDown() {
        val other = """{"event":"postgres_changes","payload":{"data":{"type":"INSERT","record":{}}},"ref":null,"topic":"realtime:chat-other"}"""
        assertEquals(RealtimeProtocol.Event.Ignored, RealtimeProtocol.parse(other, chat, "7"))

        val update = """{"event":"postgres_changes","payload":{"data":{"type":"UPDATE","record":{"id":"x"}}},"ref":null,"topic":"$topic"}"""
        assertEquals(RealtimeProtocol.Event.Ignored, RealtimeProtocol.parse(update, chat, "7"))

        // A row that doesn't decode (no id) is skipped, not a crash.
        val broken = """{"event":"postgres_changes","payload":{"data":{"type":"INSERT","record":{"body":"hi"}}},"ref":null,"topic":"$topic"}"""
        assertEquals(RealtimeProtocol.Event.Ignored, RealtimeProtocol.parse(broken, chat, "7"))

        // A row from another chat on our topic (shouldn't happen) is not ours.
        val stray = """{"event":"postgres_changes","payload":{"data":{"type":"INSERT","record":{"id":"x","chat_id":"c2",
            "sender":"s","body":"b","created_at":"2026-11-03 04:08:44+00"}}},"ref":null,"topic":"$topic"}"""
        assertEquals(RealtimeProtocol.Event.Ignored, RealtimeProtocol.parse(stray, chat, "7"))

        assertEquals(RealtimeProtocol.Event.Ignored, RealtimeProtocol.parse("not json", chat, "7"))
        assertEquals(RealtimeProtocol.Event.Ignored, RealtimeProtocol.parse("""{"event":"presence_state","topic":"$topic"}""", chat, "7"))

        val subscribed = """{"event":"system","payload":{"channel":"chat-x","extension":"postgres_changes",
            "message":"Subscribed to PostgreSQL","status":"ok"},"ref":null,"topic":"$topic"}"""
        assertEquals(RealtimeProtocol.Event.Ignored, RealtimeProtocol.parse(subscribed, chat, "7"))
        val failed = """{"event":"system","payload":{"message":"Unable to subscribe","status":"error"},"ref":null,"topic":"$topic"}"""
        assertTrue(RealtimeProtocol.parse(failed, chat, "7") is RealtimeProtocol.Event.Down)

        assertTrue(RealtimeProtocol.parse("""{"event":"phx_error","payload":{},"ref":"7","topic":"$topic"}""", chat, "7") is RealtimeProtocol.Event.Down)
        assertTrue(RealtimeProtocol.parse("""{"event":"phx_close","payload":{},"ref":"7","topic":"$topic"}""", chat, "7") is RealtimeProtocol.Event.Down)
    }

    @Test
    fun backoffMatchesIos() {
        assertEquals(listOf(2_000L, 4_000L, 8_000L, 16_000L, 30_000L, 30_000L), (1..6).map(ChatRealtime::backoff))
    }
}
