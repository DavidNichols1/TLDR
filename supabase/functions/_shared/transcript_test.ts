// deno test supabase/functions/_shared/
// Offline checks for the transcript both edge functions send to Muse Spark
// and for the refs coming back. No network, no database.

import { assertEquals } from "jsr:@std/assert@1";
import { buildTextTranscript, buildTranscript, resolveRefs } from "./transcript.ts";
import { cleanAnswer, cleanCatchUp } from "./brief.ts";

Deno.test("catch-up transcript keeps its exact line format", () => {
  const names = new Map([["u1", "Maya"], ["u2", "David"]]);
  const t = buildTranscript(
    [{ id: "a", sender: "u1", body: "skiing?", created_at: "2026-11-02T01:00:00Z" }],
    [
      { id: "b", sender: "u2", body: "yes\n\n  Saturday", created_at: "2026-11-02T02:41:00Z" },
      { id: "c", sender: "u9", body: "who am I", created_at: "2026-11-02T03:00:00Z" },
    ],
    names,
    "America/Denver",
  );
  assertEquals(t.text, [
    "=== ALREADY READ (context only, do not summarize) ===",
    "[m1] Sun, Nov 1, 6:00 PM · Maya: skiing?",
    "=== UNREAD (summarize these) ===",
    "[m2] Sun, Nov 1, 7:41 PM · David: yes / Saturday",
    "[m3] Sun, Nov 1, 8:00 PM · Someone: who am I",
  ].join("\n"));
  assertEquals([...t.refs], [["m1", "a"], ["m2", "b"], ["m3", "c"]]);
});

Deno.test("text transcript: refs are request indexes, times optional", () => {
  const t = buildTextTranscript([
    { sender: "Maya", text: "leaving at 6\nfrom Jordan's", at: "2026-11-07T13:00:00Z" },
    { sender: "Sam", text: "x".repeat(700), at: null },
  ], "America/Denver", 40);
  const lines = t.text.split("\n");
  assertEquals(lines[0], "=== MESSAGES ===");
  assertEquals(lines[1], "[m1] Sat, Nov 7, 6:00 AM · Maya: leaving at 6 / from Jordan's");
  assertEquals(lines[2], `[m2] Sam: ${"x".repeat(600)}…`);
  assertEquals([...t.refs], [["m1", 40], ["m2", 41]]);
  assertEquals(buildTextTranscript([], "UTC").text, "");
});

Deno.test("index 0 is a real ref; unknown and repeated refs are dropped", () => {
  const refs = new Map([["m1", 0], ["m2", 1]]);
  assertEquals(resolveRefs(["m1", "[m2]", "m1", "m9", 3, null], refs), [0, 1]);
  const brief = cleanCatchUp({
    tldr: "Trip is Saturday \u2014 6am", // an em dash the cleaner must strip
    highlights: [{ text: "Leaving at 6", refs: ["m1"] }, { text: "Made up", refs: ["m9"] }],
    plans: [], open_questions: [], owes: [], for_you: [],
  }, refs);
  assertEquals(brief.tldr, "Trip is Saturday, 6am");
  assertEquals(brief.highlights, [{ text: "Leaving at 6", refs: [0] }]);
  const answer = cleanAnswer({ answer: "6am", found: true, refs: ["m2"] }, refs);
  assertEquals(answer, { answer: "6am", found: true, refs: [1] });
});
