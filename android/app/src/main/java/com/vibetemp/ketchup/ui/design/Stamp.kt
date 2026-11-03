package com.vibetemp.ketchup.ui.design

import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vibetemp.ketchup.ui.theme.KetchupTheme

/**
 * A rubber stamp, tilted a few degrees: "CONFIRMED" in pickle green on a
 * plan ticket, or another word in another color ("MAYBE" in inkSoft,
 * [dashed] for something not settled yet). Shrinks to fit a narrow stub
 * instead of wrapping (iOS `Stamp`). TalkBack reads the original casing.
 */
@Composable
fun Stamp(
    text: String,
    modifier: Modifier = Modifier,
    color: Color = KetchupTheme.colors.pickle,
    tilt: Float = -4f,
    dashed: Boolean = false,
) {
    val style = KetchupTheme.type.monoCaption2.copy(fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp, color = color)
    BasicText(
        text = text.uppercase(),
        style = style,
        maxLines = 1,
        softWrap = false,
        autoSize = TextAutoSize.StepBased(minFontSize = style.fontSize * 0.6f, maxFontSize = style.fontSize, stepSize = 0.5.sp),
        modifier = modifier
            .semantics { contentDescription = text }
            .rotate(tilt)
            .drawBehind {
                val width = 1.5.dp.toPx()
                val inset = width / 2
                drawRoundRect(
                    color = color,
                    topLeft = Offset(inset, inset),
                    size = Size(size.width - width, size.height - width),
                    cornerRadius = CornerRadius(4.dp.toPx()),
                    style = Stroke(
                        width = width,
                        pathEffect = if (dashed) PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 2.5.dp.toPx())) else null,
                    ),
                )
            }
            .padding(horizontal = 7.dp, vertical = 3.dp),
    )
}
