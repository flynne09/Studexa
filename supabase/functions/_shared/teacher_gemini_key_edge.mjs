import { SupabaseIdentityError, verifySupabaseToken } from "./supabase_identity.mjs";
import { PostgresStoreError, postgresClient } from "./postgres_rest.mjs";
import { CredentialStoreError, teacherCredentialStore, validateGeminiApiKey } from "./teacher_credentials.mjs";

// Standard CORS headers allowing browser/Flutter clients to call the teacher Gemini key endpoint.
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, PUT, DELETE, OPTIONS",
};

/**
 * Helper to serialize `body` as a JSON HTTP `Response` with `status` and CORS headers.
 */
function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

/**
 * Edge Function handler for teacher Gemini API key management (`GET` status, `PUT` verify & save, `DELETE` remove).
 * Verifies the caller's Supabase token and confirms they have the `teacher` role before accessing credentials.
 */
export async function handleTeacherGeminiKeyRequest(request, deps = {}) {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (!["GET", "PUT", "DELETE"].includes(request.method)) return json(405, { error: "Use GET, PUT, or DELETE." });
  const auth = request.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ") || auth.length <= 7) return json(401, { error: "Sign in again to manage your API key." });

  const fetchImpl = deps.fetchImpl || fetch;
  try {
    const token = auth.slice(7);
    const user = await (deps.verifyToken || verifySupabaseToken)(token, fetchImpl, deps.authOptions);
    const uid = user.id || user;
    const database = deps.database || deps.firestore || postgresClient(token, fetchImpl);
    const profile = await database.get("profiles", uid);
    if (profile?.data.role !== "teacher") {
      return json(403, { error: "Only Teacher accounts can manage a Gemini API key." });
    }
    const credentials = deps.credentials || teacherCredentialStore(fetchImpl);
    if (request.method === "GET") {
      return json(200, { success: true, status: await credentials.status(uid) });
    }
    if (request.method === "DELETE") {
      return json(200, { success: true, status: await credentials.remove(uid) });
    }

    let body;
    try {
      body = await request.json();
    } catch (_) {
      return json(400, { error: "Enter a valid Gemini API key.", code: "invalid-api-key" });
    }
    const validation = await (deps.validateKey || validateGeminiApiKey)(body?.apiKey, fetchImpl);
    if (!validation.valid) {
      return json(400, {
        error: "Google rejected this API key. Check the key and the Google project, then try again.",
        code: "invalid-api-key",
      });
    }
    const status = await credentials.save(uid, validation.apiKey);
    return json(200, { success: true, status });
  } catch (error) {
    if (error instanceof SupabaseIdentityError) return json(error.status, { error: error.message });
    if (error instanceof PostgresStoreError) {
      return json([401, 403].includes(error.status) ? error.status : 503, {
        error: "Could not verify your Teacher account. Try again.",
      });
    }
    if (error instanceof CredentialStoreError) {
      return json(error.status === 503 ? 503 : 500, { error: error.message, code: "credential-service-unavailable" });
    }
    console.error("Teacher Gemini key request failed", { name: error?.name || "Error" });
    return json(503, { error: "Gemini API Settings are temporarily unavailable. Try again." });
  }
}
