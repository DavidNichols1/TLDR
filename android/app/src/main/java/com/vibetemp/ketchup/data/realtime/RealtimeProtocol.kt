package com.vibetemp.ketchup.data.realtime

import com.vibetemp.ketchup.data.KetchupJson
import com.vibetemp.ketchup.data.Message
import com.vibetemp.ketchup.data.obj
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Supabase Realtime's Phoenix protocol (vsn 1.0.0, JSON frames), exactly as
 * iOS `Net/Realtime.swift` speaks it: one channel per open chat,
 * `realtime:chat-<id>`, joined with a postgres_changes filter on that chat's
 * message inserts and the member's access token, so Realtime applies the
 * messages select policy (non-members and blocked senders get nothing).
 * Plain functions, so the JVM tests check every frame.
 */
object RealtimeProtocol {

    /** Seconds between heartbeats (iOS sends one every 25 s; Realtime drops a socket after about a minute without). */
    const val HEARTBEAT_MS = 25_000L

    fun topic(chatId: String): String = "realtime:chat-${chatId.lowercase()}"

    /** The channel join: INSERTs on public.messages for this chat only, no broadcast or presence. */
    fun join(chatId: String, accessToken: String, ref: String): String = obj(
        "topic" to topic(chatId),
        "event" to "phx_join",
        "ref" to ref,
        "join_ref" to ref,
        "payload" to obj(
            "config" to obj(
                "broadcast" to obj("ack" to false, "self" to false),
                "presence" to obj("enabled" to false),
                "postgres_changes" to listOf(
                    obj(
                        "event" to "INSERT",
                        "schema" to "public",
                        "table" to "messages",
                        "filter" to "chat_id=eq.${chatId.lowercase()}",
                    ),
                ),
                "private" to false,
            ),
            "access_token" to accessToken,
        ),
    ).toString()

    /** Keeps the socket open; it goes on the "phoenix" topic, not the channel's. */
    fun heartbeat(ref: String): String =
        obj("topic" to "phoenix", "event" to "heartbeat", "payload" to obj(), "ref" to ref).toString()

    /** Hands the channel a refreshed token (they last an hour). */
    fun accessToken(chatId: String, accessToken: String, ref: String, joinRef: String): String = obj(
        "topic" to topic(chatId),
        "event" to "access_token",
        "payload" to obj("access_token" to accessToken),
        "ref" to ref,
        "join_ref" to joinRef,
    ).toString()

    /** Leaves the channel politely before the socket closes. */
    fun leave(chatId: String, ref: String, joinRef: String): String = obj(
        "topic" to topic(chatId),
        "event" to "phx_leave",
        "payload" to obj(),
        "ref" to ref,
        "join_ref" to joinRef,
    ).toString()

    /** What a frame from the server means for one chat's channel. */
    sealed interface Event {
        /** The join was accepted: inserts will stream. */
        data object Joined : Event

        /** The join was refused, or the channel or its postgres_changes subscription failed: nothing will stream. */
        data class Down(val reason: String) : Event

        /** A new message in this chat. */
        data class Insert(val message: Message) : Event

        /** Anything else: heartbeat replies, other topics, events we don't use. */
        data object Ignored : Event
    }

    /** Reads one server frame for [chatId]'s channel, joined with [joinRef]. Never throws. */
    fun parse(text: String, chatId: String, joinRef: String): Event {
        val frame = runCatching { KetchupJson.parseToJsonElement(text).jsonObject }.getOrNull() ?: return Event.Ignored
        if (frame.string("topic") != topic(chatId)) return Event.Ignored
        val payload = frame["payload"] as? JsonObject ?: JsonObject(emptyMap())
        return when (frame.string("event")) {
            "phx_reply" -> {
                // Replies to our heartbeats go to "phoenix"; access_token replies carry their own ref.
                if (frame.string("ref") != joinRef) return Event.Ignored
                if (payload.string("status") == "ok") Event.Joined else Event.Down("join refused: ${payload.string("status")}")
            }
            // A postgres_changes subscription status; "error" means no events will come.
            "system" -> if (payload.string("status") == "error") Event.Down("system error") else Event.Ignored
            "postgres_changes" -> {
                val data = payload["data"] as? JsonObject ?: return Event.Ignored
                if (data.string("type") != "INSERT") return Event.Ignored
                val record = data["record"] as? JsonObject ?: return Event.Ignored
                val message = runCatching { KetchupJson.decodeFromJsonElement(Message.serializer(), record) }.getOrNull()
                    ?: return Event.Ignored
                if (!message.chatId.equals(chatId, ignoreCase = true)) Event.Ignored else Event.Insert(message)
            }
            "phx_error" -> Event.Down("channel error")
            "phx_close" -> Event.Down("channel closed")
            else -> Event.Ignored
        }
    }

    private fun JsonObject.string(key: String): String? =
        (this[key] as? JsonPrimitive)?.let { runCatching { it.jsonPrimitive.contentOrNull }.getOrNull() }
}
