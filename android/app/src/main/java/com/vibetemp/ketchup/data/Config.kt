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
}
