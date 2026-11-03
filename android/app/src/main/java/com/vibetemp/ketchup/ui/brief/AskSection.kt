package com.vibetemp.ketchup.ui.brief

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.ChatAnswer
import com.vibetemp.ketchup.ui.design.ButtonFill
import com.vibetemp.ketchup.ui.design.CapsuleButton
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.MarkedText
import com.vibetemp.ketchup.ui.design.SectionTitle
import com.vibetemp.ketchup.ui.design.paperCard
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.Motion
import kotlin.math.roundToInt

/**
 * "Ask the chat", under the brief: a question in, an answer out with the
 * messages that back it up. Muse Spark says so plainly when the chat
 * doesn't have it. The field keeps the question, so asking again is one
 * edit and a tap. Port of iOS AI/AskSheet.swift.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AskSection(
    session: BriefSession,
    refs: RefContext,
    focus: FocusRequester,
    modifier: Modifier = Modifier,
    app: String? = null,
    /** The page is only Ask (the chat's Ask button): iOS's Ask sheet header, and the field focused. */
    prominent: Boolean = false,
) {
    val colors = KetchupTheme.colors
    val focusManager = LocalFocusManager.current
    var question by remember { mutableStateOf(session.lastQuestion) }
    val loading = session.answer == Phase.Loading
    val canAsk = question.isNotBlank() && !loading
    fun submit(q: String = question) {
        if (q.isBlank() || loading) return
        focusManager.clearFocus()
        session.ask(q)
    }
    // Opened for Ask, the field is ready to type in (iOS focuses it too), unless an answer is showing.
    LaunchedEffect(Unit) {
        if (prominent && session.answer == Phase.Idle) focus.requestFocus()
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(if (prominent) 24.dp else 16.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (prominent) {
                Text(
                    stringResource(R.string.brief_ask_title),
                    style = KetchupTheme.type.serifLargeTitle,
                    color = colors.ink,
                    modifier = Modifier.semantics { heading() },
                )
            } else {
                SectionTitle(stringResource(R.string.brief_ask_title))
            }
            Text(stringResource(R.string.brief_ask_subtitle), style = KetchupTheme.type.subheadline, color = colors.inkSoft)
        }
        NotepadField(question, { question = it }, canAsk, focus, onSubmit = { submit() })
        if (session.answer == Phase.Idle) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Kicker(stringResource(R.string.brief_or_try_one))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    stringArrayResource(R.array.brief_suggestions).forEach { suggestion ->
                        CapsuleButton(suggestion, onClick = {
                            question = suggestion
                            submit(suggestion)
                        }, fill = ButtonFill.Outline, compact = true)
                    }
                }
            }
        }
        val reduceMotion = KetchupTheme.reduceMotion
        AnimatedContent(
            targetState = session.answer,
            contentKey = { it::class },
            transitionSpec = {
                if (reduceMotion) fadeIn(Motion.fade()) togetherWith fadeOut(Motion.fade())
                else fadeIn(Motion.settle()) togetherWith fadeOut(Motion.fade())
            },
            label = "answer",
        ) { phase ->
            when (phase) {
                Phase.Idle -> Box(Modifier)
                Phase.Loading -> SkimmingView(
                    title = stringResource(R.string.brief_looking),
                    usually = stringResource(R.string.brief_usually_ask),
                    lines = session.skim?.ask,
                    titleStyle = KetchupTheme.type.serifTitle3,
                )
                is Phase.Failed -> BriefErrorCard(phase.message, onRetry = session::retryAsk, prominent = false)
                is Phase.Done -> {
                    val answer = phase.value.result
                    if (answer != null) {
                        AnswerCard(session.lastQuestion, answer, bylineDetails(phase.value, app), refs, Modifier.riseIn(0))
                    } else {
                        BriefErrorCard(stringResource(R.string.brief_no_answer), onRetry = session::retryAsk, prominent = false)
                    }
                }
            }
        }
    }
}

/**
 * The question box: a page of a notepad, ruled to the text, with Ask in
 * ketchup red at its foot.
 */
