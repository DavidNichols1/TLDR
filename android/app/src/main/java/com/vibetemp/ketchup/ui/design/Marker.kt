package com.vibetemp.ketchup.ui.design

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.ui.theme.KetchupColors
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.Motion
import kotlinx.coroutines.delay
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// The mustard highlighter: how Cetchup says "this part matters to you" (a
// time, an amount, your name) instead of bold color or a badge. Port of iOS
// Design/Marker.swift.

/**
 * One highlighter pass, to fill behind text (iOS `MarkerStroke`). [progress]
 * draws it from the left (0 is nothing, 1 the whole pass). The ends lean
 * like a chisel tip and the edges wobble a little, so it looks hand done.
 * [unit] is pixels per dp, for the fixed sizes (the lean, the wobble).
 */
object MarkerStroke {
    fun path(rect: Rect, progress: Float, unit: Float): Path {
        val path = Path()
        val reach = rect.width * progress.coerceIn(0f, 1f)
        if (reach <= 0.5f * unit || rect.height <= unit) return path
        val height = rect.height
        val lean = min(min(height * 0.3f, 7f * unit), reach * 0.4f)
        val wobble = min(height * 0.045f, 1.4f * unit)
        val top = rect.top + height * 0.2f
        val bottom = rect.bottom - height * 0.04f

        // A slow wave along each edge, and a 1 dp climb across the full width.
        fun edge(y: Float, x: Float, phase: Float): Float {
            val t = (x - rect.left) / max(rect.width, 1f)
            return y + wobble * sin(t * 2f * PI.toFloat() * 1.1f + phase) - t * unit
        }
        val step = 4f * unit

        // Top edge, left to right, starting `lean` in from the left end.
        var x = rect.left + lean
        path.moveTo(x, edge(top, x, 0f))
        val end = rect.left + reach
        while (x < end) {
            x = min(x + step, end)
            path.lineTo(x, edge(top, x, 0f))
        }
        // The leading end slants back to the bottom edge, then right to left.
        x = end - lean
        path.lineTo(x, edge(bottom, x, 2.1f))
        while (x > rect.left) {
            x = max(x - step, rect.left)
            path.lineTo(x, edge(bottom, x, 2.1f))
        }
        path.close()
        return path
    }
}

/** The marker's paint: mustard, dropped to 45% in dark mode so light ink stays readable on it. */
fun KetchupColors.marker(fade: Float = 1f): Color = mustard.copy(alpha = (if (isDark) 0.45f else 0.85f) * fade)

/**
 * The marker behind this whole element: a short phrase on one line, an
 * amount. [progress] is how much of it is drawn (animate it for a sweep).
 */
@Composable
fun Modifier.marker(progress: Float, fade: Float = 1f): Modifier {
    val color = KetchupTheme.colors.marker(fade)
    return drawBehind {
        if (progress <= 0f) return@drawBehind
        val unit = 1.dp.toPx()
        val rect = Rect(-4f * unit, 0f, size.width + 4f * unit, size.height)
        drawPath(MarkerStroke.path(rect, progress, unit), color)
    }
}

/**
 * How far a marker has drawn: 1 at once, or a sweep from 0 when [sweep] is
 * on, after [delayMillis]. With Reduce Motion it simply appears. Turning
 * [isOn] off takes it away.
 */
@Composable
fun markerProgress(isOn: Boolean = true, sweep: Boolean = false, delayMillis: Int = 0): Float {
    val reduceMotion = KetchupTheme.reduceMotion
    val progress = remember { Animatable(if (isOn && (!sweep || reduceMotion)) 1f else 0f) }
    LaunchedEffect(isOn) {
        val target = if (isOn) 1f else 0f
        if (progress.value == target) return@LaunchedEffect
        when {
            reduceMotion || (isOn && !sweep) -> progress.snapTo(target)
            isOn -> {
                delay(delayMillis.toLong())
                progress.animateTo(1f, Motion.sweep())
            }
            else -> progress.animateTo(0f, Motion.snappy())
        }
    }
    return progress.value
}

/**
 * A sentence with the marker behind some of its words ([marks], ranges into
 * [text]), following them as they wrap: the times and money in a gist, the
 * reader's name in a question (iOS `markRuns`). With [sweep] the marks draw
 * on once, after [delayMillis]; with Reduce Motion they simply appear.
 */
@Composable
fun MarkedText(
    text: AnnotatedString,
    marks: List<IntRange>,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    sweep: Boolean = false,
    delayMillis: Int = 0,
    maxLines: Int = Int.MAX_VALUE,
    inlineContent: Map<String, InlineTextContent> = emptyMap(),
) {
    val progress = markerProgress(isOn = true, sweep = sweep, delayMillis = delayMillis)
    var layout by remember { mutableStateOf<TextLayoutResult?>(null) }
    val paint = KetchupTheme.colors.marker()
    Text(
        text = text,
        style = style,
        color = color,
        maxLines = maxLines,
        overflow = TextOverflow.Ellipsis,
        inlineContent = inlineContent,
        onTextLayout = { layout = it },
        modifier = modifier.drawBehind {
            val result = layout ?: return@drawBehind
            if (progress <= 0f || marks.isEmpty()) return@drawBehind
            val unit = 1.dp.toPx()
            for (rect in markRects(result, marks, style.fontSize.toPx())) {
                drawPath(MarkerStroke.path(rect.inflateWidth(3f * unit), progress, unit), paint)
            }
        },
    )
}

/** A sentence and its marks as plain strings, for the common case. */
@Composable
fun MarkedText(
    text: String,
    marks: List<IntRange>,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    sweep: Boolean = false,
    delayMillis: Int = 0,
) = MarkedText(AnnotatedString(text), marks, style, color, modifier, sweep, delayMillis)

/**
 * The boxes the marker fills for [marks], one per line a mark runs across:
 * from just under the cap height to just below the baseline, like iOS's
 * typographic bounds.
 */
internal fun markRects(layout: TextLayoutResult, marks: List<IntRange>, fontSizePx: Float): List<Rect> {
    val rects = mutableListOf<Rect>()
    val length = layout.layoutInput.text.length
    for (mark in marks) {
        val first = mark.first.coerceIn(0, length)
        val last = mark.last.coerceIn(0, length - 1)
        if (last < first) continue
        val startLine = layout.getLineForOffset(first)
        val endLine = layout.getLineForOffset(last)
        for (line in startLine..endLine) {
            if (line >= layout.lineCount) break
            val s = if (line == startLine) first else layout.getLineStart(line)
            var e = if (line == endLine) last else layout.getLineEnd(line, visibleEnd = true) - 1
            if (e < s) continue
            // Don't mark the space a line wraps on.
            while (e > s && layout.layoutInput.text[e].isWhitespace()) e--
            val left = layout.getBoundingBox(s).left
            val right = layout.getBoundingBox(e).right
            val baseline = layout.getLineBaseline(line)
            rects += Rect(min(left, right), baseline - fontSizePx * 0.92f, max(left, right), baseline + fontSizePx * 0.26f)
        }
    }
    return rects
}

private fun Rect.inflateWidth(by: Float) = Rect(left - by, top, right + by, bottom)
