package com.vibetemp.ketchup.data

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.UnknownHostException

/** The terms gate (migration 0011, TermsGate), against a recording fake: no network, no live backend. */
class TermsGateTest {

    private class Store(var saved: AuthSession?) : SessionStore {
        override fun load() = saved
        override fun save(session: AuthSession?) { saved = session }
    }

    /** Answers each request with [answer], and keeps what was sent. */
    private class Routes(val answer: suspend (HttpRequest) -> HttpResponse) : Transport {
        val sent = mutableListOf<HttpRequest>()
        override suspend fun send(request: HttpRequest): HttpResponse {
            sent += request
            return answer(request)
        }
        fun calls() = sent.map { "${it.method} ${it.url.substringAfter(".supabase.co").substringBefore('?')}" }
    }

    /** What a phone kept, by user id. */
    private class Kept(vararg kept: Pair<String, String>) : TermsStore {
        val versions = mutableMapOf(*kept)
        override fun version(userId: String) = versions[userId]
        override fun keep(userId: String, version: String) { versions[userId] = version }
    }

    private val me = "d0000000-0000-4000-8000-000000000001"

    private fun client(routes: Routes) =
        SupabaseClient(Store(AuthSession("access", "refresh", me, "david@example.com", 2_000_000L)), routes) { 1_000_000L }

    private fun answering(status: Int, body: String) = Routes { HttpResponse(status, body) }

    private fun row(version: String) = """[{"version":"$version","accepted_at":"2026-11-04T18:00:00+00:00"}]"""

    private val accepted = """{"version":"2026-11-04","accepted_at":"2026-11-04T18:00:00+00:00"}"""

    /** PostgREST before migration 0011: no table, no function. */
    private val noTable = """{"code":"PGRST205","message":"Could not find the table 'public.terms_acceptances' in the schema cache"}"""
    private val noFunction = """{"code":"PGRST202","message":"Could not find the function public.accept_terms(p_version) in the schema cache"}"""

    @Test
    fun noRowMeansTheTermsScreen() = runBlocking {
        val routes = answering(200, "[]")
        val kept = Kept()
        assertTrue(TermsGate(client(routes), kept).needsAgreement(me))
        assertEquals(listOf("GET /rest/v1/terms_acceptances"), routes.calls())
        assertEquals("select=version,accepted_at&user_id=eq.$me", routes.sent[0].url.substringAfter('?'))
        assertEquals("Bearer access", routes.sent[0].headers["Authorization"])
        assertNull(kept.version(me))
    }

    @Test
    fun anOlderVersionMeansTheTermsScreen() = runBlocking {
        val kept = Kept()
        assertTrue(TermsGate(client(answering(200, row("2026-10-01"))), kept, version = "2026-11-04").needsAgreement(me))
        assertNull(kept.version(me))
    }

    @Test
    fun theSameOrANewerVersionIsAgreedAndKept() = runBlocking {
        for (version in listOf("2026-11-04", "2027-01-15")) {
            val kept = Kept()
            assertFalse(TermsGate(client(answering(200, row(version))), kept, version = "2026-11-04").needsAgreement(me))
            assertEquals(version, kept.version(me))
        }
    }

    @Test
    fun anErrorLetsThemInAndTheNextLaunchAsksAgain() = runBlocking {
        val missing = answering(404, noTable)
        val kept = Kept()
        val gate = TermsGate(client(missing), kept)
        assertFalse(gate.needsAgreement(me))
        // The rest of this launch doesn't ask again...
        assertFalse(gate.needsAgreement(me))
        assertEquals(1, missing.sent.size)
        assertNull(kept.version(me))
        // ...and the next launch (a new gate on the same phone) does.
        val next = answering(200, "[]")
        assertTrue(TermsGate(client(next), kept).needsAgreement(me))
        assertEquals(1, next.sent.size)

        // Offline, and a 2xx that isn't rows (a captive portal), let them in too.
        assertFalse(TermsGate(client(Routes { throw UnknownHostException("made up") }), Kept()).needsAgreement(me))
        assertFalse(TermsGate(client(answering(200, "<html>Sign in to the Wi-Fi</html>")), Kept()).needsAgreement(me))
    }

    @Test
    fun keptOnThisPhoneAsksNothing() = runBlocking {
        val routes = answering(200, "[]")
        assertFalse(TermsGate(client(routes), Kept(me to "2026-11-04")).needsAgreement(me))
        assertFalse(TermsGate(client(routes), Kept(me to "2027-01-15"), version = "2026-11-04").needsAgreement(me))
        assertTrue(routes.sent.isEmpty())
        // Kept for an older version (the terms changed since): the server decides again.
        assertTrue(TermsGate(client(routes), Kept(me to "2026-10-01"), version = "2026-11-04").needsAgreement(me))
        assertEquals(1, routes.sent.size)
        // Someone else's acceptance on this phone isn't yours.
        assertTrue(TermsGate(client(routes), Kept("d0000000-0000-4000-8000-000000000002" to "2026-11-04")).needsAgreement(me))
    }

