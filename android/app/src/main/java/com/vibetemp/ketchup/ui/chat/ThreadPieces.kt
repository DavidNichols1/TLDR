package com.vibetemp.ketchup.ui.chat

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.Message
import com.vibetemp.ketchup.ui.auth.ChatIcon
import com.vibetemp.ketchup.ui.chats.Stamps
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.Motion
import java.time.LocalDate
import java.time.ZoneId

// What a thread is drawn from (iOS Chat/ChatBubble.swift and
// ThreadDivider.swift): its rows, the day and "N new" lines, and bubbles.

/** One row of a thread, oldest first. [key] is stable for the list. */
sealed interface ThreadRow {
    val key: String

    data class Day(val day: LocalDate) : ThreadRow {
        override val key: String get() = "day-$day"
    }

    data class Unread(val count: Int) : ThreadRow {
        override val key: String get() = UNREAD_KEY
    }

    /** [startsRun]: first of a run from one sender; [endsRun]: last of it. */
    data class Bubble(val message: Message, val startsRun: Boolean, val endsRun: Boolean) : ThreadRow {
        override val key: String get() = message.id
    }

    companion object {
        const val UNREAD_KEY = "unread-divider"
    }
}

/** The thread's rows: a day line at each new day, the "N new" line before the first unread, and runs. */
fun threadRows(messages: List<Message>, firstUnreadId: String?, unreadAtOpen: Int, zone: ZoneId = ZoneId.systemDefault()): List<ThreadRow> {
    val out = ArrayList<ThreadRow>(messages.size + 8)
    var lastDay: LocalDate? = null
    var lastSender: String? = null
    for (m in messages) {
        val day = m.createdAt.atZone(zone).toLocalDate()
        if (day != lastDay) {
            out += ThreadRow.Day(day)
            lastDay = day
            lastSender = null
        }
        if (m.id == firstUnreadId && unreadAtOpen > 0) {
            out += ThreadRow.Unread(unreadAtOpen)
            lastSender = null
        }
        val continues = m.sender == lastSender
        // The bubble before this one is the same sender's, so its run goes on.
        if (continues) {
            val previous = out.last()
            if (previous is ThreadRow.Bubble) out[out.size - 1] = previous.copy(endsRun = false)
        }
        out += ThreadRow.Bubble(m, startsRun = !continues, endsRun = true)
        lastSender = m.sender
    }
    return out
}

/** A day in the thread: "TODAY", "YESTERDAY", "MONDAY, NOV 2". */
@Composable
fun DayDivider(day: LocalDate) {
    val text = Stamps.day(day, stringResource(R.string.chat_today), stringResource(R.string.chats_yesterday))
    Box(
        Modifier
            .fillMaxWidth()
            .padding(top = 18.dp, bottom = 6.dp)
            .semantics { heading() },
        contentAlignment = Alignment.Center,
    ) {
        Kicker(text)
    }
}

/**
 * Where the unread part starts: "302 NEW" on a full mustard mark between
 * hairlines (dark onMustard type in both modes). It sweeps in when it
 * first shows, and is simply there with Reduce Motion.
 */
@Composable
fun UnreadDivider(count: Int) {
    val colors = KetchupTheme.colors
    val reduceMotion = KetchupTheme.reduceMotion
    val progress = remember { Animatable(if (reduceMotion) 1f else 0f) }
    LaunchedEffect(Unit) { if (progress.value < 1f) progress.animateTo(1f, tween(500, delayMillis = 200, easing = Motion.sweepEasing)) }
    val spoken = pluralStringResource(R.plurals.chat_unread_divider_spoken, count, count)
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 14.dp)
            .clearAndSetSemantics { contentDescription = spoken },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.weight(1f).height(1.dp).background(colors.rule))
        Text(
            stringResource(R.string.chat_unread_divider, count).uppercase(),
            style = KetchupTheme.type.monoCaption2.copy(fontWeight = FontWeight.Bold, letterSpacing = 1.4.sp),
            color = colors.onMustard,
            modifier = Modifier
                .drawBehind { drawMarker(colors.mustard, progress.value) }
                .padding(horizontal = 9.dp, vertical = 5.dp),
        )
        Box(Modifier.weight(1f).height(1.dp).background(colors.rule))
    }
}

