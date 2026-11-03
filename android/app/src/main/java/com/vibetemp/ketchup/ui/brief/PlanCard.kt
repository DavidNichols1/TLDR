package com.vibetemp.ketchup.ui.brief

import android.content.ActivityNotFoundException
import android.widget.Toast
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.CatchUp
import com.vibetemp.ketchup.ui.design.Monogram
import com.vibetemp.ketchup.ui.design.Stamp
import com.vibetemp.ketchup.ui.design.Ticket
import com.vibetemp.ketchup.ui.design.pressable
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import java.time.format.TextStyle as DayStyle

/**
 * A plan Muse Spark found, as a diner order ticket: what, where, who and
 * the sources left of the tear line; when, and a CONFIRMED or MAYBE stamp,
 * on the stub. "Add to calendar" opens the phone's new-event screen,
 * prefilled; the reader checks it and saves it themselves. Port of iOS
 * AI/PlanCard.swift.
 */
@Composable
fun PlanCard(plan: CatchUp.Plan, chatName: String, app: String, readerName: String, refs: RefContext, modifier: Modifier = Modifier) {
    val colors = KetchupTheme.colors
    val context = LocalContext.current
    val noCalendar = stringResource(R.string.brief_no_calendar)
    Ticket(
        modifier = modifier,
        notchAt = 0.66f,
        main = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(plan.title, style = KetchupTheme.type.serifTitle3, color = colors.ink)
                    place(plan)?.let { Text(it, style = KetchupTheme.type.subheadline, color = colors.inkSoft) }
                }
                if (plan.who.isNotEmpty()) Going(plan.who, readerName)
                RefChips(plan.refs, refs)
                AddToCalendar {
                    val event = PlanCalendar.event(plan, chatName, app)
                    try {
                        context.startActivity(PlanCalendar.intent(event))
                    } catch (_: ActivityNotFoundException) {
                        Toast.makeText(context, noCalendar, Toast.LENGTH_SHORT).show()
                    }
                }
            }
        },
        stub = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                When(PlanTimes(plan))
                if (plan.confirmed) {
                    Stamp(stringResource(R.string.brief_confirmed))
                } else {
                    Stamp(stringResource(R.string.brief_maybe), color = colors.inkSoft, tilt = 3f, dashed = true)
                }
            }
        },
    )
}

/** Where, unless the title already says ("Dinner at Hearthstone"). */
private fun place(plan: CatchUp.Plan): String? {
    val location = plan.location?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    return location.takeUnless { plan.title.contains(it, ignoreCase = true) }
}

/** "SAT / NOV 7 / 6:00 AM / TO 1:00 PM", "ALL DAY" or "TIME TBD". Shrinks to fit the stub. */
@Composable
private fun When(times: PlanTimes) {
    val colors = KetchupTheme.colors
    val type = KetchupTheme.type
    val start = times.start
    val tbd = stringResource(R.string.brief_time_tbd)
    val allDay = stringResource(R.string.brief_all_day)
    val time = when {
        start == null -> null
        times.allDay -> allDay
        !times.hasTime -> tbd
        else -> timeText(start.toLocalTime())
    }
    val endTime = times.end?.let { end ->
        val t = timeText(end.toLocalTime())
        if (times.endsSameDay) t else "${end.dayOfWeek.getDisplayName(DayStyle.SHORT, java.util.Locale.getDefault())} $t"
    }
    val spokenEnd = times.end?.let { end ->
        val t = timeText(end.toLocalTime())
        if (times.endsSameDay) t else "${end.dayOfWeek.getDisplayName(DayStyle.FULL, java.util.Locale.getDefault())} $t"
    }
    val day = times.spokenDay()
    val spoken = when {
        start == null || day == null -> stringResource(R.string.brief_when_tbd)
        times.allDay -> stringResource(R.string.brief_when_all_day, day)
        !times.hasTime -> stringResource(R.string.brief_when_day_tbd, day)
        else -> {
            val from = stringResource(R.string.brief_when_at, day, timeText(start.toLocalTime()))
            if (spokenEnd != null) stringResource(R.string.brief_when_to, from, spokenEnd) else from
        }
    }
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp),
        modifier = Modifier.clearAndSetSemantics { contentDescription = spoken },
    ) {
        if (start == null) {
            Fitted(tbd.uppercase(), type.monoCaption.copy(fontWeight = FontWeight.SemiBold, color = colors.inkSoft))
        } else {
            Fitted(times.weekday().orEmpty().uppercase(), type.monoFootnote.copy(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.Bold, color = colors.ink))
            Fitted(times.monthDay().orEmpty().uppercase(), type.monoCaption.copy(color = colors.inkSoft))
            Fitted(
                time.orEmpty().uppercase(),
                type.monoFootnote.copy(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold, color = colors.ink),
                Modifier.padding(top = 4.dp),
            )
            if (endTime != null) {
                Fitted(stringResource(R.string.brief_until, endTime).uppercase(), type.monoCaption2.copy(color = colors.inkSoft))
            }
        }
    }
}

