package com.vibetemp.ketchup.reader

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.TextSource
import com.vibetemp.ketchup.ui.design.ButtonFill
import com.vibetemp.ketchup.ui.design.CapsuleButton
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.paperCard
import com.vibetemp.ketchup.ui.theme.KetchupTheme

/**
 * The home pager's Instagram or Snapchat page; the chat slice's pager shows
 * it. Experimental, like the iOS web readers: what the bubble does, whether
 * it's on (checked each time the page comes back), turning it on (the
 * consent screen first, then Android's accessibility settings), the
 * restricted-settings tip for a sideloaded install, and opening the
 * official app.
 */
@Composable
fun ReaderPage(source: TextSource, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    var on by remember { mutableStateOf(ReaderSetup.isServiceOn(context)) }
    var installed by remember { mutableStateOf(ReaderSetup.launchIntent(context, source) != null) }
    var consenting by rememberSaveable { mutableStateOf(false) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        on = ReaderSetup.isServiceOn(context)
        installed = ReaderSetup.launchIntent(context, source) != null
    }
    BackHandler(enabled = consenting) { consenting = false }
    Box(modifier.fillMaxSize()) {
        if (consenting) {
            ReaderConsent(
                onAgree = {
                    ReaderSetup.setConsent(context, true)
                    consenting = false
                    openSettings(context)
                },
                onNotNow = { consenting = false },
            )
        } else {
            ReaderPageContent(
                source = source,
                on = on,
                installed = installed,
                onTurnOn = { consenting = true },
                onTurnOff = { openSettings(context) },
                onOpenApp = { ReaderSetup.launchIntent(context, source)?.let(context::startActivity) },
                onAppInfo = { start(context, ReaderSetup.appInfo(context)) },
            )
        }
    }
}

/** The page itself, stateless (the previews show each state). */
@Composable
fun ReaderPageContent(
    source: TextSource,
    on: Boolean,
    installed: Boolean,
    onTurnOn: () -> Unit,
    onTurnOff: () -> Unit,
    onOpenApp: () -> Unit,
    onAppInfo: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = KetchupTheme.colors
    Column(
        modifier
            .fillMaxSize()
            .background(colors.cream)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Kicker(stringResource(R.string.reader_page_kicker))
            Text(
                stringResource(R.string.reader_page_title, source.appName),
                style = KetchupTheme.type.serifTitle,
                color = colors.ink,
                modifier = Modifier.semantics { heading() },
            )
            Text(stringResource(R.string.reader_page_body, source.appName), style = KetchupTheme.type.body, color = colors.ink)
        }

        Row(
            Modifier.paperCard(padding = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.size(10.dp).background(if (on) colors.pickle else colors.inkFaint, CircleShape))
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(if (on) R.string.reader_page_on else R.string.reader_page_off), style = KetchupTheme.type.headline, color = colors.ink)
                Text(
                    stringResource(if (on) R.string.reader_page_on_detail else R.string.reader_page_off_detail),
                    style = KetchupTheme.type.footnote,
                    color = colors.inkSoft,
                )
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            // One ketchup button: turn it on, or once it's on, go to the app.
            if (!on) CapsuleButton(stringResource(R.string.reader_page_turn_on), onClick = onTurnOn)
            if (installed) {
                CapsuleButton(
                    stringResource(R.string.reader_page_open, source.appName),
                    onClick = onOpenApp,
                    fill = if (on) ButtonFill.Ketchup else ButtonFill.Outline,
                )
            } else {
                Text(stringResource(R.string.reader_page_not_installed, source.appName), style = KetchupTheme.type.subheadline, color = colors.inkSoft)
            }
            if (on) CapsuleButton(stringResource(R.string.reader_page_turn_off), onClick = onTurnOff, fill = ButtonFill.Outline, compact = true)
        }

        if (source == TextSource.SNAPCHAT) {
            Column(Modifier.paperCard(padding = 14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Kicker(stringResource(R.string.reader_page_snapchat_kicker), color = colors.ketchupText)
                Text(stringResource(R.string.reader_page_snapchat_untested), style = KetchupTheme.type.subheadline, color = colors.ink)
            }
        }

        if (!on && ReaderSetup.mayNeedRestrictedSettings) {
            Column(Modifier.paperCard(padding = 14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.reader_page_restricted_title), style = KetchupTheme.type.headline, color = colors.ink)
                Text(stringResource(R.string.reader_page_restricted_body), style = KetchupTheme.type.subheadline, color = colors.ink)
                CapsuleButton(stringResource(R.string.reader_page_app_info), onClick = onAppInfo, fill = ButtonFill.Outline, compact = true)
            }
        }

        Text(stringResource(R.string.reader_page_terms), style = KetchupTheme.type.footnote, color = colors.inkSoft)
    }
}

/**
 * The disclosure before Android's switch: what the bubble reads, when,
 * and where it goes, and an affirmative tap. Nothing is read until then.
 */
@Composable
fun ReaderConsent(onAgree: () -> Unit, onNotNow: () -> Unit, modifier: Modifier = Modifier) {
    val colors = KetchupTheme.colors
    Column(
        modifier
            .fillMaxSize()
            .background(colors.cream)
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
    ) {
        Column(Modifier.paperCard(padding = 22.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Kicker(stringResource(R.string.reader_consent_kicker))
                Text(
                    stringResource(R.string.reader_consent_title),
                    style = KetchupTheme.type.serifTitle,
                    color = colors.ink,
                    modifier = Modifier.semantics { heading() },
                )
            }
            Point(stringResource(R.string.reader_consent_what_title), stringResource(R.string.reader_consent_what))
            Point(stringResource(R.string.reader_consent_when_title), stringResource(R.string.reader_consent_when))
            Point(stringResource(R.string.reader_consent_where_title), stringResource(R.string.reader_consent_where))
            Point(stringResource(R.string.reader_consent_how_title), stringResource(R.string.reader_consent_how))
            Text(stringResource(R.string.reader_page_terms), style = KetchupTheme.type.footnote, color = colors.inkSoft)
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                CapsuleButton(stringResource(R.string.reader_consent_agree), onClick = onAgree)
                CapsuleButton(stringResource(R.string.reader_consent_not_now), onClick = onNotNow, fill = ButtonFill.Outline)
            }
            Text(stringResource(R.string.reader_consent_settings_hint), style = KetchupTheme.type.footnote, color = colors.inkSoft)
        }
    }
}

@Composable
private fun Point(title: String, body: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Kicker(title)
        Text(body, style = KetchupTheme.type.subheadline, color = KetchupTheme.colors.ink)
    }
}

private fun openSettings(context: Context) {
    if (!start(context, ReaderSetup.accessibilitySettings())) start(context, Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

private fun start(context: Context, intent: Intent): Boolean = try {
    context.startActivity(intent)
    true
} catch (_: ActivityNotFoundException) {
    false
}