@Composable
private fun NotepadField(text: String, onChange: (String) -> Unit, canAsk: Boolean, focus: FocusRequester, onSubmit: () -> Unit) {
    val colors = KetchupTheme.colors
    var focused by remember { mutableStateOf(false) }
    val edge by animateFloatAsState(if (focused) 1f else 0f, Motion.fade(), label = "edge")
    val style = KetchupTheme.type.serifTitle3.copy(fontWeight = FontWeight.Normal, color = colors.ink)
    val fieldLabel = stringResource(R.string.brief_ask_field)
    val shape = RoundedCornerShape(16.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .background(colors.card, shape)
            .border(1.dp, lerp(colors.rule, colors.inkSoft, edge), shape)
            .padding(start = 18.dp, end = 18.dp, top = 16.dp, bottom = 14.dp),
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        BasicTextField(
            value = text,
            onValueChange = onChange,
            textStyle = style,
            cursorBrush = SolidColor(colors.ketchupText),
            minLines = 2,
            maxLines = 4,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = { onSubmit() }),
            modifier = Modifier
                .fillMaxWidth()
                .focusRequester(focus)
                .onFocusChanged { focused = it.isFocused }
                .semantics { contentDescription = fieldLabel }
                .drawBehind {
                    // Notepad rules: one under each line the field shows (2 to 4), the last at its foot.
                    val lines = (size.height / style.lineHeight.toPx()).roundToInt().coerceIn(2, 4)
                    val step = size.height / lines
                    for (i in 1..lines) {
                        val y = step * i - 0.5.dp.toPx()
                        drawLine(colors.rule, Offset(0f, y), Offset(size.width, y), 1.dp.toPx())
                    }
                },
            decorationBox = { inner ->
                Box {
                    if (text.isEmpty()) {
                        Text(stringResource(R.string.brief_ask_placeholder), style = style, color = colors.inkFaint, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    inner()
                }
            },
        )
        CapsuleButton(stringResource(R.string.brief_ask_button), onClick = onSubmit, compact = true, enabled = canAsk)
    }
}

/**
 * What Muse Spark said, under the question it answers, with the messages
 * behind it. When the chat doesn't say, the card goes quiet: no paper, a
 * dashed edge, and the closest messages it found.
 */
@Composable
fun AnswerCard(question: String, answer: ChatAnswer, byline: List<String>, refs: RefContext, modifier: Modifier = Modifier) {
    val colors = KetchupTheme.colors
    val answeredBy = stringResource(R.string.brief_answered_by)
    if (answer.found) {
        Column(modifier.paperCard(padding = 18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Kicker(question)
            val marks = remember(answer.answer) { BriefMarks.moneyAndTimes(answer.answer) }
            MarkedText(
                answer.answer,
                marks,
                style = KetchupTheme.type.serifTitle3.copy(fontWeight = FontWeight.Normal),
                color = colors.ink,
                sweep = true,
                delayMillis = 250,
            )
            RefChips(answer.refs, refs, limit = 2)
            MuseByline(answeredBy, byline, Modifier.padding(top = 2.dp))
        }
    } else {
        val parts = remember(answer.answer) { AnswerParts.of(answer.answer) }
        Column(
            modifier
                .fillMaxWidth()
                .dashedCard(colors.inkFaint)
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Kicker(question)
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(parts.headline, style = KetchupTheme.type.serifTitle2, color = colors.ink)
                parts.rest?.let { Text(it, style = KetchupTheme.type.body, color = colors.inkSoft) }
                // An answer Muse Spark couldn't back with a message.
                if (!parts.saysNotFound && answer.refs.isEmpty()) {
                    Text(
                        stringResource(R.string.brief_no_source),
                        style = KetchupTheme.type.footnote,
                        color = colors.inkSoft,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
            }
            if (answer.refs.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Kicker(stringResource(R.string.brief_closest))
                    RefChips(answer.refs, refs, limit = 2)
                }
            }
            MuseByline(answeredBy, byline, Modifier.padding(top = 2.dp))
        }
    }
}
