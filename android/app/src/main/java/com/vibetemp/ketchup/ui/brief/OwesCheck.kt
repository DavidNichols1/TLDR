package com.vibetemp.ketchup.ui.brief

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.CatchUp
import com.vibetemp.ketchup.ui.design.DashedRule
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.marker
import com.vibetemp.ketchup.ui.design.markerProgress
import com.vibetemp.ketchup.ui.design.pressable
import com.vibetemp.ketchup.ui.design.receiptCard
import com.vibetemp.ketchup.ui.theme.KetchupTheme

/**
 * "Who owes what" as a diner check: the reader's lines first with their
 * total marked once it scrolls into view, everyone else's after, and the
 * things to bring at the bottom. Tapping a line opens where it was said.
 * Port of iOS AI/OwesCheck.swift.
 */
@Composable
fun OwesCheck(owes: List<CatchUp.Owe>, readerName: String, refs: RefContext, modifier: Modifier = Modifier) {
    val colors = KetchupTheme.colors
    val tab = remember(owes, readerName) { Tab(owes, readerName) }
    Column(modifier.receiptCard(padding = 18.dp)) {
        if (tab.yours.isNotEmpty()) {
            Kicker(stringResource(R.string.brief_your_tab), Modifier.padding(bottom = 8.dp))
            tab.yours.forEach { CheckLine(it, refs) }
            DashedRule(Modifier.padding(vertical = 12.dp))
            Totals(tab)
        }
        if (tab.others.isNotEmpty()) {
            Kicker(
                stringResource(if (tab.yours.isEmpty()) R.string.brief_the_table else R.string.brief_everyone_else),
                Modifier.padding(top = if (tab.yours.isEmpty()) 0.dp else 26.dp, bottom = 8.dp),
            )
            tab.others.forEach { CheckLine(it, refs) }
        }
        if (tab.toBring.isNotEmpty()) {
            Kicker(
                stringResource(R.string.brief_to_bring),
                Modifier.padding(top = if (tab.yours.isEmpty() && tab.others.isEmpty()) 0.dp else 26.dp, bottom = 8.dp),
            )
            tab.toBring.forEach { CheckLine(it, refs) }
        }
        Text(
            stringResource(R.string.brief_tap_a_line),
            style = KetchupTheme.type.footnote,
            color = colors.inkSoft,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 22.dp),
        )
    }
}

/** "You → Maya  Airbnb ........ $90.00". */
@Composable
private fun CheckLine(line: Tab.Line, refs: RefContext) {
    val colors = KetchupTheme.colors
    val you = stringResource(R.string.brief_you)
    val from = if (line.fromReader) you else line.from
    val to = line.to?.let { if (line.toReader) you else it }
    val title = buildAnnotatedString {
        withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = colors.nameColor(line.from, line.fromReader))) { append(from) }
        if (to != null) {
            withStyle(SpanStyle(color = colors.inkSoft)) { append(" → ") }
            withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = colors.nameColor(line.to.orEmpty(), line.toReader))) { append(to) }
        }
        if (line.label.isNotEmpty()) {
            append("  ")
            withStyle(SpanStyle(color = colors.inkSoft)) { append(line.label) }
        }
    }
    val amount = line.amount?.let { Tab.format(it, line.symbol) }
    val spoken = spoken(line, from, to, amount)
    val first = line.refs.firstOrNull()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clearAndSetSemantics {
                contentDescription = spoken
                if (first != null) onClick(label = refs.hint) { refs.open(first, line.refs); true }
            }
            .pressable(enabled = first != null) { first?.let { refs.open(it, line.refs) } }
            .padding(vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // First baselines line up, like iOS: the arrow comes from a fallback font with a taller line.
        Text(
            title,
            style = KetchupTheme.type.monoFootnote.copy(fontSize = KetchupTheme.type.subheadline.fontSize, lineHeight = KetchupTheme.type.subheadline.lineHeight),
            color = colors.ink,
            modifier = Modifier
                .weight(1f)
                .alignByBaseline(),
        )
        if (amount != null) {
            Text(
                amount,
                modifier = Modifier.alignByBaseline(),
                style = KetchupTheme.type.monoFootnote.copy(
                    fontSize = KetchupTheme.type.subheadline.fontSize,
                    lineHeight = KetchupTheme.type.subheadline.lineHeight,
                    fontWeight = FontWeight.SemiBold,
                ),
                color = colors.ink,
                maxLines = 1,
                softWrap = false,
            )
        }
    }
}

/** A line as a sentence for TalkBack: "You owe Maya $90.00 for Airbnb", "You: Speaker and Catan". */
private fun spoken(line: Tab.Line, from: String, to: String?, amount: String?): String {
    if (amount == null) return "$from: ${line.label}"
    val verb = if (line.fromReader) "owe" else "owes"
    val whom = to?.let { " ${if (line.toReader) "you" else it}" }.orEmpty()
    val item = if (line.label.isEmpty()) "" else " for ${line.label}"
    return "$from $verb$whom $amount$item"
}

@Composable
private fun Totals(tab: Tab) {
    val colors = KetchupTheme.colors
    val view = LocalView.current
    // The total gets marked once it's on screen.
    var seen by remember { mutableStateOf(false) }
    val progress = markerProgress(isOn = seen, sweep = true)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (tab.youOwe.signum() > 0) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.brief_you_owe), style = KetchupTheme.type.headline, color = colors.ink, modifier = Modifier.weight(1f))
                Text(
                    Tab.format(tab.youOwe, tab.youOweSymbol),
                    style = KetchupTheme.type.monoBody.copy(fontSize = KetchupTheme.type.serifTitle3.fontSize, lineHeight = KetchupTheme.type.serifTitle3.lineHeight, fontWeight = FontWeight.Bold),
                    color = colors.ink,
                    modifier = Modifier
                        .onGloballyPositioned { coordinates ->
                            if (!seen) {
                                val bounds = coordinates.boundsInWindow()
                                if (bounds.height > 0 && bounds.bottom <= view.height && bounds.top >= 0) seen = true
                            }
                        }
                        .marker(progress),
                )
            }
        }
        if (tab.owedToYou.signum() > 0) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.brief_owed_to_you), style = KetchupTheme.type.subheadline, color = colors.ink, modifier = Modifier.weight(1f))
                Text(
                    Tab.format(tab.owedToYou, tab.owedSymbol),
                    style = KetchupTheme.type.monoFootnote.copy(fontSize = KetchupTheme.type.subheadline.fontSize, fontWeight = FontWeight.SemiBold),
                    color = colors.ink,
                )
            }
        }
    }
}
