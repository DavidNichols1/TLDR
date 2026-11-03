package com.vibetemp.ketchup.ui.brief

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.BriefResponse
import com.vibetemp.ketchup.data.Times
import com.vibetemp.ketchup.ui.design.ButtonFill
import com.vibetemp.ketchup.ui.design.CapsuleButton
import com.vibetemp.ketchup.ui.design.KetchupDrop
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.paperCard
import com.vibetemp.ketchup.ui.design.pressable
import com.vibetemp.ketchup.ui.theme.KetchupColors
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.Motion
import com.vibetemp.ketchup.ui.theme.person
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt

// What the brief's states share: the bar across the top, the byline that
// credits Muse Spark, the cards for a failed call, for nothing new, for
// not signed in and for a source that's gone, and how sections arrive.
// Port of iOS AI/AISheetParts.swift.

/** A person's chat color. The reader writes in ink, like their own bubbles. */
fun KetchupColors.nameColor(name: String, isMine: Boolean): Color = if (isMine) ink else person(name)

/** "302", "1,204": a count in the reader's number format. */
fun count(n: Int): String = NumberFormat.getIntegerInstance(Locale.getDefault()).format(n)

/**
 * Pinned across the top: the chat's name (or the app and the thread) as a
 * running head, an Ask button when Ask is on the page, and Done. A hairline
 * shows once the page scrolls under it.
 */
@Composable
fun BriefTopBar(title: String, scrolled: Boolean, onDone: () -> Unit, onAsk: (() -> Unit)? = null) {
    val colors = KetchupTheme.colors
    val line by animateFloatAsState(if (scrolled) 1f else 0f, Motion.fade(), label = "hairline")
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.cream)
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
            .drawBehind {
                drawLine(colors.rule.copy(alpha = line), Offset(0f, size.height - 0.5.dp.toPx()), Offset(size.width, size.height - 0.5.dp.toPx()), 1.dp.toPx())
            }
            .padding(start = 20.dp, end = 12.dp, top = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = title.uppercase(),
            modifier = Modifier
                .weight(1f)
                .semantics { contentDescription = title; heading() },
            style = KetchupTheme.type.monoCaption2.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 1.4.sp),
            color = colors.inkSoft,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (onAsk != null) {
            // A quiet pill: Done stays the bar's strong word, and Ask's own button is the page's ketchup.
            Text(
                stringResource(R.string.brief_ask_short),
                style = KetchupTheme.type.subheadline.copy(fontWeight = FontWeight.SemiBold),
                color = colors.ink,
                modifier = Modifier
                    .pressable(onClick = onAsk)
                    .semantics { role = Role.Button }
                    .border(1.dp, colors.rule, RoundedCornerShape(50))
                    .padding(horizontal = 14.dp, vertical = 6.dp),
            )
        }
        Text(
            stringResource(R.string.brief_done),
            style = KetchupTheme.type.body.copy(fontWeight = FontWeight.SemiBold),
            color = colors.ink,
            modifier = Modifier
                .pressable(onClick = onDone)
                .padding(horizontal = 8.dp, vertical = 12.dp),
        )
    }
}

/**
 * Credits Muse Spark the way a paper credits a writer: "Read by Muse Spark
 * · 302 messages · 23 s". Small and mono.
 */
@Composable
fun MuseByline(verb: String, details: List<String>, modifier: Modifier = Modifier) {
    val colors = KetchupTheme.colors
    val text = buildAnnotatedString {
        append(verb)
        append(' ')
        withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = colors.ink)) { append(stringResource(R.string.brief_model)) }
        details.forEach {
            append(" · ")
            // Each part stays on one line ("Saved Nov 2 at 9:40 PM").
            append(it.replace(' ', '\u00A0'))
        }
    }
    Text(text, modifier = modifier, style = KetchupTheme.type.monoCaption, color = colors.inkSoft)
}

/**
 * "302 messages" and how long it took ("23 s"), or when it was saved for a
 * catch-up Muse Spark had already made. [app] names a thread's source
 * ("88 Instagram messages").
 */
@Composable
fun bylineDetails(response: BriefResponse<*>, app: String? = null): List<String> {
    val parts = mutableListOf<String>()
    val messages = response.messageCount ?: 0
    if (messages > 0) {
        parts += if (app != null) {
            pluralStringResource(R.plurals.brief_byline_app_messages, messages, count(messages), app)
        } else {
            pluralStringResource(R.plurals.brief_byline_messages, messages, count(messages))
        }
    }
    val ms = response.latencyMs ?: 0
    if (response.cached) {
        parts += savedWhen(response.createdAt?.let(Times::instant))
    } else if (ms > 0) {
        parts += stringResource(R.string.brief_byline_seconds, maxOf(1, (ms / 1000.0).roundToInt()))
    }
    return parts
}

