import assert from "node:assert/strict";
import { test } from "node:test";
import { teacherCredentialStore, validateGeminiApiKey } from "../_shared/teacher_credentials.mjs";

test("credential RPC uses only the server secret and never a Firebase user header", async () => {
  const requests = [];
  const store = teacherCredentialStore(async (url, init) => {
    requests.push({ url, init });
    return new Response(JSON.stringify({ configured: false }), { status: 200 });
  }, { url: "https://project.supabase.co", secretKey: "server-secret" });
  await store.status("firebase-uid");
  assert.match(requests[0].url, /studexa_teacher_gemini_status$/);
  assert.equal(requests[0].init.headers.apikey, "server-secret");
  assert.equal(requests[0].init.headers.Authorization, undefined);
  assert.deepEqual(JSON.parse(requests[0].init.body), { p_teacher_uid: "firebase-uid" });
});

test("Gemini key validation accepts success and rejects malformed or denied keys", async () => {
  assert.deepEqual(await validateGeminiApiKey("short", async () => {
    throw new Error("must not call");
  }), { valid: false, reason: "invalid" });
  const accepted = await validateGeminiApiKey("valid-personal-gemini-key-1234", async (_url, init) => {
    assert.equal(init.headers["x-goog-api-key"], "valid-personal-gemini-key-1234");
    return new Response("{}", { status: 200 });
  });
  assert.equal(accepted.valid, true);
  const rejected = await validateGeminiApiKey("denied-personal-gemini-key-1234", async () =>
    new Response("{}", { status: 403 }));
  assert.deepEqual(rejected, { valid: false, reason: "rejected" });
});
