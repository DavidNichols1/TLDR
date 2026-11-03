package com.vibetemp.ketchup.debug

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.data.ApiException
import com.vibetemp.ketchup.data.AskResponse
import com.vibetemp.ketchup.data.BriefResponse
import com.vibetemp.ketchup.data.BriefSource
import com.vibetemp.ketchup.data.CatchUp
import com.vibetemp.ketchup.data.CatchUpResponse
import com.vibetemp.ketchup.data.ChatAnswer
import com.vibetemp.ketchup.data.KetchupJson
import com.vibetemp.ketchup.ui.brief.BriefActivity
import com.vibetemp.ketchup.ui.brief.BriefBackend
import com.vibetemp.ketchup.ui.brief.BriefErrors
import com.vibetemp.ketchup.ui.brief.BriefPage
import com.vibetemp.ketchup.ui.brief.BriefSection
import com.vibetemp.ketchup.ui.brief.BriefSession
import com.vibetemp.ketchup.ui.brief.Cited
import com.vibetemp.ketchup.ui.brief.CitedRequest
import com.vibetemp.ketchup.ui.brief.Phase
import com.vibetemp.ketchup.ui.brief.Refs
import com.vibetemp.ketchup.ui.brief.Skim
import com.vibetemp.ketchup.ui.brief.SkimLines
import com.vibetemp.ketchup.ui.design.CapsuleButton
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import java.time.Instant

// The brief slice's preview screens: Catch me up and Ask on fixtures, with
// no sign-in, no network and no Muse Spark calls. A scripted backend plays
// back the real Breck brief and answers (like iOS Debug/AIPreviewScreen.swift),
// and iOS's hand-written Instagram brief (Debug/WebChatPreviewScreen.swift)
// over the synthetic Instagram thread (made-up people). Names start with
// "brief" or "ask".

val BriefPreviews: Map<String, @Composable () -> Unit> = mapOf(
    "brief-loading" to { BriefPreview(Script.breck(catchUp = Script.FOREVER)) },
    "brief-loading-still" to { BriefPreview(Script.breck(catchUp = Script.FOREVER), reduceMotion = true) },
    "brief" to { BriefPreview(Script.breck(), landed = true) },
    "brief-plans" to { BriefPreview(Script.breck(), landed = true, section = BriefSection.Plans) },
    "brief-owes" to { BriefPreview(Script.breck(), landed = true, section = BriefSection.Owes) },
    "brief-questions" to { BriefPreview(Script.breck(), landed = true, section = BriefSection.Questions) },
    "brief-checked" to { BriefPreview(Script.breck(), landed = true, done = setOf(0, 2)) },
    "brief-cached" to { BriefPreview(Script.breck(cached = true), landed = true) },
    "brief-thread" to { BriefPreview(Script.instagram(), landed = true) },
    "brief-thread-loading" to { BriefPreview(Script.instagram(catchUp = Script.FOREVER)) },
    "brief-citations" to {
        BriefPreview(Script.instagram(), landed = true, cited = CitedRequest(tapped = "64", refs = listOf("63", "64")))
    },
    "brief-empty" to { BriefPreview(Script.breck(catchUp = { Script.NOTHING_NEW }), landed = true, nothingNew = true) },
    "brief-error" to { BriefPreview(Script.breck(), failed = "Request failed (502). Try again.") },
    "brief-signed-out" to { BriefPreview(Script.breck(signedIn = false)) },
    "brief-gone" to { BriefPage(null, onDone = {}, onJump = {}, onOpenApp = {}) },
    "ask-first" to { BriefPreview(Script.breck(), askFirst = true) },
    "ask" to { BriefPreview(Script.breck(), landed = true, section = BriefSection.Ask) },
    "ask-answer" to { BriefPreview(Script.breck(), landed = true, answered = Answered.FOUND, section = BriefSection.Ask) },
    "ask-notfound" to { BriefPreview(Script.breck(), landed = true, answered = Answered.NOT_FOUND, section = BriefSection.Ask) },
    "brief-own-task" to { OwnTaskLauncher() },
)

/**
 * Opens the real BriefActivity the way the reader service will: from a
 * context that isn't an activity, so it gets a task of its own and Back
 * returns here. Not signed in on a preview phone, so it lands on Sign in.
 */
