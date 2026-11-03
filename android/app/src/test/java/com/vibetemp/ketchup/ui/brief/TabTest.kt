package com.vibetemp.ketchup.ui.brief

import com.vibetemp.ketchup.Fixtures
import com.vibetemp.ketchup.data.BriefResponse
import com.vibetemp.ketchup.data.CatchUp
import com.vibetemp.ketchup.data.KetchupJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigDecimal
import java.util.Locale

/** The money lines on the diner check, from Muse Spark's real Breck owes (iOS `Tab`). */
class TabTest {

    private val owes = KetchupJson.decodeFromString(BriefResponse.serializer(CatchUp.serializer()), Fixtures.asset("brief.json"))
        .result!!.owes

    private fun money(s: String) = BigDecimal(s)

    @Test
    fun breckCheckReadsLikeIOS() {
        val tab = Tab(owes, reader = "David")

        // Your tab: what David owes, in Muse Spark's order.
        assertEquals(listOf("Maya", "Jordan"), tab.yours.map { it.to })
        assertTrue(tab.yours.all { it.fromReader && !it.toReader })
        assertEquals(listOf("Airbnb", "Gas"), tab.yours.map { it.label })
        assertEquals(listOf(money("90"), money("20")), tab.yours.map { it.amount })
        assertEquals(0, money("110").compareTo(tab.youOwe))
        assertEquals("$", tab.youOweSymbol)
        assertEquals(0, BigDecimal.ZERO.compareTo(tab.owedToYou))

        // Everyone else: money between other people.
        assertEquals(listOf("Sam", "Sam", "Priya", "Theo"), tab.others.map { it.from })
        assertEquals(listOf("Theo", "Jordan", "Maya", "Maya"), tab.others.map { it.to })
        assertEquals("Mission Ballroom tickets", tab.others.first().label)
        assertEquals(money("45"), tab.others.first().amount)

        // To bring: no amount.
        assertEquals(1, tab.toBring.size)
        val bring = tab.toBring.single()
        assertTrue(bring.fromReader)
        assertNull(bring.amount)
        assertNull(bring.to)
        assertEquals("Speaker and Catan", bring.label)

        // Every line keeps its sources.
        assertTrue((tab.yours + tab.others + tab.toBring).all { it.refs.isNotEmpty() })
    }

    @Test
    fun totalsFormatInTheReadersNumbers() {
        assertEquals("$110.00", Tab.format(Tab(owes, "David").youOwe, "$", Locale.US))
        assertEquals("$1,200.50", Tab.format(money("1200.5"), "$", Locale.US))
        assertEquals("€45.00", Tab.format(money("45"), "€", Locale.US))
    }

    @Test
    fun parseReadsTheAmountAndTheItem() {
        assertEquals(Tab.Parsed(money("90"), "$", "Airbnb"), Tab.parse("$90 for Airbnb"))
        assertEquals(Tab.Parsed(money("90"), "$", "Airbnb"), Tab.parse("Send Maya $90 for the Airbnb"))
        assertEquals(Tab.Parsed(money("248"), "$", "Airbnb, by Friday"), Tab.parse("$248 for the Airbnb, by Friday"))
        assertEquals(Tab.Parsed(money("1200.50"), "$", "Cabin"), Tab.parse("$1,200.50 for the cabin"))
        assertEquals(Tab.Parsed(money("45"), "€", "Tickets"), Tab.parse("€ 45 for tickets"))
        // The comma after an amount isn't a thousands separator.
        assertEquals(money("540"), Tab.parse("$540, so $90 each").amount)
        assertEquals(Tab.Parsed(null, "$", "Speaker and Catan"), Tab.parse("Bring the speaker and Catan"))
        assertEquals(Tab.Parsed(null, "$", "Snacks"), Tab.parse("brings snacks."))
    }

    @Test
    fun theReaderIsYouByNameOrByWord() {
        assertTrue(Tab.isReader("David", "David"))
        assertTrue(Tab.isReader("david", "David Nichols"))
        assertTrue(Tab.isReader("David Nichols", "David Nichols"))
        assertTrue(Tab.isReader("you", ""))
        assertTrue(Tab.isReader("Me", "Me"))
        assertFalse(Tab.isReader("Maya", "David"))
        assertFalse(Tab.isReader(null, "David"))
        assertFalse(Tab.isReader("  ", "David"))
        assertFalse(Tab.isReader("David", ""))
    }

    @Test
    fun owedToTheReaderCountsSeparately() {
        val tab = Tab(
            listOf(
                CatchUp.Owe(who = "Maya", owesWhom = "David", what = "$20 for gas", refs = listOf("a")),
                CatchUp.Owe(who = "Sam", owesWhom = "you", what = "€15 for lift tickets", refs = listOf("b")),
                CatchUp.Owe(who = "David", owesWhom = "Theo", what = "$5 for coffee", refs = listOf("c")),
            ),
            reader = "David",
        )
        // What the reader owes comes first, then what's owed to them.
        assertEquals(listOf("Theo", "David", "you"), tab.yours.map { it.to })
        assertEquals(0, money("5").compareTo(tab.youOwe))
        assertEquals(0, money("35").compareTo(tab.owedToYou))
        assertEquals("€", tab.owedSymbol)
        assertTrue(tab.others.isEmpty())
    }
}
