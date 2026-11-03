package com.vibetemp.ketchup.debug

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.Monogram
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.person

// The chat slice's preview screens (sign-in, inbox, thread, ...). Add a
// name and its screen to the map; the index picks it up.

val ChatPreviews: Map<String, @Composable () -> Unit> = mapOf(
    "chat-breck" to { BreckThreadSample() },
)

/** A starting point: the end of the Breck thread on fixtures, plain bubbles on cream. */
@Composable
private fun BreckThreadSample() {
    val data = previewData()
    val colors = KetchupTheme.colors
    Column(
        Modifier
            .fillMaxSize()
            .background(colors.cream)
            .safeDrawingPadding(),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(data.breck.name, style = KetchupTheme.type.serifTitle3, color = colors.ink)
                Kicker("${data.breck.memberCount} people · ${data.breck.unreadCount} new")
            }
        }
        HorizontalDivider(color = colors.rule)
        LazyColumn(
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            items(data.messages.takeLast(24), key = { it.id }) { message ->
                val mine = message.sender == PreviewData.ME
                val name = data.senderName(message)
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start,
                    verticalAlignment = Alignment.Bottom,
                ) {
                    if (!mine) {
                        Monogram(name, size = 28.dp)
                        Box(Modifier.padding(start = 6.dp))
                    }
                    Column(
                        Modifier
                            .widthIn(max = 280.dp)
                            .then(
                                if (mine) Modifier.background(colors.ink, RoundedCornerShape(18.dp))
                                else Modifier
                                    .background(colors.card, RoundedCornerShape(18.dp))
                                    .border(1.dp, colors.rule, RoundedCornerShape(18.dp)),
                            )
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                    ) {
                        if (!mine) Text(name, style = KetchupTheme.type.caption, color = colors.person(name))
                        Text(message.body, style = KetchupTheme.type.body, color = if (mine) colors.onInk else colors.ink)
                    }
                }
            }
        }
    }
}
