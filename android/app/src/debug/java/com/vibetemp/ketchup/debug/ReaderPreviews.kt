package com.vibetemp.ketchup.debug

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.TextSource
import com.vibetemp.ketchup.reader.PanelState
import com.vibetemp.ketchup.reader.ReadProgress
import com.vibetemp.ketchup.reader.ReaderBubble
import com.vibetemp.ketchup.reader.ReaderConsent
import com.vibetemp.ketchup.reader.ReaderPage
import com.vibetemp.ketchup.reader.ReaderPageContent
import com.vibetemp.ketchup.reader.ReaderPanel
import com.vibetemp.ketchup.reader.SnapchatNameScreen
import com.vibetemp.ketchup.ui.brief.BriefActivity
import com.vibetemp.ketchup.ui.design.CapsuleButton
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.paperCard
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.person

// The reader slice's preview screens. Names start with "reader-".
//
//   reader-instagram-page   the home pager's Instagram page, live: is the bubble on, is Instagram installed
//   reader-snapchat-page    the same for Snapchat, with its "not tested on a real phone" note
//   reader-page-on          the Instagram page with the bubble on and Instagram installed
//   reader-consent          the disclosure before Android's accessibility settings
//   reader-snap-name        "Your name on Snapchat", asked once before the first Snapchat read
//   reader-snapchat-page-named  the Snapchat page with that name saved, and Change
//   reader-panel            the bubble and each state of its panel, over an Instagram-white page
//   reader-panel-snapchat   the same panel over Snapchat, where it asks you to scroll
//   reader-fixture          opens the synthetic Instagram thread the service reads on an emulator
//   reader-instagram        the synthetic thread as catch-up-text will see it

val ReaderPreviews: Map<String, @Composable () -> Unit> = mapOf(
    "reader-instagram-page" to { ReaderPage(TextSource.INSTAGRAM, Modifier.safeDrawingPadding()) },
    "reader-snapchat-page" to { ReaderPage(TextSource.SNAPCHAT, Modifier.safeDrawingPadding()) },
    "reader-page-on" to {
        ReaderPageContent(
            TextSource.INSTAGRAM, on = true, installed = true,
            onTurnOn = {}, onTurnOff = {}, onOpenApp = {}, onAppInfo = {},
            modifier = Modifier.safeDrawingPadding(),
        )
    },
    "reader-consent" to { ReaderConsent(onAgree = {}, onNotNow = {}, modifier = Modifier.safeDrawingPadding()) },
    "reader-snap-name" to { SnapchatNameScreen(initial = "Dave N", onSave = {}, onCancel = {}) },
    "reader-snapchat-page-named" to {
        ReaderPageContent(
            TextSource.SNAPCHAT, on = true, installed = true,
            onTurnOn = {}, onTurnOff = {}, onOpenApp = {}, onAppInfo = {},
            modifier = Modifier.safeDrawingPadding(),
            snapchatName = "Dave N",
        )
    },
    "reader-panel" to { PanelStates() },
    "reader-panel-snapchat" to { PanelStates(TextSource.SNAPCHAT) },
    "reader-fixture" to { FixtureLauncher() },
    "reader-instagram" to { InstagramThreadSample() },
)

/** The bubble and each panel state as they float over another app. */
@Composable
private fun PanelStates(source: TextSource = TextSource.INSTAGRAM) {
    val states = listOf(
        "Tap the bubble" to PanelState.Pick,
        "Reading" to PanelState.Reading(ReadProgress(found = 18, wanted = 30)),
        "Until I stop scrolling" to PanelState.Reading(ReadProgress(found = 24, wanted = 0, following = true)),
        "Not signed in" to PanelState.SignIn,
        "Not set up" to PanelState.Setup,
        "Nothing found" to PanelState.Problem(R.string.reader_problem_nothing, 30),
    )
    Column(
        Modifier
            .fillMaxSize()
            .background(Color.White)
            .safeDrawingPadding()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ReaderBubble()
            Text("The bubble, over a ${source.appName} thread", style = KetchupTheme.type.footnote, color = Color(0xFF737373))
        }
        states.forEach { (label, state) ->
            Text(label, style = KetchupTheme.type.monoCaption, color = Color(0xFF737373))
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
                ReaderPanel(state, source, onPick = {}, onStop = {}, onClose = {}, onOpenApp = {})
            }
        }
    }
}

/** Opens debug/ReaderFixtureActivity, the thread the service reads on an emulator. */
@Composable
private fun FixtureLauncher() {
    val context = LocalContext.current
    val colors = KetchupTheme.colors
    Column(
        Modifier
            .fillMaxSize()
            .background(colors.cream)
            .safeDrawingPadding()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Kicker("Reader fixture")
        Text("A synthetic Instagram thread", style = KetchupTheme.type.serifTitle2, color = colors.ink)
        Text(
            "Breck Crew 🎿, made-up people, drawn the way Instagram's app draws a DM thread. With the reader " +
                "service on, the Ketchup bubble shows over it and reads it offline.",
            style = KetchupTheme.type.subheadline,
            color = colors.ink,
        )
        CapsuleButton("Open the test thread", onClick = {
            context.startActivity(Intent(context, ReaderFixtureActivity::class.java))
        })
    }
}

/**
 * The synthetic Instagram thread as the reader hands it to the brief, each
 * message as catch-up-text will see it. The button hands it to
 * BriefActivity the way the service does.
 */
@Composable
private fun InstagramThreadSample() {
    val thread = previewData().instagramThread
    val colors = KetchupTheme.colors
    val context = LocalContext.current
    Column(
        Modifier
            .fillMaxSize()
            .background(colors.cream)
            .safeDrawingPadding()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Kicker("${thread.source.appName} · ${thread.messages.size} messages read")
            Text(thread.displayTitle, style = KetchupTheme.type.serifTitle2, color = colors.ink)
        }
        CapsuleButton("Open the brief", onClick = { BriefActivity.start(context, thread) })
        LazyColumn(
            Modifier.weight(1f),
            contentPadding = PaddingValues(bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            itemsIndexed(thread.messages) { index, message ->
                val sender = message.wireSender(PreviewData.MY_NAME)
                Column(Modifier.paperCard(padding = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Kicker("$index · $sender", color = if (message.isMine) colors.ink else colors.person(sender))
                    Text(message.wireText(PreviewData.MY_NAME), style = KetchupTheme.type.subheadline, color = colors.ink)
                }
            }
        }
    }
}
