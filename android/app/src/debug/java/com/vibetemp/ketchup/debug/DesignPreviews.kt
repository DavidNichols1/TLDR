package com.vibetemp.ketchup.debug

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.ui.design.ButtonFill
import com.vibetemp.ketchup.ui.design.CapsuleButton
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.KetchupDrop
import com.vibetemp.ketchup.ui.design.Monogram
import com.vibetemp.ketchup.ui.design.SectionTitle
import com.vibetemp.ketchup.ui.design.Wordmark
import com.vibetemp.ketchup.ui.design.paperCard
import com.vibetemp.ketchup.ui.theme.KetchupTheme

// The shared design system, live (iOS `-screen design`). Shared: change it
// with the theme, not from a slice.

val DesignPreviews: Map<String, @Composable () -> Unit> = mapOf(
    "design" to { DesignGallery() },
)

@Composable
private fun DesignGallery() {
    val colors = KetchupTheme.colors
    Column(
        Modifier
            .fillMaxSize()
            .background(colors.cream)
            .safeDrawingPadding()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Kicker("Design system")
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            KetchupDrop(size = 64.dp)
            Wordmark(drawIn = true)
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            listOf(16, 24, 40, 96).forEach { KetchupDrop(size = it.dp) }
        }
        SectionTitle("Buttons", count = 4)
        CapsuleButton("Catch me up", onClick = {})
        CapsuleButton("Ask the chat", onClick = {}, fill = ButtonFill.Ink)
        CapsuleButton("Not now", onClick = {}, fill = ButtonFill.Outline)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CapsuleButton("Add to calendar", onClick = {}, compact = true)
            CapsuleButton("Try again", onClick = {}, fill = ButtonFill.Outline, compact = true)
        }
        SectionTitle("People", count = 6)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("David", "Maya", "Jordan", "Priya", "Sam", "Theo").forEach { Monogram(it) }
        }
        SectionTitle("Paper")
        Column(Modifier.paperCard(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Kicker("For you")
            Text("Confirm with Priya by Thursday noon", style = KetchupTheme.type.serifTitle3, color = colors.ink)
            Text("Hearthstone needs a final headcount or they drop the table to 4.", style = KetchupTheme.type.subheadline, color = colors.inkSoft)
        }
        SectionTitle("Colors")
        val swatches = listOf(
            "cream" to colors.cream, "card" to colors.card, "rule" to colors.rule, "ink" to colors.ink,
            "inkSoft" to colors.inkSoft, "ketchup" to colors.ketchup, "mustard" to colors.mustard, "pickle" to colors.pickle,
        )
        swatches.chunked(4).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { (name, color) -> Swatch(name, color) }
            }
        }
    }
}

@Composable
private fun Swatch(name: String, color: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(
            Modifier
                .size(56.dp)
                .background(color, RoundedCornerShape(12.dp))
                .border(1.dp, KetchupTheme.colors.rule, RoundedCornerShape(12.dp)),
        )
        Text(name, style = KetchupTheme.type.monoCaption2, color = KetchupTheme.colors.inkSoft)
    }
}
