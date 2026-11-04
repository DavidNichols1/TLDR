package com.vibetemp.ketchup.ui.chats

import androidx.annotation.DrawableRes
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.ui.auth.ChatIcon
import com.vibetemp.ketchup.ui.auth.NameField
import com.vibetemp.ketchup.ui.design.CapsuleButton
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.KetchupDrop
import com.vibetemp.ketchup.ui.design.Monogram
import com.vibetemp.ketchup.ui.design.SectionTitle
import com.vibetemp.ketchup.ui.design.Wordmark
import com.vibetemp.ketchup.ui.design.paperCard
import com.vibetemp.ketchup.ui.design.pressable
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import kotlinx.coroutines.launch

/**
 * A minimal Settings (iOS `SettingsView`, from your monogram at the top of
 * Chats): who you are, Change your name, Sign out (asked once more), and
 * the About colophon. Settings has no ketchup button.
 */
@Composable
fun SettingsScreen(app: AppModel, onBack: () -> Unit, onEditName: () -> Unit, confirmingSignOut: Boolean = false) {
    val colors = KetchupTheme.colors
    val scope = rememberCoroutineScope()
    var confirm by rememberSaveable { mutableStateOf(confirmingSignOut) }
    val name = app.me?.displayName ?: stringResource(R.string.settings_you)
    val email = app.email

    PageScaffold(title = null, onBack = onBack) {
        Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Kicker(stringResource(R.string.settings_kicker))
                Text(
                    name,
                    style = KetchupTheme.type.serifLargeTitle,
                    color = colors.ink,
                    maxLines = 2,
                    modifier = Modifier.semantics { heading() },
                )
                if (email != null) {
                    val signedIn = stringResource(R.string.settings_signed_in_as, email)
                    Text(
                        email,
                        style = KetchupTheme.type.subheadline,
                        color = colors.inkSoft,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.semantics { contentDescription = signedIn },
                    )
                }
            }
            Spacer(Modifier.width(16.dp))
            Monogram(app.me?.displayName ?: "?", size = 56.dp)
        }

        SettingsSection(stringResource(R.string.settings_you), footer = stringResource(R.string.settings_you_footer)) {
            SettingsRow(stringResource(R.string.settings_change_name), R.drawable.chat_ic_pencil, chevron = true, onClick = onEditName)
        }
        SettingsSection(stringResource(R.string.settings_account)) {
            SettingsRow(stringResource(R.string.settings_sign_out), R.drawable.chat_ic_sign_out, onClick = { confirm = true })
        }
        About()
    }

    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            confirmButton = {
                TextButton(onClick = {
                    confirm = false
                    scope.launch { app.signOut() }
                }) { Text(stringResource(R.string.settings_sign_out), color = colors.ketchupText, fontWeight = FontWeight.SemiBold) }
            },
            dismissButton = {
                TextButton(onClick = { confirm = false }) { Text(stringResource(R.string.sheet_cancel), color = colors.ink) }
            },
            title = { Text(stringResource(R.string.settings_sign_out_title), style = KetchupTheme.type.serifTitle3, color = colors.ink) },
            text = {
                Text(
                    if (email != null) stringResource(R.string.settings_sign_out_body, email) else stringResource(R.string.settings_sign_out_body_plain),
                    style = KetchupTheme.type.body,
                    color = colors.inkSoft,
                )
            },
            containerColor = colors.card,
        )
    }

    // A new name that didn't go through (AppModel.renameNow).
    app.problem?.let { problem ->
        AlertDialog(
            onDismissRequest = { app.problem = null },
            confirmButton = { TextButton(onClick = { app.problem = null }) { Text(stringResource(R.string.chats_ok), color = colors.ketchupText) } },
            title = { Text(stringResource(R.string.settings_problem_title), style = KetchupTheme.type.serifTitle3, color = colors.ink) },
            text = { Text(problem, style = KetchupTheme.type.body, color = colors.inkSoft) },
            containerColor = colors.card,
        )
    }
}

/**
 * Change your name, from Settings: it changes everywhere at once and the
 * page closes; if the server says no, it changes back and Settings says so.
 */
