// Muse Spark reads only for people who've said yes (migration 0010's
// ai_consents). Cetchup sends the messages you catch up on, your friends'
// included, to Meta's Muse Spark, so Apple's guideline 5.1.2(i) needs your
// explicit OK first, and Meta's terms (section 10.1) need you to be 18 or
// older. The apps ask once, with a sheet, and keep the answer here; until
// then catch-up and catch-up-text refuse with a 403 the apps show as is.
//
// Read as the caller: RLS shows each person only their own row.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const CONSENT_MESSAGE =
  "Cetchup needs your OK before it sends messages to Muse Spark. Allow it in the app, then try again.";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

/** Null when the caller has said yes; otherwise the response to send instead. */
export async function consentRefusal(asUser: SupabaseClient, user: string): Promise<Response | null> {
  const { data, error } = await asUser.from("ai_consents").select("consented_at").eq("user_id", user).maybeSingle();
  if (error) {
    console.error(JSON.stringify({ consent_error: error.code ?? "unknown" }));
    return json(500, { error: "Couldn't check your OK for Muse Spark. Try again." });
  }
  if (!data) return json(403, { error: CONSENT_MESSAGE, kind: "consent_required" });
  return null;
}
