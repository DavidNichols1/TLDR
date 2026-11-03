package com.vibetemp.ketchup.data

import android.content.Context
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.time.Instant
import java.util.TimeZone
import java.util.UUID

/**
 * Every server call the slices make, as plain suspend functions. Reads go
 * through PostgREST as the signed-in member, so Row Level Security decides
 * what comes back. A failure throws [ApiException] with a sentence a person
 * can read. Port of iOS `Net/KetchupAPI.swift` and `WebChat/WebChatAPI.swift`.
 *
 *     val api = KetchupApi.get(context)
 *     api.sendCode("you@example.com"); api.verifyCode("you@example.com", "12345678")
 *     val chats = api.myChats()
 */
class KetchupApi(val client: SupabaseClient) {

    val session: StateFlow<AuthSession?> get() = client.session

    // MARK: Sign-in

    suspend fun sendCode(email: String) = client.sendCode(email.trim())

    suspend fun verifyCode(email: String, code: String): AuthSession =
        client.verifyCode(email.trim(), code.filter(Char::isDigit))

    suspend fun signOut() = client.signOut()

    // MARK: Profile

    suspend fun myProfile(): Profile? {
        val me = client.userId ?: throw ApiException.notSignedIn()
        val body = client.select("profiles", "id" to "eq.$me", "select" to "id,display_name,avatar_path")
        return KetchupJson.decodeFromString(ListSerializer(Profile.serializer()), body).firstOrNull()
    }

    suspend fun setDisplayName(name: String) {
        val me = client.userId ?: throw ApiException.notSignedIn()
        client.rest("PATCH", "/rest/v1/profiles", listOf("id" to "eq.$me"), obj("display_name" to name.trim()).toString())
    }

    // MARK: Chats

    /** The inbox, newest activity first, with unread counts. */
    suspend fun myChats(): List<ChatSummary> =
        KetchupJson.decodeFromString(ListSerializer(ChatSummary.serializer()), client.rpc("my_chats"))

    suspend fun createChat(name: String): String =
        KetchupJson.decodeFromString(ChatRow.serializer(), client.rpc("create_chat", obj("p_name" to name))).id
            ?: throw ApiException.badResponse()

    /** The chat's id, or null when no chat has that code. */
    suspend fun joinChat(code: String): String? {
        val body = client.rpc("join_chat", obj("p_code" to code))
        // A wrong code comes back as `null` or as a row of nulls.
        return runCatching { KetchupJson.decodeFromString(ChatRow.serializer(), body).id }.getOrNull()
    }

    suspend fun leaveChat(chatId: String) {
        client.rpc("leave_chat", obj("p_chat" to chatId))
    }

    /** Moves your read cursor forward to [at] (or now); never back. */
    suspend fun markRead(chatId: String, at: Instant? = null) {
        client.rpc("mark_read", if (at == null) obj("p_chat" to chatId) else obj("p_chat" to chatId, "p_at" to Times.iso(at)))
    }

    suspend fun members(chatId: String): List<Member> = KetchupJson.decodeFromString(
        ListSerializer(Member.serializer()),
        client.select(
            "chat_members",
            "chat_id" to "eq.$chatId",
            "select" to "user_id,joined_at,last_read_at,profile:profiles(id,display_name,avatar_path)",
            "order" to "joined_at.asc",
        ),
    )

    // MARK: Messages

    /** A page of messages, oldest first: the newest [limit], or the [limit] before [before]. */
    suspend fun messages(chatId: String, before: Instant? = null, limit: Int = 200): List<Message> {
        val query = mutableListOf(
            "chat_id" to "eq.$chatId",
            "select" to MESSAGE_COLUMNS,
            "order" to "created_at.desc",
            "limit" to limit.toString(),
        )
        if (before != null) query += "created_at" to "lt.${Times.iso(before)}"
        val body = client.rest("GET", "/rest/v1/messages", query)
        return KetchupJson.decodeFromString(ListSerializer(Message.serializer()), body).reversed()
    }

    /** Everything after [after], oldest first (the polling fallback when Realtime drops). */
    suspend fun messagesAfter(chatId: String, after: Instant): List<Message> = KetchupJson.decodeFromString(
        ListSerializer(Message.serializer()),
        client.select(
            "messages",
            "chat_id" to "eq.$chatId",
            "created_at" to "gt.${Times.iso(after)}",
            "select" to MESSAGE_COLUMNS,
            "order" to "created_at.asc",
            "limit" to "500",
        ),
    )

