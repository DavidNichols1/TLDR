package com.vibetemp.ketchup.ui.brief

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.CatchUp
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.MarkedText
import com.vibetemp.ketchup.ui.design.Monogram
import com.vibetemp.ketchup.ui.design.SectionTitle
import com.vibetemp.ketchup.ui.design.pressable
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.person

/** The brief's sections, for a preview that opens scrolled to one. */
enum class BriefSection { ForYou, Plans, Owes, Questions, Highlights, Ask }

/** Milliseconds the brief waits before rising in, so the skim that was there has faded first. */
const val HAND_OVER_MS = 140

/**
 * A catch-up laid out for someone coming back to the chat, in the order
 * they need it: the gist with its times and money marked, their to-dos,
 * the plans as order tickets, who owes what as a diner check, the
 * questions still waiting on a reply, then the rest of the highlights.
 * Empty sections are left out. Sections rise in once, one after another.
 * Port of iOS AI/CatchUpContent.swift.
 */
@Composable
fun CatchUpContent(
    brief: CatchUp,
    byline: List<String>,
    chatName: String,
    app: String,
    readerName: String,
    refs: RefContext,
    modifier: Modifier = Modifier,
    /** Where each section starts on screen, for scrolling to one. */
    onSection: (BriefSection, Float) -> Unit = { _, _ -> },
    initiallyDone: Set<Int> = emptySet(),
) {
    val first = firstName(readerName)
    fun Modifier.section(section: BriefSection) = onGloballyPositioned { onSection(section, it.positionInRoot().y) }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(40.dp)) {
        Column(Modifier.riseIn(0, HAND_OVER_MS), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            val marks = remember(brief.tldr) { BriefMarks.moneyAndTimes(brief.tldr) }
            MarkedText(
                brief.tldr,
                marks,
                style = KetchupTheme.type.serifTitle2.copy(fontWeight = FontWeight.SemiBold),
                color = KetchupTheme.colors.ink,
                sweep = true,
                delayMillis = HAND_OVER_MS + 350,
                modifier = Modifier.semantics { heading() },
            )
            MuseByline(stringResource(R.string.brief_read_by), byline)
        }
        if (brief.forYou.isNotEmpty()) {
            Column(Modifier.section(BriefSection.ForYou).riseIn(2, HAND_OVER_MS), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionTitle(
                    if (first != null) stringResource(R.string.brief_for_you_name, first) else stringResource(R.string.brief_for_you),
                    count = brief.forYou.size,
                )
                ForYouList(brief.forYou, refs, initiallyDone = initiallyDone)
            }
        }
        if (brief.plans.isNotEmpty()) {
            Column(Modifier.section(BriefSection.Plans).riseIn(3, HAND_OVER_MS), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionTitle(stringResource(R.string.brief_plans), count = brief.plans.size)
                val plans = remember(brief.plans) { PlanTimes.soonestFirst(brief.plans) }
                plans.forEach { PlanCard(it, chatName, app, readerName, refs) }
            }
        }
        if (brief.owes.isNotEmpty()) {
            Column(Modifier.section(BriefSection.Owes).riseIn(4, HAND_OVER_MS), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionTitle(stringResource(R.string.brief_owes), count = brief.owes.size)
                OwesCheck(brief.owes, readerName, refs)
            }
        }
        if (brief.openQuestions.isNotEmpty()) {
            Column(Modifier.section(BriefSection.Questions).riseIn(5, HAND_OVER_MS), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                SectionTitle(stringResource(R.string.brief_questions), count = brief.openQuestions.size)
                // Questions that name the reader come first.
                val questions = remember(brief.openQuestions, first) {
                    if (first == null) brief.openQuestions
                    else brief.openQuestions.sortedBy { if (BriefMarks.mentions(first, it.question)) 0 else 1 }
                }
                questions.forEach { QuestionBubble(it, first, refs) }
            }
        }
        if (brief.highlights.isNotEmpty()) {
            Column(Modifier.section(BriefSection.Highlights).riseIn(6, HAND_OVER_MS), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                SectionTitle(stringResource(R.string.brief_highlights), count = brief.highlights.size)
                brief.highlights.forEachIndexed { i, item -> Highlight(i, item, refs) }
            }
        }
    }
}

@Composable
private fun Highlight(index: Int, item: CatchUp.Item, refs: RefContext) {
    val colors = KetchupTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(
            "%02d".format(index + 1),
            style = KetchupTheme.type.monoFootnote.copy(
                fontSize = KetchupTheme.type.subheadline.fontSize,
                lineHeight = KetchupTheme.type.body.lineHeight,
                fontWeight = FontWeight.SemiBold,
            ),
            color = colors.ketchupText,
            modifier = Modifier.clearAndSetSemantics { },
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(item.text, style = KetchupTheme.type.body, color = colors.ink)
            RefChips(item.refs, refs)
        }
    }
}

/**
 * An open question as the asker's message: their monogram and name in
 * their chat color, a received bubble, "No reply yet" under it. The
 * reader's name is marked. Tapping it opens the question where it was asked.
 */
@Composable
private fun QuestionBubble(question: CatchUp.Question, readerFirstName: String?, refs: RefContext) {
    val colors = KetchupTheme.colors
    val asker = question.askedBy?.trim()?.takeIf { it.isNotEmpty() }
    val avatar = 30.dp * LocalDensity.current.fontScale.coerceAtMost(1.6f)
    val spoken = if (asker != null) stringResource(R.string.brief_asked, asker, question.question)
    else stringResource(R.string.brief_asked_anon, question.question)
    val first = question.refs.firstOrNull()
    val bubble = RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp, bottomEnd = 18.dp, bottomStart = 6.dp)
    Column(
        Modifier
            .clearAndSetSemantics {
                contentDescription = spoken
                if (first != null) onClick(label = refs.hint) { refs.open(first, question.refs); true }
            }
            .pressable(enabled = first != null) { first?.let { refs.open(it, question.refs) } },
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (asker != null) Monogram(asker, size = avatar)
            Column(Modifier.weight(1f, fill = false), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (asker != null) {
                    Text(
                        asker,
                        style = KetchupTheme.type.caption.copy(fontWeight = FontWeight.SemiBold),
                        color = colors.person(asker),
                        modifier = Modifier.padding(start = 8.dp),
                    )
                }
                val marks = remember(question.question, readerFirstName) {
                    readerFirstName?.let { BriefMarks.name(it, question.question) }.orEmpty()
                }
                MarkedText(
                    question.question,
                    marks,
                    style = KetchupTheme.type.body,
                    color = colors.ink,
                    modifier = Modifier
                        .background(colors.card, bubble)
                        .border(1.dp, colors.rule, bubble)
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                )
            }
            Spacer(Modifier.widthIn(min = 32.dp))
        }
        Kicker(
            stringResource(R.string.brief_no_reply),
            Modifier.padding(start = (if (asker == null) 0.dp else avatar + 10.dp) + 8.dp),
        )
    }
}
