package com.vibetemp.ketchup.ui.theme

import android.provider.Settings
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalContext

private val LocalKetchupColors = staticCompositionLocalOf { LightKetchupColors }
private val LocalKetchupType = staticCompositionLocalOf { KetchupType() }
private val LocalReduceMotion = staticCompositionLocalOf { false }

/**
 * The diner theme. Wrap every screen in it; read the tokens with
 * `KetchupTheme.colors.ink`, `KetchupTheme.type.serifTitle3`. Material 3's
 * color scheme is mapped onto the same tokens, so stock components match.
 */
@Composable
fun KetchupTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val colors = if (darkTheme) DarkKetchupColors else LightKetchupColors
    val type = remember { KetchupType() }
    val context = LocalContext.current
    // Android's Reduce Motion: "Remove animations" sets the animator scale to 0.
    val reduceMotion = remember(context) {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
    val scheme = if (darkTheme) {
        darkColorScheme(
            primary = colors.ketchup, onPrimary = colors.onKetchup,
            secondary = colors.ink, onSecondary = colors.onInk,
            tertiary = colors.mustard, onTertiary = colors.onMustard,
            background = colors.cream, onBackground = colors.ink,
            surface = colors.cream, onSurface = colors.ink,
            surfaceVariant = colors.card, onSurfaceVariant = colors.inkSoft,
            surfaceContainer = colors.card, surfaceContainerHigh = colors.card, surfaceContainerLow = colors.card,
            outline = colors.rule, outlineVariant = colors.rule, error = colors.ketchupText,
        )
    } else {
        lightColorScheme(
            primary = colors.ketchup, onPrimary = colors.onKetchup,
            secondary = colors.ink, onSecondary = colors.onInk,
            tertiary = colors.mustard, onTertiary = colors.onMustard,
            background = colors.cream, onBackground = colors.ink,
            surface = colors.cream, onSurface = colors.ink,
            surfaceVariant = colors.card, onSurfaceVariant = colors.inkSoft,
            surfaceContainer = colors.card, surfaceContainerHigh = colors.card, surfaceContainerLow = colors.card,
            outline = colors.rule, outlineVariant = colors.rule, error = colors.ketchupText,
        )
    }
    CompositionLocalProvider(
        LocalKetchupColors provides colors,
        LocalKetchupType provides type,
        LocalReduceMotion provides reduceMotion,
    ) {
        MaterialTheme(colorScheme = scheme, typography = type.material(), content = content)
    }
}

object KetchupTheme {
    val colors: KetchupColors
        @Composable @ReadOnlyComposable get() = LocalKetchupColors.current

    val type: KetchupType
        @Composable @ReadOnlyComposable get() = LocalKetchupType.current

    /** True when the system's "Remove animations" is on: fade instead of moving things. */
    val reduceMotion: Boolean
        @Composable @ReadOnlyComposable get() = LocalReduceMotion.current
}

/**
 * How things move (iOS `Motion`). Springs settle without bounce unless the
 * user flicked or checked something; with [KetchupTheme.reduceMotion] use
 * [fade] so nothing travels.
 */
object Motion {
    /** The marker's curve: quick start, long soft finish. */
    val sweepEasing = CubicBezierEasing(0.23f, 1f, 0.32f, 1f)

    /** The default for most changes (0.3 s, no bounce). */
    fun <T> snappy() = spring<T>(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = 440f)

    /** Bigger moves, content arriving (0.45 s, no bounce). */
    fun <T> settle() = spring<T>(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = 195f)

    /** Only something the user flicked or checked (a little bounce). */
    fun <T> lively() = spring<T>(dampingRatio = 0.8f, stiffness = 250f)

    /** Buttons going down and up (0.16 s, no bounce). */
    fun <T> press() = spring<T>(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = 1500f)

    /** The marker pass. */
    fun <T> sweep() = tween<T>(durationMillis = 500, easing = sweepEasing)

    /** The wordmark's squiggle drawing in. */
    fun <T> squirt(delayMillis: Int = 0) = tween<T>(durationMillis = 900, delayMillis = delayMillis, easing = sweepEasing)

    /** What Reduce Motion gets instead: a short fade. */
    fun <T> fade() = tween<T>(durationMillis = 200)

    /** Milliseconds between items arriving one after another. */
    const val STAGGER_MS = 40
}
