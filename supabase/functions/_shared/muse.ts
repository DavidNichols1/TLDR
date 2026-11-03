// Meta Model API client (Muse Spark).
//
// The key lives only in the edge function's secrets (META_API_KEY), never in
// the app or this repo. Set it with:
//   supabase secrets set META_API_KEY=... --project-ref cfqlnthmqwkhjbhylvgu
//
// PENDING: the request below is filled in from Meta's Model API docs. Until
// then every call fails loudly instead of guessing an endpoint.

export interface MuseRequest {
  system: string;
  user: string;
  /** Ask the model for a JSON object back. */
  json?: boolean;
  temperature?: number;
  maxTokens?: number;
}

export interface MuseResponse {
  text: string;
  model: string;
}

export class MuseNotConfigured extends Error {}

export async function museChat(_req: MuseRequest): Promise<MuseResponse> {
  const key = Deno.env.get("META_API_KEY");
  if (!key) throw new MuseNotConfigured("META_API_KEY is not set on this project");
  throw new MuseNotConfigured("Muse Spark request not wired up yet (waiting on Meta Model API docs)");
}
