package com.vibetemp.ketchup.data

import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonTransformingSerializer
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId

/**
 * The one JSON setup for everything the server sends and the app keeps:
 * unknown keys are skipped (the server can add fields), nulls are left out
 * of what the app sends, and defaults fill in what a row leaves out.
 */
val KetchupJson: Json = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    coerceInputValues = true
    encodeDefaults = true
}

/**
 * A JSON object from plain values: strings, numbers, booleans, null, lists
 * of those, or JSON elements. For RPC arguments and request bodies.
 */
fun obj(vararg pairs: Pair<String, Any?>): JsonObject = JsonObject(pairs.associate { (k, v) -> k to element(v) })

private fun element(value: Any?): JsonElement = when (value) {
    null -> JsonNull
    is JsonElement -> value
    is String -> JsonPrimitive(value)
    is Number -> JsonPrimitive(value)
    is Boolean -> JsonPrimitive(value)
    is Iterable<*> -> JsonArray(value.map(::element))
    else -> throw IllegalArgumentException("Not a JSON value: ${value::class.simpleName}")
}

/** Postgres and Muse Spark times. */
object Times {
    /**
     * A Postgres timestamp as PostgREST ("2026-11-02T19:41:05.123456+00:00")
     * or Realtime's text form ("2026-11-02 19:41:05+00") sends it, or plain
     * ISO 8601 ("2026-11-03T04:08:44Z"). Null when it isn't a time.
     */
    fun instant(raw: String): Instant? {
        var s = raw.trim().replace(' ', 'T')
        // An hours-only offset ("+00") gets its minutes ("+00:00").
        val tail = s.takeLast(3)
        if (s.length > 6 && (tail[0] == '+' || tail[0] == '-') && tail.drop(1).all(Char::isDigit)) s += ":00"
        return runCatching { OffsetDateTime.parse(s).toInstant() }.getOrNull()
            ?: runCatching { Instant.parse(s) }.getOrNull()
    }

    /**
     * A plan's `starts_at`/`ends_at`. Muse Spark is asked for ISO 8601 with
     * an offset, but the edge function keeps anything JavaScript can parse,
     * so a bare date ("2026-11-06") or a local time without an offset counts
     * too, read in [zone] (iOS `CatchUp.Plan.parse`).
     */
    fun planTime(raw: String, zone: ZoneId = ZoneId.systemDefault()): Instant? =
        instant(raw)
            ?: runCatching { LocalDateTime.parse(raw).atZone(zone).toInstant() }.getOrNull()
            ?: runCatching { LocalDate.parse(raw).atStartOfDay(zone).toInstant() }.getOrNull()

    /**
     * What the server takes: ISO 8601 in UTC at full precision. Postgres keeps
     * microseconds and so does this (iOS rounds to milliseconds), so a read
     * cursor or a page boundary set to a message's own time still covers it.
     */
    fun iso(instant: Instant): String = instant.toString()
}

/** [Instant] as the server's timestamp string. */
object InstantSerializer : KSerializer<Instant> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("ketchup.Instant", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeString(Times.iso(value))

    override fun deserialize(decoder: Decoder): Instant {
        val raw = decoder.decodeString()
        return Times.instant(raw) ?: throw IllegalArgumentException("Unparseable time: $raw")
    }
}

/**
 * A brief's `refs`. The `catch-up` function cites Ketchup messages by id
 * ("6b38f000-..."); `catch-up-text` cites a [TextThread]'s messages by their
 * index in the request (0, 3, 12). Both arrive here as strings ("0", "3"),
 * so one model fits both: [BriefSource.message] turns a ref back into its
 * message.
 */
object RefsSerializer : JsonTransformingSerializer<List<String>>(ListSerializer(String.serializer())) {
    override fun transformDeserialize(element: JsonElement): JsonElement =
        JsonArray((element as? JsonArray).orEmpty().mapNotNull { item ->
            (item as? JsonPrimitive)?.content?.takeIf { it.isNotBlank() && it != "null" }?.let(::JsonPrimitive)
        })
}
