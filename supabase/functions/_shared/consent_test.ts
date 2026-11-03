// deno test supabase/functions/_shared/
// consent.ts: no row is a 403 the apps show as is, a row lets the call
// through, and a database problem is a 500, never a pass. The table's own
// rules (your row only, 18 or older, the server's time) are in
// supabase/tests/rls_check.sql.

import { assertEquals, assertFalse, assertMatch } from "jsr:@std/assert@1";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { CONSENT_MESSAGE, consentRefusal } from "./consent.ts";

function asUser(answer: { data: unknown; error: { code: string } | null }, seen: string[] = []): SupabaseClient {
  const query = {
    select: (columns: string) => { seen.push(`select ${columns}`); return query; },
    eq: (column: string, value: string) => { seen.push(`${column}=${value}`); return query; },
    maybeSingle: () => Promise.resolve(answer),
  };
  return { from: (table: string) => { seen.push(table); return query; } } as unknown as SupabaseClient;
}

Deno.test("no consent yet: a readable 403", async () => {
  const seen: string[] = [];
  const refused = await consentRefusal(asUser({ data: null, error: null }, seen), "u1");
  assertEquals(refused?.status, 403);
  assertEquals(await refused?.json(), { error: CONSENT_MESSAGE, kind: "consent_required" });
  assertEquals(seen, ["ai_consents", "select consented_at", "user_id=u1"]);
  assertFalse(/[–—]/.test(CONSENT_MESSAGE));
});

Deno.test("with consent: the call goes ahead", async () => {
  assertEquals(await consentRefusal(asUser({ data: { consented_at: "2026-11-03T20:00:00Z" }, error: null }), "u1"), null);
});

Deno.test("the database not answering is a 500, never a pass", async () => {
  const refused = await consentRefusal(asUser({ data: null, error: { code: "42P01" } }), "u1");
  assertEquals(refused?.status, 500);
  assertMatch((await refused?.json()).error, /Muse Spark/);
});
