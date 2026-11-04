package com.vibetemp.ketchup.ui.design

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.Motion
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.sin

/**
 * A wavy line, like a squirt of mustard: under the wordmark, or as a quiet
 * divider. The humps swell in the middle and trail off at the ends (iOS
 * `Squiggle`). An open path: stroke it with round caps.
 */
fun squigglePath(size: Size, waves: Int = 6): Path {
    val count = max(waves, 1)
    val width = size.width / count
    val mid = size.height / 2
    return Path().apply {
        moveTo(0f, mid)
        for (i in 0 until count) {
            val x = i * width
            val swell = sin(PI * (i + 0.5) / count).toFloat()
            val height = size.height / 2 * (0.55f + 0.45f * swell)
            // Handles at 4/3 of the height put the hump's peak at `height`.
            val lift = (if (i % 2 == 0) -1 else 1) * height * 4 / 3
            cubicTo(x + width / 3, mid + lift, x + width * 2 / 3, mid + lift, x + width, mid)
        }
    }
}

/**
 * "Cetchup" in serif black italic with the mustard squiggle under it. A
 * fixed size on purpose: it's a logo, so it doesn't follow the font scale.
 * [drawIn] draws the squiggle the first time it appears (it is simply there
 * with Reduce Motion on).
 */
@Composable
fun Wordmark(modifier: Modifier = Modifier, size: Dp = 44.dp, drawIn: Boolean = false) {
    val colors = KetchupTheme.colors
    val reduceMotion = KetchupTheme.reduceMotion
    val drawn = remember { Animatable(if (drawIn && !reduceMotion) 0f else 1f) }
    LaunchedEffect(Unit) {
        if (drawn.value < 1f) drawn.animateTo(1f, Motion.squirt(delayMillis = 250))
    }
    val density = LocalDensity.current
    val fontSize = with(density) { (size.toPx() / density.density / density.fontScale).sp }
    Box(
        modifier.clearAndSetSemantics {
            contentDescription = "Cetchup"
            heading()
        },
    ) {
        Text(
            text = "Cetchup",
            modifier = Modifier.padding(bottom = size * 0.2f),
            style = TextStyle(
                fontFamily = FontFamily.Serif,
                fontWeight = FontWeight.Black,
                fontStyle = FontStyle.Italic,
                fontSize = fontSize,
                lineHeight = fontSize * 1.15f,
                letterSpacing = fontSize * -0.025f,
                color = colors.ketchup,
            ),
        )
        // The squirt sits in a band along the bottom, inset a little more on the right.
        Canvas(Modifier.matchParentSize()) {
            val band = size.toPx() * 0.16f
            val left = size.toPx() * 0.04f
            val right = size.toPx() * 0.1f
            val path = squigglePath(Size(this.size.width - left - right, band))
            val measure = PathMeasure().apply { setPath(path, false) }
            val part = Path()
            measure.getSegment(0f, measure.length * drawn.value, part, true)
            translate(left, this.size.height - band) {
                drawPath(
                    part,
                    colors.mustard,
                    style = Stroke(width = max(2.dp.toPx(), size.toPx() * 0.07f), cap = StrokeCap.Round, join = StrokeJoin.Round),
                )
            }
        }
    }
}
