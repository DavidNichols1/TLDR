package com.vibetemp.ketchup.debug

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.paperCard
import com.vibetemp.ketchup.ui.design.pressable
import com.vibetemp.ketchup.ui.theme.KetchupTheme

/**
 * Offline preview mode, debug builds only (iOS `-screen`):
 *
 *     adb shell am start -n com.vibetemp.ketchup/.MainActivity --es screen <name>
 *
 * opens one screen on fixture data: no sign-in, no network, no Muse Spark
 * calls (MainActivity turns on `Previewing`, so the client refuses to send).
 * `list`, or a name that isn't a screen, shows every name; tap one to open it.
 *
 * The names come from one file per slice, each a map from name to screen:
 * ChatPreviews.kt (chat), BriefPreviews.kt (brief), ReaderPreviews.kt
 * (reader), plus DesignPreviews.kt (the shared design system). Fixtures:
 * PreviewData.kt over src/debug/assets/fixtures/.
 */
object PreviewHost {
    const val EXTRA_SCREEN = "screen"
    const val AVAILABLE = true

    /** Every screen, in the order the index shows them. */
    val screens: Map<String, @Composable () -> Unit> by lazy {
        val maps = listOf(DesignPreviews, ChatPreviews, BriefPreviews, ReaderPreviews)
        val clash = maps.flatMap { it.keys }.groupBy { it }.filterValues { it.size > 1 }.keys
        check(clash.isEmpty()) { "Two preview files use the same name: $clash" }
        maps.fold(emptyMap()) { all, map -> all + map }
    }

    @Composable
    fun Screen(name: String) {
        var open by remember(name) { mutableStateOf(name) }
        val screen = screens[open]
        key(open) {
            if (screen != null) screen() else PreviewIndex(unknown = open.takeIf { it != "list" }) { open = it }
        }
    }
}

/** The list of names. Tapping one opens it. */
@Composable
private fun PreviewIndex(unknown: String?, open: (String) -> Unit) {
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
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Kicker("Offline preview")
            Text("Pick a screen", style = KetchupTheme.type.serifLargeTitle, color = colors.ink)
            if (unknown != null) {
                Text("There's no screen called \"$unknown\".", style = KetchupTheme.type.subheadline, color = colors.inkSoft)
            }
        }
        Column(Modifier.paperCard(padding = 14.dp)) {
            val names = PreviewHost.screens.keys.toList()
            names.forEach { name ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .pressable { open(name) }
                        .padding(vertical = 12.dp),
                ) {
                    Text(name, style = KetchupTheme.type.monoBody, color = colors.ink)
                }
                if (name != names.last()) HorizontalDivider(color = colors.rule)
            }
        }
        Text(
            "Launch with: adb shell am start -n com.vibetemp.ketchup/.MainActivity --es screen <name>",
            style = KetchupTheme.type.footnote,
            color = colors.inkSoft,
        )
    }
}
