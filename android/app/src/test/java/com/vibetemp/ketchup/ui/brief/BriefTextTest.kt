package com.vibetemp.ketchup.ui.brief

import com.vibetemp.ketchup.Fixtures
import com.vibetemp.ketchup.data.ApiException
import com.vibetemp.ketchup.data.BriefResponse
import com.vibetemp.ketchup.data.CatchUp
import com.vibetemp.ketchup.data.KetchupJson
import kotlinx.serialization.SerializationException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

/** Where the marker goes in Muse Spark's sentences, how answers split, and what errors say. */
class BriefTextTest {

    private fun marked(text: String) = BriefMarks.moneyAndTimes(text).map { text.substring(it) }

    @Test
    fun theBreckGistMarksItsTimesAndMoney() {
        val tldr = KetchupJson.decodeFromString(BriefResponse.serializer(CatchUp.serializer()), Fixtures.asset("brief.json")).result!!.tldr
        // As in iOS's ai-catchup screenshot: not "the Friday storm", not "refunded Friday night".
        assertEquals(listOf("Saturday 6am", "$90", "Saturday 7:30", "Thursday"), marked(tldr))
    }

    @Test
    fun anOldAmountStaysPlain() {
        val answer = "You owe $90 to Maya for the Airbnb (reduced from $140 after the Friday-night refund), and $20 to Jordan for gas since you're in his car."
        assertEquals(listOf("$90", "$20"), marked(answer))
        assertEquals(listOf("$90"), marked("It's $90 now, instead of $140. It was $150."))
    }

    @Test
    fun timesInTheirShapes() {
        val text = "Breck is on: you leave Saturday at 6am from Jordan's, the Airbnb is $248 each by Friday, and Priya gets in Saturday around 9pm."
        assertEquals(listOf("Saturday at 6am", "$248", "Friday", "9pm"), marked(text))
        assertEquals(listOf("Thursday noon", "5:45am", "$1,200.50"), marked("Confirm by Thursday noon, meet at 5:45am, it's $1,200.50 total"))
        assertEquals(listOf("7:30 p.m."), marked("Dinner at 7:30 p.m. sharp"))
        assertEquals(emptyList<String>(), marked("the Friday storm and 3 people"))
    }

    @Test
    fun theReadersNameAsAName() {
        val q = "Is David actually coming? Hearthstone needs a headcount by Thursday noon"
        assertEquals(listOf("David"), BriefMarks.name("David", q).map { q.substring(it) })
        assertTrue(BriefMarks.mentions("David", q))
        // A reader called Will doesn't light up every "will".
        assertFalse(BriefMarks.mentions("will", "who will drive?"))
        assertTrue(BriefMarks.mentions("will", "Will, are you driving?"))
        assertEquals(emptyList<IntRange>(), BriefMarks.name("", q))
    }

    @Test
    fun theFirstNameToGreet() {
        assertEquals("David", firstName("David Nichols"))
        assertEquals("David", firstName(" David "))
        assertNull(firstName(""))
        assertNull(firstName("Me"))
        assertNull(firstName("Someone"))
    }

    @Test
    fun notFoundAnswersSplitAfterTheChatDoesntSay() {
        assertEquals(
            AnswerParts("The chat doesn't say.", "Sam asked twice and nobody answered.", saysNotFound = true),
            AnswerParts.of("The chat doesn't say. Sam asked twice and nobody answered."),
        )
        assertEquals(AnswerParts("The chat doesn't say.", null, true), AnswerParts.of("The chat doesn’t say."))
        // No cut mid-sentence.
        assertEquals(
            AnswerParts("The chat doesn't say whether the house has a hot tub.", null, true),
            AnswerParts.of("The chat doesn't say whether the house has a hot tub."),
        )
        assertEquals(
            AnswerParts("Probably Saturday.", "Nobody confirmed it.", false),
            AnswerParts.of("Probably Saturday. Nobody confirmed it."),
        )
    }

    @Test
    fun errorsSaySomethingAPersonCanRead() {
        assertEquals("Muse Spark is busy right now. Try again in a moment.", BriefErrors.message(ApiException("Request failed (502). Try again.", 502)))
        assertEquals("Muse Spark isn't switched on yet. Try again soon.", BriefErrors.message(ApiException("Requested function was not found", 404)))
        assertEquals("That's a lot of catching up. Try again in a bit.", BriefErrors.message(ApiException("That's a lot of catching up. Try again in a bit.", 400)))
        assertEquals("Muse Spark took too long. Try again.", BriefErrors.message(SocketTimeoutException()))
        assertEquals("You're offline. Reconnect and try again.", BriefErrors.message(UnknownHostException("x.supabase.co")))
        assertEquals("Muse Spark sent back something unexpected. Try again.", BriefErrors.message(SerializationException("bad")))
        assertEquals("Couldn't reach Muse Spark. Try again.", BriefErrors.message(IOException("reset")))
    }

    @Test
    fun firstSentenceForAHeadline() {
        assertEquals("Muse Spark is busy right now." to "Try again in a moment.", Sentences.first("Muse Spark is busy right now. Try again in a moment."))
        assertEquals("No stop here" to null, Sentences.first("No stop here"))
    }
}