@Composable
private fun OwnTaskLauncher() {
    val context = LocalContext.current
    val thread = previewData().instagramThread
    Column(
        Modifier
            .fillMaxSize()
            .background(KetchupTheme.colors.cream)
            .safeDrawingPadding()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Kicker("Reader handoff")
        Text("Open the brief in its own task", style = KetchupTheme.type.serifTitle2, color = KetchupTheme.colors.ink)
        CapsuleButton("Open over this app", onClick = { BriefActivity.start(context.applicationContext, thread) })
    }
}

private enum class Answered { FOUND, NOT_FOUND }

/**
 * One brief page on a [Script]. [landed] starts it with the catch-up
 * already here ([nothingNew] for the empty one), [failed] with a failure,
 * [answered] with an Ask answer, [askFirst] the way the chat's Ask button
 * opens it (no catch-up until Catch me up is tapped); otherwise it plays
 * the script. Try again, Catch me up and Ask play the script too. A tapped
 * source in a chat shows a toast here instead of jumping.
 */
@Composable
private fun BriefPreview(
    script: Script,
    landed: Boolean = false,
    nothingNew: Boolean = false,
    failed: String? = null,
    answered: Answered? = null,
    section: BriefSection? = null,
    cited: CitedRequest? = null,
    reduceMotion: Boolean? = null,
    done: Set<Int> = emptySet(),
    askFirst: Boolean = false,
) {
    val data = previewData()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val session = remember {
        BriefSession(script.source, script, scope, askFirst).apply {
            readerName = script.reader
            when {
                nothingNew -> catchUp = Phase.Done(Script.NOTHING_NEW)
                landed -> catchUp = Phase.Done(script.landed)
                failed != null -> catchUp = Phase.Failed(BriefErrors.message(ApiException(failed, 502)))
            }
            when (answered) {
                Answered.FOUND -> {
                    lastQuestion = data.answerQuestion
                    answer = Phase.Done(data.answer)
                }
                Answered.NOT_FOUND -> {
                    lastQuestion = data.notFoundQuestion
                    answer = Phase.Done(data.notFound)
                }
                null -> Unit
            }
        }
    }
    LaunchedEffect(session) { session.start() }
    BriefPage(
        session,
        onDone = { Toast.makeText(context, "Done closes the brief", Toast.LENGTH_SHORT).show() },
        onJump = { id -> Toast.makeText(context, "Jumps the chat to message ${id.take(8)}", Toast.LENGTH_SHORT).show() },
        onOpenApp = { Toast.makeText(context, "Opens Ketchup", Toast.LENGTH_SHORT).show() },
        initialSection = section,
        initialCited = cited,
        initiallyDone = done,
        reduceMotion = reduceMotion ?: KetchupTheme.reduceMotion,
    )
}

/**
 * A backend that plays back fixtures: the brief after a short wait (or
 * never, for the reading screen), any question answered from the Ask
 * fixtures ("hot tub" gets the one the chat doesn't say).
 */
