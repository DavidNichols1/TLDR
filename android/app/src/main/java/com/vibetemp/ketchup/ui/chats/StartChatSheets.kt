package com.vibetemp.ketchup.ui.chats

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.ui.auth.CodeField
import com.vibetemp.ketchup.ui.auth.PaperField
import com.vibetemp.ketchup.ui.auth.TextAction
import com.vibetemp.ketchup.ui.design.CapsuleButton
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.theme.KetchupTheme

// The inbox's "+": name a new chat, or join one with its 6-character
// invite code (iOS Views/StartChatSheets.swift). Both only collect the
// input; ChatsScreen does the work.

/** Name a new chat. [onCreate] runs with the name already in [name]. */
@Composable
fun NewChatSheet(name: String, onName: (String) -> Unit, onCreate: () -> Unit, onCancel: () -> Unit) {
    val focus = remember { FocusRequester() }
    val trimmed = name.trim()
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    StartChatPage(
        kicker = stringResource(R.string.newchat_kicker),
        title = stringResource(R.string.newchat_title),
        onCancel = onCancel,
    ) {
        PaperField(
            value = name,
            onValueChange = { onName(it.take(50)) },
            placeholder = stringResource(R.string.newchat_placeholder),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { if (trimmed.isNotEmpty()) onCreate() }),
            focusRequester = focus,
        )
        Text(stringResource(R.string.newchat_note), style = KetchupTheme.type.footnote, color = KetchupTheme.colors.inkSoft)
        CapsuleButton(
            stringResource(R.string.newchat_start),
            onClick = onCreate,
            enabled = trimmed.isNotEmpty(),
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}

/** Join with an invite code: six boxes, like the sign-in code. */
@Composable
fun JoinChatSheet(code: String, onCode: (String) -> Unit, onJoin: () -> Unit, onCancel: () -> Unit) {
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    StartChatPage(
        kicker = stringResource(R.string.join_kicker),
        title = stringResource(R.string.join_title),
        onCancel = onCancel,
    ) {
        CodeField(
            value = code,
            onValueChange = { onCode(InviteCode.clean(it)) },
            length = InviteCode.LENGTH,
            digits = false,
            label = stringResource(R.string.join_label),
            focusRequester = focus,
            onSubmit = { if (code.length == InviteCode.LENGTH) onJoin() },
        )
        Text(stringResource(R.string.join_note), style = KetchupTheme.type.footnote, color = KetchupTheme.colors.inkSoft)
        CapsuleButton(
            stringResource(R.string.join_button),
            onClick = onJoin,
            enabled = code.length == InviteCode.LENGTH,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}

/** The page both sheets share: Cancel, a kicker and a serif question, then the form. */
@Composable
private fun StartChatPage(kicker: String, title: String, onCancel: () -> Unit, form: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp)
            .padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(Modifier.fillMaxWidth()) {
            TextAction(stringResource(R.string.sheet_cancel), KetchupTheme.colors.ketchupText, enabled = true, onClick = onCancel)
        }
        Column(Modifier.padding(bottom = 6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Kicker(kicker)
            Text(
                title,
                style = KetchupTheme.type.serifTitle,
                color = KetchupTheme.colors.ink,
                modifier = Modifier.semantics { heading() },
            )
        }
        form()
    }
}

/** Invite codes: six capital letters and numbers. */
object InviteCode {
    const val LENGTH = 6

    /**
     * Capitals and numbers, at most six. From a pasted share message
     * ("Join “Breck” on Ketchup with code WQGAEA") it keeps the word after
     * "code", or else the last 6-character word (iOS `JoinChatSheet.clean`).
     */
    fun clean(raw: String): String {
        val upper = raw.uppercase()
        val kept = upper.filter { it.isLetterOrDigit() && it.code < 128 }
        if (kept.length <= LENGTH) return kept
        Regex("CODE[^A-Z0-9]+([A-Z0-9]{6})\\b").find(upper)?.let { return it.groupValues[1] }
        Regex("\\b[A-Z0-9]{6}\\b").findAll(upper).lastOrNull()?.let { return it.value }
        return kept.take(LENGTH)
    }
}
