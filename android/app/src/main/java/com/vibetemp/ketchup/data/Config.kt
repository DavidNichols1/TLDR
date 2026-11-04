package com.vibetemp.ketchup.data

/**
 * Backend coordinates, copied from iOS `Config.swift`. The publishable key is
 * safe to ship: it only grants what Row Level Security allows. The
 * service-role key and the Meta Model API key never appear in the app or
 * this repo.
 */
object Config {
    /** Supabase project cfqlnthmqwkhjbhylvgu (still named "TLDR" in the dashboard). */
    const val SUPABASE_URL = "https://cfqlnthmqwkhjbhylvgu.supabase.co"

    /** Publishable (client) key. Not a secret: RLS is the gate. */
    const val PUBLISHABLE_KEY = "sb_publishable_wBQM04epqb9p6riHKjGmCA_YNF9OpZl"

    /**
     * Digits in the emailed sign-in code. Must match the project's
     * Auth > Sign In / Providers > Email > "Email OTP Length" (8 on this project).
     */
    const val OTP_LENGTH = 8

    /** Realtime websocket (Phoenix protocol), for the chat slice's `data/realtime/`. */
    const val REALTIME_URL =
        "wss://cfqlnthmqwkhjbhylvgu.supabase.co/realtime/v1/websocket?apikey=$PUBLISHABLE_KEY&vsn=1.0.0"

    /** The Terms of Service, opened in the system browser (sign-in and the terms screen). */
    const val TERMS_URL = "https://cetchup.ai/terms"

    /** The Privacy Policy, opened in the system browser. */
    const val PRIVACY_URL = "https://cetchup.ai/privacy"

    /**
     * The version of the terms the app asks people to agree to: the date they
     * were published, `YYYY-MM-DD` (migration 0011, data/TermsGate.kt).
     * Bumping it to a new date asks everyone to agree again, once, before the
     * app. The terms screen's "Updated" line is read from it.
     */
    const val TERMS_VERSION = "2026-11-04"
}
