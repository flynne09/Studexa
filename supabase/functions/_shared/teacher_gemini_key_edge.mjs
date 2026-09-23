import { FirebaseIdentityError, verifyFirebaseToken } from "./firebase_identity.mjs";
import { FirestoreError, firestoreClient } from "./firestore_rest.mjs";
import { CredentialStoreError, teacherCredentialStore, validateGeminiApiKey } from "./teacher_credentials.mjs";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, PUT, DELETE, OPTIONS",
};

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

export async function handleTeacherGeminiKeyRequest(request, deps = {}) {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (!["GET", "PUT", "DELETE"].includes(request.method)) return json(405, { error: "Use GET, PUT, or DELETE." });
  const auth = request.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ") || auth.length <= 7) return json(401, { error: "Sign in again to manage your API key." });

  const fetchImpl = deps.fetchImpl || fetch;
  try {
    const token = auth.slice(7);
    const uid = await (deps.verifyToken || verifyFirebaseToken)(token, fetchImpl, deps.firebaseApiKey);
    const firestore = deps.firestore || firestoreClient(token, fetchImpl);
    const profile = await firestore.get("users", uid);
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
    if (error instanceof FirebaseIdentityError) return json(error.status, { error: error.message });
    if (error instanceof FirestoreError) {
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
