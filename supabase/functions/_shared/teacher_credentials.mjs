export class CredentialStoreError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

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

export function teacherCredentialStore(fetchImpl = fetch, options = {}) {
  const url = options.url || globalThis.Deno?.env.get("SUPABASE_URL") || "";
  const secretKey = options.secretKey || defaultSecretKey();
  if (!url || !secretKey) {
    throw new CredentialStoreError(500, "Teacher credential storage is not configured.");
  }

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
    status: (uid) => rpc("studexa_teacher_gemini_status", { p_teacher_uid: uid }),
    getCredential: (uid) => rpc("studexa_get_teacher_gemini_credential", { p_teacher_uid: uid }),
    save: (uid, apiKey) => rpc("studexa_upsert_teacher_gemini_credential", {
      p_teacher_uid: uid,
      p_api_key: apiKey,
      p_last_four: apiKey.slice(-4),
    }),
    markInvalid: (uid) => rpc("studexa_mark_teacher_gemini_invalid", { p_teacher_uid: uid }),
    remove: (uid) => rpc("studexa_delete_teacher_gemini_credential", { p_teacher_uid: uid }),
    getBackupSession: (uid, sessionId) => rpc("studexa_get_backup_session", {
      p_teacher_uid: uid, p_client_session_id: sessionId,
    }),
    reserveBackup: (uid, sessionId, reason) => rpc("studexa_reserve_backup_session", {
      p_teacher_uid: uid, p_client_session_id: sessionId, p_reason: reason,
    }),
    finishBackup: (uid, sessionId, success) => rpc("studexa_finish_backup_session", {
      p_teacher_uid: uid, p_client_session_id: sessionId, p_success: success,
    }),
  };
}

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
