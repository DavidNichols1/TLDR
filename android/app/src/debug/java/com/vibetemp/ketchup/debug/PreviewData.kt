package com.vibetemp.ketchup.debug

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import com.vibetemp.ketchup.data.AskResponse
import com.vibetemp.ketchup.data.BriefResponse
import com.vibetemp.ketchup.data.BriefSource
import com.vibetemp.ketchup.data.CatchUp
import com.vibetemp.ketchup.data.CatchUpResponse
import com.vibetemp.ketchup.data.ChatAnswer
import com.vibetemp.ketchup.data.ChatSummary
import com.vibetemp.ketchup.data.InstantSerializer
import com.vibetemp.ketchup.data.KetchupJson
import com.vibetemp.ketchup.data.Member
import com.vibetemp.ketchup.data.Message
import com.vibetemp.ketchup.data.Profile
import com.vibetemp.ketchup.data.TextThread
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.time.Instant

/**
 * Fixture data for the offline previews, debug builds only. The fixtures are
 * real (iOS `Debug/Fixtures/`): the seeded "Breck Weekend 🎿" chat and what
 * Muse Spark actually said about it, plus the synthetic Instagram test
 * thread (made-up people). Decoded with the app's own [KetchupJson], so
 * previews go through the same code as live data; a broken fixture stops
 * the app.
 *
 * In a composable: `val data = previewData()`.
 */
class PreviewData private constructor(context: Context) {

    /** The 41 messages Muse Spark cited (their ids are the brief's refs), then the chat's last three lines. */
    val messages: List<Message>

    /** The Breck inbox row: 302 unread, nothing read yet. */
    val breck: ChatSummary

    val members: List<Member>

    /** The live catch-up of all 302 messages. */
    val brief: CatchUpResponse = load(context, "brief", BriefResponse.serializer(CatchUp.serializer()))

    /** A live Ask answer, and the question it answered. */
    val answer: AskResponse = load(context, "ask", BriefResponse.serializer(ChatAnswer.serializer()))
    val answerQuestion: String = load(context, "ask", Asked.serializer()).question

    /** A "the chat doesn't say" answer, and its question. */
    val notFound: AskResponse = load(context, "ask-notfound", BriefResponse.serializer(ChatAnswer.serializer()))
    val notFoundQuestion: String = load(context, "ask-notfound", Asked.serializer()).question

    /** The synthetic Instagram thread "Breck Crew 🎿" as the reader would hand it over: 88 messages, one reply. */
    val instagramThread: TextThread = load(context, "instagram-thread", TextThread.serializer())

    /** Breck as a brief's source. */
    val breckSource: BriefSource.Chat get() = BriefSource.Chat(breck.id, breck.name)

    init {
        val cited = load(context, "messages", ListSerializer(FixtureMessage.serializer())).map {
            Message(id = it.id, chatId = BRECK_ID, sender = idOf(it.name), body = it.body, createdAt = it.createdAt)
        }
        val last = cited.lastOrNull()?.createdAt ?: BRECK_CREATED
        val goodnights = listOf(
            Triple("Sam", "5:45 is a made up time", 40L),
            Triple("Priya", "goodnight!! 🌙", 95L),
            Triple("Maya", "goodnight losers 💙", 160L),
        ).mapIndexed { i, (name, body, after) ->
            Message(
                id = "e0000000-0000-4000-8000-00000000000${i + 1}",
                chatId = BRECK_ID,
                sender = idOf(name),
                body = body,
                createdAt = last.plusSeconds(after),
            )
        }
        messages = cited + goodnights
        breck = ChatSummary(
            id = BRECK_ID, name = "Breck Weekend 🎿", inviteCode = "WQGAEA", memberCount = 6,
            createdAt = BRECK_CREATED, lastMessageAt = messages.last().createdAt,
            lastMessagePreview = "goodnight losers 💙", lastMessageSenderName = "Maya",
            lastReadAt = BRECK_CREATED, unreadCount = 302,
        )
        members = CAST.map { (id, name) -> Member(id, BRECK_CREATED, BRECK_CREATED, Profile(id, name)) }
    }

    /** The name of whoever sent [message] in Breck. */
    fun senderName(message: Message): String = CAST.firstOrNull { it.first == message.sender }?.second ?: "Someone"

    /** `{id, name, body, created_at}` rows in messages.json. */
    @Serializable
    private data class FixtureMessage(
        val id: String,
        val name: String,
        val body: String,
        @SerialName("created_at") @Serializable(InstantSerializer::class) val createdAt: Instant,
    )

    /** The `question` the Ask fixtures carry next to the envelope. */
    @Serializable
    private data class Asked(val question: String)

    companion object {
        /** The reader. They've been away, so all of Breck is unread. */
        const val ME = "d0000000-0000-4000-8000-000000000001"
        const val MY_NAME = "David"
        const val BRECK_ID = "b0000000-0000-4000-8000-00000000b4ec"

        /** Before the first message, which is where the reader's cursor sits. */
        val BRECK_CREATED: Instant = Instant.parse("2026-10-28T18:00:00Z")

        private val CAST = listOf(
            ME to MY_NAME,
            "d0000000-0000-4000-8000-000000000002" to "Maya",
            "d0000000-0000-4000-8000-000000000003" to "Jordan",
            "d0000000-0000-4000-8000-000000000004" to "Priya",
            "d0000000-0000-4000-8000-000000000005" to "Sam",
            "d0000000-0000-4000-8000-000000000006" to "Theo",
        )

        private fun idOf(name: String) = CAST.firstOrNull { it.second == name }?.first ?: ME

        @Volatile
        private var loaded: PreviewData? = null

        fun get(context: Context): PreviewData = loaded ?: synchronized(this) {
            loaded ?: PreviewData(context.applicationContext).also { loaded = it }
        }

        private fun <T> load(context: Context, name: String, serializer: KSerializer<T>): T {
            val text = context.assets.open("fixtures/$name.json").bufferedReader().use { it.readText() }
            return runCatching { KetchupJson.decodeFromString(serializer, text) }
                .getOrElse { throw IllegalStateException("Fixture $name.json didn't decode", it) }
        }
    }
}

/** The fixtures, for a preview screen. */
@Composable
fun previewData(): PreviewData = PreviewData.get(LocalContext.current)
