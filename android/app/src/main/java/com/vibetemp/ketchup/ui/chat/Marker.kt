package com.vibetemp.ketchup.ui.chat

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.translate
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * One mustard highlighter pass (iOS `MarkerStroke`): how Cetchup says "this
 * part matters" instead of a badge. [progress] draws it from the left (0 is
 * nothing, 1 the whole pass). The ends lean like a chisel tip and the edges
 * wobble a little, so it looks hand done. It inks a band from 20% to 96% of
 * its height. The chat slice's copy; the brief slice draws its own.
 */
fun markerPath(size: Size, progress: Float, density: Float): Path {
    val path = Path()
    val reach = size.width * progress.coerceIn(0f, 1f)
    if (reach <= 0.5f * density || size.height <= density) return path
    val height = size.height
    val lean = minOf(height * 0.3f, 7f * density, reach * 0.4f)
    val wobble = min(height * 0.045f, 1.4f * density)
    val top = height * 0.2f
    val bottom = height - height * 0.04f
    // A slow wave along each edge, and a one-point climb across the full width.
    fun y(base: Float, x: Float, phase: Float): Float {
        val t = x / max(size.width, 1f)
        return base + wobble * sin(t * 2f * PI.toFloat() * 1.1f + phase) - t * density
    }
    val step = 4f * density
    var x = lean
    path.moveTo(x, y(top, x, 0f))
    while (x < reach) {
        x = min(x + step, reach)
        path.lineTo(x, y(top, x, 0f))
    }
    // The leading end slants back to the bottom edge, then right to left.
    x = reach - lean
    path.lineTo(x, y(bottom, x, 2.1f))
    while (x > 0f) {
        x = max(x - step, 0f)
        path.lineTo(x, y(bottom, x, 2.1f))
    }
    path.close()
    return path
}

/** Draws the marker over [size] at [topLeft] in this scope. */
fun DrawScope.drawMarker(color: Color, progress: Float = 1f, topLeft: Offset = Offset.Zero, size: Size = this.size) {
    val path = markerPath(size, progress, density)
    translate(topLeft.x, topLeft.y) { drawPath(path, color) }
}
