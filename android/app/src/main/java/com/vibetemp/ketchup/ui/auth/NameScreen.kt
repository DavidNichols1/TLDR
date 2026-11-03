package com.vibetemp.ketchup.ui.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.ui.chat.ChatModel
import com.vibetemp.ketchup.ui.chats.AppModel
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.Monogram
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/**
 * Once, right after sign-up (iOS `NameView`): the name your friends see, and
 * the name Muse Spark uses when it says "Sam owes you $12". Prefilled with
 * the one sign-up picked (your email's first part).
 */
@Composable
fun NameScreen(app: AppModel) {
    val colors = KetchupTheme.colors
    val scope = rememberCoroutineScope()
    var name by rememberSaveable { mutableStateOf(app.defaultName) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val focus = remember { FocusRequester() }
    val trimmed = name.trim()

    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    fun save() {
        if (busy || trimmed.isEmpty() || trimmed.length > 30) return
        busy = true
        scope.launch {
            try {
                app.rename(name)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = ChatModel.readable(e)
            } finally {
                busy = false
            }
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(colors.cream)
            .safeDrawingPadding()
            .imePadding(),
        contentAlignment = Alignment.TopCenter,
    ) {
        Column(
            Modifier
                .widthIn(max = 520.dp)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(top = 48.dp, bottom = 24.dp),
        ) {
            Kicker(stringResource(R.string.name_kicker))
            Text(
                stringResource(R.string.name_headline),
                style = KetchupTheme.type.serifLargeTitle,
                color = colors.ink,
                modifier = Modifier
                    .padding(top = 8.dp)
                    .semantics { heading() },
            )
            Text(
                stringResource(R.string.name_pitch),
                style = KetchupTheme.type.body,
                color = colors.inkSoft,
                modifier = Modifier.padding(top = 10.dp),
            )
            NameField(
                name = name,
                onName = { name = it },
                focus = focus,
                onDone = ::save,
                modifier = Modifier.padding(top = 28.dp),
            )
            error?.let { FormError(it, Modifier.padding(top = 12.dp)) }
            BusyCapsule(
                stringResource(R.string.name_save),
                busy = busy,
                onClick = ::save,
                enabled = trimmed.isNotEmpty() && trimmed.length <= 30,
                modifier = Modifier.padding(top = 12.dp),
            )
            TextAction(
                stringResource(R.string.name_keep, app.defaultName),
                colors.ink,
                enabled = !busy,
                onClick = app::confirmName,
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .padding(top = 12.dp),
            )
        }
    }
}

/** A name field whose monogram follows what you type: how you'll look in member lists. */
@Composable
fun NameField(name: String, onName: (String) -> Unit, focus: FocusRequester, onDone: () -> Unit, modifier: Modifier = Modifier) {
    val trimmed = name.trim()
    PaperField(
        value = name,
        onValueChange = { onName(it.take(40)) },
        placeholder = stringResource(R.string.name_placeholder),
        modifier = modifier,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { onDone() }),
        focusRequester = focus,
        leading = { Monogram(trimmed.ifEmpty { "?" }, size = 30.dp) },
    )
}
