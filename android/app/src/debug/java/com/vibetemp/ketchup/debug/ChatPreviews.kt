package com.vibetemp.ketchup.debug

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.vibetemp.ketchup.data.ApiException
import com.vibetemp.ketchup.data.ChatSummary
import com.vibetemp.ketchup.data.Member
import com.vibetemp.ketchup.data.Message
import com.vibetemp.ketchup.data.Profile
import com.vibetemp.ketchup.ui.auth.NameScreen
import com.vibetemp.ketchup.ui.auth.SignInScreen
import com.vibetemp.ketchup.ui.auth.SignInStart
import com.vibetemp.ketchup.ui.auth.TermsScreen
import com.vibetemp.ketchup.ui.chat.ChatBackend
import com.vibetemp.ketchup.ui.chat.ChatStart
import com.vibetemp.ketchup.ui.chats.AppModel
import com.vibetemp.ketchup.ui.chats.Home
import com.vibetemp.ketchup.ui.chats.HomePage
import com.vibetemp.ketchup.ui.chats.HomeStart
import com.vibetemp.ketchup.ui.chats.InboxSheet
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import java.time.Instant

// The chat slice's preview screens, on fixtures with no sign-in and no
// network (iOS Debug/CorePreviewScreen.swift, same names):
//
//     adb shell am start -n com.vibetemp.ketchup/.MainActivity --es screen chat
//
// signin, signin-code, signin-password (the password path, empty) and
// signin-password-error (a wrong password), terms (the terms screen before
// the app) and terms-offline (Agree couldn't save), name, home
// (the pager on Chats), home-instagram, home-snapchat, inbox-loading,
// inbox-empty, new-chat, join, chat (Breck, 302 new), chat-loading,
// chat-jump (a brief's jump to Maya's "$540 total"), chat-joined (Rowan
// joins Breck and says hi: "Rowan joined" under "1 new"), info (Members and
// invite), settings, and chat-not-sent (a send that fails and offers a
// retry). chat-breck is the old name for chat.

val ChatPreviews: Map<String, @Composable () -> Unit> = mapOf(
    "signin" to { SignInScreen(api = null) },
    "signin-code" to {
        SignInScreen(api = null, start = SignInStart(email = AppModel.PREVIEW_EMAIL, code = "4821", atCode = true, cooldown = 42))
    },
    "signin-password" to { SignInScreen(api = null, start = SignInStart(email = AppModel.PREVIEW_EMAIL, usePassword = true)) },
    "signin-password-error" to {
        SignInScreen(api = null, start = SignInStart(email = AppModel.PREVIEW_EMAIL, usePassword = true, error = wrongPassword()))
    },
    "terms" to { TermsScreen(rememberPreviewApp()) },
    "terms-offline" to { TermsScreen(rememberPreviewApp(refuses = true), failedAtStart = true) },
    "name" to { NameScreen(rememberPreviewApp(name = "david")) },
    "home" to { Home(rememberPreviewApp(), HomeStart(page = HomePage.CHATS, remembers = false)) },
    "home-instagram" to { Home(rememberPreviewApp(), HomeStart(page = HomePage.INSTAGRAM, remembers = false)) },
    "home-snapchat" to { Home(rememberPreviewApp(), HomeStart(page = HomePage.SNAPCHAT, remembers = false)) },
    "inbox-loading" to { Home(rememberPreviewApp(loading = true), HomeStart(page = HomePage.CHATS, remembers = false)) },
    "inbox-empty" to { Home(rememberPreviewApp(chats = emptyList()), HomeStart(page = HomePage.CHATS, remembers = false)) },
    "new-chat" to { Home(rememberPreviewApp(), HomeStart(page = HomePage.CHATS, remembers = false, sheet = InboxSheet.NewChat)) },
    "join" to { Home(rememberPreviewApp(), HomeStart(page = HomePage.CHATS, remembers = false, sheet = InboxSheet.Join)) },
    "chat" to { BreckChat() },
    "chat-breck" to { BreckChat() },
    "chat-loading" to { BreckChat(holdsLoading = true) },
    "chat-jump" to { BreckChat(ChatStart(jumpTo = JUMP_TARGET)) },
    "chat-joined" to { BreckChat(joined = true) },
    "info" to { BreckChat(ChatStart(info = true)) },
    "chat-not-sent" to { BreckChat(ChatStart(send = "on my way"), sendsFail = true) },
    "settings" to { Home(rememberPreviewApp(), HomeStart(page = HomePage.CHATS, remembers = false, stack = listOf("settings"))) },
)

