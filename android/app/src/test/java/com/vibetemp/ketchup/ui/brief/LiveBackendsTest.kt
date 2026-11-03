package com.vibetemp.ketchup.ui.brief

import com.vibetemp.ketchup.Fixtures
import com.vibetemp.ketchup.data.AuthSession
import com.vibetemp.ketchup.data.BriefSource
import com.vibetemp.ketchup.data.HttpRequest
import com.vibetemp.ketchup.data.HttpResponse
import com.vibetemp.ketchup.data.KetchupApi
import com.vibetemp.ketchup.data.KetchupJson
import com.vibetemp.ketchup.data.SessionStore
import com.vibetemp.ketchup.data.SupabaseClient
import com.vibetemp.ketchup.data.TextThread
import com.vibetemp.ketchup.data.Transport
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The live backends on the app's real client, against a recording fake
 * transport (no network): what a chat's and a thread's brief send, and that
 * only a Ketchup chat's successful catch-up moves the read cursor, to `until`.
 */
class LiveBackendsTest {

    private val me = "d0000000-0000-4000-8000-000000000001"
    private val chat = BriefSource.Chat("b0000000-0000-4000-8000-00000000b4ec", "Breck Weekend")

    private class Store(var saved: AuthSession?) : SessionStore {
        override fun load() = saved
        override fun save(session: AuthSession?) { saved = session }
    }

    /** Answers by path, so the skim's parallel reads can come in any order; keeps what was sent. */
    private class Routes(private val answer: (HttpRequest) -> HttpResponse) : Transport {
        val sent = mutableListOf<HttpRequest>()
        override suspend fun send(request: HttpRequest): HttpResponse {
            sent += request
            return answer(request)
        }
        fun to(path: String) = sent.filter { it.url.substringBefore('?').endsWith(path) }
    }

    private fun api(transport: Transport, signedIn: Boolean = true): KetchupApi {
        val session = AuthSession("access", "refresh", me, "david@example.com", expiresAt = 2_000_000L)
        return KetchupApi(SupabaseClient(Store(if (signedIn) session else null), transport) { 1_000_000L })
    }

    private fun chatRoutes(catchUp: HttpResponse) = Routes { request ->
        val path = request.url.substringAfter(".supabase.co").substringBefore('?')
        when (path) {
            "/rest/v1/chat_members" -> HttpResponse(
                200,
                """[{"user_id":"$me","joined_at":"2026-10-28T18:00:00Z","last_read_at":"2026-10-28T18:00:00Z",
                    "profile":{"id":"$me","display_name":"David"}}]""",
            )
            "/rest/v1/messages" -> HttpResponse(200, "[]")
            "/rest/v1/rpc/my_chats" -> HttpResponse(200, "[]")
            "/functions/v1/catch-up" -> catchUp
            "/rest/v1/rpc/mark_read" -> HttpResponse(204, "")
            else -> error("Unexpected ${request.method} $path")
        }
    }

    private fun run(source: BriefSource, api: KetchupApi): BriefSession =
        BriefSession(source, liveBackend(api, source), CoroutineScope(Dispatchers.Unconfined)).apply { start() }

    @Test
    fun aChatsBriefMarksItReadThroughUntil() {
        val routes = chatRoutes(HttpResponse(200, Fixtures.asset("brief.json")))
        val session = run(chat, api(routes))
        assertEquals(BriefStage.Brief, session.stage())
        assertEquals("David", session.readerName)

        val catchUp = KetchupJson.parseToJsonElement(routes.to("/functions/v1/catch-up").single().body!!).jsonObject
        assertEquals(chat.id, catchUp.getValue("chat_id").jsonPrimitive.content)
        assertEquals("catch_up", catchUp.getValue("mode").jsonPrimitive.content)

        val markRead = KetchupJson.parseToJsonElement(routes.to("/rest/v1/rpc/mark_read").single().body!!).jsonObject
        assertEquals(chat.id, markRead.getValue("p_chat").jsonPrimitive.content)
        assertEquals("2026-11-03T04:08:44Z", markRead.getValue("p_at").jsonPrimitive.content)

        // Cited messages the page didn't load are fetched by id, in this chat only.
        val cited = routes.to("/rest/v1/messages").map { it.url }.filter { "id=in." in it }
        assertTrue(cited.isNotEmpty())
        assertTrue(cited.all { "chat_id=eq.${chat.id}" in it })
    }