/** "Saved at 9:40 PM" today, "Saved Nov 2 at 9:40 PM" before, or just "Saved". */
@Composable
private fun savedWhen(at: Instant?, zone: ZoneId = ZoneId.systemDefault()): String {
    at ?: return stringResource(R.string.brief_saved)
    val time = timeText(at.atZone(zone).toLocalTime())
    val day = at.atZone(zone).toLocalDate()
    return if (day == LocalDate.now(zone)) {
        stringResource(R.string.brief_saved_at, time)
    } else {
        stringResource(R.string.brief_saved_on, DateTimeFormatter.ofPattern("MMM d", Locale.getDefault()).format(day), time)
    }
}

/**
 * A Muse Spark call that didn't come back: what happened in plain words,
 * and a way to try again. [prominent] makes Try again the page's one
 * ketchup button; Ask keeps that for its own Ask button.
 */
@Composable
fun BriefErrorCard(message: String, onRetry: () -> Unit, modifier: Modifier = Modifier, note: String? = null, prominent: Boolean = true) {
    val colors = KetchupTheme.colors
    val (first, rest) = Sentences.first(message)
    // "Try again." under a Try again button says it twice.
    val restShown = rest?.takeUnless { it.lowercase().startsWith("try again.") && it.length <= 10 }
    val more = listOfNotNull(restShown, note).joinToString(" ")
    Column(modifier.paperCard(padding = 20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Kicker(stringResource(R.string.brief_didnt_go_through), color = colors.ketchupText)
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(first, style = KetchupTheme.type.serifTitle3, color = colors.ink)
            if (more.isNotEmpty()) Text(more, style = KetchupTheme.type.subheadline, color = colors.inkSoft)
        }
        if (prominent) {
            CapsuleButton(stringResource(R.string.brief_try_again), onClick = onRetry)
        } else {
            CapsuleButton(stringResource(R.string.brief_try_again), onClick = onRetry, fill = ButtonFill.Ink, compact = true)
        }
    }
}

/** A centered note with the drop: nothing new, not signed in. */
@Composable
fun DropNote(title: String, body: String, modifier: Modifier = Modifier, action: (@Composable () -> Unit)? = null) {
    val colors = KetchupTheme.colors
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        KetchupDrop(size = 72.dp, modifier = Modifier.padding(bottom = 6.dp))
        Text(
            title,
            style = KetchupTheme.type.serifTitle2,
            color = colors.ink,
            textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() },
        )
        Text(body, style = KetchupTheme.type.subheadline, color = colors.inkSoft, textAlign = TextAlign.Center)
        if (action != null) Box(Modifier.padding(top = 10.dp)) { action() }
    }
}

/** A quiet card: the source this page was opened for is gone (the process died in between). */
@Composable
fun GoneCard(modifier: Modifier = Modifier) {
    val colors = KetchupTheme.colors
    Column(modifier.paperCard(padding = 20.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(stringResource(R.string.brief_source_gone), style = KetchupTheme.type.serifTitle3, color = colors.ink)
        Text(stringResource(R.string.brief_source_gone_body), style = KetchupTheme.type.subheadline, color = colors.inkSoft)
    }
}

/** A dashed hairline box, for an answer the chat couldn't back up. */
fun Modifier.dashedCard(color: Color): Modifier = drawBehind {
    val width = 1.2.dp.toPx()
    drawRoundRect(
        color = color,
        topLeft = Offset(width / 2, width / 2),
        size = size.copy(width = size.width - width, height = size.height - width),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(16.dp.toPx()),
        style = Stroke(width = width, pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx()))),
    )
}

/**
 * Rises into place [index] beats after it first shows (plus [afterMillis]),
 * for a page's sections arriving once. Only fades with Reduce Motion.
 */
@Composable
fun Modifier.riseIn(index: Int, afterMillis: Int = 0): Modifier {
    val reduceMotion = KetchupTheme.reduceMotion
    val shift = with(LocalDensity.current) { 16.dp.toPx() }
    val alpha = remember { Animatable(0f) }
    val offset = remember { Animatable(if (reduceMotion) 0f else shift) }
    LaunchedEffect(Unit) {
        delay(afterMillis + index * Motion.STAGGER_MS.toLong())
        launch { alpha.animateTo(1f, if (reduceMotion) Motion.fade() else Motion.settle()) }
        if (!reduceMotion) offset.animateTo(0f, Motion.settle())
    }
    return graphicsLayer {
        this.alpha = alpha.value
        translationY = offset.value
    }
}

/** A small capsule with a hairline, for "+2" and the like. */
@Composable
fun HairlineCapsule(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = KetchupTheme.colors
    Text(
        text,
        style = KetchupTheme.type.monoCaption.copy(fontWeight = FontWeight.SemiBold),
        color = colors.inkSoft,
        maxLines = 1,
        modifier = modifier
            .pressable(onClick = onClick)
            .border(1.dp, colors.rule, RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 6.dp),
    )
}

/** Faded, for a line that's done. */
fun Modifier.dimmed(on: Boolean): Modifier = alpha(if (on) 0.55f else 1f)

/** A spacer line of [height]. */
@Composable
fun Gap(height: Int) = Box(Modifier.height(height.dp))