    @Test
    fun agreeingCallsTheRpcAndKeepsIt() = runBlocking {
        val routes = answering(200, accepted)
        val kept = Kept()
        TermsGate(client(routes), kept).agree(me)
        val call = routes.sent.single()
        assertEquals("POST", call.method)
        assertEquals("${Config.SUPABASE_URL}/rest/v1/rpc/accept_terms", call.url)
        assertEquals("""{"p_version":"2026-11-04"}""", call.body)
        assertEquals("Bearer access", call.headers["Authorization"])
        assertEquals("2026-11-04", kept.version(me))
        // Kept: the next launch needs no network.
        val later = answering(200, "[]")
        assertFalse(TermsGate(client(later), kept).needsAgreement(me))
        assertTrue(later.sent.isEmpty())
    }

    @Test
    fun anAgreeThatFailsThrowsAndKeepsNothing() = runBlocking {
        for (routes in listOf(answering(503, """{"message":"upstream down"}"""), Routes { throw UnknownHostException("made up") })) {
            val kept = Kept()
            val gate = TermsGate(client(routes), kept)
            assertTrue(runCatching { gate.agree(me) }.exceptionOrNull() != null)
            assertNull(kept.version(me))
            // Still not agreed: the screen stays, to try again.
            assertTrue(TermsGate(client(answering(200, "[]")), kept).needsAgreement(me))
        }
    }

    @Test
    fun theSignInPathRecordsAcceptance() = runBlocking {
        // Each way in, then what AppModel.signedIn does with the new session.
        val session = """{"access_token":"a","refresh_token":"r","expires_in":3600,"user":{"id":"$me","email":"david@example.com"}}"""
        for ((name, signIn) in listOf<Pair<String, suspend (KetchupApi) -> AuthSession>>(
            "/auth/v1/verify" to { it.verifyCode("david@example.com", "12345678") },
            "/auth/v1/token" to { it.signInWithPassword("david@example.com", "made-up pass") },
        )) {
            val routes = Routes { request -> HttpResponse(200, if (request.url.contains("/auth/v1/")) session else accepted) }
            val client = SupabaseClient(Store(null), routes) { 1_000_000L }
            val kept = Kept()
            val signedIn = signIn(KetchupApi(client))
            assertFalse(TermsGate(client, kept).signedIn(signedIn.userId))
            assertEquals(listOf("POST $name", "POST /rest/v1/rpc/accept_terms"), routes.calls())
            assertEquals("""{"p_version":"2026-11-04"}""", routes.sent[1].body)
            assertEquals("Bearer a", routes.sent[1].headers["Authorization"])
            assertEquals("2026-11-04", kept.version(me))
        }
    }

    @Test
    fun aSignInIsAgreedBeforeAcceptTermsAnswers() = runBlocking {
        // accept_terms is slow, and the root's own check runs while it's on its way.
        val reply = CompletableDeferred<HttpResponse>()
        val routes = Routes { request -> if (request.url.contains("/rpc/accept_terms")) reply.await() else HttpResponse(200, "[]") }
        val kept = Kept()
        val gate = TermsGate(client(routes), kept)
        val signIn = async(start = CoroutineStart.UNDISPATCHED) { gate.signedIn(me) }
        assertFalse(gate.needsAgreement(me))
        assertEquals(listOf("POST /rest/v1/rpc/accept_terms"), routes.calls())
        reply.complete(HttpResponse(200, accepted))
        assertFalse(signIn.await())
        assertEquals("2026-11-04", kept.version(me))
    }

    @Test
    fun aCheckAlreadyAskingWhenTheSignInLandsShowsNoScreen() = runBlocking {
        // The root's check got there first and the server has no row yet.
        val rows = CompletableDeferred<HttpResponse>()
        val routes = Routes { request -> if (request.method == "GET") rows.await() else HttpResponse(200, accepted) }
        val gate = TermsGate(client(routes), Kept())
        val check = async(start = CoroutineStart.UNDISPATCHED) { gate.needsAgreement(me) }
        assertFalse(gate.signedIn(me))
        rows.complete(HttpResponse(200, "[]"))
        assertFalse(check.await())
    }

    @Test
    fun aSignInThatCantRecordFallsBackToTheCheck() = runBlocking {
        // Before 0011: no function and no table, so they're let in.
        val before = Routes { request -> HttpResponse(404, if (request.method == "POST") noFunction else noTable) }
        val kept = Kept()
        assertFalse(TermsGate(client(before), kept).signedIn(me))
        assertEquals(listOf("POST /rest/v1/rpc/accept_terms", "GET /rest/v1/terms_acceptances"), before.calls())
        assertNull(kept.version(me))

        // The save failed, but the check finds no row: the terms screen after all.
        val flaky = Routes { request -> if (request.method == "POST") HttpResponse(500, """{"message":"made up"}""") else HttpResponse(200, "[]") }
        assertTrue(TermsGate(client(flaky), Kept()).signedIn(me))
    }
}