/** Maya's "so the Airbnb is now $540 total = $90 each", a message the catch-up cites, a good way up the thread. */
private const val JUMP_TARGET = "6fe6a3cc-7a99-5aa3-a3dd-be8a6a18adb5"

/** What the live project answers a wrong email or password with, read the app's own way. */
private fun wrongPassword(): String? =
    ApiException.from(400, """{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}""").message

/** The pager with Breck open over it, so Back goes to the inbox. [joined]: Rowan joins at the end ([JoinedBreck]). */
@Composable
private fun BreckChat(start: ChatStart = ChatStart(), holdsLoading: Boolean = false, sendsFail: Boolean = false, joined: Boolean = false) {
    val app = rememberPreviewApp(holdsLoading = holdsLoading, sendsFail = sendsFail, joined = joined)
    Home(app, HomeStart(page = HomePage.CHATS, remembers = false, stack = listOf("chat:${PreviewData.BRECK_ID}"), chat = start))
}

/**
 * An offline app signed in as David with Breck on top of three quieter
 * chats (iOS `PreviewData.inbox`). [loading]: the inbox never answers.
 * [holdsLoading]: an opened chat never gets its first page. [refuses]: the
 * pretend server says no (the terms screen's Agree, as if offline).
 */
@Composable
private fun rememberPreviewApp(
    name: String = PreviewData.MY_NAME,
    chats: List<ChatSummary>? = null,
    loading: Boolean = false,
    holdsLoading: Boolean = false,
    sendsFail: Boolean = false,
    joined: Boolean = false,
    refuses: Boolean = false,
): AppModel {
    val context = LocalContext.current
    val data = previewData()
    return remember(name, chats, loading, holdsLoading, sendsFail, joined, refuses) {
        val inbox = PreviewInbox(data, joined)
        AppModel.offline(context, Profile(PreviewData.ME, name), chats ?: inbox.chats, loading).apply {
            chatBackend = FixtureChatBackend(inbox.messages, inbox.members, holdsLoading, sendsFail)
            previewRefuses = refuses
        }
    }
}

/** The inbox's chats and what's in them: Breck from the fixtures, three made up (iOS `PreviewData.others`). */
private class PreviewInbox(data: PreviewData, joined: Boolean = false) {
    val chats: List<ChatSummary>
    val messages = mutableMapOf<String, List<Message>>()
    val members = mutableMapOf<String, List<Member>>()

    init {
        val breck = if (joined) JoinedBreck.chat(data) else data.breck
        messages[PreviewData.BRECK_ID] = if (joined) JoinedBreck.messages(data) else data.messages
        members[PreviewData.BRECK_ID] = if (joined) JoinedBreck.members(data) else data.members
        // Times hang off Breck's last message, so the order never changes.
        val anchor = data.messages.last().createdAt
        val others = listOf(
            other(
                "Roommates", "RM8T2Q", 1, listOf("Nina", "Marcus"), anchor,
                listOf(
                    Triple("Marcus", "plumber is coming Thursday between 8 and noon", 190.0),
                    Triple(PreviewData.MY_NAME, "I'm home Thursday morning, I'll let him in", 182.0),
                    Triple("Nina", "hero 🙏", 75.0),
                    Triple("Marcus", "also rent is due Friday", 62.0),
                    Triple("Nina", "who keeps buying oat milk and not drinking it", 50.0),
                ),
                readThrough = 1,
            ),
            other(
                "Capstone team", "CAP5T9", 2, listOf("Owen", "Lena", "Raj"), anchor,
                listOf(
                    Triple("Lena", "draft of the methods section is in the doc", 1_700.0),
                    Triple("Raj", "I'll do the lit review table tonight", 1_640.0),
                    Triple("Owen", "pushed the slides, someone check slide 9 please", 1_560.0),
                ),
                readThrough = null, unread = 41,
            ),
            other(
                "Family", "FAM1LY", 3, listOf("Aunt Rosa", "Grandma June"), anchor,
                listOf(
                    Triple("Grandma June", "Who is bringing rolls on Thanksgiving?", 4_400.0),
                    Triple(PreviewData.MY_NAME, "I've got rolls", 4_350.0),
                    Triple("Aunt Rosa", "sending the casserole recipe now", 4_320.0),
                ),
                readThrough = 2,
            ),
        )
        chats = listOf(breck) + others
    }

