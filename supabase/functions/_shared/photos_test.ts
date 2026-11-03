// deno test supabase/functions/_shared/
// Offline checks for the photos a catch-up attaches: which ones, their
// numbers and labels, and what's left out. fetch is stubbed; no network.

import { assertEquals } from "jsr:@std/assert@1";
import { loadPhotos, MAX_PHOTOS, photoImages, photoNote, smallPath, withoutPhotos } from "./photos.ts";
import { buildTranscript, type ChatMessage } from "./transcript.ts";

const msg = (id: string, minute: number, image_path: string | null = null, body = ""): ChatMessage =>
  ({ id, sender: "u1", body, created_at: `2026-11-07T02:${String(minute).padStart(2, "0")}:00Z`, image_path });

Deno.test("small copies are named like the app names them", () => {
  assertEquals(smallPath("c/abc.jpg"), "c/abc_small.jpg");
});

Deno.test("the newest photos are attached, numbered oldest first; failures stay [photo]", async () => {
  const messages = [msg("t", 0, null, "hi")];
  for (let i = 1; i <= MAX_PHOTOS + 2; i++) messages.push(msg(`p${i}`, i, `c/p${i}.jpg`, i === 8 ? "the cabin" : ""));
  const asked: string[] = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = ((input: string | URL | Request) => {
    const url = String(input);
    asked.push(url.slice(url.lastIndexOf("/") + 1));
    // p4's small copy is missing; everything else is a 3-byte "photo".
    return Promise.resolve(url.endsWith("p4_small.jpg")
      ? new Response("nope", { status: 400 })
      : new Response(new Uint8Array([1, 2, 3])));
  }) as typeof fetch;
  try {
    const photos = await loadPhotos(messages, { url: "https://x.test", apiKey: "k", auth: "Bearer t" });
    // Only the newest six were asked for: p3 to p8.
    assertEquals(asked.sort(), ["p3_small.jpg", "p4_small.jpg", "p5_small.jpg", "p6_small.jpg", "p7_small.jpg", "p8_small.jpg"]);
    assertEquals([...photos.numbers], [["p3", 1], ["p5", 2], ["p6", 3], ["p7", 4], ["p8", 5]]);
    assertEquals(photos.urls.get("p3"), "data:image/jpeg;base64,AQID");
    assertEquals(photos.skipped, 3); // p1, p2 (over the cap) and p4 (failed)

    const names = new Map([["u1", "Maya"]]);
    const t = buildTranscript([], messages, names, "America/Denver", photos.numbers);
    const lines = t.text.split("\n");
    assertEquals(lines[2], "[m2] Fri, Nov 6, 7:01 PM · Maya: [photo]");
    assertEquals(lines[4], "[m4] Fri, Nov 6, 7:03 PM · Maya: [photo 1]");
    assertEquals(lines[9], "[m9] Fri, Nov 6, 7:08 PM · Maya: [photo 5] the cabin");
    const images = photoImages(photos, t, messages, names);
    assertEquals(images.map((i) => i.label), [
      "Photo 1: [m4] from Maya", "Photo 2: [m6] from Maya", "Photo 3: [m7] from Maya",
      "Photo 4: [m8] from Maya", "Photo 5: [m9] from Maya",
    ]);
    assertEquals(photoNote(photos, true).startsWith(`Photos: the photos marked "[photo N]" are attached`), true);
    assertEquals(withoutPhotos(photos).skipped, 8);
    assertEquals(photoNote(withoutPhotos(photos), true).startsWith(`Photos: "[photo]" marks a photo`), true);
    assertEquals(photoNote(withoutPhotos(photos), false), "");
  } finally {
    globalThis.fetch = realFetch;
  }
});
