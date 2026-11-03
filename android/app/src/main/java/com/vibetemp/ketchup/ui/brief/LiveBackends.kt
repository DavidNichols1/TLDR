package com.vibetemp.ketchup.ui.brief

import com.vibetemp.ketchup.data.AskResponse
import com.vibetemp.ketchup.data.BriefSource
import com.vibetemp.ketchup.data.CatchUpResponse
import com.vibetemp.ketchup.data.KetchupApi
import com.vibetemp.ketchup.data.KetchupJson
import com.vibetemp.ketchup.data.Member
import com.vibetemp.ketchup.data.Message
import com.vibetemp.ketchup.data.TextThread
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.builtins.ListSerializer
import java.time.Instant

/** The live backend for [source], on the app's one API client. */
fun liveBackend(api: KetchupApi, source: BriefSource): BriefBackend = when (source) {
    is BriefSource.Chat -> ChatBackend(api, source)
    is TextThread -> ThreadBackend(api, source)
}

/**
 * A Ketchup chat: the `catch-up` edge function reads it from the database
 * as the signed-in member. The skim runs the chat's own recent messages;
 * a source chip names its sender the way the chat does.
 */
internal class ChatBackend(private val api: KetchupApi, private val chat: BriefSource.Chat) : BriefBackend {
    override val signedIn: Boolean get() = api.session.value != null
    private val me: String? get() = api.session.value?.userId

    private val lock = Mutex()
    private var members: List<Member>? = null
    /** Messages fetched so far, by id: the newest page, then any cited ones from before it. */
    private val loaded = HashMap<String, Message>()

    private suspend fun members(): List<Member> = lock.withLock {
        members ?: api.members(chat.id).also { members = it }
    }

    private suspend fun names(): Map<String, String> =
        catching { members() }.getOrDefault(emptyList()).associate { it.userId to it.name }

    /** Members without a profile come through as "Someone", which isn't a name to greet. */
    override suspend fun readerName(): String {
        val me = me ?: return ""
        return names()[me]?.trim()?.takeIf { it.isNotEmpty() && it != "Someone" }.orEmpty()
    }

    override suspend fun skim(): Skim = coroutineScope {
        val people = async { catching { members() }.getOrDefault(emptyList()) }
        val unread = async { catching { api.myChats().firstOrNull { it.id == chat.id }?.unreadCount }.getOrNull() }
        val page = api.messages(chat.id)
        lock.withLock { page.forEach { loaded[it.id] = it } }
        val members = people.await()
        val names = members.associate { it.userId to it.name }
        val lastRead = members.firstOrNull { it.userId == me }?.lastReadAt
        fun lines(messages: List<Message>) = messages.map { SkimLines.line(Refs.inChat(it, names, me)) }
        Skim(
            catchUp = lines(SkimLines.window(page, lastRead)),
            ask = lines(SkimLines.window(page, null)),
            unread = unread.await() ?: lastRead?.let { read -> page.count { it.createdAt > read } },
        )
    }

    override suspend fun catchUp(readerName: String): CatchUpResponse = api.catchUp(chat.id)

    override suspend fun ask(question: String, readerName: String): AskResponse = api.ask(chat.id, question)

    /** Cited messages older than the page the skim loaded are fetched by id, in one call per 80. */
    override suspend fun cited(refs: Collection<String>): Map<String, Cited> {
        val missing = lock.withLock { refs.filter { it !in loaded && UUID_SHAPE.matches(it) } }
        for (chunk in missing.chunked(80)) {
            val body = api.client.select(
                "messages",
                "chat_id" to "eq.${chat.id}",
                "id" to "in.(${chunk.joinToString(",")})",
                "select" to MESSAGE_COLUMNS,
            )
            val found = KetchupJson.decodeFromString(ListSerializer(Message.serializer()), body)
            lock.withLock { found.forEach { loaded[it.id] = it } }
        }
        val names = names()
        val me = me
        return lock.withLock { refs.mapNotNull { ref -> loaded[ref]?.let { ref to Refs.inChat(it, names, me) } }.toMap() }
    }

    override suspend fun caughtUp(until: Instant?) = api.markRead(chat.id, until)

    private companion object {
        const val MESSAGE_COLUMNS = "id,chat_id,sender,body,created_at,image_path,image_width,image_height"
        val UUID_SHAPE = Regex("^[0-9a-fA-F-]{36}$")
    }
}

/**
 * A thread read off Instagram or Snapchat: `catch-up-text` gets the
 * messages themselves and stores nothing. Refs are indexes into the thread,
 * so everything a chip needs is already here. Held in memory only.
 */
internal class ThreadBackend(private val api: KetchupApi, private val thread: TextThread) : BriefBackend {
    override val signedIn: Boolean get() = api.session.value != null

    /** The reader's Ketchup name, so their own messages and "For you" come out right; "Me" without one (iOS). */
    override suspend fun readerName(): String =
        catching { api.myProfile()?.displayName }.getOrNull()?.trim()?.takeIf { it.isNotEmpty() } ?: "Me"

    override suspend fun skim(): Skim {
        val lines = thread.messages.indices.mapNotNull { i -> Refs.inThread(thread, i.toString())?.let(SkimLines::line) }
        return Skim(catchUp = lines, ask = lines, unread = thread.messages.size)
    }

    override suspend fun catchUp(readerName: String): CatchUpResponse = api.catchUp(thread, readerName)

    override suspend fun ask(question: String, readerName: String): AskResponse = api.ask(thread, question, readerName)

    override suspend fun cited(refs: Collection<String>): Map<String, Cited> =
        refs.mapNotNull { ref -> Refs.inThread(thread, ref)?.let { ref to it } }.toMap()

    override suspend fun caughtUp(until: Instant?) = Unit
}