/**
 * One bubble (iOS `ChatBubble`). Other people's are card paper with a
 * hairline, mine are ink. A run from one sender tucks its inside corners
 * in. Pending bubbles are faded; a failed one says so and retries on tap.
 * A long press copies the text and shows when it was sent. [highlighted]:
 * a brief's jump landed here, so a mustard marker sweeps behind it.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ChatBubble(
    message: Message,
    mine: Boolean,
    senderName: String?,
    senderColor: Color,
    startsRun: Boolean,
    endsRun: Boolean,
    highlighted: Boolean,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = KetchupTheme.colors
    val context = LocalContext.current
    var menu by remember { mutableStateOf(false) }
    val round = 18.dp
    val tucked = 6.dp
    val top = if (startsRun) round else tucked
    val bottom = if (endsRun) round else tucked
    val shape = if (mine) {
        RoundedCornerShape(topStart = round, bottomStart = round, bottomEnd = bottom, topEnd = top)
    } else {
        RoundedCornerShape(topStart = top, bottomStart = bottom, bottomEnd = round, topEnd = round)
    }
    // Photos are drawn by iOS's PhotoBubble; here a photo message reads as its caption.
    val photo = stringResource(R.string.chat_photo)
    val text = when {
        message.imagePath == null -> message.body
        message.body.isEmpty() -> photo
        else -> "📷 ${message.body}"
    }
    Column(
        modifier
            .fillMaxWidth()
            .padding(start = if (mine) 56.dp else 0.dp, end = if (mine) 0.dp else 56.dp),
        horizontalAlignment = if (mine) Alignment.End else Alignment.Start,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (senderName != null && !mine) {
            Text(
                senderName,
                style = KetchupTheme.type.caption.copy(fontWeight = FontWeight.SemiBold),
                color = senderColor,
                modifier = Modifier.padding(start = 12.dp),
            )
        }
        Box {
            Text(
                text,
                style = KetchupTheme.type.body,
                color = if (mine) colors.onInk else colors.ink,
                modifier = Modifier
                    .jumpMark(highlighted)
                    .alpha(if (message.pending) 0.55f else 1f)
                    .background(if (mine) colors.ink else colors.card, shape)
                    .then(if (mine) Modifier else Modifier.border(1.dp, colors.rule, shape))
                    .combinedClickable(
                        onClick = { if (message.failed) onRetry() },
                        onLongClick = { menu = true },
                    )
                    .padding(horizontal = 14.dp, vertical = 9.dp),
            )
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, containerColor = colors.card) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.chat_copy), style = KetchupTheme.type.body, color = colors.ink) },
                    leadingIcon = { ChatIcon(R.drawable.chat_ic_copy, null, colors.ink, size = 20.dp) },
                    onClick = {
                        menu = false
                        copy(context, message.body)
                    },
                )
                DropdownMenuItem(
                    text = { Text(Stamps.full(message.createdAt), style = KetchupTheme.type.monoCaption, color = colors.inkSoft) },
                    onClick = { menu = false },
                    enabled = false,
                )
            }
        }
        if (message.failed) {
            Row(
                Modifier
                    .clickable(onClick = onRetry)
                    .padding(horizontal = 6.dp, vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                ChatIcon(R.drawable.chat_ic_alert, null, colors.ketchupText, size = 14.dp)
                Text(
                    stringResource(R.string.chat_not_sent),
                    style = KetchupTheme.type.caption.copy(fontWeight = FontWeight.SemiBold),
                    color = colors.ketchupText,
                )
            }
        }
    }
}

/**
 * The jump-to-message highlight: one mustard marker pass behind the
 * bubble, reaching a little past it on every side, then a fade. With
 * Reduce Motion it's a plain tint.
 */
@Composable
private fun Modifier.jumpMark(on: Boolean): Modifier {
    val colors = KetchupTheme.colors
    val reduceMotion = KetchupTheme.reduceMotion
    val progress = remember { Animatable(0f) }
    val shown by animateFloatAsState(if (on) 1f else 0f, tween(if (on) 150 else 400), label = "jump")
    LaunchedEffect(on) {
        if (on) {
            progress.snapTo(if (reduceMotion) 1f else 0f)
            if (!reduceMotion) progress.animateTo(1f, Motion.sweep())
        }
    }
    if (shown <= 0f) return this
    return drawBehind {
        val reachX = 10.dp.toPx()
        val reachY = 8.dp.toPx()
        if (reduceMotion) {
            drawRoundRect(
                colors.mustard.copy(alpha = 0.45f * shown),
                topLeft = Offset(-reachY, -reachY),
                size = Size(size.width + reachY * 2, size.height + reachY * 2),
                cornerRadius = CornerRadius(22.dp.toPx()),
            )
        } else {
            // The marker inks 20% to 96% of its height: size it so that band covers the bubble and the reach.
            val height = (size.height + reachY * 2) / 0.76f
            drawMarker(
                colors.mustard.copy(alpha = 0.9f * shown),
                progress.value,
                topLeft = Offset(-reachX, -reachY - height * 0.2f),
                size = Size(size.width + reachX * 2, height),
            )
        }
    }
}

private fun copy(context: Context, text: String) {
    val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return
    clipboard.setPrimaryClip(ClipData.newPlainText("Ketchup message", text))
}

/** Room for the avatar column when a bubble isn't the last of its run. */
@Composable
fun AvatarGap(size: Dp) {
    Spacer(Modifier.size(width = size, height = 1.dp))
}
