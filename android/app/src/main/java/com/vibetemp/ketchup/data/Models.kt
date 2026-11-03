package com.vibetemp.ketchup.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient
import java.time.Instant

// Rows as PostgREST returns them, and Muse Spark's results as the edge
// functions return them (shape set by supabase/functions/_shared/brief.ts).
// Ids are the server's lowercase uuid strings. Ports of iOS Models.swift.

/** A `profiles` row. */
@Serializable
data class Profile(
    val id: String,
    @SerialName("display_name") val displayName: String,
    /** Their photo in the avatars bucket, if they set one. */
    @SerialName("avatar_path") val avatarPath: String? = null,
)

/** A row of the inbox: what `my_chats()` returns. */
@Serializable
data class ChatSummary(
    val id: String,
    val name: String,
    @SerialName("invite_code") val inviteCode: String,
    @SerialName("member_count") val memberCount: Int,
    @SerialName("created_at") @Serializable(InstantSerializer::class) val createdAt: Instant,
    @SerialName("last_message_at") @Serializable(InstantSerializer::class) val lastMessageAt: Instant? = null,
    @SerialName("last_message_preview") val lastMessagePreview: String? = null,
    @SerialName("last_message_sender_name") val lastMessageSenderName: String? = null,
    @SerialName("last_read_at") @Serializable(InstantSerializer::class) val lastReadAt: Instant,
    @SerialName("unread_count") val unreadCount: Int = 0,
)

/** What `create_chat` and `join_chat` return: a chats row (all nulls for a wrong code). */
@Serializable
data class ChatRow(
    val id: String? = null,
    val name: String? = null,
    @SerialName("invite_code") val inviteCode: String? = null,
)

/** A `chat_members` row with its profile. */
@Serializable
data class Member(
    @SerialName("user_id") val userId: String,
    @SerialName("joined_at") @Serializable(InstantSerializer::class) val joinedAt: Instant,
    @SerialName("last_read_at") @Serializable(InstantSerializer::class) val lastReadAt: Instant,
    val profile: Profile? = null,
) {
    val name: String get() = profile?.displayName ?: "Someone"
}

/** A `messages` row. */
@Serializable
data class Message(
    val id: String,
    @SerialName("chat_id") val chatId: String,
    val sender: String,
    /** The text, or a photo's caption (may be empty then). */
    val body: String,
    @SerialName("created_at") @Serializable(InstantSerializer::class) val createdAt: Instant,
    /** A photo in the chat-media bucket and its size in pixels. */
    @SerialName("image_path") val imagePath: String? = null,
    @SerialName("image_width") val imageWidth: Int? = null,
    @SerialName("image_height") val imageHeight: Int? = null,
    /** App only, never sent: an optimistic bubble not yet confirmed, or one that failed. */
    @Transient val pending: Boolean = false,
    @Transient val failed: Boolean = false,
    /** [TEXT], or [JOINED] for a "Maya joined" line the server writes (migration 0009). Rows from before it have none. */
    val kind: String = TEXT,
) {
    /** A "Maya joined" line: drawn small and centered, never counted as unread. */
    val isJoin: Boolean get() = kind == JOINED

    companion object {
        const val TEXT = "text"
        const val JOINED = "joined"
    }
}

// MARK: Muse Spark

/** "Catch me up": the brief's `result`. Every item cites the messages it came from. */
@Serializable
data class CatchUp(
    /** 1 to 3 sentences, the gist. The field keeps the app's old name, TL;DR. */
    val tldr: String,
    val highlights: List<Item> = emptyList(),
    val plans: List<Plan> = emptyList(),
    @SerialName("open_questions") val openQuestions: List<Question> = emptyList(),
    val owes: List<Owe> = emptyList(),
    @SerialName("for_you") val forYou: List<Item> = emptyList(),
) {
    @Serializable
    data class Item(
        val text: String,
        @Serializable(RefsSerializer::class) val refs: List<String> = emptyList(),
    )

    @Serializable
    data class Plan(
        val title: String,
        /** ISO 8601, usually with the reader's offset; [Times.planTime] reads it. */
        @SerialName("starts_at") val startsAt: String? = null,
        @SerialName("ends_at") val endsAt: String? = null,
        @SerialName("all_day") val allDay: Boolean = false,
        val location: String? = null,
        /** "confirmed" or "proposed". */
        val status: String = "proposed",
        val who: List<String> = emptyList(),
        @Serializable(RefsSerializer::class) val refs: List<String> = emptyList(),
    ) {
        val confirmed: Boolean get() = status == "confirmed"
    }

    @Serializable
    data class Question(
        val question: String,
        @SerialName("asked_by") val askedBy: String? = null,
        @Serializable(RefsSerializer::class) val refs: List<String> = emptyList(),
    )

    @Serializable
    data class Owe(
        val who: String,
        @SerialName("owes_whom") val owesWhom: String? = null,
        val what: String,
        @Serializable(RefsSerializer::class) val refs: List<String> = emptyList(),
    )
}

/** "Ask the chat": the answer's `result`. `found` is false when the chat doesn't say. */
@Serializable
data class ChatAnswer(
    val answer: String,
    val found: Boolean = false,
    @Serializable(RefsSerializer::class) val refs: List<String> = emptyList(),
)

/**
 * The envelope both edge functions return around a [CatchUp] or a
 * [ChatAnswer]. `catch-up` fills the brief fields (`brief_id`, `since`,
 * `until`); `catch-up-text` fills `source` and `truncated`.
 */
@Serializable
data class BriefResponse<T>(
    /** "catch_up" or "ask". */
    val kind: String? = null,
    /** Nothing unread (catch-up) or no messages at all (text catch-up). */
    val empty: Boolean = false,
    /** Served from a brief made earlier for the same window. */
    val cached: Boolean = false,
    val result: T? = null,
    val model: String? = null,
    @SerialName("message_count") val messageCount: Int? = null,
    @SerialName("latency_ms") val latencyMs: Long? = null,
    /** Its `ai_briefs` row, new or reused (Ketchup chats only). */
    @SerialName("brief_id") val briefId: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    /** The window it read. Catch-up moves the read cursor to `until`, not to now. */
    val since: String? = null,
    val until: String? = null,
    /** catch-up-text: "instagram" or "snapchat", and whether older messages were left out. */
    val source: String? = null,
    val truncated: Boolean = false,
    val error: String? = null,
) {
    val untilInstant: Instant? get() = until?.let(Times::instant)
}

typealias CatchUpResponse = BriefResponse<CatchUp>
typealias AskResponse = BriefResponse<ChatAnswer>
