package com.vibetemp.ketchup.data

import com.vibetemp.ketchup.Fixtures
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** The iOS fixtures (Muse Spark's real answers about Breck) decode into the Android models. */
class BriefFixtureTest {

    private val brief = KetchupJson.decodeFromString(BriefResponse.serializer(CatchUp.serializer()), Fixtures.asset("brief.json"))

    @Test
    fun sampleBriefDecodes() {
        assertEquals("catch_up", brief.kind)
        assertFalse(brief.cached)
        assertFalse(brief.empty)
        assertEquals("muse-spark-1.3", brief.model)
        assertEquals(302, brief.messageCount)
        assertEquals(23028L, brief.latencyMs)
        assertEquals(Instant.parse("2026-11-03T04:08:44Z"), brief.untilInstant)

        assertNotNull(brief.result)
        val result = brief.result!!
        assertTrue(result.tldr.startsWith("Breck trip moved to Saturday 6am"))
        assertEquals(5, result.highlights.size)
        assertEquals(4, result.highlights[0].refs.size)

        val drive = result.plans.first()
        assertEquals("Drive to Keystone / Breck", drive.title)
        assertTrue(drive.confirmed)
        assertFalse(drive.allDay)
        assertEquals("Maya's place", drive.location)
        assertEquals(Instant.parse("2026-11-07T13:00:00Z"), drive.startsAt?.let { Times.planTime(it) })
        assertTrue(drive.who.contains("David"))

        assertTrue(result.openQuestions.isNotEmpty())
        assertTrue(result.owes.isNotEmpty())
        assertTrue(result.forYou.isNotEmpty())
    }

    @Test
    fun everyRefIsAFixtureMessage() {
        val result = brief.result!!
        val ids = KetchupJson.parseToJsonElement(Fixtures.asset("messages.json")).jsonArray
            .map { it.jsonObject.getValue("id").jsonPrimitive.content }.toSet()
        val refs = result.highlights.flatMap { it.refs } + result.plans.flatMap { it.refs } +
            result.openQuestions.flatMap { it.refs } + result.owes.flatMap { it.refs } + result.forYou.flatMap { it.refs }
        assertTrue(refs.isNotEmpty())
        assertEquals(emptySet<String>(), refs.toSet() - ids)
    }

    @Test
    fun askAnswersDecode() {
        val found = KetchupJson.decodeFromString(BriefResponse.serializer(ChatAnswer.serializer()), Fixtures.asset("ask.json"))
        assertEquals("ask", found.kind)
        assertTrue(found.result!!.found)
        assertEquals(5, found.result!!.refs.size)

        val notFound = KetchupJson.decodeFromString(BriefResponse.serializer(ChatAnswer.serializer()), Fixtures.asset("ask-notfound.json"))
        assertFalse(notFound.result!!.found)
        assertTrue(notFound.result!!.answer.startsWith("The chat doesn't say"))
    }

    @Test
    fun emptyAndCachedEnvelopesDecode() {
        val empty = KetchupJson.decodeFromString(BriefResponse.serializer(CatchUp.serializer()), """{"kind":"catch_up","empty":true,"message_count":0}""")
        assertTrue(empty.empty)
        assertEquals(null, empty.result)

        // A repeat over the same window: the ai_briefs row spread into the envelope.
        val cached = KetchupJson.decodeFromString(
            BriefResponse.serializer(CatchUp.serializer()),
            """{"kind":"catch_up","cached":true,"brief_id":"0f1e","id":"0f1e","result":{"tldr":"Same as before."},
               "model":"muse-spark-1.3","message_count":3,"since":"2026-11-02T19:41:05.123456+00:00",
               "until":"2026-11-02T19:45:00+00:00","latency_ms":900,"created_at":"2026-11-02T19:46:00+00:00"}""",
        )
        assertTrue(cached.cached)
        assertEquals("0f1e", cached.briefId)
        assertEquals("Same as before.", cached.result!!.tldr)
        assertEquals(emptyList<CatchUp.Item>(), cached.result!!.highlights)
    }
}
