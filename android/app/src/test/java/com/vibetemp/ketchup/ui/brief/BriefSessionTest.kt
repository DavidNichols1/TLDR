package com.vibetemp.ketchup.ui.brief

import com.vibetemp.ketchup.Fixtures
import com.vibetemp.ketchup.data.ApiException
import com.vibetemp.ketchup.data.AskResponse
import com.vibetemp.ketchup.data.BriefResponse
import com.vibetemp.ketchup.data.BriefSource
import com.vibetemp.ketchup.data.CatchUp
import com.vibetemp.ketchup.data.CatchUpResponse
import com.vibetemp.ketchup.data.ChatAnswer
import com.vibetemp.ketchup.data.KetchupJson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** The page's state as the catch-up and Ask calls come back, on a fake backend (no network). */
class BriefSessionTest {

    private val brief = KetchupJson.decodeFromString(BriefResponse.serializer(CatchUp.serializer()), Fixtures.asset("brief.json"))
    private val answer = KetchupJson.decodeFromString(BriefResponse.serializer(ChatAnswer.serializer()), Fixtures.asset("ask.json"))
    private val chat = BriefSource.Chat("b0000000-0000-4000-8000-00000000b4ec", "Breck Weekend")

    private class Fake(
        var signedInNow: Boolean = true,
        var catchUps: MutableList<() -> CatchUpResponse> = mutableListOf(),
        var asks: MutableList<(String) -> AskResponse> = mutableListOf(),
    ) : BriefBackend {
        val readersSent = mutableListOf<String>()
        val questions = mutableListOf<String>()
        val caughtUpTo = mutableListOf<Instant?>()
        override val signedIn get() = signedInNow
        override suspend fun readerName() = "David"
        override suspend fun skim() = Skim(emptyList(), emptyList(), unread = 302)
        override suspend fun catchUp(readerName: String): CatchUpResponse {
            readersSent += readerName
            return catchUps.removeAt(0)()
        }
        override suspend fun ask(question: String, readerName: String): AskResponse {
            questions += question
            return asks.removeAt(0)(question)
        }
        override suspend fun cited(refs: Collection<String>) = refs.associateWith { Cited("Maya", "message $it") }
        override suspend fun caughtUp(until: Instant?) {
            caughtUpTo += until
        }
    }

    /** Runs every launch at once on this thread: the fake never suspends. */
    private fun session(fake: Fake) = BriefSession(chat, fake, CoroutineScope(Dispatchers.Unconfined))

    @Test
    fun notSignedInTurnsToSignInAndCallsNothing() {
        val fake = Fake(signedInNow = false)
        val s = session(fake).apply { start() }
        assertTrue(s.signedOut)
        assertEquals(BriefStage.SignedOut, s.stage())
        assertTrue(fake.readersSent.isEmpty())
    }

    @Test
    fun aBriefLandsWithItsSourcesAndMovesTheReadCursorToUntil() {
        val fake = Fake(catchUps = mutableListOf({ brief }))
        val s = session(fake).apply { start() }
        assertEquals(BriefStage.Brief, s.stage())
        assertEquals(302, s.skim?.unread)
        assertEquals("David", s.readerName)
        assertEquals(listOf("David"), fake.readersSent)
        assertEquals(listOf(Instant.parse("2026-11-03T04:08:44Z")), fake.caughtUpTo)
        assertEquals(Refs.all(brief.result!!).toSet(), s.cited.keys)
        // Starting again doesn't spend another catch-up.
        s.start()
        assertEquals(1, fake.readersSent.size)
    }

    @Test
    fun nothingNewLeavesTheCursorAlone() {
        val fake = Fake(catchUps = mutableListOf({ CatchUpResponse(kind = "catch_up", empty = true, messageCount = 0) }))
        val s = session(fake).apply { start() }
        assertEquals(BriefStage.Empty, s.stage())
        assertTrue(fake.caughtUpTo.isEmpty())
    }

    @Test
    fun aFailureSaysWhatHappenedMarksNothingAndTryAgainWorks() {
        val fake = Fake(catchUps = mutableListOf({ throw ApiException("Request failed (502). Try again.", 502) }, { brief }))
        val s = session(fake).apply { start() }
        assertEquals(Phase.Failed("Muse Spark is busy right now. Try again in a moment."), s.catchUp)
        assertTrue(fake.caughtUpTo.isEmpty())
        s.runCatchUp()
        assertEquals(BriefStage.Brief, s.stage())
        assertEquals(1, fake.caughtUpTo.size)
    }

    @Test
    fun anErrorInTheEnvelopeFails() {
        val fake = Fake(catchUps = mutableListOf({ CatchUpResponse(error = "You're not in this chat") }))
        val s = session(fake).apply { start() }
        assertEquals(Phase.Failed("You're not in this chat"), s.catchUp)
    }

    @Test
    fun theSessionEndingMidCallTurnsToSignIn() {
        val fake = Fake()
        fake.catchUps += {
            fake.signedInNow = false
            throw ApiException.notSignedIn()
        }
        val s = session(fake).apply { start() }
        assertTrue(s.signedOut)
        assertEquals(BriefStage.SignedOut, s.stage())
    }

    @Test
    fun askKeepsTheTrimmedQuestionAndItsSources() {
        val fake = Fake(catchUps = mutableListOf({ brief }), asks = mutableListOf({ _ -> answer }))
        val s = session(fake).apply { start() }
        s.ask("  How much do I owe and to who?  ")
        assertEquals(listOf("How much do I owe and to who?"), fake.questions)
        assertEquals("How much do I owe and to who?", s.lastQuestion)
        assertEquals(answer, s.answer.done)
        assertTrue(s.cited.keys.containsAll(answer.result!!.refs))
        // A blank question asks nothing.
        s.ask("   ")
        assertEquals(1, fake.questions.size)
    }

    @Test
    fun aFailedAskTriesTheSameQuestionAgain() {
        val fake = Fake(
            catchUps = mutableListOf({ brief }),
            asks = mutableListOf({ _ -> throw java.net.SocketTimeoutException() }, { _ -> answer }),
        )
        val s = session(fake).apply { start() }
        s.ask("When are we leaving?")
        assertEquals(Phase.Failed("Muse Spark took too long. Try again."), s.answer)
        s.retryAsk()
        assertEquals(listOf("When are we leaving?", "When are we leaving?"), fake.questions)
        assertEquals(answer, s.answer.done)
        assertNull(s.catchUp.let { if (it is Phase.Failed) it else null })
        assertFalse(s.signedOut)
    }
}
