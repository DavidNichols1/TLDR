package com.vibetemp.ketchup.ui.design

import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.Motion

/** A capsule button's fill: the one thing to press, a strong second choice, or a quiet one. */
enum class ButtonFill { Ketchup, Ink, Outline }

/**
 * A capsule button (iOS `CapsuleButtonStyle`). [ButtonFill.Ketchup] is the
 * screen's one main action and gives a light haptic tap as it goes down.
 * Large ones fill the width; [compact] hugs its label, for buttons inside
 * cards ("Add to calendar", "Try again"). Gives a little as you press;
 * with Reduce Motion it dims instead.
 */
@Composable
fun CapsuleButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    fill: ButtonFill = ButtonFill.Ketchup,
    compact: Boolean = false,
    enabled: Boolean = true,
) {
    val colors = KetchupTheme.colors
    val reduceMotion = KetchupTheme.reduceMotion
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed && !reduceMotion) 0.97f else 1f, Motion.press(), label = "press")
    val view = LocalView.current
    if (fill == ButtonFill.Ketchup) {
        LaunchedEffect(interaction) {
            interaction.interactions.collect { if (it is PressInteraction.Press) view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY) }
        }
    }
    val labelColor = when (fill) {
        ButtonFill.Ketchup -> colors.onKetchup
        ButtonFill.Ink -> colors.onInk
        ButtonFill.Outline -> colors.ink
    }
    // Scale and dim the whole capsule, fill included (before the background, or only the label would).
    val base = (if (compact) modifier else modifier.fillMaxWidth())
        .graphicsLayer {
            scaleX = scale
            scaleY = scale
        }
        .alpha(if (!enabled) 0.4f else if (pressed && reduceMotion) 0.7f else 1f)
    val filled = when (fill) {
        ButtonFill.Ketchup -> base.background(colors.ketchup, CircleShape)
        ButtonFill.Ink -> base.background(colors.ink, CircleShape)
        ButtonFill.Outline -> base.border(1.dp, colors.ink, CircleShape)
    }
    Box(
        modifier = filled
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = if (compact) 16.dp else 22.dp, vertical = if (compact) 9.dp else 15.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            color = labelColor,
            textAlign = TextAlign.Center,
            style = if (compact) KetchupTheme.type.subheadline.copy(fontWeight = FontWeight.SemiBold)
            else KetchupTheme.type.headline,
        )
    }
}

/**
 * For things that already look tappable (a card, a row, a chip): they give a
 * little as you press, scale only (iOS `.pressable`). With Reduce Motion they
 * dim instead of shrinking.
 */
fun Modifier.pressable(enabled: Boolean = true, scaleTo: Float = 0.97f, onClick: () -> Unit): Modifier = composed {
    val reduceMotion = KetchupTheme.reduceMotion
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed && !reduceMotion) scaleTo else 1f, Motion.press(), label = "pressable")
    this
        .graphicsLayer {
            scaleX = scale
            scaleY = scale
        }
        .alpha(if (pressed && reduceMotion) 0.7f else 1f)
        .clickable(interactionSource = interaction, indication = null, enabled = enabled, onClick = onClick)
}
