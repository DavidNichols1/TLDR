package com.vibetemp.ketchup.ui.chats

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.ChatSummary
import com.vibetemp.ketchup.ui.design.KetchupDrop
import com.vibetemp.ketchup.ui.design.Monogram
import com.vibetemp.ketchup.ui.design.pressable
import com.vibetemp.ketchup.ui.theme.KetchupTheme

/** Unread count that earns the catch-up nudge on a row (iOS `ChatListRow.nudgeAt`). */
const val NUDGE_AT = 15

/**
 * One inbox row (iOS `ChatListRow`): the chat's monogram, its name and
 * time, "Maya: goodnight losers" under it, a mustard unread badge, and for
 * a pile of unread, a catch-up nudge with the drop.
 */
@Composable
fun ChatListRow(chat: ChatSummary, onOpen: () -> Unit) {
    val colors = KetchupTheme.colors
    val unread = chat.unreadCount
    val count = if (unread > 999) "999+" else unread.toString()
    val stamp = Stamps.inbox(chat.lastMessageAt ?: chat.createdAt, stringResource(R.string.chats_yesterday))
    val noMessages = stringResource(R.string.chats_no_messages)
    val preview = buildAnnotatedString {
        val text = chat.lastMessagePreview
        if (text == null) {
            append(noMessages)
        } else {
            chat.lastMessageSenderName?.let { who ->
                withStyle(SpanStyle(fontWeight = FontWeight.Medium, color = colors.ink)) { append("$who:") }
                append(" ")
            }
            append(text)
        }
    }
    val unreadWords = pluralStringResource(R.plurals.chats_row_unread, unread, unread)
    val spoken = buildList {
        add(chat.name)
        if (unread > 0) add(unreadWords)
        chat.lastMessagePreview?.let { add(listOfNotNull(chat.lastMessageSenderName, it).joinToString(": ")) }
        add(stamp)
    }.joinToString(", ")

    Row(
        Modifier
            .fillMaxWidth()
            .pressable(scaleTo = 0.98f, onClick = onOpen)
            .clearAndSetSemantics { contentDescription = spoken }
            .padding(horizontal = 20.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Monogram(chat.name, size = ROW_MONOGRAM)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    chat.name,
                    style = KetchupTheme.type.headline,
                    color = colors.ink,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Text(stamp, style = KetchupTheme.type.monoCaption, color = if (unread > 0) colors.ink else colors.inkSoft)
            }
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    preview,
                    style = KetchupTheme.type.subheadline,
                    color = colors.inkSoft,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                if (unread > 0) {
                    Text(
                        count,
                        style = KetchupTheme.type.monoCaption.copy(fontWeight = FontWeight.Bold),
                        color = colors.onMustard,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .padding(top = 2.dp)
                            .background(colors.mustard, CircleShape)
                            .widthIn(min = 24.dp)
                            .padding(horizontal = 7.dp, vertical = 2.dp),
                    )
                }
            }
            if (unread >= NUDGE_AT) {
                Row(
                    Modifier.padding(top = 3.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    KetchupDrop(size = 12.dp, color = colors.ketchupText)
                    Text(
                        stringResource(R.string.chats_nudge, count),
                        style = KetchupTheme.type.monoCaption.copy(fontWeight = FontWeight.SemiBold),
                        color = colors.ketchupText,
                    )
                }
            }
        }
    }
}
