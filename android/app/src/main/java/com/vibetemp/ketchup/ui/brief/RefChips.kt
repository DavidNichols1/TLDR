package com.vibetemp.ketchup.ui.brief

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.ui.design.pressable
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.Motion

/**
 * How the brief's items talk to their sources. [open] gets the ref tapped
 * and every ref of its item: a Ketchup chat jumps to the one tapped, a
 * thread read off another app shows them all in a sheet.
 */
@Immutable
class RefContext(
    val cited: Map<String, Cited>,
    val open: (ref: String, all: List<String>) -> Unit,
    /** What a tap does, for TalkBack. */
    val hint: String,
)

/** The page's [RefContext]: the session's cited messages, and what a tap does here. */
@Composable
fun rememberRefContext(session: BriefSession, open: (String, List<String>) -> Unit): RefContext {
    val hint = stringResource(if (session.isThread) R.string.brief_shows_message else R.string.brief_shows_in_chat)
    val cited = session.cited
    return remember(cited, hint, open) { RefContext(cited, open, hint) }
}

/**
 * One source: "● Maya · so the Airbnb is now…". The dot and the name are in
 * the sender's chat color; the reader is "You" in ink. Tapping it opens the
 * message (iOS `RefChip`).
 */
@Composable
fun RefChip(ref: String, all: List<String>, context: RefContext, modifier: Modifier = Modifier) {
    val colors = KetchupTheme.colors
    val cited = context.cited[ref]
    val you = stringResource(R.string.brief_you)
    val name = cited?.let { if (it.isMine) you else it.name.ifEmpty { "Someone" } }
    val dot = cited?.let { colors.nameColor(it.name, it.isMine) } ?: colors.inkFaint
    val label = if (cited != null && name != null) {
        buildAnnotatedString {
            withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = colors.ink)) { append(name) }
            append(" · ")
            append(cited.preview)
        }
    } else {
        buildAnnotatedString { append(stringResource(R.string.brief_see_message)) }
    }
    val spoken = if (cited != null) "$name: ${cited.text}" else stringResource(R.string.brief_see_message)
    Row(
        modifier = modifier
            .clearAndSetSemantics {
                contentDescription = spoken
                onClick(label = context.hint) { context.open(ref, all); true }
            }
            .pressable { context.open(ref, all) }
            .background(colors.cream, CircleShape)
            .border(1.dp, colors.rule, CircleShape)
            .padding(start = 9.dp, end = 11.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(7.dp).background(dot, CircleShape))
        Text(
            label,
            style = KetchupTheme.type.caption,
            color = colors.inkSoft,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/**
 * An item's sources. Past [limit] they fold into a "+2" that opens the rest
 * in place. One chip and its "+2" share a line, the chip giving way; more
 * than one wrap (iOS `RefChips`).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun RefChips(refs: List<String>, context: RefContext, modifier: Modifier = Modifier, limit: Int = 1) {
    if (refs.isEmpty()) return
    var showAll by rememberSaveable(refs) { mutableStateOf(false) }
    val shown = if (showAll) refs else refs.take(maxOf(limit, 1))
    val hidden = refs.size - shown.size
    val more: @Composable () -> Unit = {
        if (hidden > 0) {
            val spoken = pluralStringResource(R.plurals.brief_more_sources, hidden, hidden)
            HairlineCapsule("+$hidden", Modifier.semantics { contentDescription = spoken }) { showAll = true }
        }
    }
    val sized = modifier.animateContentSize(Motion.snappy())
    if (shown.size == 1) {
        Row(sized, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            RefChip(shown[0], refs, context, Modifier.weight(1f, fill = false))
            more()
        }
    } else {
        FlowRow(sized, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            shown.forEach { RefChip(it, refs, context) }
            more()
        }
    }
}
