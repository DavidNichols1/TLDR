package com.vibetemp.ketchup.ui.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// Money as a diner check: small rounded top corners and a zigzag bottom, as
// if torn off the pad. Port of iOS Design/Paper.swift (`ReceiptShape`,
// `receiptCard()`).

/** A diner check's outline: rounded top corners, a torn zigzag bottom edge. */
object ReceiptShape : Shape {
    /** How deep the teeth cut, for padding content clear of them. */
    val toothDepth: Dp = 6.dp
    private val toothWidth = 12.dp
    private val cornerRadius = 6.dp

    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val path = Path()
        val depth = with(density) { toothDepth.toPx() }
        val w = size.width
        val h = size.height
        if (w <= 0f || h <= depth) return Outline.Generic(path)
        val k = 0.5523f
        val c = max(0f, min(with(density) { cornerRadius.toPx() }, min(w / 2, (h - depth) / 2)))
        val corner = c * (1 - k)
        val teeth = max(1, (w / with(density) { toothWidth.toPx() }).roundToInt())
        val tooth = w / teeth
        path.moveTo(c, 0f)
        path.lineTo(w - c, 0f)
        path.cubicTo(w - corner, 0f, w, corner, w, c)
        path.lineTo(w, h - depth)
        // The torn edge, right to left: down to each tooth's point, back up.
        for (i in 0 until teeth) {
            val right = w - i * tooth
            path.lineTo(right - tooth / 2, h)
            path.lineTo(right - tooth, h - depth)
        }
        path.lineTo(0f, c)
        path.cubicTo(0f, corner, corner, 0f, c, 0f)
        path.close()
        return Outline.Generic(path)
    }
}

/**
 * A diner check: [ReceiptShape] card paper with a hairline. Extra bottom
 * padding keeps the content off the teeth. Fills the width.
 */
@Composable
fun Modifier.receiptCard(padding: Dp = 16.dp): Modifier {
    val colors = KetchupTheme.colors
    return this
        .fillMaxWidth()
        .background(colors.card, ReceiptShape)
        .border(1.dp, colors.rule, ReceiptShape)
        .padding(start = padding, end = padding, top = padding, bottom = padding + ReceiptShape.toothDepth)
}

/** The dashed line above a check's total. Decorative. */
@Composable
fun DashedRule(modifier: Modifier = Modifier) {
    val color = KetchupTheme.colors.inkSoft
    Canvas(
        modifier
            .fillMaxWidth()
            .height(1.dp)
            .clearAndSetSemantics { },
    ) {
        drawLine(
            color = color,
            start = Offset(0f, size.height / 2),
            end = Offset(size.width, size.height / 2),
            strokeWidth = 1.dp.toPx(),
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx())),
        )
    }
}
