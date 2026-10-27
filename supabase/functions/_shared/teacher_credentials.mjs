/**
 * Error thrown when accessing or verifying teacher Gemini API credentials fails.
 */
export class CredentialStoreError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

/**
 * Resolves the privileged Supabase service-role/secret key from environment variables
 * so the edge function can invoke security-definer credential RPCs.
 */
function defaultSecretKey() {
  const keys = globalThis.Deno?.env.get("SUPABASE_SECRET_KEYS");
  if (keys) {
    try {
      const parsed = JSON.parse(keys);
      if (parsed.default) return parsed.default;
    } catch (_) {
      throw new CredentialStoreError(500, "Supabase server credentials are invalid.");
    }
  }
  return globalThis.Deno?.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
}

/**
 * Creates a client for managing encrypted teacher Gemini API keys and backup generation sessions
 * via PostgreSQL RPC functions.
 */
export function teacherCredentialStore(fetchImpl = fetch, options = {}) {
  const url = options.url || globalThis.Deno?.env.get("SUPABASE_URL") || "";
  const secretKey = options.secretKey || defaultSecretKey();
  if (!url || !secretKey) {
    throw new CredentialStoreError(500, "Teacher credential storage is not configured.");
  }

  /**
   * Invokes a PostgreSQL RPC function by `name` using the server secret key.
   */
  async function rpc(name, body) {
    const response = await fetchImpl(`${url}/rest/v1/rpc/${name}`, {
      method: "POST",
      signal: AbortSignal.timeout(10000),
      headers: { apikey: secretKey, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!response.ok) {
      throw new CredentialStoreError(response.status, `Credential storage request failed (${response.status}).`);
    }
    return response.status === 204 ? null : response.json();
  }

  return {
    // Returns key configuration status and remaining grace/daily fallback counts for a teacher.
    status: (uid) => rpc("studexa_teacher_gemini_status", { p_teacher_uid: uid }),
    // Retrieves the decrypted personal Gemini API key for server-side quiz generation.
    getCredential: (uid) => rpc("studexa_get_teacher_gemini_credential", { p_teacher_uid: uid }),
    // Saves or replaces a verified personal Gemini API key and stores its last four characters for display.
    save: (uid, apiKey) => rpc("studexa_upsert_teacher_gemini_credential", {
      p_teacher_uid: uid,
      p_api_key: apiKey,
      p_last_four: apiKey.slice(-4),
    }),
    // Marks the teacher's saved Gemini API key as invalid when Google rejects it.
    markInvalid: (uid) => rpc("studexa_mark_teacher_gemini_invalid", { p_teacher_uid: uid }),
    // Deletes the teacher's saved personal Gemini API key.
    remove: (uid) => rpc("studexa_delete_teacher_gemini_credential", { p_teacher_uid: uid }),
    // Looks up an existing backup session reservation for idempotency across batch calls.
    getBackupSession: (uid, sessionId) => rpc("studexa_get_backup_session", {
      p_teacher_uid: uid, p_client_session_id: sessionId,
    }),
    // Reserves a lifetime grace or daily fallback session before calling the shared backup Gemini key.
    reserveBackup: (uid, sessionId, reason) => rpc("studexa_reserve_backup_session", {
      p_teacher_uid: uid, p_client_session_id: sessionId, p_reason: reason,
    }),
    // Finalizes a reserved backup session, committing or releasing the quota depending on `success`.
    finishBackup: (uid, sessionId, success) => rpc("studexa_finish_backup_session", {
      p_teacher_uid: uid, p_client_session_id: sessionId, p_success: success,
    }),
  };
}

/**
 * Verifies a candidate Gemini API key by making a lightweight `models?pageSize=1` request to Google AI Studio.
 */
export async function validateGeminiApiKey(apiKey, fetchImpl = fetch) {
  const key = typeof apiKey === "string" ? apiKey.trim() : "";
  if (key.length < 20 || key.length > 512 || /\s/.test(key)) {
    return { valid: false, reason: "invalid" };
  }
  let response;
  try {
    response = await fetchImpl("https://generativelanguage.googleapis.com/v1beta/models?pageSize=1", {
      method: "GET",
      headers: { "x-goog-api-key": key },
      signal: AbortSignal.timeout(10000),
    });
  } catch (_) {
    throw new CredentialStoreError(503, "Could not contact Google AI Studio to verify this key.");
  }
  if (response.ok) return { valid: true, apiKey: key };
  if ([400, 401, 403].includes(response.status)) return { valid: false, reason: "rejected" };
  throw new CredentialStoreError(503, "Google AI Studio could not verify this key right now.");
}
