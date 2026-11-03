package com.vibetemp.ketchup.ui.plans

import com.vibetemp.ketchup.data.ApiException
import com.vibetemp.ketchup.ui.brief.BriefErrors
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Android has no purchase flow (it's sideloaded), so a plan's refusals just
 * have to read well: the brief shows the server's own sentence for the 402
 * (today's allowance) and the 403 (no Muse Spark consent yet), word for word
 * from supabase/functions/_shared/plan.ts and consent.ts.
 */
class PlanRefusalsTest {

    private fun shown(status: Int, body: String) = BriefErrors.message(ApiException.from(status, body))

    @Test
    fun theAllowanceRefusalReadsAsTheServerSaysIt() {
        val usedUp = """{"error":"You've used today's 150 free messages.","kind":"plan_limit","plan":"free","used":150,
            "limit":150,"needed":302,"resets_at":"2026-11-04T07:00:00+00:00"}"""
        assertEquals("You've used today's 150 free messages.", shown(402, usedUp))

        val tooBig = """{"error":"This catch-up reads 302 messages. Free covers 150 a day, and you have 38 left today.",
            "kind":"plan_limit","plan":"free","used":112,"limit":150,"needed":302,"resets_at":null}"""
        assertEquals("This catch-up reads 302 messages. Free covers 150 a day, and you have 38 left today.", shown(402, tooBig))
    }

    @Test
    fun theConsentRefusalReadsAsTheServerSaysIt() {
        val noConsent = """{"error":"Ketchup needs your OK before it sends messages to Muse Spark. Allow it in the app, then try again.",
            "kind":"consent_required"}"""
        assertEquals("Ketchup needs your OK before it sends messages to Muse Spark. Allow it in the app, then try again.",
            shown(403, noConsent))
    }
}
