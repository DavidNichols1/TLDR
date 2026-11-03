// delete-account: Settings → Delete account. Deletes the caller's account
// and everything it wrote, then the files they uploaded.
//
// POST {}
// Authorization: Bearer <the person's Supabase access token>
//
// 1. delete_account() as the caller (their token): one transaction for every
//    row (profile, memberships, messages, their catch-ups, and friends' saved
//    catch-ups that read them; migration 0007). It returns the files they
//    own. If it fails, nothing has changed, photos included.
// 2. Those files, through the Storage API with the service role. By now the
//    person's own permissions went with their rows (reading a chat photo
//    needs membership), which is why this runs here and not on the phone.
//    A file that won't delete is logged by count; the account is gone either
//    way.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const BUCKETS = ["avatars", "chat-media"];

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

// Counts only, never ids or paths.
const log = (fields: Record<string, unknown>) => console.log(JSON.stringify({ fn: "delete-account", ...fields }));

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "Sign in first" });

  const asUser = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userErr } = await asUser.auth.getUser();
  if (userErr || !userData.user) return json(401, { error: "Sign in first" });

  // Rows first, as the person.
  const { data: files, error: rpcErr } = await asUser.rpc("delete_account");
  if (rpcErr) {
    log({ deleted: false });
    return json(500, { error: "Couldn't delete your account. Nothing was changed. Try again." });
  }

  // Then their files, with the service role.
  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  let removed = 0;
  let failed = 0;
  for (const bucket of BUCKETS) {
    const paths: string[] = Array.isArray(files?.[bucket]) ? files[bucket] : [];
    // The API takes up to 1,000 names a call.
    for (let start = 0; start < paths.length; start += 500) {
      const batch = paths.slice(start, start + 500);
      const { data, error } = await admin.storage.from(bucket).remove(batch);
      if (error) failed += batch.length;
      else removed += data?.length ?? 0;
    }
  }
  log({ deleted: true, files: removed, file_errors: failed });
  return json(200, { deleted: true, files: removed, file_errors: failed });
});
