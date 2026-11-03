package com.vibetemp.ketchup.data

import com.vibetemp.ketchup.Fixtures
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** A TextThread goes to catch-up-text in exactly the shape the iOS readers send. */
class TextThreadTest {

    private val thread = KetchupJson.decodeFromString(TextThread.serializer(), Fixtures.asset("instagram-thread.json"))

    @Test
    fun wireFormMatchesTheIosReader() {
        // What iOS's Instagram reader returns for the same synthetic page.
        val expected = KetchupJson.parseToJsonElement(Fixtures.repo("ios/Ketchup/Instagram/Fixture/ig-thread-fixture.expected.json"))
            .jsonObject.getValue("messages").jsonArray.map { it.jsonObject }
        assertEquals(88, thread.messages.size)
        assertEquals(expected.size, thread.messages.size)
        assertEquals(1, thread.messages.count { it.quote != null })
        thread.messages.zip(expected).forEach { (message, ios) ->
            val isMe = ios.getValue("isMe").jsonPrimitive.boolean
            assertEquals(isMe, message.isMine)
            // WebChatAPI.swift: `m.isMe ? readerName : m.sender`.
            assertEquals(if (isMe) "David" else ios.getValue("sender").jsonPrimitive.content, message.wireSender("David"))
            assertEquals(ios.getValue("text").jsonPrimitive.content, message.wireText("David"))
        }
    }

    @Test
    fun quotesFoldLikeTheReaders() {
        val reply = TextMessage("Jordan", "perfect", quote = TextMessage.Quote("Maya", "2 spots in the garage"))
        assertEquals("(replying to Maya: \"2 spots in the garage\") perfect", reply.wireText("David"))
        val toMe = TextMessage("Maya", "yes", quote = TextMessage.Quote(text = "you in?", isMine = true))
        assertEquals("(replying to David: \"you in?\") yes", toMe.wireText("David"))
        val noWords = TextMessage("Sam", "lol", quote = TextMessage.Quote(sender = "Theo"))
        assertEquals("(replying to Theo) lol", noWords.wireText("David"))
        val bare = TextMessage("Sam", "", quote = TextMessage.Quote())
        assertEquals("(replying to a message)", bare.wireText("David"))
        val long = TextMessage("Sam", "ok", quote = TextMessage.Quote("Maya", "x".repeat(300)))
        assertEquals(120 + "(replying to Maya: \"\") ok".length, long.wireText("David").length)
    }

    @Test
    fun requestBodyIsWhatCatchUpTextTakes() {
        val small = TextThread(
            TextSource.SNAPCHAT, "Ski crew",
            listOf(
                TextMessage("Maya", "leaving at 6", at = "2026-11-03T01:07:00Z"),
                TextMessage("Me", "on my way", isMine = true),
            ),
            ReaderStats(found = 2, scrolls = 0, ms = 12, reachedStart = true, stop = "start"),
        )
        val body = KetchupJson.parseToJsonElement(KetchupApi.textRequest(small, "David", "catch_up", null, "America/Denver")).jsonObject
        assertEquals(setOf("mode", "source", "thread_title", "reader_name", "time_zone", "messages", "reader"), body.keys)
        assertEquals("catch_up", body.str("mode"))
        assertEquals("snapchat", body.str("source"))
        assertEquals("Ski crew", body.str("thread_title"))
        assertEquals("David", body.str("reader_name"))
        assertEquals("America/Denver", body.str("time_zone"))
        val messages = body.getValue("messages").jsonArray.map { it.jsonObject }
        assertEquals(mapOf("sender" to "Maya", "text" to "leaving at 6", "at" to "2026-11-03T01:07:00Z"), messages[0].strings())
        // Mine go under the reader's name, and no `at` when there's none.
        assertEquals(mapOf("sender" to "David", "text" to "on my way"), messages[1].strings())
        assertEquals(setOf("found", "scrolls", "ms", "reachedStart", "stop"), body.getValue("reader").jsonObject.keys)

        val ask = KetchupJson.parseToJsonElement(KetchupApi.textRequest(small, "David", "ask", "when do we leave?", "America/Denver")).jsonObject
        assertEquals("ask", ask.str("mode"))
        assertEquals("when do we leave?", ask.str("question"))
    }

    @Test
    fun indexRefsResolveToThreadMessages() {
        // catch-up-text cites messages by their index in the request.
        val response = KetchupJson.decodeFromString(
            BriefResponse.serializer(CatchUp.serializer()),
            """{"kind":"catch_up","source":"instagram","cached":false,"model":"muse-spark-1.3","message_count":88,
               "truncated":false,"latency_ms":9000,"result":{"tldr":"Breck is on.","highlights":[{"text":"It's the 14th","refs":[0,6]}],
               "plans":[],"open_questions":[{"question":"Which weekend?","asked_by":"Sam","refs":[5]}],"owes":[],"for_you":[]}}""",
        )
        assertEquals("instagram", response.source)
        assertFalse(response.truncated)
        val refs = response.result!!.highlights[0].refs
        assertEquals(listOf("0", "6"), refs)
        assertEquals("ok it's official", thread.message(refs[0])?.text)
        assertEquals("the 14th sam. I literally just said that", thread.message(refs[1])?.text)
        assertEquals("wait which weekend", thread.message(response.result!!.openQuestions[0].refs[0])?.text)
        assertNull(thread.message("6b38f000-3939-54a8-8fb8-290471639ee2"))
        assertNull(thread.message("400"))

        val answer = KetchupJson.decodeFromString(BriefResponse.serializer(ChatAnswer.serializer()), """{"kind":"ask","source":"instagram","result":{"answer":"The 14th.","found":true,"refs":[6]}}""")
        assertTrue(answer.result!!.found)
        assertEquals(listOf("6"), answer.result!!.refs)
    }

    @Test
    fun sourcesRoundTrip() {
        val chat: BriefSource = BriefSource.Chat("b0000000-0000-4000-8000-00000000b4ec", "Breck Weekend 🎿")
        val again = KetchupJson.decodeFromString(BriefSource.serializer(), KetchupJson.encodeToString(BriefSource.serializer(), chat))
        assertEquals(chat, again)
        val text: BriefSource = thread
        assertEquals(thread, KetchupJson.decodeFromString(BriefSource.serializer(), KetchupJson.encodeToString(BriefSource.serializer(), text)))
        assertEquals("Breck Crew 🎿", thread.displayTitle)
        assertEquals("Snapchat chat", TextThread(TextSource.SNAPCHAT, " ", emptyList()).displayTitle)
        assertEquals(TextSource.INSTAGRAM, TextSource.forPackage("com.instagram.android"))
        assertNull(TextSource.forPackage("com.whatsapp"))
    }

    private fun JsonObject.str(key: String) = getValue(key).jsonPrimitive.content
    private fun JsonObject.strings() = mapValues { it.value.jsonPrimitive.content }
}
