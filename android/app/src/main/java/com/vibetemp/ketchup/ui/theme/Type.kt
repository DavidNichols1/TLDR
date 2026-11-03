package com.vibetemp.ketchup.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.runtime.Immutable
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp

/**
 * The type ramp. iOS uses New York, SF Mono and SF Pro; Android uses its
 * built-in serif, monospace and sans families (no downloaded fonts). Sizes
 * are iOS's text styles in sp, so they follow the system font size.
 *
 * - serif (bold): headlines, section titles, the wordmark
 * - mono (medium): times, amounts, codes, counts, kickers
 * - sans: everything else
 */
@Immutable
data class KetchupType(
    val serifLargeTitle: TextStyle = serif(34.sp, 41.sp),
    val serifTitle: TextStyle = serif(28.sp, 34.sp),
    val serifTitle2: TextStyle = serif(22.sp, 28.sp),
    val serifTitle3: TextStyle = serif(20.sp, 25.sp),
    val serifHeadline: TextStyle = serif(17.sp, 22.sp),

    val headline: TextStyle = sans(17.sp, 22.sp, FontWeight.SemiBold),
    val body: TextStyle = sans(17.sp, 22.sp),
    val callout: TextStyle = sans(16.sp, 21.sp),
    val subheadline: TextStyle = sans(15.sp, 20.sp),
    val footnote: TextStyle = sans(13.sp, 18.sp),
    val caption: TextStyle = sans(12.sp, 16.sp),

    val monoBody: TextStyle = mono(17.sp, 22.sp),
    val monoFootnote: TextStyle = mono(13.sp, 18.sp),
    val monoCaption: TextStyle = mono(12.sp, 16.sp),
    val monoCaption2: TextStyle = mono(11.sp, 13.sp),
)

private fun serif(size: TextUnit, line: TextUnit, weight: FontWeight = FontWeight.Bold) =
    TextStyle(fontFamily = FontFamily.Serif, fontWeight = weight, fontSize = size, lineHeight = line)

private fun mono(size: TextUnit, line: TextUnit, weight: FontWeight = FontWeight.Medium) =
    TextStyle(fontFamily = FontFamily.Monospace, fontWeight = weight, fontSize = size, lineHeight = line)

private fun sans(size: TextUnit, line: TextUnit, weight: FontWeight = FontWeight.Normal) =
    TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = weight, fontSize = size, lineHeight = line)

/** Material 3's slots mapped onto the ramp, so stock components (text fields, dialogs) match. */
internal fun KetchupType.material(): Typography = Typography(
    displayLarge = serifLargeTitle,
    displayMedium = serifLargeTitle,
    displaySmall = serifTitle,
    headlineLarge = serifTitle,
    headlineMedium = serifTitle2,
    headlineSmall = serifTitle3,
    titleLarge = serifTitle3,
    titleMedium = headline,
    titleSmall = subheadline.copy(fontWeight = FontWeight.SemiBold),
    bodyLarge = body,
    bodyMedium = subheadline,
    bodySmall = footnote,
    labelLarge = subheadline.copy(fontWeight = FontWeight.SemiBold),
    labelMedium = monoCaption,
    labelSmall = monoCaption2,
)
