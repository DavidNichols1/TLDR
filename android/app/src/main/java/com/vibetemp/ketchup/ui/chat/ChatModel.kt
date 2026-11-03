package com.vibetemp.ketchup.ui.chat

import com.vibetemp.ketchup.data.ApiException
import com.vibetemp.ketchup.data.ChatSummary
import com.vibetemp.ketchup.data.KetchupApi
import com.vibetemp.ketchup.data.Member
import com.vibetemp.ketchup.data.Message
import com.vibetemp.ketchup.data.realtime.LiveMessages
import com.vibetemp.ketchup.data.realtime.NotLive
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.IOException
import java.time.Instant
import java.util.UUID
import kotlin.math.max
import kotlin.math.min

/** The server calls one open chat makes. [LiveChatBackend] is the real one; previews and tests use fixtures. */
interface ChatBackend {
    /** A page, oldest first: the newest [limit], or the [limit] before [before]. */
    suspend fun messages(chatId: String, before: Instant?, limit: Int): List<Message>
    suspend fun messagesAfter(chatId: String, after: Instant): List<Message>
    suspend fun members(chatId: String): List<Member>
    suspend fun send(chatId: String, body: String, id: String): Message
    suspend fun markRead(chatId: String, at: Instant?)

    /**
     * Offline previews hold a slice of a longer chat (44 of Breck's 302
     * messages): the unread count stays the inbox row's instead of being
     * recounted from your member row, as iOS's previews do.
     */
    val partial: Boolean get() = false
}

class LiveChatBackend(private val api: KetchupApi) : ChatBackend {
    override suspend fun messages(chatId: String, before: Instant?, limit: Int) = api.messages(chatId, before, limit)
    override suspend fun messagesAfter(chatId: String, after: Instant) = api.messagesAfter(chatId, after)
    override suspend fun members(chatId: String) = api.members(chatId)
    override suspend fun send(chatId: String, body: String, id: String) = api.send(chatId, body, id)
    override suspend fun markRead(chatId: String, at: Instant?) = api.markRead(chatId, at)
}

/** Everything a chat screen draws, as one value. */
data class ChatState(
    /** Oldest first: confirmed messages by server time, then bubbles still in flight in send order. */
    val messages: List<Message> = emptyList(),
    val members: List<Member> = emptyList(),
    /** Member id to display name. */
    val names: Map<String, String> = emptyMap(),
    /** A first page is in (the skeleton goes). */
    val loaded: Boolean = false,
    val loadError: String? = null,
    val hasOlder: Boolean = false,
    val loadingOlder: Boolean = false,
    /** Unread when the chat opened; drives the Catch me up button until the cursor moves. */
    val unreadCount: Int = 0,
    /** The same number frozen at open, for the "N new" divider. */
    val unreadAtOpen: Int = 0,
    /** Where the "N new" divider goes. */
    val firstUnreadId: String? = null,
    /** The server's first page is in, with the unread count from your member row. */
    val synced: Boolean = false,
)

/**
 * One open chat: its messages, members, live updates, sending, and the
 * read cursor (iOS `Chat/ChatModel.swift`).
 *
 * Sending is optimistic. The bubble appears at once under an id the app
 * picks, and the insert uses that same id as the row's id, so the insert's
 * reply, the Realtime echo and the polling fallback all merge by id:
 * whichever lands first confirms the bubble and the rest are no-ops. Pages
 * merge the same way, so a Realtime row that a page also returns is never
 * shown twice.
 *
 * Read cursor (mark_read): opening a chat does NOT mark it read. The point
 * of the app is "Catch me up · 302 new", and catch-up reads everything
 * after the server's cursor. The cursor moves only when a catch-up is
 * opened (the brief does that), when the user scrolls down to the bottom
 * themselves, when they send (the server's trigger moves the sender's
 * cursor), or when they leave having seen the bottom.
 *
 * Every mutation runs on [scope]'s dispatcher (the main thread in the app).
 */
