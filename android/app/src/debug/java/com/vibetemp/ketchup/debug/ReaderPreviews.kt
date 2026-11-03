package com.vibetemp.ketchup.debug

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.ui.brief.BriefActivity
import com.vibetemp.ketchup.ui.design.CapsuleButton
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.paperCard
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.person

// The reader slice's preview screens (the trigger, reading, errors, ...).
// Add a name and its screen to the map; the index picks it up. Names start
// with "reader-".

val ReaderPreviews: Map<String, @Composable () -> Unit> = mapOf(
    "reader-instagram" to { InstagramThreadSample() },
)

/**
 * A starting point: the synthetic Instagram thread as the reader would hand
 * it to the brief, each message as catch-up-text will see it. The button
 * hands it to BriefActivity the way the service will.
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
