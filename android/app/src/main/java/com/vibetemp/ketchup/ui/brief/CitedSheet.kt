package com.vibetemp.ketchup.ui.brief

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.Monogram
import com.vibetemp.ketchup.ui.design.pressable
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import kotlinx.coroutines.launch
import java.time.ZoneId
import java.time.format.TextStyle as DayStyle
import java.util.Locale

/** The sources a tap on a thread's brief opened: every ref of the item, and the one tapped. */
@Immutable
data class CitedRequest(val tapped: String, val refs: List<String>)

/**
 * A thread read off Instagram or Snapchat can't be jumped into, so tapping
 * a source shows the item's cited messages here instead, in the order they
 * were said: who said it in their chat color, what they replied to, about
 * when. The one tapped is marked. Nothing here was saved (iOS
 * `WebQuoteCard`, for all of an item's sources at once).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CitedSheet(request: CitedRequest, cited: Map<String, Cited>, app: String, onDismiss: () -> Unit) {
    val colors = KetchupTheme.colors
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    val scope = rememberCoroutineScope()
    val messages = Refs.inOrder(request.refs).mapNotNull { ref -> cited[ref]?.let { ref to it } }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = state,
        containerColor = colors.cream,
        contentColor = colors.ink,
        tonalElevation = 0.dp,
        scrimColor = colors.ink.copy(alpha = 0.32f),
        dragHandle = { BottomSheetDefaults.DragHandle(color = colors.rule) },
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(start = 20.dp, end = 12.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Kicker(stringResource(R.string.brief_from_app_chat, app), Modifier.weight(1f))
                Text(
                    stringResource(R.string.brief_done),
                    style = KetchupTheme.type.body.copy(fontWeight = FontWeight.SemiBold),
                    color = colors.ink,
                    modifier = Modifier
                        .pressable { scope.launch { state.hide() }.invokeOnCompletion { onDismiss() } }
                        .padding(horizontal = 8.dp, vertical = 10.dp),
                )
            }
            Column(Modifier.padding(end = 8.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                messages.forEach { (ref, message) -> CitedMessage(message, tapped = ref == request.tapped) }
            }
            Text(
                stringResource(R.string.brief_cited_footer, app),
                style = KetchupTheme.type.footnote,
                color = colors.inkSoft,
            )
        }
    }
}

/** One source, whole: the sender's monogram and name, about when, what it replies to, the words. */
@Composable
private fun CitedMessage(message: Cited, tapped: Boolean) {
    val colors = KetchupTheme.colors
    val you = stringResource(R.string.brief_you)
    val name = if (message.isMine) you else message.name.ifEmpty { "Someone" }
    val tint = colors.nameColor(message.name, message.isMine)
    val avatar = 32.dp * LocalDensity.current.fontScale.coerceAtMost(1.6f)
    val bubble = RoundedCornerShape(topStart = 6.dp, topEnd = 18.dp, bottomEnd = 18.dp, bottomStart = 18.dp)
    Column(Modifier.semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Monogram(name, size = avatar, color = tint)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(name, style = KetchupTheme.type.headline, color = tint)
                message.at?.let { at ->
                    val zoned = at.atZone(ZoneId.systemDefault())
                    val day = zoned.dayOfWeek.getDisplayName(DayStyle.SHORT, Locale.getDefault())
                    Text(
                        stringResource(R.string.brief_about_time, "$day ${timeText(zoned.toLocalTime())}"),
                        style = KetchupTheme.type.monoCaption,
                        color = colors.inkSoft,
                    )
                }
            }
        }
        Column(
            Modifier
                .padding(start = avatar + 10.dp)
                .background(colors.card, bubble)
                .border(if (tapped) 1.5.dp else 1.dp, if (tapped) colors.mustard else colors.rule, bubble)
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            message.quote?.let { quote -> QuoteLine(quote) }
            Text(message.text, style = KetchupTheme.type.body, color = colors.ink)
        }
    }
}

/** What a message replies to, as the app quoted it: a rule down its side, who said it, the words. */
@Composable
private fun QuoteLine(quote: Cited.Quote) {
    val colors = KetchupTheme.colors
    val who = when {
        quote.isMine -> stringResource(R.string.brief_replying_to_you)
        quote.name != null -> stringResource(R.string.brief_replying_to, quote.name)
        else -> null
    }
    Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(
            Modifier
                .width(2.dp)
                .fillMaxHeight()
                .background(colors.rule, RoundedCornerShape(1.dp)),
        )
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (who != null) Text(who, style = KetchupTheme.type.caption.copy(fontWeight = FontWeight.SemiBold), color = colors.inkSoft)
            quote.text?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = KetchupTheme.type.footnote, color = colors.inkSoft, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}
