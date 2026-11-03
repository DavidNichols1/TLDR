// Meta Model API client (Muse Spark).
//
// The key lives only in the edge function's secrets (META_API_KEY), never in
// the app or this repo. Set it with:
//   supabase secrets set META_API_KEY=... --project-ref cfqlnthmqwkhjbhylvgu
//
// Wire format from Meta's docs (https://dev.meta.ai/docs):
//   POST https://api.meta.ai/v1/chat/completions, Authorization: Bearer <key>
//   response_format json_schema = schema-constrained decoding
//   max_completion_tokens counts reasoning + visible output
//   reasoning_effort: minimal | low | medium | high | xhigh | max
//   429 / 500 / 503 are retryable (honor Retry-After); other 4xx are not.
// Optional overrides: META_MODEL (default muse-spark-1.3), META_REASONING (default low).

const ENDPOINT = "https://api.meta.ai/v1/chat/completions";
const TIMEOUT_MS = 110_000; // stay under the edge function's wall-clock limit

export interface JSONSchema {
  name: string;
  schema: Record<string, unknown>;
}

export interface MuseRequest {
  system: string;
  user: string;
  /** Ask the model for a JSON object back. */
  json?: boolean;
  /** Constrain the output to this schema (implies json). */
  schema?: JSONSchema;
  temperature?: number;
  maxTokens?: number;
  /** Keep the API's error text out of the logs: the request carries messages
   *  that must not be logged (catch-up-text). Status and code still log. */
  quiet?: boolean;
}

export interface MuseResponse {
  text: string;
  model: string;
  usage: { prompt: number; completion: number; reasoning: number };
}

export class MuseNotConfigured extends Error {}

export class MuseError extends Error {
  constructor(message: string, readonly status: number, readonly code: string | null) {
    super(message);
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function post(key: string, body: Record<string, unknown>): Promise<Response> {
  return fetch(ENDPOINT, {
    method: "POST",
    headers: { "Authorization": `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
}

async function errorOf(res: Response): Promise<MuseError> {
  // An unknown path returns 404 with an empty body, so read text, not json.
  const raw = await res.text().catch(() => "");
  let message = raw.slice(0, 300) || res.statusText;
  let code: string | null = null;
  try {
    const e = JSON.parse(raw)?.error;
    if (e?.message) message = String(e.message);
    if (e?.code) code = String(e.code);
  } catch { /* not JSON */ }
  return new MuseError(`Meta Model API ${res.status}: ${message}`, res.status, code);
}

export async function museChat(req: MuseRequest): Promise<MuseResponse> {
  const key = Deno.env.get("META_API_KEY");
  if (!key) throw new MuseNotConfigured("META_API_KEY is not set on this project");

  const body: Record<string, unknown> = {
    model: Deno.env.get("META_MODEL") || "muse-spark-1.3",
    messages: [
      { role: "system", content: req.system },
      { role: "user", content: req.user },
    ],
    reasoning_effort: Deno.env.get("META_REASONING") || "low",
    max_completion_tokens: req.maxTokens ?? 4000,
  };
  if (req.temperature !== undefined) body.temperature = req.temperature;
  if (req.schema) {
    body.response_format = { type: "json_schema", json_schema: { ...req.schema, strict: true } };
  } else if (req.json) {
    body.response_format = { type: "json_object" };
  }

  let res = await post(key, body);

  // Retry once on the documented retryable statuses, honoring Retry-After (capped).
  if (res.status === 429 || res.status === 500 || res.status === 503) {
    const wait = Number(res.headers.get("Retry-After"));
    await res.body?.cancel();
    await sleep(Math.min(Number.isFinite(wait) && wait > 0 ? wait * 1000 : 1500, 8000));
    res = await post(key, body);
  }

  // If the schema itself is rejected, fall back to plain JSON mode; the
  // prompt still describes the shape and brief.ts validates every field.
  if (res.status === 400 && req.schema) {
    const rejected = await errorOf(res);
    console.warn("json_schema rejected, retrying as json_object:",
      req.quiet ? `${rejected.status} ${rejected.code ?? ""}`.trim() : rejected.message);
    res = await post(key, { ...body, response_format: { type: "json_object" } });
  }

  if (!res.ok) throw await errorOf(res);

  const data = await res.json();
  const choice = data?.choices?.[0];
  const text = choice?.message?.content;
  if (typeof text !== "string" || !text.trim()) {
    throw new MuseError(`Meta Model API returned no content (finish_reason ${choice?.finish_reason ?? "?"})`, 502, null);
  }
  return {
    text,
    model: typeof data.model === "string" ? data.model : String(body.model),
    usage: {
      prompt: data.usage?.prompt_tokens ?? 0,
      completion: data.usage?.completion_tokens ?? 0,
      reasoning: data.usage?.completion_tokens_details?.reasoning_tokens ?? 0,
    },
  };
}
