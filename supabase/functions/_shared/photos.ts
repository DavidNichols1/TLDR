// The photos Muse Spark sees with a chat: the newest few in the window it
// reads, as their small copies (768 px, 80 to 180 KB). They're downloaded
// with the caller's token, so Row Level Security still decides what can be
// read, and sent inline as data URLs: Meta never fetches from our storage.
// A photo that's missing, too big or slow is left out, and its line in the
// transcript stays "[photo]". Measured Nov 3, 2026: a 768 x 576 photo is
// about 590 prompt tokens.

import { encodeBase64 } from "jsr:@std/encoding@1/base64";
import type { MuseImage } from "./muse.ts";
import type { ChatMessage, Transcript } from "./transcript.ts";

/** Newest photos one request shows (about 600 tokens each). */
export const MAX_PHOTOS = 6;
const MAX_BYTES = 400_000;
const TIMEOUT_MS = 6_000;

/** "<chat>/<id>.jpg" → "<chat>/<id>_small.jpg", as the app names them. */
export function smallPath(path: string): string {
  return path.endsWith(".jpg") ? `${path.slice(0, -4)}_small.jpg` : `${path}_small`;
}

export interface Photos {
  /** message id → its photo's number in this request, oldest first */
  numbers: Map<string, number>;
  /** message id → data URL */
  urls: Map<string, string>;
  /** photo messages in the window that weren't attached (over the cap or failed) */
  skipped: number;
}

/** Downloads the newest MAX_PHOTOS photos among `messages`, in parallel. */
export async function loadPhotos(
  messages: ChatMessage[],
  storage: { url: string; apiKey: string; auth: string },
): Promise<Photos> {
  const withPhotos = messages.filter((m) => m.image_path);
  const newest = withPhotos.slice(-MAX_PHOTOS);
  const loaded = await Promise.all(newest.map(async (m) => {
    try {
      const res = await fetch(`${storage.url}/storage/v1/object/chat-media/${smallPath(m.image_path!)}`, {
        headers: { apikey: storage.apiKey, Authorization: storage.auth },
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
      if (!res.ok) {
        await res.body?.cancel();
        return null;
      }
      const bytes = new Uint8Array(await res.arrayBuffer());
      if (bytes.length === 0 || bytes.length > MAX_BYTES) return null;
      return { id: m.id, url: `data:image/jpeg;base64,${encodeBase64(bytes)}` };
    } catch {
      return null;
    }
  }));
  const numbers = new Map<string, number>();
  const urls = new Map<string, string>();
  for (const photo of loaded) {
    if (!photo) continue;
    numbers.set(photo.id, numbers.size + 1);
    urls.set(photo.id, photo.url);
  }
  return { numbers, urls, skipped: withPhotos.length - numbers.size };
}

/** The attached photos in number order, each labelled with its ref and sender. */
export function photoImages(photos: Photos, transcript: Transcript, messages: ChatMessage[],
  names: Map<string, string>): MuseImage[] {
  const refOf = new Map([...transcript.refs].map(([ref, id]) => [id, ref]));
  const byId = new Map(messages.map((m) => [m.id, m]));
  return [...photos.numbers].map(([id, number]) => {
    const sender = names.get(byId.get(id)?.sender ?? "") ?? "Someone";
    return { label: `Photo ${number}: [${refOf.get(id) ?? "?"}] from ${sender}`, url: photos.urls.get(id)! };
  });
}

/** The same window with nothing attached (Meta refused a photo). */
export function withoutPhotos(photos: Photos): Photos {
  return { numbers: new Map(), urls: new Map(), skipped: photos.skipped + photos.numbers.size };
}

/** What the prompt's header says about photos, if the window has any. */
export function photoNote(photos: Photos, windowHasPhotos: boolean): string {
  if (photos.numbers.size === 0) {
    return windowHasPhotos
      ? `Photos: "[photo]" marks a photo someone sent. You can't see it; any words after it are its caption.\n`
      : "";
  }
  return `Photos: the photos marked "[photo N]" are attached after the transcript, each labelled with its number, ref and sender. ` +
    `Read them like messages: a photo can hold what matters (a code, a time, a total, a plan). Cite a photo's ref like any message. ` +
    `Say what a photo shows only when it matters to the reader, and never describe or identify the people in it. ` +
    `"[photo]" with no number is a photo that isn't attached; any words after it are its caption.\n`;
}
