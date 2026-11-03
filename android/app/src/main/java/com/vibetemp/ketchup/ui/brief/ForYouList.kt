package com.vibetemp.ketchup.ui.brief

import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.CatchUp
import com.vibetemp.ketchup.ui.design.paperCard
import com.vibetemp.ketchup.ui.design.pressable
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.Motion

/**
 * "For you": the reader's to-dos as a checklist on one card. Tapping the
 * circle checks one off (a pickle check, a pen stroke through the words);
 * that lives only on this page. Tapping the words opens where it was said.
 * Port of iOS AI/ForYouList.swift.
 */
@Composable
fun ForYouList(items: List<CatchUp.Item>, refs: RefContext, modifier: Modifier = Modifier, initiallyDone: Set<Int> = emptySet()) {
    var done by rememberSaveable { mutableStateOf(initiallyDone.toList()) }
    val colors = KetchupTheme.colors
    Column(modifier.paperCard(padding = 0.dp)) {
        items.forEachIndexed { i, item ->
            if (i > 0) HorizontalDivider(Modifier.padding(start = 54.dp), thickness = 1.dp, color = colors.rule)
            ToDoRow(item, isDone = i in done, refs = refs) { done = if (i in done) done - i else done + i }
        }
    }
}

@Composable
private fun ToDoRow(item: CatchUp.Item, isDone: Boolean, refs: RefContext, toggle: () -> Unit) {
    val colors = KetchupTheme.colors
    val view = LocalView.current
    val stateText = stringResource(if (isDone) R.string.brief_to_do_done else R.string.brief_to_do_open)
    val showWhere = stringResource(R.string.brief_show_where)
    Row(
        Modifier
            .fillMaxWidth()
            .padding(start = 6.dp, end = 16.dp, top = 14.dp, bottom = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.Top,
    ) {
        // A 44 dp target around the 24 dp ring, nudged up so the ring sits on the first line.
        Box(
            Modifier
                .offset(y = (-10).dp)
                .size(44.dp)
                .toggleable(value = isDone, role = Role.Checkbox, interactionSource = null, indication = null) {
                    view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                    toggle()
                }
                .semantics {
                    contentDescription = item.text
                    stateDescription = stateText
                },
            contentAlignment = Alignment.Center,
        ) { Check(isDone) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            StruckText(
                item.text,
                struck = isDone,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = showWhere }
                    .pressable(enabled = item.refs.isNotEmpty()) { item.refs.firstOrNull()?.let { refs.open(it, item.refs) } },
            )
            RefChips(item.refs, refs, Modifier.dimmed(isDone))
        }
    }
}

/** An empty ring, or a pickle dot with a check that pops in. */
@Composable
private fun Check(isDone: Boolean) {
    val colors = KetchupTheme.colors
    val reduceMotion = KetchupTheme.reduceMotion
    val fill by animateFloatAsState(if (isDone) 1f else 0f, if (reduceMotion) Motion.fade() else Motion.lively(), label = "check")
    Canvas(Modifier.size(24.dp)) {
        val r = size.minDimension / 2
        val ring = 1.5.dp.toPx()
        drawCircle(if (isDone) colors.pickle else colors.inkSoft, radius = r - ring / 2, style = Stroke(ring))
        if (fill > 0f) {
            val scale = 0.3f + 0.7f * fill
            drawCircle(colors.pickle.copy(alpha = fill.coerceIn(0f, 1f)), radius = r * scale)
            val s = size.minDimension
            val tick = Path().apply {
                moveTo(s * 0.29f, s * 0.52f)
                lineTo(s * 0.44f, s * 0.66f)
                lineTo(s * 0.72f, s * 0.36f)
            }
            scale(0.4f + 0.6f * fill, Offset(s / 2, s / 2)) {
                drawPath(tick, colors.card.copy(alpha = fill.coerceIn(0f, 1f)), style = Stroke(s * 0.1f, cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
        }
    }
}

/**
 * A to-do's words with a pen stroke through them once it's done, drawn left
 * to right across each line in turn (iOS `.struck()`). Quick and plain with
 * Reduce Motion.
 */
@Composable
private fun StruckText(text: String, struck: Boolean, modifier: Modifier = Modifier) {
    val colors = KetchupTheme.colors
    val reduceMotion = KetchupTheme.reduceMotion
    val progress = remember { Animatable(if (struck) 1f else 0f) }
    LaunchedEffect(struck) {
        val target = if (struck) 1f else 0f
        progress.animateTo(target, if (reduceMotion) Motion.fade() else if (struck) Motion.sweep() else Motion.snappy())
    }
    var layout by remember { mutableStateOf<TextLayoutResult?>(null) }
    val stroke = with(LocalDensity.current) { 1.6.dp.toPx() }
    val style = KetchupTheme.type.body
    val fontPx = with(LocalDensity.current) { style.fontSize.toPx() }
    Text(
        text,
        style = style,
        color = if (struck) colors.inkSoft else colors.ink,
        onTextLayout = { layout = it },
        modifier = modifier.drawWithContent {
            drawContent()
            val result = layout ?: return@drawWithContent
            if (progress.value <= 0f) return@drawWithContent
            val widths = (0 until result.lineCount).map { result.getLineRight(it) - result.getLineLeft(it) }
            var left = widths.sum() * progress.value
            for (line in 0 until result.lineCount) {
                val length = minOf(widths[line], left)
                left -= widths[line]
                if (length <= 0.5f) continue
                // Through the middle of the lowercase letters.
                val y = result.getLineBaseline(line) - fontPx * 0.3f
                val x = result.getLineLeft(line)
                drawLine(colors.inkSoft, Offset(x - 1f, y), Offset(x + length + 1f, y), stroke, StrokeCap.Round)
            }
        },
    )
}