    /** One made-up chat. Lines are (who, what, minutes before the anchor); you've read through line [readThrough]. */
    private fun other(
        name: String,
        code: String,
        suffix: Int,
        people: List<String>,
        anchor: Instant,
        lines: List<Triple<String, String, Double>>,
        readThrough: Int?,
        unread: Int? = null,
    ): ChatSummary {
        val chatId = "c0000000-0000-4000-8000-%012d".format(suffix)
        val created = anchor.minusSeconds(60L * 60 * 24 * 30)
        val cast = listOf(PreviewData.ME to PreviewData.MY_NAME) +
            people.mapIndexed { i, person -> "d0000000-0000-4000-8000-0000000%02d%03d".format(suffix, i) to person }
        val list = lines.mapIndexed { i, (who, what, minutes) ->
            Message(
                id = "e0000000-0000-4000-8000-0000000%02d%03d".format(suffix, i),
                chatId = chatId,
                sender = cast.firstOrNull { it.second == who }?.first ?: PreviewData.ME,
                body = what,
                createdAt = anchor.minusSeconds((minutes * 60).toLong()),
            )
        }
        messages[chatId] = list
        members[chatId] = cast.map { (id, person) -> Member(id, created, created, Profile(id, person)) }
        val readAt = readThrough?.let { list[it].createdAt } ?: created
        val last = list.last()
        return ChatSummary(
            id = chatId, name = name, inviteCode = code, memberCount = cast.size, createdAt = created,
            lastMessageAt = last.createdAt, lastMessagePreview = last.body,
            lastMessageSenderName = cast.firstOrNull { it.first == last.sender }?.second,
            lastReadAt = readAt,
            unreadCount = unread ?: list.count { it.createdAt > readAt && it.sender != PreviewData.ME },
        )
    }
}

/**
 * `chat-joined` (iOS `-screen chat-joined`): Breck read through Maya's
 * "goodnight losers 💙", then Rowan (made up, a friend of Maya's) joins with
 * the invite code and says hi. "Rowan joined" sits under the "1 new" line: a
 * join line starts the new part but isn't counted.
 */
private object JoinedBreck {
    private const val ROWAN = "d0000000-0000-4000-8000-000000000007"

    private fun readTo(data: PreviewData): Instant = data.messages.last().createdAt

    fun messages(data: PreviewData): List<Message> = data.messages + listOf(
        Message(
            id = "f0000000-0000-4000-8000-000000000001", chatId = PreviewData.BRECK_ID, sender = ROWAN,
            body = "joined", createdAt = readTo(data).plusSeconds(30L * 60), kind = Message.JOINED,
        ),
        Message(
            id = "f0000000-0000-4000-8000-000000000002", chatId = PreviewData.BRECK_ID, sender = ROWAN,
            body = "hey! Maya sent me the code. what did I miss? 👀", createdAt = readTo(data).plusSeconds(31L * 60),
        ),
    )

    fun members(data: PreviewData): List<Member> =
        data.members + Member(ROWAN, readTo(data).plusSeconds(30L * 60), PreviewData.BRECK_CREATED, Profile(ROWAN, "Rowan"))

    fun chat(data: PreviewData): ChatSummary {
        val last = messages(data).last()
        return data.breck.copy(
            memberCount = data.members.size + 1, lastMessageAt = last.createdAt, lastMessagePreview = last.body,
            lastMessageSenderName = "Rowan", lastReadAt = readTo(data), unreadCount = 1,
        )
    }
}

/**
 * The chats' fixtures as a server: pages like PostgREST, members, and a
 * send that confirms after a moment. Nothing leaves the phone.
 */
private class FixtureChatBackend(
    private val messages: Map<String, List<Message>>,
    private val members: Map<String, List<Member>>,
    private val holdsLoading: Boolean,
    /** Every send fails, as if offline (`chat-not-sent`). */
    private val sendsFail: Boolean = false,
) : ChatBackend {
    private val sent = mutableMapOf<String, MutableList<Message>>()

    override val partial: Boolean get() = true

    private fun all(chatId: String) = messages[chatId].orEmpty() + sent[chatId].orEmpty()

    override suspend fun messages(chatId: String, before: Instant?, limit: Int): List<Message> {
        if (holdsLoading) awaitCancellation()
        delay(250)
        val older = if (before == null) all(chatId) else all(chatId).filter { it.createdAt < before }
        return older.takeLast(limit)
    }

    override suspend fun messagesAfter(chatId: String, after: Instant): List<Message> = all(chatId).filter { it.createdAt > after }

    override suspend fun members(chatId: String): List<Member> = members[chatId].orEmpty()

    override suspend fun send(chatId: String, body: String, id: String): Message {
        delay(400)
        if (sendsFail) throw java.io.IOException("Offline preview: this send fails on purpose.")
        val row = Message(id = id, chatId = chatId, sender = PreviewData.ME, body = body, createdAt = Instant.now())
        sent.getOrPut(chatId) { mutableListOf() } += row
        return row
    }

    override suspend fun markRead(chatId: String, at: Instant?) = Unit
}
