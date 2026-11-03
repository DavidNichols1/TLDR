package com.vibetemp.ketchup.ui.brief

import android.os.Build
import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.BriefSource
import com.vibetemp.ketchup.data.CatchUpResponse
import com.vibetemp.ketchup.data.TextThread
import com.vibetemp.ketchup.ui.design.CapsuleButton
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import com.vibetemp.ketchup.ui.theme.Motion
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/** Where the page is: what the bar and the content show. */
enum class BriefStage { SignedOut, Gone, Reading, Failed, Empty, Brief }

fun BriefSession?.stage(): BriefStage = when {
    this == null -> BriefStage.Gone
    signedOut -> BriefStage.SignedOut
    else -> when (val phase = catchUp) {
        Phase.Idle, Phase.Loading -> BriefStage.Reading
        is Phase.Failed -> BriefStage.Failed
        is Phase.Done -> if (phase.value.result == null) BriefStage.Empty else BriefStage.Brief
    }
}

/**
 * Catch me up and Ask the chat, for one source, as a page: the bar across
 * the top, then what Muse Spark is doing or what it found, then Ask under
 * it. [session] is null when the source is gone (the process died in
 * between). For a Ketchup chat a tapped source calls [onJump] with the
 * message's id; for a thread read off another app it opens the cited
 * messages in a sheet, since there's no chat in Ketchup to jump into.
 */
@Composable
fun BriefPage(
    session: BriefSession?,
    onDone: () -> Unit,
    onJump: (String) -> Unit,
    onOpenApp: () -> Unit,
    initialSection: BriefSection? = null,
    initialCited: CitedRequest? = null,
    initiallyDone: Set<Int> = emptySet(),
    reduceMotion: Boolean = KetchupTheme.reduceMotion,
) {
    val colors = KetchupTheme.colors
    val scroll = rememberScrollState()
    val focus = remember { FocusRequester() }
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val margin = with(LocalDensity.current) { 12.dp.toPx() }
    var sheet by remember { mutableStateOf(initialCited) }
    // Where the scrolling content starts on screen, and where each section starts in it.
    var viewportTop by remember { mutableFloatStateOf(0f) }
    val sections = remember { mutableStateMapOf<BriefSection, Float>() }
    fun place(section: BriefSection, yInRoot: Float) {
        sections[section] = yInRoot - viewportTop + scroll.value
    }

    val stage = session.stage()
    val thread = session?.source as? TextThread
    val app = thread?.source?.appName
    val askShown = session != null && (stage == BriefStage.Brief || (stage == BriefStage.Empty && thread == null))

    // A brief landing while the page is open gets a success tap.
    var landed by remember { mutableStateOf(stage) }
    LaunchedEffect(stage) {
        if (landed == BriefStage.Reading && stage == BriefStage.Brief) {
            view.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY)
        }
        landed = stage
    }
    // Asking brings the question and what comes back up to the top of the page.
    LaunchedEffect(session) {
        session ?: return@LaunchedEffect
        var asked: Phase<*> = session.answer
        snapshotFlow { session.answer }.collect { phase ->
            val moved = phase != asked && (phase == Phase.Loading || asked == Phase.Loading)
            asked = phase
            val top = sections[BriefSection.Ask]
            if (moved && top != null) {
                // The new content animates in: wait for the room to scroll (or the page's end).
                val target = (top - margin).toInt().coerceAtLeast(0)
                withTimeoutOrNull(700) { snapshotFlow { scroll.maxValue }.first { it >= target } }
                scroll.animateScrollTo(target.coerceAtMost(scroll.maxValue))
            }
        }
    }
    // A preview can open scrolled to a section, once it's laid out.
    LaunchedEffect(initialSection) {
        val section = initialSection ?: return@LaunchedEffect
        val y = snapshotFlow { sections[section] }.filterNotNull().first()
        delay(450)
        scroll.animateScrollTo((y - margin).toInt().coerceAtLeast(0))
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(colors.cream),
    ) {
        Column(Modifier.fillMaxSize()) {
            val title = when (val source = session?.source) {
                null -> stringResource(R.string.brief_kicker)
                is TextThread -> stringResource(R.string.brief_running_head_thread, source.source.appName, source.displayTitle)
                is BriefSource.Chat -> source.displayTitle
            }
            BriefTopBar(
                title = title,
                scrolled = scroll.value > 0,
                onDone = onDone,
                onAsk = if (!askShown) null else {
                    {
                        scope.launch {
                            sections[BriefSection.Ask]?.let { scroll.animateScrollTo((it - margin).toInt().coerceAtLeast(0)) }
                            focus.requestFocus()
                        }
                    }
                },
            )
            Column(
                Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .onGloballyPositioned { viewportTop = it.positionInRoot().y }
                    .verticalScroll(scroll)
                    .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom + WindowInsetsSides.Horizontal))
                    .padding(start = 20.dp, end = 20.dp, top = 14.dp, bottom = 40.dp),
                verticalArrangement = Arrangement.spacedBy(40.dp),
            ) {
                AnimatedContent(
                    targetState = stage,
                    transitionSpec = {
                        val enter = when {
                            // The brief's sections rise in on their own.
                            targetState == BriefStage.Brief -> EnterTransition.None
                            reduceMotion -> fadeIn(Motion.fade())
                            else -> fadeIn(Motion.settle())
                        }
                        (enter togetherWith fadeOut(Motion.fade())).using(null)
                    },
                    label = "stage",
                ) { shown ->
                    StageContent(shown, session, onOpenApp, initiallyDone, onSection = ::place) { ref, all ->
                        if (thread != null) sheet = CitedRequest(ref, all) else onJump(ref)
                    }
                }
                if (askShown) {
                    AskSection(
                        session,
                        rememberRefContext(session) { ref, all -> if (thread != null) sheet = CitedRequest(ref, all) else onJump(ref) },
                        focus,
                        app = app,
                        modifier = Modifier
                            .onGloballyPositioned { place(BriefSection.Ask, it.positionInRoot().y) }
                            .riseIn(7, HAND_OVER_MS),
                    )
                }
                if (thread != null && stage == BriefStage.Brief) {
                    ThreadFooter(thread, session?.catchUp?.done)
                }
            }
        }
        val request = sheet
        if (request != null && session != null && app != null) {
            CitedSheet(request, session.cited, app, session.source.displayTitle) { sheet = null }
        }
    }
}