private class Script(
    val source: BriefSource,
    val reader: String,
    val landed: CatchUpResponse,
    private val skim: Skim,
    private val lookup: (String) -> Cited?,
    private val catchUp: suspend () -> CatchUpResponse,
    private val answer: suspend (String) -> AskResponse,
    override val signedIn: Boolean,
) : BriefBackend {
    override suspend fun readerName() = reader
    override suspend fun skim() = skim
    override suspend fun catchUp(readerName: String) = catchUp()
    override suspend fun ask(question: String, readerName: String) = answer(question)
    override suspend fun cited(refs: Collection<String>) = refs.mapNotNull { ref -> lookup(ref)?.let { ref to it } }.toMap()
    override suspend fun caughtUp(until: Instant?) = Unit

    companion object {
        /** A catch-up that never lands, for the reading screen. */
        val FOREVER: suspend () -> CatchUpResponse = { awaitCancellation() }

        /** What `catch-up` sends back when nothing is unread. */
        val NOTHING_NEW = CatchUpResponse(kind = "catch_up", empty = true, model = "muse-spark-1.3", messageCount = 0)

        /** Breck, all 302 messages unread, read by David. */
        @Composable
        fun breck(
            catchUp: (suspend () -> CatchUpResponse)? = null,
            cached: Boolean = false,
            signedIn: Boolean = true,
        ): Script {
            val data = previewData()
            val brief = if (cached) data.brief.copy(cached = true, createdAt = "2026-11-02T21:40:00-07:00") else data.brief
            val names = data.members.associate { it.userId to it.name }
            val messages = data.messages.associateBy { it.id }
            val lines = data.messages.map { SkimLines.line(Refs.inChat(it, names, PreviewData.ME)) }
            return Script(
                source = data.breckSource,
                reader = PreviewData.MY_NAME,
                landed = brief,
                skim = Skim(catchUp = lines, ask = lines, unread = data.breck.unreadCount),
                lookup = { ref -> messages[ref]?.let { Refs.inChat(it, names, PreviewData.ME) } },
                catchUp = catchUp ?: {
                    delay(2_500)
                    brief
                },
                answer = { question ->
                    delay(2_000)
                    if ("hot tub" in question.lowercase()) data.notFound else data.answer
                },
                signedIn = signedIn,
            )
        }

        /** The synthetic Instagram thread "Breck Crew 🎿", 88 messages, and iOS's hand-written brief of it. */
        @Composable
        fun instagram(catchUp: (suspend () -> CatchUpResponse)? = null): Script {
            val data = previewData()
            val thread = data.instagramThread
            val brief = KetchupJson.decodeFromString(BriefResponse.serializer(CatchUp.serializer()), INSTAGRAM_BRIEF)
            val lines = thread.messages.indices.mapNotNull { Refs.inThread(thread, it.toString())?.let(SkimLines::line) }
            return Script(
                source = thread,
                reader = PreviewData.MY_NAME,
                landed = brief,
                skim = Skim(catchUp = lines, ask = lines, unread = thread.messages.size),
                lookup = { ref -> Refs.inThread(thread, ref) },
                catchUp = catchUp ?: {
                    delay(2_500)
                    brief
                },
                answer = { _ ->
                    delay(2_000)
                    INSTAGRAM_ANSWER
                },
                signedIn = true,
            )
        }

        private val INSTAGRAM_ANSWER = AskResponse(
            kind = "ask",
            source = "instagram",
            model = "muse-spark-1.3",
            messageCount = 88,
            latencyMs = 2_800,
            result = ChatAnswer(
                answer = "Jordan asked if you're bringing the speaker, and Sam needs your boot size by tomorrow.",
                found = true,
                refs = listOf("84", "85"),
            ),
        )

        /** Written by hand in catch-up-text's shape (iOS WebChatPreviewScreen), refs as indexes into the thread. */
        private const val INSTAGRAM_BRIEF = """
            {"kind":"catch_up","source":"instagram","cached":false,"model":"muse-spark-1.3","message_count":88,"latency_ms":17400,
             "result":{"tldr":"Breck is on: you leave Saturday at 6am from Jordan's, the Airbnb is ${'$'}248 each by Friday, and Priya gets in Saturday around 9pm.",
              "for_you":[{"text":"Jordan asked if you're bringing the speaker.","refs":[84]},{"text":"Sam needs your boot size by tomorrow for the rental.","refs":[85]}],
              "plans":[{"title":"Drive to Breck","starts_at":"2026-11-07T06:00:00-07:00","ends_at":null,"all_day":false,"location":"Jordan's place","status":"confirmed","who":["Jordan","Maya","Sam","David"],"refs":[44,75]},
                       {"title":"Dinner at The Rusty Gondola","starts_at":"2026-11-07T19:30:00-07:00","ends_at":null,"all_day":false,"location":"The Rusty Gondola","status":"confirmed","who":[],"refs":[53]}],
              "open_questions":[{"question":"David, are you bringing the speaker?","asked_by":"Jordan","refs":[84]}],
              "owes":[{"who":"David","owes_whom":"Maya","what":"${'$'}248 for the Airbnb, by Friday","refs":[23,71]}],
              "highlights":[{"text":"The trip became official","refs":[0]},{"text":"Garage has 2 spots, so both cars fit","refs":[63,64]}]}}
        """
    }
}
