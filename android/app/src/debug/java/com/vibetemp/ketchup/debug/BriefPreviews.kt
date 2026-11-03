package com.vibetemp.ketchup.debug

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.SectionTitle
import com.vibetemp.ketchup.ui.design.paperCard
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.person

// The brief slice's preview screens (catch-up, ask, loading, errors, ...).
// Add a name and its screen to the map; the index picks it up. Names start
// with "brief-".

val BriefPreviews: Map<String, @Composable () -> Unit> = mapOf(
    "brief-breck" to { BreckBriefSample() },
)

/** A starting point: Muse Spark's real brief of Breck, the gist and highlights, each with its first source. */
@Composable
private fun BreckBriefSample() {
    val data = previewData()
    val brief = data.brief
    val result = brief.result ?: return
    val colors = KetchupTheme.colors
    Column(
        Modifier
            .fillMaxSize()
            .background(colors.cream)
            .safeDrawingPadding()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Kicker("Read by Muse Spark · ${brief.messageCount} messages · ${(brief.latencyMs ?: 0) / 1000} s")
        Text(data.breck.name, style = KetchupTheme.type.serifTitle, color = colors.ink)
        Text(result.tldr, style = KetchupTheme.type.serifTitle3.copy(fontWeight = FontWeight.Normal), color = colors.ink)
        SectionTitle("Highlights", count = result.highlights.size)
        result.highlights.forEach { item ->
            val source = item.refs.firstNotNullOfOrNull { ref -> data.messages.firstOrNull { it.id == ref } }
            Column(Modifier.paperCard(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(item.text, style = KetchupTheme.type.body, color = colors.ink)
                if (source != null) {
                    val name = data.senderName(source)
                    Text(
                        "$name: ${source.body}",
                        style = KetchupTheme.type.footnote,
                        color = colors.person(name),
                        maxLines = 1,
                    )
                }
            }
        }
        SectionTitle("Plans", count = result.plans.size)
    }
}
