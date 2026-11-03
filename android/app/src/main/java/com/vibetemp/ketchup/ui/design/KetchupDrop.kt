package com.vibetemp.ketchup.ui.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import kotlin.math.min

/**
 * The logo shape: a ketchup drop that is also a chat bubble. A teardrop,
 * point up, with a speech-bubble tail at the lower left. Drawn in a unit
 * square with cubic curves only (iOS `KetchupDrop`), centered in whatever
 * size it gets. Reads from 16 dp up. Usable as a clip or background shape.
 */
object KetchupDropShape : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline =
        Outline.Generic(dropPath(size))

    /** The drop in [size], keeping its proportions. */
    fun dropPath(size: Size): Path {
        val side = min(size.width, size.height)
        val x0 = (size.width - side) / 2
        val y0 = (size.height - side) / 2
        fun x(u: Float) = x0 + u * side
        fun y(v: Float) = y0 + v * side
        // The bulb is a circle centered at (0.53, 0.60) with radius 0.34.
        return Path().apply {
            moveTo(x(0.53f), y(0.035f))
            // Right flank, tip to the widest point.
            cubicTo(x(0.625f), y(0.185f), x(0.87f), y(0.37f), x(0.87f), y(0.60f))
            // Bulb, lower right quarter.
            cubicTo(x(0.87f), y(0.788f), x(0.718f), y(0.94f), x(0.53f), y(0.94f))
            // Tail: the bottom runs on past the bulb to a point at the lower left...
            cubicTo(x(0.40f), y(0.94f), x(0.26f), y(0.945f), x(0.17f), y(0.955f))
            // ...and the back of the tail curves up into the bulb's side.
            cubicTo(x(0.215f), y(0.925f), x(0.276f), y(0.839f), x(0.236f), y(0.77f))
            // Bulb, left side up to the widest point.
            cubicTo(x(0.206f), y(0.718f), x(0.19f), y(0.66f), x(0.19f), y(0.60f))
            // Left flank back to the tip.
            cubicTo(x(0.19f), y(0.37f), x(0.435f), y(0.185f), x(0.53f), y(0.035f))
            close()
        }
    }

    /** The highlight for big drops: a short curved stroke inside the bulb's upper left. */
    fun shinePath(size: Size): Path {
        val side = min(size.width, size.height)
        val x0 = (size.width - side) / 2
        val y0 = (size.height - side) / 2
        return Path().apply {
            moveTo(x0 + 0.392f * side, y0 + 0.403f * side)
            cubicTo(x0 + 0.334f * side, y0 + 0.444f * side, x0 + 0.297f * side, y0 + 0.508f * side, x0 + 0.291f * side, y0 + 0.579f * side)
        }
    }
}

/**
 * The logo, filled with ketchup. [shine] adds the highlight (skip it below
 * about 40 dp). Decorative: TalkBack skips it.
 */
@Composable
fun KetchupDrop(
    modifier: Modifier = Modifier,
    size: Dp = 24.dp,
    color: Color = KetchupTheme.colors.ketchup,
    shine: Boolean = size >= 40.dp,
) {
    val shineColor = KetchupTheme.colors.onKetchup
    Canvas(modifier.size(size).clearAndSetSemantics { }) {
        drawPath(KetchupDropShape.dropPath(this.size), color)
        if (shine) {
            val side = min(this.size.width, this.size.height)
            drawPath(KetchupDropShape.shinePath(this.size), shineColor, style = Stroke(width = side * 0.07f, cap = StrokeCap.Round))
        }
    }
}
