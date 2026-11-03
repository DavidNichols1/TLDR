package com.vibetemp.ketchup.ui.chat

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.ui.auth.ChatIcon
import com.vibetemp.ketchup.ui.design.KetchupDrop
import com.vibetemp.ketchup.ui.design.pressable
import com.vibetemp.ketchup.ui.theme.KetchupTheme

/** The cap messages_body_check sets (2,000 characters). */
const val MESSAGE_MAX = 2_000

/** The trimmed text, or null when it's empty or over the cap. */
fun sendable(text: String): String? = text.trim().takeIf { it.isNotEmpty() && it.length <= MESSAGE_MAX }

/**
 * Pinned under the chat's title (iOS `CatchUpBar`): the big ketchup "Catch
 * me up · 302 new" while there's something to catch up on, and Ask always.
 * Both open the brief.
 */
@Composable
fun CatchUpBar(unread: Int, onCatchUp: () -> Unit, onAsk: () -> Unit) {
    val colors = KetchupTheme.colors
    Column(Modifier.background(colors.cream)) {
        Row(
            Modifier
                .fillMaxWidth()
                .height(IntrinsicSize.Min)
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (unread > 0) {
                CatchUpButton(unread, onCatchUp, Modifier.weight(1f))
            } else {
                Spacer(Modifier.weight(1f))
            }
            AskButton(if (unread > 0) stringResource(R.string.chat_ask) else stringResource(R.string.chat_ask_the_chat), onAsk, Modifier.fillMaxHeight())
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(colors.rule))
    }
}

/** The chat's one ketchup thing: the drop, "Catch me up", and "302 new" under it in mono. */
@Composable
private fun CatchUpButton(unread: Int, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = KetchupTheme.colors
    val view = LocalView.current
    val label = stringResource(R.string.chat_catch_up)
    val value = pluralStringResource(R.plurals.chat_new_messages_spoken, unread, unread)
    Row(
        modifier
            .pressable {
                view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                onClick()
            }
            .background(colors.ketchup, CircleShape)
            .clearAndSetSemantics {
                contentDescription = "$label, $value"
                role = Role.Button
                onClick { onClick(); true }
            }
            .padding(horizontal = 20.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        KetchupDrop(size = 18.dp, color = colors.onKetchup)
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(label, style = KetchupTheme.type.headline, color = colors.onKetchup, maxLines = 1)
            Text(
                stringResource(R.string.chat_new_count, if (unread > 999) "999+" else unread.toString()),
                style = KetchupTheme.type.monoCaption,
                color = colors.onKetchup,
                maxLines = 1,
            )
        }
    }
}

/** A quiet outline capsule: the bubble icon and "Ask". */
@Composable
private fun AskButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = KetchupTheme.colors
    Row(
        modifier
            .pressable(onClick = onClick)
            .border(1.dp, colors.ink, CircleShape)
            .semantics(mergeDescendants = true) { role = Role.Button }
            .padding(horizontal = 16.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        ChatIcon(R.drawable.chat_ic_ask, null, colors.ink, size = 18.dp)
        Text(text, style = KetchupTheme.type.subheadline.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = colors.ink)
    }
}

/**
 * The composer (iOS `ChatInputBar`): a paper field that grows to five lines
 * and a send button that only turns ketchup when there's something to send.
 */
@Composable
fun ChatInputBar(text: String, onText: (String) -> Unit, onSend: () -> Unit, modifier: Modifier = Modifier) {
    val colors = KetchupTheme.colors
    var focused by remember { mutableStateOf(false) }
    val canSend = sendable(text) != null
    val field = RoundedCornerShape(20.dp)
    val sendLabel = stringResource(R.string.chat_send)
    Column(modifier.background(colors.cream)) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(colors.rule))
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 8.dp),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            BasicTextField(
                value = text,
                onValueChange = onText,
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = 40.dp)
                    .onFocusChanged { focused = it.isFocused },
                textStyle = KetchupTheme.type.body.copy(color = colors.ink),
                cursorBrush = SolidColor(colors.ketchupText),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                maxLines = 5,
                decorationBox = { inner ->
                    Box(
                        Modifier
                            .background(colors.card, field)
                            .border(1.dp, if (focused) colors.inkSoft else colors.rule, field)
                            .heightIn(min = 40.dp)
                            .padding(horizontal = 14.dp, vertical = 9.dp),
                        contentAlignment = Alignment.CenterStart,
                    ) {
                        if (text.isEmpty()) Text(stringResource(R.string.chat_message_placeholder), style = KetchupTheme.type.body, color = colors.inkFaint)
                        inner()
                    }
                },
            )
            Box(
                Modifier
                    .size(40.dp)
                    .pressable(enabled = canSend, onClick = onSend)
                    .background(if (canSend) colors.ketchup else colors.rule, CircleShape)
                    .semantics {
                        contentDescription = sendLabel
                        role = Role.Button
                    },
                contentAlignment = Alignment.Center,
            ) {
                ChatIcon(R.drawable.chat_ic_send, null, if (canSend) colors.onKetchup else colors.inkFaint, size = 22.dp)
            }
        }
    }
}
