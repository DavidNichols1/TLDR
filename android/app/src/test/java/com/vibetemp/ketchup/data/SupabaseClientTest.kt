package com.vibetemp.ketchup.data

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.Instant

/** The client's requests and session rules, against a recording fake: no network, no live backend. */
class SupabaseClientTest {

    private class MemoryStore(var saved: AuthSession? = null) : SessionStore {
        override fun load() = saved
        override fun save(session: AuthSession?) { saved = session }
    }

    /** Answers each request with the next canned response, and keeps what was sent. */
    private class FakeTransport(vararg answers: HttpResponse) : Transport {
        val sent = mutableListOf<HttpRequest>()
        private val queue = ArrayDeque(answers.toList())
        override suspend fun send(request: HttpRequest): HttpResponse {
            sent += request
            return queue.removeFirstOrNull() ?: error("No answer for ${request.method} ${request.url}")
        }
    }

    private var clock = 1_000_000L
    private val base = Config.SUPABASE_URL

    private fun session(expiresAt: Long = clock + 3600) =
        AuthSession("access-1", "refresh-1", "d0000000-0000-4000-8000-000000000001", "david@example.com", expiresAt)

    private fun sessionJson(access: String, refresh: String) =
        """{"access_token":"$access","refresh_token":"$refresh","expires_in":3600,"token_type":"bearer",
           "user":{"id":"d0000000-0000-4000-8000-000000000001","email":"david@example.com"}}"""

    @After
    fun tearDown() {
        Previewing.active = false
    }

    @Test
    fun sendCodeAndVerifyKeepTheSession() = runBlocking {
        val store = MemoryStore()
        val transport = FakeTransport(HttpResponse(200, "{}"), HttpResponse(200, sessionJson("a", "r")))
        val api = KetchupApi(SupabaseClient(store, transport) { clock })

        api.sendCode(" david@example.com ")
        val otp = transport.sent[0]
        assertEquals("POST", otp.method)
        assertEquals("$base/auth/v1/otp", otp.url)
        assertEquals(Config.PUBLISHABLE_KEY, otp.headers["apikey"])
        assertNull(otp.headers["Authorization"])
        assertEquals("""{"email":"david@example.com","create_user":true}""", otp.body)

        val signedIn = api.verifyCode("david@example.com", "1234 5678")
        assertEquals("$base/auth/v1/verify", transport.sent[1].url)
        assertEquals("""{"type":"email","email":"david@example.com","token":"12345678"}""", transport.sent[1].body)
        assertEquals("a", signedIn.accessToken)
        assertEquals(clock + 3600, signedIn.expiresAt)
        assertEquals(signedIn, store.saved)
        assertEquals(signedIn, api.session.value)
    }

    @Test
    fun readsCarryTheTokenAndDecode() = runBlocking {
        val inbox = """[{"id":"b0000000-0000-4000-8000-00000000b4ec","name":"Breck Weekend 🎿","invite_code":"WQGAEA",
            "member_count":6,"created_at":"2026-10-28T18:00:00+00:00","last_message_at":"2026-11-03T04:11:24.5+00:00",
            "last_message_preview":"goodnight losers 💙","last_message_sender_name":"Maya",
            "last_read_at":"2026-10-28T18:00:00+00:00","unread_count":302}]"""
        val page = """[{"id":"m2","chat_id":"c","sender":"s","body":"second","created_at":"2026-11-03T04:08:44.123456+00:00"},
            {"id":"m1","chat_id":"c","sender":"s","body":"first","created_at":"2026-11-03T04:08:40+00:00","image_path":null}]"""
        val transport = FakeTransport(HttpResponse(200, inbox), HttpResponse(200, page))
        val api = KetchupApi(SupabaseClient(MemoryStore(session()), transport) { clock })

        val chats = api.myChats()
        assertEquals("$base/rest/v1/rpc/my_chats", transport.sent[0].url)
        assertEquals("Bearer access-1", transport.sent[0].headers["Authorization"])
        assertEquals(302, chats.single().unreadCount)
        assertEquals(Instant.parse("2026-11-03T04:11:24.500Z"), chats.single().lastMessageAt)

        val messages = api.messages("c", before = Instant.parse("2026-11-03T05:00:00Z"), limit = 2)
        assertEquals(
            // Every column: rows have a kind ("Maya joined") only once migration 0009 is applied.
            "$base/rest/v1/messages?chat_id=eq.c&select=*" +
                "&order=created_at.desc&limit=2&created_at=lt.2026-11-03T05:00:00Z",
            transport.sent[1].url,
        )
        assertEquals(listOf("first", "second"), messages.map { it.body })
    }

