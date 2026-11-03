package com.vibetemp.ketchup.data

import android.content.Intent
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID

// FROZEN CONTRACT (Android foundation, Nov 3, 2026). The chat, brief and
// reader slices all build on this file: the reader slice makes TextThreads,
// the chat slice makes Chats, the brief slice turns either into a brief.
// Don't change a name or a field's meaning; if something is truly missing,
// add an optional field with a default and say so in your report.

/** What a brief is for: a Ketchup chat, or a thread read off another app's screen. */
@Serializable
sealed interface BriefSource {
    /** What the brief's top bar calls it: the chat's name, or the thread's title. */
    val displayTitle: String

    /** A Ketchup chat. The `catch-up` edge function reads it from the database as the signed-in member. */
    @Serializable
    @SerialName("chat")
    data class Chat(val id: String, val name: String) : BriefSource {
        override val displayTitle: String get() = name
    }
}

/**
 * A thread the reader service read off the Instagram or Snapchat app's
 * screen, oldest message first. It goes to the `catch-up-text` edge
 * function, which stores nothing from it; the app keeps it in memory only,
 * for one catch-up (never on disk, never in a log).
 *
 * catch-up-text takes `{ source, thread_title, messages: [{ sender, text, at? }] }`
 * plus the request's own `mode`, `question`, `reader_name`, `time_zone` and
 * `reader` (counts only). [TextMessage.wireSender] and [TextMessage.wireText]
 * fold "mine" and the quoted reply into that shape, the way the iOS readers do.
 */
@Serializable
@SerialName("text")
data class TextThread(
    val source: TextSource,
    /** The thread's name as the app shows it (a person or a group); may be empty. */
    val title: String,
    val messages: List<TextMessage>,
    /** How the read went, in counts only (catch-up-text's `reader`, for its log). */
    val stats: ReaderStats? = null,
) : BriefSource {
    override val displayTitle: String get() = title.ifBlank { "${source.appName} chat" }

    /** The message a brief's ref cites: catch-up-text refs are indexes into [messages]. */
    fun message(ref: String): TextMessage? = ref.toIntOrNull()?.let(messages::getOrNull)
}

/** Where a [TextThread] came from. [id] is catch-up-text's `source`. */
@Serializable
enum class TextSource(val id: String, val appName: String, val packageName: String) {
    @SerialName("instagram")
    INSTAGRAM("instagram", "Instagram", "com.instagram.android"),

    @SerialName("snapchat")
    SNAPCHAT("snapchat", "Snapchat", "com.snapchat.android");

    companion object {
        fun forPackage(packageName: CharSequence?): TextSource? = entries.firstOrNull { it.packageName == packageName }
    }
}

/** One message as the reader saw it on screen. */
@Serializable
data class TextMessage(
    /** The name the app shows for whoever sent it. Ignored on the wire when [isMine]. */
    val sender: String,
    /** What it says. A photo, sticker or voice note is a placeholder like "[photo]". */
    val text: String,
    /** Sent by the person using Ketchup. */
    val isMine: Boolean = false,
    /** The message this one replies to, as the app quoted it, if it's a reply. */
    val quote: Quote? = null,
    /** ISO 8601, when the app printed a time near it (approximate). */
    val at: String? = null,
) {
    @Serializable
    data class Quote(
        /** Who wrote the quoted message, if the app says. */
        val sender: String? = null,
        /** The quoted words, if the app shows them. */
        val text: String? = null,
        /** The quoted message was the reader's own. */
        val isMine: Boolean = false,
    )

    /** Who sent it, as catch-up-text sees it: the reader's own go under their Ketchup name. */
    fun wireSender(readerName: String): String = if (isMine) readerName else sender

    /**
     * What it says, as catch-up-text sees it: a reply leads with its quote,
     * `(replying to Maya: "2 spots in the garage") perfect`, exactly like the
     * iOS Instagram and Snapchat readers, so Muse Spark reads both the same.
     */
    fun wireText(readerName: String): String {
        val q = quote ?: return text
        val to = (if (q.isMine) readerName else q.sender.orEmpty()).trim()
        val said = q.text.orEmpty().replace(Regex("\\s+"), " ").trim()
            .let { if (it.length > QUOTE_MAX) it.take(QUOTE_MAX - 1) + "…" else it }
        val lead = if (said.isNotEmpty()) {
            "(replying to ${if (to.isNotEmpty()) "$to: " else ""}\"$said\")"
        } else {
            "(replying to ${to.ifEmpty { "a message" }})"
        }
        return if (text.isEmpty()) lead else "$lead $text"
    }

    private companion object {
        /** Characters of a quote kept on the wire (iOS keeps 80 for Instagram, 200 for Snapchat). */
        const val QUOTE_MAX = 120
    }
}

/**
 * How a read went, in counts only: catch-up-text logs these keys and nothing
 * else (never text or names). It keeps `root` only when it's one of
 * "aria-label", "grid", "scroller", "main", and `stop` only when it's one of
 * "enough", "budget", "steps", "loads", "start", "no-scroller".
 */
@Serializable
data class ReaderStats(
    val found: Int? = null,
    val scrolls: Int? = null,
    val ms: Long? = null,
    val reachedStart: Boolean? = null,
    val stop: String? = null,
    val root: String? = null,
    val steps: Int? = null,
    val gaps: Int? = null,
    val placeholders: Int? = null,
    val rows: Int? = null,
    val units: Int? = null,
    val skipped: Int? = null,
    val empty: Int? = null,
    val dupes: Int? = null,
)

/**
 * Hands a [BriefSource] to BriefActivity through its Intent. A Chat rides
 * in the extras (small, survives the process). A TextThread stays in this
 * process's memory and only a key rides along: a long thread would pass
 * Binder's size limit, and a friend's messages shouldn't sit in the
 * system's copy of the Intent. If the process died in between, [from]
 * returns null and the brief asks the reader to tap Catch me up again.
 */
object BriefSourceIntent {
    private const val EXTRA_CHAT = "com.vibetemp.ketchup.extra.BRIEF_CHAT"
    private const val EXTRA_THREAD = "com.vibetemp.ketchup.extra.BRIEF_THREAD"

    fun put(intent: Intent, source: BriefSource): Intent = when (source) {
        is BriefSource.Chat -> intent.putExtra(EXTRA_CHAT, KetchupJson.encodeToString(BriefSource.Chat.serializer(), source))
        is TextThread -> intent.putExtra(EXTRA_THREAD, HeldThreads.hold(source))
    }

    fun from(intent: Intent?): BriefSource? {
        intent ?: return null
        intent.getStringExtra(EXTRA_CHAT)?.let { raw ->
            return runCatching { KetchupJson.decodeFromString(BriefSource.Chat.serializer(), raw) }.getOrNull()
        }
        return intent.getStringExtra(EXTRA_THREAD)?.let(HeldThreads::get)
    }
}

/** The last few threads handed to BriefActivity, in memory only (a rotation reads its own again). */
internal object HeldThreads {
    private const val KEEP = 4
    private val held = LinkedHashMap<String, TextThread>()

    @Synchronized
    fun hold(thread: TextThread): String {
        val key = UUID.randomUUID().toString()
        held[key] = thread
        while (held.size > KEEP) held.remove(held.keys.first())
        return key
    }

    @Synchronized
    fun get(key: String): TextThread? = held[key]
}