class ChatModel(
    val chat: ChatSummary,
    val myId: String,
    private val backend: ChatBackend,
    /** Outlives the screen: a send or a mark-read finishes after you leave. */
    private val scope: CoroutineScope,
    live: (onInsert: (Message) -> Unit) -> LiveMessages = { NotLive },
    private val now: () -> Instant = Instant::now,
) {
    private val _state = MutableStateFlow(ChatState(unreadCount = chat.unreadCount))
    val state: StateFlow<ChatState> = _state.asStateFlow()

    /** New messages as they're sent; polling covers for it while it isn't live. */
    val realtime: LiveMessages = live { merge(listOf(it)) }

    /** Your read cursor when the chat opened: the inbox row's, then your member row's. */
    private var cursorAtOpen: Instant = chat.lastReadAt

    /** What you've read through on this phone since (a send, scrolling to the bottom), ahead of the server. */
    private var readThrough: Instant? = null

    /** The bottom of the thread has been on screen since it was placed. */
    var sawBottom = false
    private var opening = false

    // MARK: Loading

    /**
     * Starts Realtime and loads the first page: back past the first unread
     * message (plus a little context), so the "N new" divider lands where
     * the unread part starts. Then the members, your cursor from your member
     * row, and pages back to it. Safe to call again (poll does until the
     * first page is in).
     */
    suspend fun open() {
        realtime.start()
        val now = _state.value
        if (now.synced || opening) return
        opening = true
        try {
            var paged = false
            try {
                val limit = min(max(PAGE_SIZE, now.unreadCount + 25), MAX_FIRST_LOAD)
                val page = backend.messages(chat.id, null, limit)
                _state.update { it.copy(hasOlder = page.size >= limit) }
                merge(page)
                _state.update { it.copy(loaded = true, loadError = null) }
                paged = true
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(loadError = readable(e)) }
            }
            var exact = false
            if (loadMembers() && paged && !backend.partial) exact = readFromServerCursor()
            computeUnread(exact)
            if (paged) _state.update { it.copy(synced = true) }
        } finally {
            opening = false
        }
    }

    /** Stops Realtime, and marks read if the bottom was seen. */
    fun close() {
        realtime.stop()
        if (sawBottom) markRead()
    }

    /** Loads the members (names and your cursor). False when it couldn't. */
    suspend fun loadMembers(): Boolean {
        val list = try {
            backend.members(chat.id)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return false
        }
        _state.update { it.copy(members = list, names = list.associate { m -> m.userId to m.name }) }
        return true
    }

    /**
     * Takes your cursor from your member row (the server's word; the inbox
     * row can be old) and pages back until the unread part is all here.
     * True when it is, so the unread count can be exact.
     */
    private suspend fun readFromServerCursor(): Boolean {
        val mine = _state.value.members.firstOrNull { it.userId == myId } ?: return false
        cursorAtOpen = mine.lastReadAt
        while (true) {
            val s = _state.value
            val oldest = s.messages.firstOrNull { !it.pending && !it.failed } ?: break
            if (!s.hasOlder || s.messages.size >= MAX_FIRST_LOAD || oldest.createdAt <= cursorAtOpen) break
            val before = s.messages.size
            loadOlder()
            if (_state.value.messages.size == before) break
        }
        val s = _state.value
        return !s.hasOlder || (s.messages.firstOrNull()?.let { it.createdAt <= cursorAtOpen } ?: true)
    }

    /** The page before the oldest message here. */
    suspend fun loadOlder() {
        val s = _state.value
        if (!s.hasOlder || s.loadingOlder) return
        val oldest = s.messages.firstOrNull { !it.pending && !it.failed } ?: return
        _state.update { it.copy(loadingOlder = true) }
        try {
            val page = backend.messages(chat.id, oldest.createdAt, PAGE_SIZE)
            _state.update { it.copy(hasOlder = page.size >= PAGE_SIZE) }
            merge(page)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Scrolling up again tries again.
        } finally {
            _state.update { it.copy(loadingOlder = false) }
        }
    }

    /** Pages back until [id] is here (a brief can cite an old message). False if it still isn't. */
    suspend fun ensureLoaded(id: String): Boolean {
        var pages = 0
        while (_state.value.messages.none { it.id == id } && _state.value.hasOlder && pages < MAX_JUMP_PAGES) {
            val before = _state.value.messages.size
            loadOlder()
            pages += 1
            if (_state.value.messages.size == before) break
        }
        return _state.value.messages.any { it.id == id }
    }

    /**
     * The fallback while Realtime is down: everything newer than what's
     * here. Until the first page is in (opened offline), tries that instead.
     */
    suspend fun poll() {
        if (!_state.value.synced) return open()
        val newest = _state.value.messages.lastOrNull { !it.pending && !it.failed }?.createdAt ?: chat.createdAt
        val fresh = try {
            backend.messagesAfter(chat.id, newest)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return
        }
        merge(fresh)
    }

    /**
     * After a brief: the catch-up moves your cursor on the server, so take
     * it from your member row again. The divider stays where it was.
     */
    suspend fun refreshCursor() {
        if (!loadMembers()) return
        val server = _state.value.members.firstOrNull { it.userId == myId }?.lastReadAt ?: return
        if (server <= latest(cursorAtOpen, readThrough)) return
        readThrough = server
        val cursor = latest(cursorAtOpen, readThrough)
        val unread = _state.value.messages.count { it.createdAt > cursor && it.sender != myId && !it.pending }
        _state.update { it.copy(unreadCount = min(it.unreadCount, unread)) }
    }

    /**
     * Where unread starts. [exact]: everything after the cursor is here, so
     * the count is what's here, not at least the inbox row's.
     */
    private fun computeUnread(exact: Boolean = false) {
        val cursor = latest(cursorAtOpen, readThrough)
        _state.update { s ->
            val unread = s.messages.filter { it.createdAt > cursor && it.sender != myId && !it.pending }
            val count = if (exact) unread.size else max(s.unreadCount, unread.size)
            s.copy(
                unreadCount = count,
                unreadAtOpen = count,
                firstUnreadId = if (count == 0) null else unread.firstOrNull()?.id,
            )
        }
    }

    // MARK: Merging

    /** Adds or confirms messages by id (see [ThreadMerge.merge]); a new sender's name gets loaded. */
    fun merge(incoming: List<Message>) {
        if (incoming.isEmpty()) return
        var unknownSender = false
        _state.update { s ->
            val merged = ThreadMerge.merge(s.messages, incoming, chat.id)
            unknownSender = incoming.any { it.chatId == chat.id && it.sender !in s.names }
            s.copy(messages = merged)
        }
        // Someone new joined since the members loaded.
        if (unknownSender && _state.value.members.isNotEmpty()) scope.launch { loadMembers() }
    }

    // MARK: Sending

    /** Sends [text] (already trimmed and under the cap). The bubble shows at once. */
    fun send(text: String): Job {
        val id = UUID.randomUUID().toString()
        val at = now()
        _state.update {
            it.copy(messages = it.messages + Message(id = id, chatId = chat.id, sender = myId, body = text, createdAt = at, pending = true))
        }
        // The server moves the sender's own cursor on insert (apply_message).
        caughtUp(at)
        return scope.launch { deliver(id) }
    }

    /** Tries a bubble that didn't send again, under the same id. */
    fun retry(id: String): Job? {
        val m = _state.value.messages.firstOrNull { it.id == id } ?: return null
        if (!m.failed) return null
        updateMessage(id) { it.copy(failed = false, pending = true) }
        return scope.launch { deliver(id) }
    }

    private suspend fun deliver(id: String) {
        val local = _state.value.messages.firstOrNull { it.id == id } ?: return
        if (!local.pending) return
        try {
            merge(listOf(backend.send(chat.id, local.body, id)))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            val still = _state.value.messages.firstOrNull { it.id == id }
            if (still == null || !still.pending) return
            val landed = e is ApiException && (e.code == "23505" || e.message.orEmpty().lowercase().contains("duplicate key"))
            // A duplicate key means an earlier try did land and only its reply was lost: it's sent.
            updateMessage(id) { it.copy(pending = false, failed = !landed) }
        }
    }

    private fun updateMessage(id: String, change: (Message) -> Message) {
        _state.update { s -> s.copy(messages = s.messages.map { if (it.id == id) change(it) else it }) }
    }

    // MARK: Read cursor

    /** The user scrolled down to the bottom themselves. */
    fun reachedBottomByScrolling() {
        sawBottom = true
        if (_state.value.unreadCount > 0) markRead()
    }

    /** Moves the cursor to [at] (or now) here at once, and on the server. */
    fun markRead(at: Instant? = null) {
        caughtUp(at ?: now())
        scope.launch {
            try {
                backend.markRead(chat.id, at)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // The next visit tries again; the count here is already right.
            }
        }
    }

    private fun caughtUp(through: Instant) {
        readThrough = latest(readThrough, through)
        _state.update { it.copy(unreadCount = 0) }
    }

    // MARK: Lookups

    /** "You", a member's name, or "Someone" for a sender who has left. */
    fun name(of: String): String = if (of == myId) "You" else _state.value.names[of] ?: "Someone"

    companion object {
        const val PAGE_SIZE = 200

        /** The edge function reads at most 600 unread; PostgREST serves up to 1000 rows. */
        const val MAX_FIRST_LOAD = 700

        /** How far back a jump to a cited message pages before giving up. */
        const val MAX_JUMP_PAGES = 6

        private fun latest(a: Instant?, b: Instant?): Instant = when {
            a == null -> b ?: Instant.MIN
            b == null -> a
            else -> maxOf(a, b)
        }

        /** A sentence a person can read, for any failure. */
        fun readable(e: Throwable): String = when (e) {
            is ApiException -> e.message ?: "Something went wrong. Try again."
            is IOException -> "Couldn't reach Ketchup. Check your connection and try again."
            else -> "Something went wrong. Try again."
        }
    }
}

/** The thread's merge rule as a plain function, so the tests can check it. */
object ThreadMerge {
    /**
     * Adds or confirms [incoming] by id. A row the server has is confirmed
     * (not pending, not failed) and replaces any copy here; rows for other
     * chats are ignored. Confirmed messages sort by server time (then id);
     * bubbles still in flight stay at the bottom in send order.
     */
    fun merge(current: List<Message>, incoming: List<Message>, chatId: String): List<Message> {
        if (incoming.isEmpty()) return current
        val byId = LinkedHashMap<String, Message>(current.size + incoming.size)
        for (m in current) byId[m.id] = m
        for (m in incoming) {
            if (m.chatId != chatId) continue
            byId[m.id] = m.copy(pending = false, failed = false)
        }
        val all = byId.values
        val confirmed = all.filter { !it.pending && !it.failed }.sortedWith(compareBy<Message>({ it.createdAt }, { it.id }))
        val inFlight = all.filter { it.pending || it.failed }
        return confirmed + inFlight
    }
}
