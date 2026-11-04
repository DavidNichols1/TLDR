// report-alert: emails David when someone files a report (a long press on a
// message, or Report on a profile). The app has already saved the report
// (reports table, migration 0007); this only sends a heads-up. The email
// has no names and no message text: the reason, whether it's a message or
// a person, how many are waiting, and the SQL to read it (CLAUDE.md).
//
// POST { report_id }
// Authorization: Bearer <the reporter's Supabase access token>
//
// Needs two secrets, set by David: RESEND_API_KEY and REPORTS_EMAIL (where
// to send it). Without them it answers { emailed: false } and does nothing.
// Only the reporter's own report from the last 10 minutes, and each one is
// emailed once (reports.emailed_at).

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const REPORTS_EMAIL = Deno.env.get("REPORTS_EMAIL") ?? "";
const FROM = Deno.env.get("REPORTS_FROM") ?? "Cetchup <noreply@vibetemp.com>";

const REASONS: Record<string, string> = {
  spam: "Spam",
  harassment: "Harassment or bullying",
  hate: "Hate",
  threats: "Threats or violence",
  sexual: "Sexual content",
  other: "Something else",
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

// Counts only, never content.
const log = (fields: Record<string, unknown>) => console.log(JSON.stringify({ fn: "report-alert", ...fields }));

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "Sign in first" });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "Bad JSON" });
  }
  const reportId = typeof body.report_id === "string" ? body.report_id : "";
  if (!/^[0-9a-f-]{36}$/i.test(reportId)) return json(400, { error: "report_id required" });

  const asUser = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userErr } = await asUser.auth.getUser();
  if (userErr || !userData.user) return json(401, { error: "Sign in first" });

  // Nobody reads reports through the API, so the service role looks it up,
  // and only the caller's own, recent, not yet emailed one.
  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const since = new Date(Date.now() - 10 * 60_000).toISOString();
  const { data: report } = await admin
    .from("reports").select("id, reason, message_id")
    .eq("id", reportId).eq("reporter", userData.user.id)
    .is("emailed_at", null).gte("created_at", since)
    .maybeSingle();
  if (!report) return json(200, { emailed: false });

  if (!RESEND_API_KEY || !REPORTS_EMAIL) {
    log({ emailed: false, why: "not configured" });
    return json(200, { emailed: false });
  }

  // Claim it first, so two calls can't both send.
  const { data: claimed } = await admin
    .from("reports").update({ emailed_at: new Date().toISOString() })
    .eq("id", report.id).is("emailed_at", null)
    .select("id").maybeSingle();
  if (!claimed) return json(200, { emailed: false });

  const reason = REASONS[report.reason] ?? report.reason;
  const { count: waiting } = await admin
    .from("reports").select("id", { count: "exact", head: true }).is("reviewed_at", null);
  const text = [
    "Someone filed a report on Cetchup.",
    "",
    `Reason: ${reason}`,
    `About: ${report.message_id ? "a message" : "a person"}`,
    `Waiting for review: ${waiting ?? 1}`,
    "",
    "Read it in the Supabase SQL editor:",
    "  select created_at, reason, reported_name, message_body, message_image, note",
    `    from reports where id = '${report.id}';`,
    "",
    "When you've looked:",
    `  update reports set reviewed_at = now() where id = '${report.id}';`,
  ].join("\n");

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${RESEND_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: FROM, to: [REPORTS_EMAIL], subject: `Cetchup: a new report (${reason})`, text }),
  });
  if (!res.ok) {
    // Let a later call try again.
    await admin.from("reports").update({ emailed_at: null }).eq("id", report.id);
    log({ emailed: false, status: res.status });
    return json(200, { emailed: false });
  }
  log({ emailed: true, waiting });
  return json(200, { emailed: true });
});