@Composable
private fun StageContent(
    stage: BriefStage,
    session: BriefSession?,
    onOpenApp: () -> Unit,
    initiallyDone: Set<Int>,
    onSection: (BriefSection, Float) -> Unit,
    open: (String, List<String>) -> Unit,
) {
    val thread = session?.source as? TextThread
    when (stage) {
        BriefStage.Gone -> GoneCard()
        BriefStage.SignedOut -> DropNote(
            stringResource(R.string.brief_signed_out),
            stringResource(R.string.brief_signed_out_body),
        ) { CapsuleButton(stringResource(R.string.brief_open_ketchup), onClick = onOpenApp, compact = true) }
        BriefStage.Reading -> {
            session ?: return
            val unread = if (thread != null) thread.messages.size else session.skim?.unread
            SkimmingView(
                title = if (unread == null || unread <= 0) stringResource(R.string.brief_reading_chat)
                else pluralStringResource(R.plurals.brief_reading_count, unread, count(unread)),
                subtitle = if (thread != null) stringResource(R.string.brief_skimming_thread, thread.source.appName)
                else stringResource(R.string.brief_skimming),
                usually = stringResource(if (thread != null) R.string.brief_usually_thread else R.string.brief_usually),
                lines = session.skim?.catchUp,
            )
        }
        BriefStage.Failed -> {
            session ?: return
            val failed = session.catchUp as? Phase.Failed ?: return
            BriefErrorCard(
                failed.message,
                onRetry = session::runCatchUp,
                note = stringResource(if (thread != null) R.string.brief_nothing_saved else R.string.brief_nothing_marked),
                modifier = Modifier.riseIn(0),
            )
        }
        BriefStage.Empty -> if (thread != null) {
            DropNote(stringResource(R.string.brief_thread_empty), stringResource(R.string.brief_thread_empty_body), Modifier.riseIn(0))
        } else {
            DropNote(stringResource(R.string.brief_caught_up), stringResource(R.string.brief_caught_up_body), Modifier.riseIn(0))
        }
        BriefStage.Brief -> {
            session ?: return
            val response = session.catchUp.done ?: return
            val brief = response.result ?: return
            CatchUpContent(
                brief = brief,
                byline = bylineDetails(response, thread?.source?.appName),
                chatName = session.source.displayTitle,
                app = thread?.source?.appName ?: "Ketchup",
                readerName = session.readerName,
                refs = rememberRefContext(session, open),
                onSection = onSection,
                initiallyDone = initiallyDone,
            )
        }
    }
}

/** What a thread's catch-up covered, and that nothing was saved, said once and quietly. */
@Composable
private fun ThreadFooter(thread: TextThread, response: CatchUpResponse?) {
    val read = response?.messageCount ?: thread.messages.size
    val whole = thread.stats?.reachedStart == true && response?.truncated != true
    val covers = if (whole) stringResource(R.string.brief_footer_whole)
    else pluralStringResource(R.plurals.brief_footer_last, read, count(read))
    Text(
        "$covers ${stringResource(R.string.brief_footer_thread, thread.source.appName)}",
        style = KetchupTheme.type.footnote,
        color = KetchupTheme.colors.inkSoft,
        modifier = Modifier.riseIn(8, HAND_OVER_MS),
    )
}
