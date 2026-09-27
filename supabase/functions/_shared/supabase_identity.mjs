export class SupabaseIdentityError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function environment(name) {
  return globalThis.Deno?.env.get(name) || "";
}

export async function verifySupabaseToken(token, fetchImpl = fetch, options = {}) {
  const url = options.url || environment("SUPABASE_URL");
  const apiKey = options.apiKey || environment("SUPABASE_ANON_KEY");
  if (!url || !apiKey) {
    throw new SupabaseIdentityError(500, "Authentication is not configured.");
  }
  let response;
  try {
    response = await fetchImpl(`${url}/auth/v1/user`, {
      headers: { Authorization: `Bearer ${token}`, apikey: apiKey },
      signal: AbortSignal.timeout(10000),
    });
  } catch (_) {
    throw new SupabaseIdentityError(503, "Could not verify your session. Try again.");
  }
  if (!response.ok) throw new SupabaseIdentityError(401, "Sign in again to continue.");
  const user = await response.json();
  if (!user?.id) throw new SupabaseIdentityError(401, "Sign in again to continue.");
  return user;
}
