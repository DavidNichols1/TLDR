package com.vibetemp.ketchup.data

import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test

/** The one-time Muse Spark question (ConsentGate), against a recording fake: no network, no live backend. */
class ConsentGateTest {

    private class Store(var saved: AuthSession?) : SessionStore {
        override fun load() = saved
        override fun save(session: AuthSession?) { saved = session }
    }

    /** Answers by method and path, and keeps what was sent. */
    private class Routes(val answer: (HttpRequest) -> HttpResponse) : Transport {
        val sent = mutableListOf<HttpRequest>()
        override suspend fun send(request: HttpRequest): HttpResponse {
            sent += request
            return answer(request)
        }
        fun calls() = sent.map { "${it.method} ${it.url.substringAfter(".supabase.co").substringBefore('?')}" }
    }

    private fun client(user: String, routes: Routes) =
        SupabaseClient(Store(AuthSession("access", "refresh", user, "david@example.com", 2_000_000L)), routes) { 1_000_000L }

    private fun saved(consented: Boolean) = Routes { request ->
        when {
            request.method == "GET" -> HttpResponse(200, if (consented) """[{"consented_at":"2026-11-03T20:00:00+00:00"}]""" else "[]")
            request.url.contains("/rest/v1/ai_consents") -> HttpResponse(201, "")
            else -> HttpResponse(200, "{}")
        }
    }

    @After
    fun tearDown() {
        ConsentGate.enabled = false
    }

    @Test
    fun offTheCallGoesAsBefore() = runBlocking {
        val routes = saved(consented = false)
        client("u-off", routes).function("catch-up", "{}")
        assertEquals(listOf("POST /functions/v1/catch-up"), routes.calls())
    }

    @Test
    fun alreadyAllowedOnTheServerAsksNothing() = runBlocking {
        ConsentGate.enabled = true
        val routes = saved(consented = true)
        val api = client("u-allowed", routes)
        api.function("catch-up", "{}")
        api.function("catch-up-text", "{}")
        assertEquals(
            listOf("GET /rest/v1/ai_consents", "POST /functions/v1/catch-up", "POST /functions/v1/catch-up-text"),
            routes.calls(),
        )
        assertEquals("select=consented_at&user_id=eq.u-allowed", routes.sent[0].url.substringAfter('?'))
        assertNull(ConsentGate.asking.value)
    }

    @Test
    fun yesIsSavedThenTheBriefGoes() = runBlocking {
        ConsentGate.enabled = true
        val routes = saved(consented = false)
        val api = client("u-yes", routes)
        val brief = async { api.function("catch-up-text", "{}") }
        while (ConsentGate.asking.value == null) yield()
        ConsentGate.answer(true)
        brief.await()
        assertEquals(
            listOf("GET /rest/v1/ai_consents", "POST /rest/v1/ai_consents", "POST /functions/v1/catch-up-text"),
            routes.calls(),
        )
        assertEquals("""{"user_id":"u-yes","confirmed_adult":true}""", routes.sent[1].body)
        assertEquals("resolution=ignore-duplicates,return=minimal", routes.sent[1].headers["Prefer"])
        assertNull(ConsentGate.asking.value)
        // Asked once: the next brief goes straight to Muse Spark.
        api.function("catch-up", "{}")
        assertEquals("POST /functions/v1/catch-up", routes.calls().last())
        assertEquals(4, routes.sent.size)
    }

    @Test
    fun notNowSendsNothing() = runBlocking {
        ConsentGate.enabled = true
        val routes = saved(consented = false)
        val api = client("u-no", routes)
        val brief = async { runCatching { api.function("catch-up", "{}") } }
        while (ConsentGate.asking.value == null) yield()
        ConsentGate.answer(false)
        val error = brief.await().exceptionOrNull() ?: return@runBlocking fail("Not now should stop the brief")
        assertEquals(ConsentGate.DECLINED, error.message)
        assertEquals(listOf("GET /rest/v1/ai_consents"), routes.calls())
    }

    @Test
    fun noConsentTableMeansTheServerHasNoPlansYet() = runBlocking {
        ConsentGate.enabled = true
        val routes = Routes { request ->
            if (request.method == "GET") HttpResponse(404, """{"code":"PGRST205","message":"Could not find the table 'public.ai_consents'"}""")
            else HttpResponse(200, "{}")
        }
        client("u-old-server", routes).function("catch-up", "{}")
        assertEquals(listOf("GET /rest/v1/ai_consents", "POST /functions/v1/catch-up"), routes.calls())
        assertNull(ConsentGate.asking.value)
    }

    @Test
    fun onlyMuseSparkCallsAsk() = runBlocking {
        ConsentGate.enabled = true
        val routes = saved(consented = false)
        client("u-other", routes).function("verify-purchase", "{}")
        assertEquals(listOf("POST /functions/v1/verify-purchase"), routes.calls())
    }

    @Test
    fun aRefusalFromTheServerChecksAgainNextTime() = runBlocking {
        ConsentGate.enabled = true
        var refuse = true
        val routes = Routes { request ->
            when {
                request.method == "GET" -> HttpResponse(200, """[{"consented_at":"2026-11-03T20:00:00+00:00"}]""")
                refuse -> HttpResponse(403, """{"error":"Ketchup needs your OK before it sends messages to Muse Spark.","kind":"consent_required"}""")
                else -> HttpResponse(200, "{}")
            }
        }
        val api = client("u-withdrawn", routes)
        val first = runCatching { api.function("catch-up", "{}") }.exceptionOrNull()
        assertEquals("Ketchup needs your OK before it sends messages to Muse Spark.", first?.message)
        refuse = false
        api.function("catch-up", "{}")
        assertEquals(
            listOf("GET /rest/v1/ai_consents", "POST /functions/v1/catch-up", "GET /rest/v1/ai_consents", "POST /functions/v1/catch-up"),
            routes.calls(),
        )
    }
}
