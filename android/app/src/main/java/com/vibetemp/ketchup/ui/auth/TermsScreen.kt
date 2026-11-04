package com.vibetemp.ketchup.ui.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.Config
import com.vibetemp.ketchup.ui.chats.AppModel
import com.vibetemp.ketchup.ui.design.ButtonFill
import com.vibetemp.ketchup.ui.design.paperCard
import com.vibetemp.ketchup.ui.design.pressable
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/**
 * Before the app, once per version of the terms (migration 0011,
 * data/TermsGate.kt): you're signed in but haven't agreed to
 * [Config.TERMS_VERSION] yet. Both documents open in the system browser.
 * Agree records it (accept_terms) and the root moves on; if that fails it
 * says so and Agree stays, to try again. Sign out is the way out.
 * [failedAtStart]: a preview opens on the failure.
 */
@Composable
fun TermsScreen(app: AppModel, failedAtStart: Boolean = false) {
    val colors = KetchupTheme.colors
    val scope = rememberCoroutineScope()
    var saving by remember { mutableStateOf(false) }
    var signingOut by remember { mutableStateOf(false) }
    var failed by rememberSaveable { mutableStateOf(failedAtStart) }

    fun agree() {
        if (saving || signingOut) return
        saving = true
        failed = false
        scope.launch {
            try {
                app.agreeToTerms()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failed = true
            } finally {
                saving = false
            }
        }
    }

    fun signOut() {
        if (saving || signingOut) return
        signingOut = true
        scope.launch {
            try {
                app.signOut()
            } finally {
                signingOut = false
            }
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(colors.cream)
            .safeDrawingPadding(),
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
            Text(
                stringResource(R.string.terms_title),
                style = KetchupTheme.type.serifLargeTitle,
                color = colors.ink,
                modifier = Modifier.semantics { heading() },
            )
            Text(
                stringResource(R.string.terms_pitch),
                style = KetchupTheme.type.body,
                color = colors.inkSoft,
                modifier = Modifier.padding(top = 10.dp),
            )
            Column(
                Modifier
                    .padding(top = 28.dp)
                    .paperCard(padding = 0.dp),
            ) {
                DocumentRow(stringResource(R.string.terms_of_service), Config.TERMS_URL)
                HorizontalDivider(color = colors.rule)
                DocumentRow(stringResource(R.string.terms_privacy_policy), Config.PRIVACY_URL)
            }
            Text(
                stringResource(R.string.terms_updated, publishedOn(Config.TERMS_VERSION)),
                style = KetchupTheme.type.footnote,
                color = colors.inkSoft,
                modifier = Modifier.padding(top = 10.dp, start = 4.dp),
            )
            if (failed) FormError(stringResource(R.string.terms_save_failed), Modifier.padding(top = 24.dp))
            BusyCapsule(
                stringResource(R.string.terms_agree),
                busy = saving,
                onClick = ::agree,
                enabled = !signingOut,
                modifier = Modifier.padding(top = if (failed) 12.dp else 28.dp),
            )
            BusyCapsule(
                stringResource(R.string.settings_sign_out),
                busy = signingOut,
                onClick = ::signOut,
                enabled = !saving,
                fill = ButtonFill.Outline,
                modifier = Modifier.padding(top = 10.dp),
            )
        }
    }
}

/** One document on the card: its name and an open-in-browser mark. */
@Composable
private fun DocumentRow(title: String, url: String) {
    val colors = KetchupTheme.colors
    val uri = LocalUriHandler.current
    Row(
        Modifier
            .fillMaxWidth()
            .pressable { uri.openSafely(url) }
            .semantics(mergeDescendants = true) { }
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(title, style = KetchupTheme.type.body, color = colors.ink, modifier = Modifier.weight(1f))
        ChatIcon(R.drawable.chat_ic_open, stringResource(R.string.terms_opens_browser), colors.inkSoft, size = 20.dp)
    }
}

/**
 * "By continuing, you agree to Cetchup's Terms of Service and Privacy
 * Policy.", directly under sign-in's button. Both names are links to the
 * system browser; it wraps at any text size, and TalkBack reaches each link.
 */
@Composable
fun TermsNote(modifier: Modifier = Modifier) {
    val colors = KetchupTheme.colors
    val uri = LocalUriHandler.current
    val terms = stringResource(R.string.terms_of_service)
    val privacy = stringResource(R.string.terms_privacy_policy)
    val line = stringResource(R.string.terms_by_continuing, terms, privacy)
    val styles = TextLinkStyles(
        SpanStyle(color = colors.ketchupText, fontWeight = FontWeight.SemiBold, textDecoration = TextDecoration.Underline),
    )
    Text(
        buildAnnotatedString {
            append(line)
            for ((name, url) in listOf(terms to Config.TERMS_URL, privacy to Config.PRIVACY_URL)) {
                val at = line.indexOf(name)
                if (at >= 0) addLink(LinkAnnotation.Url(url, styles) { uri.openSafely(url) }, at, at + name.length)
            }
        },
        style = KetchupTheme.type.footnote,
        color = colors.inkSoft,
        modifier = modifier,
    )
}

/** The system browser (ACTION_VIEW). A phone with nothing to open it does nothing rather than crash. */
private fun UriHandler.openSafely(url: String) {
    runCatching { openUri(url) }
}

/** A terms version ("2026-11-04") as the date people read ("November 4, 2026"), or as is if it isn't a date. */
private fun publishedOn(version: String): String =
    runCatching { LocalDate.parse(version).format(DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG)) }.getOrDefault(version)