    /**
     * Sends [body] under a client-chosen [id], so the optimistic bubble and
     * the Realtime echo are the same message. Returns the saved row.
     */
    suspend fun send(chatId: String, body: String, id: String = UUID.randomUUID().toString()): Message {
        val row = obj("id" to id, "chat_id" to chatId, "body" to body)
        val saved = client.insert("messages", row.toString(), MESSAGE_COLUMNS)
        return KetchupJson.decodeFromString(ListSerializer(Message.serializer()), saved).firstOrNull()
            ?: throw ApiException.badResponse()
    }

    // MARK: Muse Spark, Ketchup chats (edge function `catch-up`)

    /** Catch me up on a chat's unread messages. `empty` when there's nothing new. */
    suspend fun catchUp(chatId: String, timeZone: String = TimeZone.getDefault().id): CatchUpResponse =
        KetchupJson.decodeFromString(
            BriefResponse.serializer(CatchUp.serializer()),
            client.function("catch-up", obj("chat_id" to chatId, "mode" to "catch_up", "time_zone" to timeZone).toString()),
        )

    /** Ask the chat a question. `result.found` is false when the chat doesn't say. */
    suspend fun ask(chatId: String, question: String, timeZone: String = TimeZone.getDefault().id): AskResponse =
        KetchupJson.decodeFromString(
            BriefResponse.serializer(ChatAnswer.serializer()),
            client.function(
                "catch-up",
                obj("chat_id" to chatId, "mode" to "ask", "question" to question, "time_zone" to timeZone).toString(),
            ),
        )

    // MARK: Muse Spark, a thread read off another app (edge function `catch-up-text`)

    /**
     * Catch me up on [thread]. [readerName] is the reader's Ketchup display
     * name: their own messages go under it, so "For you" comes out right.
     * Refs come back as indexes into the thread ([TextThread.message]).
     */
    suspend fun catchUp(thread: TextThread, readerName: String, timeZone: String = TimeZone.getDefault().id): CatchUpResponse =
        KetchupJson.decodeFromString(
            BriefResponse.serializer(CatchUp.serializer()),
            client.function("catch-up-text", textRequest(thread, readerName, "catch_up", null, timeZone)),
        )

    suspend fun ask(
        thread: TextThread,
        question: String,
        readerName: String,
        timeZone: String = TimeZone.getDefault().id,
    ): AskResponse = KetchupJson.decodeFromString(
        BriefResponse.serializer(ChatAnswer.serializer()),
        client.function("catch-up-text", textRequest(thread, readerName, "ask", question, timeZone)),
    )

    // MARK: Either kind of source

    /** Catch me up on whatever [source] is ([readerName] only matters for a [TextThread]). */
    suspend fun catchUp(source: BriefSource, readerName: String): CatchUpResponse = when (source) {
        is BriefSource.Chat -> catchUp(source.id)
        is TextThread -> catchUp(source, readerName)
    }

    suspend fun ask(source: BriefSource, question: String, readerName: String): AskResponse = when (source) {
        is BriefSource.Chat -> ask(source.id, question)
        is TextThread -> ask(source, question, readerName)
    }

    /** catch-up-text's request body (supabase/functions/catch-up-text/index.ts). */
    @Serializable
    internal data class TextRequest(
        val mode: String,
        val question: String? = null,
        val source: String,
        @SerialName("thread_title") val threadTitle: String,
        @SerialName("reader_name") val readerName: String,
        @SerialName("time_zone") val timeZone: String,
        val messages: List<WireMessage>,
        /** Counts only, for the server log. */
        val reader: ReaderStats? = null,
    )

    @Serializable
    internal data class WireMessage(val sender: String, val text: String, val at: String? = null)

    companion object {
        /** Every column: `kind` (a "Maya joined" line) exists only once migration 0009 is applied, and this build has to work on either side of it. */
        private const val MESSAGE_COLUMNS = "*"

        @Volatile
        private var instance: KetchupApi? = null

        /** The app's one client, on the session kept in private storage. Safe from the reader service too. */
        fun get(context: Context): KetchupApi = instance ?: synchronized(this) {
            instance ?: KetchupApi(SupabaseClient(PrefsSessionStore(context))).also { instance = it }
        }

        internal fun textRequest(thread: TextThread, readerName: String, mode: String, question: String?, timeZone: String): String =
            KetchupJson.encodeToString(
                TextRequest.serializer(),
                TextRequest(
                    mode = mode,
                    question = question,
                    source = thread.source.id,
                    threadTitle = thread.title,
                    readerName = readerName,
                    timeZone = timeZone,
                    messages = thread.messages.map { WireMessage(it.wireSender(readerName), it.wireText(readerName), it.at) },
                    reader = thread.stats,
                ),
            )
    }
}