@Composable
fun EditNameScreen(app: AppModel, onDone: () -> Unit) {
    val colors = KetchupTheme.colors
    var name by rememberSaveable { mutableStateOf(app.me?.displayName.orEmpty()) }
    val focus = remember { FocusRequester() }
    val trimmed = name.trim()
    val unchanged = trimmed == app.me?.displayName
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    fun save() {
        if (unchanged || trimmed.isEmpty() || trimmed.length > 30) return
        app.renameNow(name)
        onDone()
    }

    PageScaffold(title = stringResource(R.string.editname_title), onBack = onDone) {
        Text(
            stringResource(R.string.name_headline),
            style = KetchupTheme.type.serifTitle,
            color = colors.ink,
            modifier = Modifier.semantics { heading() },
        )
        Text(stringResource(R.string.name_pitch), style = KetchupTheme.type.body, color = colors.inkSoft)
        NameField(name, { name = it }, focus, onDone = ::save, modifier = Modifier.padding(top = 10.dp))
        CapsuleButton(
            stringResource(R.string.editname_save),
            onClick = ::save,
            enabled = !unchanged && trimmed.isNotEmpty() && trimmed.length <= 30,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}

/** A pushed page: back and a serif title in a slim bar, then a scrolling column. */
@Composable
fun PageScaffold(title: String?, onBack: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    val colors = KetchupTheme.colors
    Column(
        Modifier
            .fillMaxSize()
            .background(colors.cream)
            .imePadding(),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .height(BAR_ROW)
                .padding(horizontal = 6.dp),
            contentAlignment = Alignment.CenterStart,
        ) {
            BackButton(onBack)
            if (title != null) {
                Text(
                    title,
                    style = KetchupTheme.type.serifHeadline,
                    color = colors.ink,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .semantics { heading() },
                )
            }
        }
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(horizontal = 20.dp)
                .padding(top = 4.dp, bottom = 36.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
            content = content,
        )
    }
}

/** The bar's back arrow. */
@Composable
fun BackButton(onBack: () -> Unit, modifier: Modifier = Modifier) {
    val label = stringResource(R.string.chat_back)
    Box(
        modifier
            .size(44.dp)
            .pressable(onClick = onBack)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        ChatIcon(R.drawable.chat_ic_back, null, KetchupTheme.colors.ink, size = 24.dp)
    }
}

/** A titled group of rows on one paper card (iOS `SettingsSection`). */
@Composable
private fun SettingsSection(title: String, footer: String? = null, rows: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionTitle(title)
        Column(Modifier.paperCard(padding = 0.dp), content = rows)
        if (footer != null) Text(footer, style = KetchupTheme.type.footnote, color = KetchupTheme.colors.inkSoft)
    }
}

/** One row: an inkSoft icon, the label, and a chevron for rows that open a page. */
@Composable
private fun SettingsRow(title: String, @DrawableRes icon: Int, chevron: Boolean = false, onClick: () -> Unit) {
    val colors = KetchupTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .pressable(onClick = onClick)
            .semantics(mergeDescendants = true) { }
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        ChatIcon(icon, null, colors.inkSoft, size = 22.dp)
        Text(title, style = KetchupTheme.type.body, color = colors.ink, modifier = Modifier.weight(1f))
        if (chevron) ChatIcon(R.drawable.chat_ic_chevron, null, colors.inkFaint, size = 20.dp)
    }
}

/** The colophon: the drop and the name, the version, Muse Spark's byline, where Cetchup was made. */
@Composable
private fun About() {
    val colors = KetchupTheme.colors
    val context = LocalContext.current
    val version = remember(context) {
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull() ?: "0.1"
    }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionTitle(stringResource(R.string.settings_about))
        Column(
            Modifier
                .paperCard(padding = 20.dp)
                .semantics(mergeDescendants = true) { },
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            KetchupDrop(size = 30.dp, modifier = Modifier.rotate(-8f))
            Wordmark(size = 30.dp)
            Kicker(stringResource(R.string.settings_version, version), modifier = Modifier.padding(top = 2.dp))
            Text(
                stringResource(R.string.settings_read_by),
                style = KetchupTheme.type.monoCaption,
                color = colors.inkSoft,
            )
            Text(
                stringResource(R.string.settings_hackathon),
                style = KetchupTheme.type.footnote,
                color = colors.inkSoft,
                textAlign = TextAlign.Center,
            )
        }
    }
}
