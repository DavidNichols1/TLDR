package com.vibetemp.ketchup.ui.design

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import kotlin.math.max
import kotlin.math.min

// A plan as a diner order ticket: rounded paper with a half-circle bite out
// of the top and bottom edges and a dotted tear line between them. The plan
// sits left of the line, a stub (the date, a stamp) right of it. Port of iOS
// Design/Paper.swift (`Ticket`, `TicketShape`, `PerforationLine`).

/**
 * A ticket's outline: a rounded rectangle with a bite out of the top and
 * bottom edges at [notchAt] (a share of the width, keep it between 0.2 and
 * 0.8). Use it as a background and border shape.
 */
class TicketShape(
    private val notchAt: Float = 0.72f,
    private val notchRadius: Dp = 9.dp,
    private val cornerRadius: Dp = 14.dp,
) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val k = 0.5523f // a quarter circle's cubic handle, as a share of its radius
        val w = size.width
        val h = size.height
        val c = max(0f, min(with(density) { cornerRadius.toPx() }, min(w / 2, h / 2)))
        val bite = min(with(density) { notchRadius.toPx() }, h / 2 - 1)
        val x = w * (if (layoutDirection == LayoutDirection.Rtl) 1 - notchAt else notchAt)
        val corner = c * (1 - k)
        val path = Path().apply {
            moveTo(c, 0f)
            // Top edge, with the bite dipping into the paper.
            lineTo(x - bite, 0f)
            cubicTo(x - bite, k * bite, x - k * bite, bite, x, bite)
            cubicTo(x + k * bite, bite, x + bite, k * bite, x + bite, 0f)
            lineTo(w - c, 0f)
            cubicTo(w - corner, 0f, w, corner, w, c)
            lineTo(w, h - c)
            cubicTo(w, h - corner, w - corner, h, w - c, h)
            // Bottom edge, right to left, with its bite.
            lineTo(x + bite, h)
            cubicTo(x + bite, h - k * bite, x + k * bite, h - bite, x, h - bite)
            cubicTo(x - k * bite, h - bite, x - bite, h - k * bite, x - bite, h)
            lineTo(c, h)
            cubicTo(corner, h, 0f, h - corner, 0f, h - c)
            lineTo(0f, c)
            cubicTo(0f, corner, corner, 0f, c, 0f)
            close()
        }
        return Outline.Generic(path)
    }
}

/**
 * A plan ticket with its two parts placed for you: [main] left of the tear
 * line, [stub] right of it, centered top to bottom. Card paper, a hairline,
 * round perforation dots 5 dp apart, no shadow.
 */
@Composable
fun Ticket(
    modifier: Modifier = Modifier,
    notchAt: Float = 0.72f,
    main: @Composable () -> Unit,
    stub: @Composable () -> Unit,
) {
    val colors = KetchupTheme.colors
    val shape = TicketShape(notchAt)
    val padding = 16.dp
    val gap = 12.dp
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .background(colors.card, shape)
            .border(1.dp, colors.rule, shape)
            .drawBehind {
                val bite = 9.dp.toPx()
                val x = size.width * (if (layoutDirection == LayoutDirection.Rtl) 1 - notchAt else notchAt)
                drawLine(
                    color = colors.inkFaint,
                    start = Offset(x, bite + 5.dp.toPx()),
                    end = Offset(x, size.height - bite - 5.dp.toPx()),
                    strokeWidth = 1.5.dp.toPx(),
                    cap = StrokeCap.Round,
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(0.1f, 5.dp.toPx())),
                )
            },
    ) {
        Box(
            Modifier
                .weight(notchAt)
                .padding(start = padding, top = padding, bottom = padding, end = gap),
        ) { main() }
        Box(
            Modifier
                .weight(1 - notchAt)
                .fillMaxHeight()
                .padding(start = gap, end = padding, top = padding, bottom = padding),
            contentAlignment = Alignment.Center,
        ) { stub() }
    }
}
