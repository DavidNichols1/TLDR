package com.vibetemp.ketchup.ui.auth

import androidx.annotation.DrawableRes
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.ui.design.ButtonFill
import com.vibetemp.ketchup.ui.design.CapsuleButton
import com.vibetemp.ketchup.ui.theme.KetchupTheme

// What the chat slice's screens type into (iOS Views/FormPieces.swift): a
// text field drawn as paper, code boxes that are really one text field, and
// the small notes under a form.

/**
 * A text field on paper: card fill and a hairline that turns ink while it
 * has focus. [leading] sits before the text (the name step's monogram).
 * [visualTransformation] draws a password as dots.
 */
@Composable
fun PaperField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    singleLine: Boolean = true,
    focusRequester: FocusRequester? = null,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    leading: (@Composable () -> Unit)? = null,
) {
    val colors = KetchupTheme.colors
    var focused by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(14.dp)
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier
            .fillMaxWidth()
            .then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier)
            .onFocusChanged { focused = it.isFocused },
        textStyle = KetchupTheme.type.body.copy(color = colors.ink),
        cursorBrush = SolidColor(colors.ketchupText),
        keyboardOptions = keyboardOptions,
        keyboardActions = keyboardActions,
        visualTransformation = visualTransformation,
        singleLine = singleLine,
        decorationBox = { inner ->
            Row(
                Modifier
                    .background(colors.card, shape)
                    .border(if (focused) 1.5.dp else 1.dp, if (focused) colors.ink else colors.rule, shape)
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                leading?.invoke()
                Box(Modifier.weight(1f)) {
                    if (value.isEmpty()) Text(placeholder, style = KetchupTheme.type.body, color = colors.inkFaint, maxLines = 1)
                    inner()
                }
            }
        },
    )
}

/**
 * A code typed one character per box (iOS `CodeField`). The boxes only draw
 * [value]; one invisible text field under them does the typing, so paste,
 * the keyboard and TalkBack all see a single field. The caller filters and
 * caps [value], and submits when it's full. [digits]: the emailed sign-in
 * code (number keys); otherwise an invite code (capitals and numbers).
 */
@Composable
fun CodeField(
    value: String,
    onValueChange: (String) -> Unit,
    length: Int,
    digits: Boolean,
    label: String,
    focusRequester: FocusRequester,
    modifier: Modifier = Modifier,
    onSubmit: () -> Unit = {},
) {
    var focused by remember { mutableStateOf(false) }
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier
            .fillMaxWidth()
            .focusRequester(focusRequester)
            .onFocusChanged { focused = it.isFocused }
            .semantics { contentDescription = label },
        textStyle = TextStyle(color = Color.Transparent),
        cursorBrush = SolidColor(Color.Transparent),
        keyboardOptions = if (digits) {
            KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done)
        } else {
            KeyboardOptions(
                capitalization = KeyboardCapitalization.Characters,
                autoCorrectEnabled = false,
                keyboardType = KeyboardType.Ascii,
                imeAction = ImeAction.Go,
            )
        },
        keyboardActions = KeyboardActions(onDone = { onSubmit() }, onGo = { onSubmit() }),
        singleLine = true,
        decorationBox = { inner ->
            Box {
                CodeBoxes(value, length, focused)
                // The real field: laid out for the keyboard, drawn invisible.
                Box(Modifier.matchParentSize().alpha(0f)) { inner() }
            }
        },
    )
}

/** One mono character a box, a ketchup caret in the next empty box, and a wider gap halfway (1234 5678, WQG AEA). */
@Composable
private fun CodeBoxes(text: String, length: Int, active: Boolean) {
    val half = if (length >= 6) length / 2 else length
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        BoxGroup(text, 0 until half, active, Modifier.weight(1f))
        if (half < length) BoxGroup(text, half until length, active, Modifier.weight(1f))
    }
}

@Composable
private fun BoxGroup(text: String, range: IntRange, active: Boolean, modifier: Modifier) {
    val colors = KetchupTheme.colors
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        for (index in range) {
            val character = text.getOrNull(index)?.toString()
            val next = active && index == text.length
            val shape = RoundedCornerShape(10.dp)
            Box(
                Modifier
                    .weight(1f)
                    .background(colors.card, shape)
                    .border(if (next) 1.5.dp else 1.dp, if (next) colors.ink else colors.rule, shape)
                    .padding(vertical = 12.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    character ?: "0",
                    modifier = Modifier.alpha(if (character == null) 0f else 1f),
                    style = KetchupTheme.type.monoBody.copy(fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.SemiBold),
                    color = colors.ink,
                    textAlign = TextAlign.Center,
                    maxLines = 1,
                )
                if (next) BlinkingCaret()
            }
        }
    }
}

/** The caret in the next empty box. Holds still with Reduce Motion. */
@Composable
private fun BlinkingCaret() {
    val reduceMotion = KetchupTheme.reduceMotion
    val alpha = if (reduceMotion) {
        1f
    } else {
        val blink = rememberInfiniteTransition(label = "caret")
        val value by blink.animateFloat(1f, 0.15f, infiniteRepeatable(tween(550), RepeatMode.Reverse), label = "caret")
        value
    }
    Box(
        Modifier
            .width(2.dp)
            .height(26.dp)
            .alpha(alpha)
            .background(KetchupTheme.colors.ketchupText, RoundedCornerShape(1.dp)),
    )
}

/** Footnote-sized trouble ("That code didn't work") in small ketchup red. */
@Composable
fun FormError(text: String, modifier: Modifier = Modifier) {
    FormNote(text, R.drawable.chat_ic_alert, KetchupTheme.colors.ketchupText, modifier)
}

/** A good-news line under a form ("New code sent"), in pickle. */
@Composable
fun FormNotice(text: String, modifier: Modifier = Modifier) {
    FormNote(text, R.drawable.chat_ic_check, KetchupTheme.colors.pickle, modifier)
}

@Composable
private fun FormNote(text: String, @DrawableRes icon: Int, color: Color, modifier: Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Top) {
        Icon(painterResource(icon), contentDescription = null, tint = color, modifier = Modifier.padding(top = 1.dp).size(16.dp))
        Text(text, style = KetchupTheme.type.footnote.copy(fontWeight = FontWeight.Medium), color = color)
    }
}

/** A capsule button that shows a small spinner in place of its label while [busy]. */
@Composable
fun BusyCapsule(
    text: String,
    busy: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    fill: ButtonFill = ButtonFill.Ketchup,
) {
    Box(modifier, contentAlignment = Alignment.Center) {
        CapsuleButton(if (busy) " " else text, onClick = onClick, fill = fill, enabled = enabled && !busy)
        if (busy) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                color = if (fill == ButtonFill.Outline) KetchupTheme.colors.ink else KetchupTheme.colors.onKetchup,
                strokeWidth = 2.dp,
            )
        }
    }
}

/** One of the chat slice's icons, tinted. */
@Composable
fun ChatIcon(@DrawableRes id: Int, contentDescription: String?, tint: Color, modifier: Modifier = Modifier, size: Dp = 22.dp) {
    Icon(painterResource(id), contentDescription = contentDescription, tint = tint, modifier = modifier.size(size))
}