    @Test
    fun theAskEntrySendsOnlyQuestions() {
        val routes = Routes { request ->
            when (request.url.substringAfter(".supabase.co").substringBefore('?')) {
                "/rest/v1/chat_members" -> HttpResponse(
                    200,
                    """[{"user_id":"$me","joined_at":"2026-10-28T18:00:00Z","last_read_at":"2026-10-28T18:00:00Z",
                        "profile":{"id":"$me","display_name":"David"}}]""",
                )
                "/rest/v1/messages", "/rest/v1/rpc/my_chats" -> HttpResponse(200, "[]")
                "/functions/v1/catch-up" -> {
                    val mode = KetchupJson.parseToJsonElement(request.body!!).jsonObject.getValue("mode").jsonPrimitive.content
                    if (mode == "ask") HttpResponse(200, Fixtures.asset("ask.json")) else HttpResponse(500, """{"error":"caught up"}""")
                }
                else -> error("Unexpected ${request.method} ${request.url}")
            }
        }
        val api = api(routes)
        val session = BriefSession(chat, liveBackend(api, chat), CoroutineScope(Dispatchers.Unconfined), askFirst = true)
        session.start()
        assertEquals(BriefStage.Ask, session.stage())
        assertTrue(routes.to("/functions/v1/catch-up").isEmpty())

        session.ask("How much do I owe and to who?")
        assertEquals(true, session.answer.done?.result?.found)
        val modes = routes.to("/functions/v1/catch-up").map {
            KetchupJson.parseToJsonElement(it.body!!).jsonObject.getValue("mode").jsonPrimitive.content
        }
        assertEquals(listOf("ask"), modes)
        assertTrue(routes.sent.none { "mark_read" in it.url })
    }

    @Test
    fun nothingNewOrAFailureMarksNothing() {
        val empty = chatRoutes(HttpResponse(200, """{"kind":"catch_up","empty":true,"message_count":0}"""))
        assertEquals(BriefStage.Empty, run(chat, api(empty)).stage())
        assertTrue(empty.to("/rest/v1/rpc/mark_read").isEmpty())

        val busy = chatRoutes(HttpResponse(502, """{"error":"Muse Spark couldn't summarize that right now. Try again."}"""))
        val failed = run(chat, api(busy))
        assertEquals(Phase.Failed("Muse Spark couldn't summarize that right now. Try again."), failed.catchUp)
        assertTrue(busy.to("/rest/v1/rpc/mark_read").isEmpty())
    }

    @Test
    fun notSignedInSendsNothing() {
        val routes = chatRoutes(HttpResponse(200, Fixtures.asset("brief.json")))
        val session = run(chat, api(routes, signedIn = false))
        assertTrue(session.signedOut)
        assertTrue(routes.sent.isEmpty())
    }

    @Test
    fun aThreadSendsTheReadersNameAndNeverMarksRead() {
        val thread = KetchupJson.decodeFromString(TextThread.serializer(), Fixtures.asset("instagram-thread.json"))
        val brief = """{"kind":"catch_up","source":"instagram","cached":false,"message_count":88,"latency_ms":17400,
            "result":{"tldr":"Breck is on.","for_you":[{"text":"Jordan asked about the speaker.","refs":[84]}]}}"""
        for ((profiles, sent) in listOf("""[{"id":"$me","display_name":"David"}]""" to "David", "[]" to "Me")) {
            val routes = Routes { request ->
                when (request.url.substringAfter(".supabase.co").substringBefore('?')) {
                    "/rest/v1/profiles" -> HttpResponse(200, profiles)
                    "/functions/v1/catch-up-text" -> HttpResponse(200, brief)
                    else -> error("Unexpected ${request.method} ${request.url}")
                }
            }
            val session = run(thread, api(routes))
            assertEquals(BriefStage.Brief, session.stage())
            val body = KetchupJson.parseToJsonElement(routes.to("/functions/v1/catch-up-text").single().body!!).jsonObject
            assertEquals(sent, body.getValue("reader_name").jsonPrimitive.content)
            assertEquals("instagram", body.getValue("source").jsonPrimitive.content)
            // The source chip reads the thread itself: message 84 is Jordan's.
            assertEquals("Jordan", session.cited.getValue("84").name)
            assertTrue(routes.sent.none { "mark_read" in it.url })
        }
    }
}