/** One line of the stub, shrunk (down to 70%) rather than cut or wrapped. */
@Composable
private fun Fitted(text: String, style: TextStyle, modifier: Modifier = Modifier) {
    BasicText(
        text,
        style = style.copy(textAlign = TextAlign.Center),
        maxLines = 1,
        softWrap = false,
        autoSize = TextAutoSize.StepBased(minFontSize = style.fontSize * 0.7f, maxFontSize = style.fontSize, stepSize = 0.5.sp),
        modifier = modifier,
    )
}

/** "Add to calendar", with a small calendar drawn in ink. */
@Composable
private fun AddToCalendar(onClick: () -> Unit) {
    val colors = KetchupTheme.colors
    Row(
        modifier = Modifier
            .pressable(onClick = onClick)
            .semantics { role = Role.Button }
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        CalendarGlyph(18.dp)
        Text(
            stringResource(R.string.brief_add_to_calendar),
            style = KetchupTheme.type.subheadline.copy(fontWeight = FontWeight.SemiBold),
            color = colors.ink,
        )
    }
}

/** A page of a calendar with a plus at its corner (iOS's calendar.badge.plus). Decorative. */
@Composable
private fun CalendarGlyph(size: Dp) {
    val ink = KetchupTheme.colors.ink
    val card = KetchupTheme.colors.cream
    Canvas(Modifier.size(size).clearAndSetSemantics { }) {
        val s = this.size.minDimension
        val w = s * 0.085f
        drawRoundRect(ink, Offset(s * 0.06f, s * 0.14f), Size(s * 0.76f, s * 0.7f), CornerRadius(s * 0.14f), style = Stroke(w))
        drawLine(ink, Offset(s * 0.06f, s * 0.34f), Offset(s * 0.82f, s * 0.34f), w)
        drawLine(ink, Offset(s * 0.27f, s * 0.06f), Offset(s * 0.27f, s * 0.2f), w, StrokeCap.Round)
        drawLine(ink, Offset(s * 0.61f, s * 0.06f), Offset(s * 0.61f, s * 0.2f), w, StrokeCap.Round)
        // The plus, on its own disc so it reads over the page's corner.
        drawCircle(card, radius = s * 0.25f, center = Offset(s * 0.76f, s * 0.76f))
        drawCircle(ink, radius = s * 0.22f, center = Offset(s * 0.76f, s * 0.76f))
        drawLine(card, Offset(s * 0.76f, s * 0.65f), Offset(s * 0.76f, s * 0.87f), w * 0.9f, StrokeCap.Round)
        drawLine(card, Offset(s * 0.65f, s * 0.76f), Offset(s * 0.87f, s * 0.76f), w * 0.9f, StrokeCap.Round)
    }
}

/** Who's going: a few monograms in their chat colors and a short count, the reader first ("You and 5 more"). */
@Composable
private fun Going(names: List<String>, readerName: String) {
    val colors = KetchupTheme.colors
    val readerIn = names.any { Tab.isReader(it, readerName) }
    val others = names.filterNot { Tab.isReader(it, readerName) }
    val you = stringResource(R.string.brief_you)
    val faces = (if (readerIn) listOf(firstName(readerName) ?: you) else emptyList()) + others
    val summary = when {
        readerIn && others.isEmpty() -> stringResource(R.string.brief_just_you)
        readerIn -> pluralStringResource(R.plurals.brief_you_and_more, others.size, others.size)
        else -> pluralStringResource(R.plurals.brief_going_count, others.size, others.size)
    }
    val spoken = stringResource(R.string.brief_going, ((if (readerIn) listOf(you.lowercase()) else emptyList()) + others).joinToString(", "))
    val size = 24.dp * LocalDensity.current.fontScale.coerceAtMost(1.6f)
    val shown = faces.take(4)
    val tile = RoundedCornerShape(size * 0.3f)
    Row(
        Modifier.clearAndSetSemantics { contentDescription = spoken },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(Modifier.width(size + size * 0.78f * (shown.size - 1))) {
            shown.forEachIndexed { i, name ->
                Box(
                    Modifier
                        .offset(x = size * 0.78f * i)
                        .background(colors.card, tile)
                        .border(1.5.dp, colors.card, tile),
                ) { Monogram(name, size = size) }
            }
        }
        Text(summary, style = KetchupTheme.type.footnote, color = colors.inkSoft, maxLines = 1)
    }
}