    @Test
    fun sendAndCatchUpPostTheRightBodies() = runBlocking {
        val row = """[{"id":"x1","chat_id":"c","sender":"me","body":"on my way","created_at":"2026-11-03T04:08:44+00:00"}]"""
        val transport = FakeTransport(HttpResponse(201, row), HttpResponse(200, """{"kind":"catch_up","empty":true,"message_count":0}"""))
        val api = KetchupApi(SupabaseClient(MemoryStore(session()), transport) { clock })

        val sent = api.send("c", "on my way", id = "x1")
        assertEquals("x1", sent.id)
        val insert = transport.sent[0]
        assertEquals("POST", insert.method)
        assertTrue(insert.url.startsWith("$base/rest/v1/messages?select="))
        assertEquals("return=representation", insert.headers["Prefer"])
        assertEquals("""{"id":"x1","chat_id":"c","body":"on my way"}""", insert.body)

        val brief = api.catchUp("c", timeZone = "America/Denver")
        assertTrue(brief.empty)
        val call = transport.sent[1]
        assertEquals("$base/functions/v1/catch-up", call.url)
        assertEquals(SupabaseClient.FUNCTION_TIMEOUT_MS, call.timeoutMs)
        assertEquals("""{"chat_id":"c","mode":"catch_up","time_zone":"America/Denver"}""", call.body)
    }

    @Test
    fun anExpiringTokenRefreshesFirst() = runBlocking {
        val store = MemoryStore(session(expiresAt = clock + 30))
        val transport = FakeTransport(HttpResponse(200, sessionJson("access-2", "refresh-2")), HttpResponse(200, "[]"))
        val api = KetchupApi(SupabaseClient(store, transport) { clock })

        api.myChats()
        assertEquals("$base/auth/v1/token?grant_type=refresh_token", transport.sent[0].url)
        assertEquals("""{"refresh_token":"refresh-1"}""", transport.sent[0].body)
        assertEquals("Bearer access-2", transport.sent[1].headers["Authorization"])
        assertEquals("refresh-2", store.saved?.refreshToken)
    }

    @Test
    fun onlyAuthRefusingTheTokenSignsOut() = runBlocking {
        // A 5xx (or no network) keeps the session for the next try.
        val keeps = MemoryStore(session(expiresAt = clock + 30))
        val flaky = SupabaseClient(keeps, FakeTransport(HttpResponse(503, """{"message":"upstream down"}""")), now = { clock })
        val e1 = runCatching { flaky.rpc("my_chats") }.exceptionOrNull() as ApiException
        assertEquals(503, e1.status)
        assertNotNull(keeps.saved)

        // 400 from the token endpoint: the refresh token is dead.
        val ends = MemoryStore(session(expiresAt = clock + 30))
        val refused = SupabaseClient(ends, FakeTransport(HttpResponse(400, """{"error":"invalid_grant","error_description":"Refresh Token Not Found"}""")), now = { clock })
        val e2 = runCatching { refused.rpc("my_chats") }.exceptionOrNull() as ApiException
        assertEquals("Sign in to continue.", e2.message)
        assertNull(ends.saved)
        assertNull(refused.session.value)
    }

    @Test
    fun signOutForgetsTheSessionEvenOffline() = runBlocking {
        val store = MemoryStore(session())
        val transport = FakeTransport(HttpResponse(500, ""))
        val client = SupabaseClient(store, transport) { clock }
        client.signOut()
        assertEquals("$base/auth/v1/logout", transport.sent.single().url)
        assertEquals("Bearer access-1", transport.sent.single().headers["Authorization"])
        assertNull(store.saved)
    }

    @Test
    fun errorsReadAsSentences() = runBlocking {
        val transport = FakeTransport(HttpResponse(403, """{"code":"42501","message":"new row violates row-level security policy for table \"messages\""}"""))
        val api = KetchupApi(SupabaseClient(MemoryStore(session()), transport) { clock })
        try {
            api.send("c", "hi")
            fail("expected a refusal")
        } catch (e: ApiException) {
            assertEquals("That isn't allowed in this chat.", e.message)
            assertEquals(403, e.status)
            assertEquals("42501", e.code)
        }
    }

    @Test
    fun previewModeSendsNothing() = runBlocking {
        Previewing.active = true
        val transport = FakeTransport()
        val api = KetchupApi(SupabaseClient(MemoryStore(session()), transport) { clock })
        for (call in listOf<suspend () -> Unit>({ api.sendCode("a@b.c") }, { api.myChats() }, { api.catchUp("c") })) {
            val e = runCatching { call() }.exceptionOrNull()
            assertEquals("Offline preview: nothing goes to the server.", e?.message)
        }
        assertTrue(transport.sent.isEmpty())
    }

    @Test
    fun rpcArgsAreJson() = runBlocking {
        val transport = FakeTransport(HttpResponse(204, ""), HttpResponse(204, ""))
        val api = KetchupApi(SupabaseClient(MemoryStore(session()), transport) { clock })
        api.markRead("c")
        api.markRead("c", at = Instant.parse("2026-11-03T04:08:44Z"))
        assertEquals("""{"p_chat":"c"}""", transport.sent[0].body)
        val second = KetchupJson.parseToJsonElement(transport.sent[1].body!!).jsonObject
        assertEquals("2026-11-03T04:08:44Z", second.getValue("p_at").jsonPrimitive.content)
    }
}
