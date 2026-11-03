package com.vibetemp.ketchup.ui.brief

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.ui.design.marker
import com.vibetemp.ketchup.ui.design.paperCard
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

/**
 * What the page shows while Muse Spark reads: the chat's real messages run
 * past a small window and the mustard marker passes over each line in turn,
 * with an honest clock and how long it usually takes. Only the few lines in
 * the window are built at any moment, so a chat of any size runs the same.
 * With Reduce Motion the first lines stand still. Port of iOS AI/Skimming.swift.
 */
@Composable
fun SkimmingView(
    title: String,
    usually: String,
    lines: List<SkimLine>?,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    /** Rows in the window; the marker reads the middle one. */
    rows: Int = 5,
    titleStyle: TextStyle = KetchupTheme.type.serifTitle,
    reduceMotion: Boolean = KetchupTheme.reduceMotion,
) {
    val colors = KetchupTheme.colors
    val fontScale = LocalDensity.current.fontScale
    val rowHeight = 30.dp * fontScale
    val nameWidth = 58.dp * fontScale
    Column(
        modifier = modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) { },
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = titleStyle, color = colors.ink)
            if (subtitle != null) Text(subtitle, style = KetchupTheme.type.subheadline, color = colors.inkSoft)
        }
        Box(
            Modifier
                .paperCard(padding = 0.dp)
                .padding(horizontal = 16.dp, vertical = 10.dp)
                .height(rowHeight * rows)
                .clipToBounds()
                .clearAndSetSemantics { },
        ) {
            when {
                lines.isNullOrEmpty() -> SkimSkeleton(rows, rowHeight, nameWidth, reduceMotion)
                reduceMotion -> Column {
                    lines.take(rows).forEachIndexed { i, line ->
                        SkimRow(line, nameWidth, rowHeight, marker = if (i == 0) 1f else 0f, markerFade = 1f, fade = if (i == 0) 1f else 0.6f)
                    }
                }
                else -> Moving(lines, rows, rowHeight, nameWidth)
            }
        }
        Clock(usually)
    }
}

/** Seconds per line, and the part of that spent moving up a row. */
private const val BEAT = 0.62f
private const val LIFT = 0.2f
/** Past this, the hint stops promising and owns up. */
private const val PATIENCE = 35

/**
 * Where everything is `t` seconds in. The line being read sits in the
 * middle row while the marker sweeps across it, then the list moves up a
 * row and the next line gets read. Lines already read keep a fading trace
 * of the marker. A long list loops; one too short to fill the window reads
 * through once and stops on its last line.
 */
@Composable
private fun Moving(lines: List<SkimLine>, rows: Int, rowHeight: androidx.compose.ui.unit.Dp, nameWidth: androidx.compose.ui.unit.Dp) {
    var t by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(lines) {
        val start = withFrameNanos { it }
        while (true) withFrameNanos { t = (it - start) / 1_000_000_000f }
    }
    val loops = lines.size > rows + 1
    val reading = BEAT - LIFT
    var step = floor(t / BEAT).toInt()
    var phase = t - step * BEAT
    if (!loops && step >= lines.size - 1) {
        step = lines.size - 1
        phase = reading
    }
    val sweep = easeOut(min(phase / reading, 1f))
    val rise = easeInOut(max(0f, (phase - reading) / LIFT))
    val slot = rows / 2
    val rowPx = with(LocalDensity.current) { rowHeight.toPx() }
    Box(Modifier.fillMaxWidth()) {
        for (index in (step - slot - 1)..(step + rows - slot)) {
            if (index < 0 || (!loops && index >= lines.size)) continue
            key(index) {
                // In rows from the top of the window, and from the reading row.
                val position = (index - step + slot) - rise
                val distance = position - slot
                SkimRow(
                    lines[index % lines.size],
                    nameWidth,
                    rowHeight,
                    marker = if (index < step) 1f else if (index == step) sweep else 0f,
                    markerFade = max(0f, 1 + distance * 0.8f),
                    fade = max(0.22f, 1 - abs(distance) * 0.32f),
                    modifier = Modifier.offset { IntOffset(0, (position * rowPx).roundToInt()) },
                )
            }
        }
    }
}

@Composable
private fun SkimRow(
    line: SkimLine,
    nameWidth: androidx.compose.ui.unit.Dp,
    rowHeight: androidx.compose.ui.unit.Dp,
    marker: Float,
    markerFade: Float,
    fade: Float,
    modifier: Modifier = Modifier,
) {
    val colors = KetchupTheme.colors
    val you = stringResource(R.string.brief_you)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(rowHeight)
            .alpha(fade),
        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            if (line.isMine) you else line.name,
            modifier = Modifier.width(nameWidth),
            style = KetchupTheme.type.subheadline.copy(fontWeight = FontWeight.SemiBold),
            color = colors.nameColor(line.name, line.isMine),
            maxLines = 1,
            overflow = TextOverflow.Clip,
        )
        Text(
            line.text,
            modifier = Modifier.marker(marker, markerFade),
            style = KetchupTheme.type.subheadline,
            color = colors.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** The window before the chat's messages are here: blank lines that breathe (still with Reduce Motion). */
@Composable
private fun SkimSkeleton(rows: Int, rowHeight: androidx.compose.ui.unit.Dp, nameWidth: androidx.compose.ui.unit.Dp, reduceMotion: Boolean) {
    val colors = KetchupTheme.colors
    val loading = stringResource(R.string.brief_loading)
    val pulse by rememberInfiniteTransition(label = "skeleton").animateFloat(
        initialValue = 1f,
        targetValue = if (reduceMotion) 1f else 0.45f,
        animationSpec = infiniteRepeatable(tween(900, easing = LinearEasing), RepeatMode.Reverse),
        label = "breathe",
    )
    val shares = listOf(0.9f, 0.62f, 0.82f, 0.5f, 0.74f)
    Column(
        Modifier
            .alpha(pulse)
            .semantics { contentDescription = loading },
    ) {
        repeat(rows) { i ->
            Row(Modifier.height(rowHeight), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.width(nameWidth)) {
                    Box(Modifier.width(nameWidth * 0.7f).height(8.dp).background(colors.rule, CircleShape))
                }
                BoxWithConstraints(Modifier.weight(1f)) {
                    Box(Modifier.width(maxWidth * shares[i % shares.size]).height(8.dp).background(colors.rule, CircleShape))
                }
            }
        }
    }
}

/** "0:04  Usually about 20 seconds", then "Taking longer than usual". */
@Composable
private fun Clock(usually: String) {
    val colors = KetchupTheme.colors
    var seconds by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1000)
            seconds++
        }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        Text(
            "%d:%02d".format(seconds / 60, seconds % 60),
            style = KetchupTheme.type.monoBody.copy(fontWeight = FontWeight.SemiBold),
            color = colors.ink,
        )
        Text(
            if (seconds < PATIENCE) usually else stringResource(R.string.brief_longer),
            style = KetchupTheme.type.subheadline,
            color = colors.inkSoft,
        )
    }
}

private fun easeOut(x: Float): Float = 1 - (1 - x).pow(3)

private fun easeInOut(x: Float): Float = if (x < 0.5f) 4 * x * x * x else 1 - (-2 * x + 2).pow(3) / 2
