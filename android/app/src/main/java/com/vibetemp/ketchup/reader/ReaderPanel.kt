package com.vibetemp.ketchup.reader

import androidx.annotation.StringRes
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.TextSource
import com.vibetemp.ketchup.ui.design.ButtonFill
import com.vibetemp.ketchup.ui.design.CapsuleButton
import com.vibetemp.ketchup.ui.design.KetchupDrop
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.pressable
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.Motion

/** What the panel over the other app shows. */
sealed interface PanelState {
    /** Last 30, 80 or 120. */
    data object Pick : PanelState

    data class Reading(val progress: ReadProgress) : PanelState

    /** No Ketchup session: sign in first. */
    data object SignIn : PanelState

    /** The service is on but nobody agreed to the consent screen yet. */
    data object Setup : PanelState

    data class Problem(@param:StringRes val message: Int, val last: Int?) : PanelState

    /** Snapchat didn't say which run is the reader's: they pick their name (most messages first), or none. */
    data class WhoAreYou(val names: List<String>) : PanelState
}

/** The floating bubble: a ketchup circle with the drop, over the thread. */
@Composable
fun ReaderBubble(modifier: Modifier = Modifier) {
    val colors = KetchupTheme.colors
    val label = stringResource(R.string.reader_bubble_label)
    Box(
        modifier
            .size(BUBBLE_DP.dp)
            .background(colors.ketchup, CircleShape)
            .border(1.dp, colors.onKetchup.copy(alpha = 0.35f), CircleShape)
            .clearAndSetSemantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        KetchupDrop(size = 28.dp, color = colors.onKetchup, shine = false)
    }
}

/** The bubble's size, for placing its window. */
const val BUBBLE_DP = 56

/**
 * The panel the bubble opens. [onPick] reads the newest 30, 80 or 120
 * messages; [onStop] stops a read; [onOpenApp] opens Ketchup (to sign in
 * or to finish setting up).
 */
@Composable
fun ReaderPanel(
    state: PanelState,
    source: TextSource,
    onPick: (Int) -> Unit,
    onStop: () -> Unit,
    onClose: () -> Unit,
    onOpenApp: () -> Unit,
    modifier: Modifier = Modifier,
    onWho: (String?) -> Unit = {},
) {
    val colors = KetchupTheme.colors
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier
            .widthIn(max = 360.dp)
            .fillMaxWidth()
            .background(colors.card, shape)
            .border(1.dp, colors.rule, shape)
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            KetchupDrop(size = 22.dp)
            Column(Modifier.weight(1f)) {
                Kicker(stringResource(R.string.reader_panel_kicker, source.appName))
                Text(
                    stringResource(titleFor(state)),
                    style = KetchupTheme.type.serifHeadline,
                    color = colors.ink,
                    modifier = Modifier.semantics { heading() },
                )
            }
            if (state !is PanelState.Reading) {
                val close = stringResource(R.string.reader_panel_close)
                Box(
                    Modifier
                        .size(36.dp)
                        .pressable(onClick = onClose)
                        .clearAndSetSemantics { contentDescription = close },
                    contentAlignment = Alignment.Center,
                ) {
                    Text("×", style = KetchupTheme.type.serifTitle3, color = colors.inkSoft)
                }
            }
        }
        when (state) {
            PanelState.Pick -> {
                Body(stringResource(R.string.reader_panel_pick_body))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ThreadReader.WINDOWS.forEach { n ->
                        CapsuleButton(
                            stringResource(R.string.reader_panel_last, n),
                            onClick = { onPick(n) },
                            modifier = Modifier.weight(1f),
                            fill = ButtonFill.Ink,
                            compact = true,
                        )
                    }
                }
                Note(stringResource(R.string.reader_panel_pick_note))
            }
            is PanelState.Reading -> {
                val p = state.progress
                Text(
                    stringResource(R.string.reader_panel_progress, p.found, p.wanted),
                    style = KetchupTheme.type.monoFootnote,
                    color = colors.ink,
                    modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                )
                ProgressLine(if (p.wanted == 0) 0f else p.found.toFloat() / p.wanted)
                Note(stringResource(if (p.restoring) R.string.reader_panel_restoring else R.string.reader_panel_scrolling))
                CapsuleButton(stringResource(R.string.reader_panel_stop), onClick = onStop, fill = ButtonFill.Outline, compact = true)
            }
            PanelState.SignIn -> {
                Body(stringResource(R.string.reader_panel_signin_body))
                CapsuleButton(stringResource(R.string.reader_panel_open_app), onClick = onOpenApp, compact = true)
            }
            PanelState.Setup -> {
                Body(stringResource(R.string.reader_panel_setup_body))
                CapsuleButton(stringResource(R.string.reader_panel_open_app), onClick = onOpenApp, compact = true)
            }
            is PanelState.WhoAreYou -> {
                Body(stringResource(R.string.reader_panel_who_body))
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    state.names.take(MAX_NAMES).forEach { name ->
                        CapsuleButton(name, onClick = { onWho(name) }, fill = ButtonFill.Ink, compact = true)
                    }
                    CapsuleButton(stringResource(R.string.reader_panel_who_none), onClick = { onWho(null) }, fill = ButtonFill.Outline, compact = true)
                }
            }
            is PanelState.Problem -> {
                Body(stringResource(state.message))
                Note(stringResource(R.string.reader_panel_nothing_kept))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    state.last?.let { last ->
                        CapsuleButton(stringResource(R.string.reader_panel_try_again), onClick = { onPick(last) }, fill = ButtonFill.Ink, compact = true)
                    }
                    CapsuleButton(stringResource(R.string.reader_panel_close), onClick = onClose, fill = ButtonFill.Outline, compact = true)
                }
            }
        }
    }
}

@StringRes
private fun titleFor(state: PanelState): Int = when (state) {
    PanelState.Pick -> R.string.reader_panel_pick_title
    is PanelState.Reading -> R.string.reader_panel_reading_title
    PanelState.SignIn -> R.string.reader_panel_signin_title
    PanelState.Setup -> R.string.reader_panel_setup_title
    is PanelState.Problem -> R.string.reader_panel_problem_title
    is PanelState.WhoAreYou -> R.string.reader_panel_who_title
}

/** The most names "Which one is you?" offers (the people with the most messages). */
private const val MAX_NAMES = 6

@Composable
private fun Body(text: String) {
    Text(text, style = KetchupTheme.type.subheadline, color = KetchupTheme.colors.ink)
}

@Composable
private fun Note(text: String) {
    Text(text, style = KetchupTheme.type.footnote, color = KetchupTheme.colors.inkSoft)
}

/** A thin ketchup line filling up as messages are read. */
@Composable
private fun ProgressLine(fraction: Float) {
    val colors = KetchupTheme.colors
    val shown by animateFloatAsState(
        fraction.coerceIn(0f, 1f),
        if (KetchupTheme.reduceMotion) Motion.fade() else Motion.settle(),
        label = "progress",
    )
    Box(
        Modifier
            .fillMaxWidth()
            .height(6.dp)
            .background(colors.rule, CircleShape)
            .semantics { progressBarRangeInfo = ProgressBarRangeInfo(fraction.coerceIn(0f, 1f), 0f..1f) },
    ) {
        Box(
            Modifier
                .fillMaxHeight()
                .fillMaxWidth(shown)
                .background(colors.ketchup, CircleShape),
        )
    }
}
