package com.vibetemp.ketchup.ui.chats

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.ApiException
import com.vibetemp.ketchup.data.ChatSummary
import com.vibetemp.ketchup.data.KetchupApi
import com.vibetemp.ketchup.data.Member
import com.vibetemp.ketchup.data.Message
import com.vibetemp.ketchup.data.Profile
import com.vibetemp.ketchup.data.realtime.ChatRealtime
import com.vibetemp.ketchup.data.realtime.LiveMessages
import com.vibetemp.ketchup.data.realtime.NotLive
import com.vibetemp.ketchup.reader.ReaderMemory
import com.vibetemp.ketchup.ui.chat.ChatBackend
import com.vibetemp.ketchup.ui.chat.ChatModel
import com.vibetemp.ketchup.ui.chat.LiveChatBackend
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * App-wide state (iOS `AppModel`): who is signed in, their name, and the
 * inbox. One per process ([get]); offline previews make their own with
 * [offline], which never touches the network.
 */
@Stable
class AppModel private constructor(
    context: Context,
    /** The client, or null in an offline preview. */
    val api: KetchupApi?,
    /** Offline preview: stands in for a session, and every server call is a no-op. */
    private val previewUser: String?,
) {
    private val resources = context.applicationContext.resources
    private val appContext = context.applicationContext
    private val prefs: SharedPreferences? =
        if (api == null) null else context.applicationContext.getSharedPreferences("ketchup.app", Context.MODE_PRIVATE)

    /** The app's own work that outlives a screen: sends, mark-read, leaving. */
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    var session by mutableStateOf(api?.session?.value)
        private set
    var me by mutableStateOf<Profile?>(null)
        private set
    var chats by mutableStateOf<List<ChatSummary>>(emptyList())
        private set
    var chatsLoaded by mutableStateOf(false)
        private set

    /** Why the inbox couldn't load the first time. */
    var notice by mutableStateOf<String?>(null)

    /** Something that changed at once and then didn't go through (leaving, a new name). */
    var problem by mutableStateOf<String?>(null)

    /** Sign-up names everyone after their email; until they confirm or change it once, the app asks. */
    var nameConfirmed by mutableStateOf(true)
        private set

    /** Previews: the inbox never finishes loading (`inbox-loading`). */
    var holdsLoading = false

    /** Where open chats load from: the server, or a preview's fixtures. */
    var chatBackend: ChatBackend = if (api != null) LiveChatBackend(api) else EmptyChatBackend

    /** Live inserts for a chat: Realtime when signed in, nothing in previews. */
    var liveMessages: (chatId: String, onInsert: (Message) -> Unit) -> LiveMessages = { chatId, onInsert ->
        if (api == null) {
            NotLive
        } else {
            ChatRealtime(chatId, scope, accessToken = { api.client.freshAccessToken() }, onInsert = onInsert)
        }
    }

    /** Chats you've just left, until the server has it. */
    private val leaving = mutableSetOf<String>()

    /** Open chats, so a rotation keeps the same one. */
    private val openChats = mutableMapOf<String, ChatModel>()

    val isPreview: Boolean get() = previewUser != null
    val isSignedIn: Boolean get() = session != null || previewUser != null
    val myId: String? get() = previewUser ?: session?.userId
    val email: String? get() = if (previewUser != null) PREVIEW_EMAIL else session?.email

    init {
        api?.let { live ->
            scope.launch {
                live.session.collect { next ->
                    val before = session?.userId
                    session = next
                    if (next == null) {
                        me = null
                        chats = emptyList()
                        chatsLoaded = false
                        notice = null
                        openChats.values.forEach { it.realtime.stop() }
                        openChats.clear()
                    } else if (next.userId != before) {
                        chatsLoaded = false
                    }
                }
            }
        }
    }

    // MARK: You

    private val nameKey: String get() = "nameConfirmed-${myId.orEmpty()}"

    /** Your profile and whether you've confirmed your name. Offline, the name already here stays. */
    suspend fun loadMe() {
        val live = api ?: return
        if (!isSignedIn) return
        nameConfirmed = prefs?.getBoolean(nameKey, false) ?: true
        try {
            live.myProfile()?.let { me = it }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Keep what's here.
        }
    }

    /** The name sign-up picked: your email's first part. */
    val defaultName: String
        get() {
            if (previewUser != null) return me?.displayName.orEmpty()
            return session?.email?.substringBefore('@')?.trim()?.take(30).orEmpty()
        }

    val needsName: Boolean
        get() {
            val profile = me ?: return false
            return !nameConfirmed && profile.displayName == defaultName
        }

    fun confirmName() {
        prefs?.edit()?.putBoolean(nameKey, true)?.apply()
        nameConfirmed = true
    }

    /** The first-run name step: waits for the server. */
    suspend fun rename(name: String) {
        val trimmed = name.trim()
        if (trimmed.length !in 1..30) throw ApiException(resources.getString(R.string.name_length_error))
        api?.setDisplayName(trimmed)
        me = me?.copy(displayName = trimmed) ?: Profile(myId.orEmpty(), trimmed)
        confirmName()
    }

    /**
     * Settings: the new name shows at once and the server follows. If it
     * says no, the old name comes back (unless it changed again since) and
     * [problem] says so.
     */
    fun renameNow(name: String) {
        val trimmed = name.trim()
        val before = me?.displayName ?: return
        if (trimmed.length !in 1..30 || trimmed == before) return
        me = me?.copy(displayName = trimmed)
        scope.launch {
            try {
                serverCall { it.setDisplayName(trimmed) }
                confirmName()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (me?.displayName == trimmed) me = me?.copy(displayName = before)
                problem = resources.getString(R.string.settings_couldnt_rename, trimmed, before, ChatModel.readable(e))
            }
        }
    }

    suspend fun signOut() {
        if (previewUser != null) return
        openChats.values.forEach { it.realtime.stop() }
        openChats.clear()
        api?.signOut()
        // The reader's one memory: the Snapchat name it learned is this account's.
        ReaderMemory.forget(appContext)
    }

    // MARK: The inbox

    suspend fun refreshChats() {
        if (!isSignedIn) return
        val live = api
        if (live == null) {
            if (!holdsLoading) chatsLoaded = true
            return
        }
        val user = myId
        try {
            // A chat you're leaving stays gone while the server catches up.
            val fresh = live.myChats().filter { it.id !in leaving }
            if (myId != user) return // signed out meanwhile
            chats = fresh
            chatsLoaded = true
            notice = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!chatsLoaded) notice = ChatModel.readable(e)
        }
    }

    fun chat(id: String): ChatSummary? = chats.firstOrNull { it.id == id }

    /** Previews: the inbox to show. */
    fun showChats(list: List<ChatSummary>) {
        chats = list
    }

    /** Clears a chat's badge here at once (the server follows). */
    fun markReadLocally(id: String) {
        chats = chats.map { if (it.id == id && it.unreadCount > 0) it.copy(unreadCount = 0, lastReadAt = Instant.now()) else it }
    }

    suspend fun createChat(name: String): String {
        val live = api ?: return PREVIEW_NEW_CHAT
        return live.createChat(name)
    }

    suspend fun joinChat(code: String): String? {
        val live = api ?: return null
        return live.joinChat(code)
    }

    /**
     * Leaves at once: the chat is out of the inbox now and the server
     * follows. If it says no, the chat comes back and [problem] says so.
     */
    fun leave(chat: ChatSummary) {
        leaving += chat.id
        chats = chats.filter { it.id != chat.id }
        forgetChat(chat.id)
        scope.launch {
            try {
                serverCall { it.leaveChat(chat.id) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                problem = resources.getString(R.string.info_couldnt_leave, chat.name, ChatModel.readable(e))
                leaving -= chat.id
                if (api != null) refreshChats() else chats = listOf(chat) + chats
                return@launch
            }
            leaving -= chat.id
        }
    }

    // MARK: Open chats

    /** The model for [chat], kept while it's open so a rotation doesn't reload it. */
    fun chatModel(chat: ChatSummary): ChatModel = openChats.getOrPut(chat.id) {
        ChatModel(chat, myId.orEmpty(), chatBackend, scope, live = { onInsert -> liveMessages(chat.id, onInsert) })
    }

    /** The chat was closed for good (not a rotation). */
    fun forgetChat(id: String) {
        openChats.remove(id)?.realtime?.stop()
    }

    // MARK: Remembered on this phone

    /** The home page you were on last ("chats", "instagram", "snapchat"). */
    var homePage: String?
        get() = prefs?.getString("home.page", null)
        set(value) {
            prefs?.edit()?.putString("home.page", value)?.apply()
        }

    /** A server call, or in a preview a pretend one that can be told to say no. */
    private suspend fun serverCall(call: suspend (KetchupApi) -> Unit) {
        val live = api
        if (live != null) return call(live)
        if (previewRefuses) {
            delay(1_200)
            throw ApiException("The server said no (a preview).")
        }
    }

    /** Previews: pretend server calls fail (`-serverRefuses`). */
    var previewRefuses = false

    companion object {
        const val PREVIEW_EMAIL = "david@example.com"
        const val PREVIEW_NEW_CHAT = "c0000000-0000-4000-8000-0000000000ff"

        @Volatile
        private var instance: AppModel? = null

        /** The signed-in app, on the session kept in private storage. */
        fun get(context: Context): AppModel = instance ?: synchronized(this) {
            instance ?: AppModel(context, KetchupApi.get(context), null).also { instance = it }
        }

        /** An offline app for previews: signed in as [me] with no session, nothing goes to the server. */
        fun offline(context: Context, me: Profile, chats: List<ChatSummary>, loading: Boolean = false): AppModel =
            AppModel(context, null, me.id).apply {
                this.me = me
                this.chats = if (loading) emptyList() else chats
                this.chatsLoaded = !loading
                this.holdsLoading = loading
            }
    }
}

/** A chat backend with nothing in it (an offline app before a preview gives it fixtures). */
private object EmptyChatBackend : ChatBackend {
    override suspend fun messages(chatId: String, before: Instant?, limit: Int): List<Message> = emptyList()
    override suspend fun messagesAfter(chatId: String, after: Instant): List<Message> = emptyList()
    override suspend fun members(chatId: String): List<Member> = emptyList()
    override suspend fun send(chatId: String, body: String, id: String): Message =
        throw ApiException("Offline preview: nothing goes to the server.")
    override suspend fun markRead(chatId: String, at: Instant?) = Unit
}
