package com.vibetemp.ketchup.ui.design

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalDensity
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.People
import com.vibetemp.ketchup.ui.theme.person

/**
 * Raised paper: card fill and a 1 dp rule border, no shadow. The default
 * container for anything grouped. Fills the width.
 */
@Composable
fun Modifier.paperCard(padding: Dp = 16.dp, radius: Dp = 16.dp): Modifier {
    val colors = KetchupTheme.colors
    val shape = RoundedCornerShape(radius)
    return this
        .fillMaxWidth()
        .background(colors.card, shape)
        .border(1.dp, colors.rule, shape)
        .padding(padding)
}

/**
 * A small mono label over a headline or a card: "FOR YOU", "SAT 6:00 AM".
 * TalkBack reads the original casing.
 */
@Composable
fun Kicker(text: String, modifier: Modifier = Modifier, color: Color = KetchupTheme.colors.inkSoft) {
    Text(
        text = text.uppercase(),
        modifier = modifier.semantics { contentDescription = text },
        style = KetchupTheme.type.monoCaption2.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 1.4.sp),
        color = color,
    )
}

/** A section heading in serif, with a faint count after it ("Plans 6"). A heading for TalkBack. */
@Composable
fun SectionTitle(title: String, modifier: Modifier = Modifier, count: Int? = null) {
    Row(
        modifier = modifier.semantics(mergeDescendants = true) { heading() },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        Text(title, style = KetchupTheme.type.serifTitle3, color = KetchupTheme.colors.ink, modifier = Modifier.alignByBaseline())
        if (count != null) {
            Text(
                count.toString(),
                style = KetchupTheme.type.monoFootnote,
                color = KetchupTheme.colors.inkFaint,
                modifier = Modifier.alignByBaseline(),
            )
        }
    }
}

/**
 * A person's initials on a soft tile of their color: rows, member lists,
 * "who's going". A rounded square, not a circle, so it reads as paper.
 * Decorative: say the name in the row instead.
 */
@Composable
fun Monogram(name: String, modifier: Modifier = Modifier, size: Dp = 36.dp, color: Color? = null) {
    val tint = color ?: KetchupTheme.colors.person(name)
    val fontSize = with(LocalDensity.current) { (size * 0.4f).toFixedSp(this) }
    Box(
        modifier = modifier
            .size(size)
            .background(tint.copy(alpha = 0.14f), RoundedCornerShape(size * 0.3f))
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            People.initials(name),
            color = tint,
            maxLines = 1,
            style = KetchupTheme.type.serifHeadline.copy(
                fontFamily = FontFamily.Serif,
                fontWeight = FontWeight.SemiBold,
                fontSize = fontSize,
                lineHeight = fontSize,
            ),
        )
    }
}

/** A dp size as sp that ignores the font scale: the monogram is drawn to its tile, like a logo. */
private fun Dp.toFixedSp(density: Density) = (value / density.fontScale).sp
