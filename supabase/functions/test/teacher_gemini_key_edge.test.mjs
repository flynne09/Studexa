import assert from "node:assert/strict";
import { test } from "node:test";
import { handleTeacherGeminiKeyRequest } from "../_shared/teacher_gemini_key_edge.mjs";

const status = { configured: false, status: "missing", maskedKey: null, graceRemaining: 3, fallbackRemainingToday: 2 };

function request(method, body, token = "teacher") {
  return new Request("https://example.test/teacher-gemini-key", {
    method,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: body == null ? undefined : JSON.stringify(body),
  });
}

function deps(role = "teacher") {
  const calls = { saved: [], removed: 0 };
  return {
    calls,
    verifyToken: async () => "teacher-uid",
    firestore: { get: async () => ({ data: { role } }) },
    credentials: {
      status: async () => status,
      save: async (_uid, key) => {
        calls.saved.push(key);
        return { ...status, configured: true, status: "valid", maskedKey: `••••${key.slice(-4)}` };
      },
      remove: async () => { calls.removed++; return status; },
    },
    validateKey: async (key) => key === "valid-personal-key-1234"
      ? { valid: true, apiKey: key }
      : { valid: false, reason: "rejected" },
  };
}

test("teacher can read masked status, validate/save, and remove without key disclosure", async () => {
  const fixture = deps();
  const read = await handleTeacherGeminiKeyRequest(request("GET"), fixture);
  assert.equal(read.status, 200);
  assert.deepEqual((await read.json()).status, status);

  const saved = await handleTeacherGeminiKeyRequest(request("PUT", { apiKey: "valid-personal-key-1234" }), fixture);
  const savedBody = await saved.json();
  assert.equal(saved.status, 200);
  assert.equal(savedBody.status.maskedKey, "••••1234");
  assert.equal(JSON.stringify(savedBody).includes("valid-personal-key"), false);
  assert.deepEqual(fixture.calls.saved, ["valid-personal-key-1234"]);

  const removed = await handleTeacherGeminiKeyRequest(request("DELETE"), fixture);
  assert.equal(removed.status, 200);
  assert.equal(fixture.calls.removed, 1);
});

test("student and invalid key are rejected before storage", async () => {
  const student = deps("student");
  assert.equal((await handleTeacherGeminiKeyRequest(request("GET"), student)).status, 403);
  const teacher = deps();
  const invalid = await handleTeacherGeminiKeyRequest(request("PUT", { apiKey: "bad" }), teacher);
  assert.equal(invalid.status, 400);
  assert.equal((await invalid.json()).code, "invalid-api-key");
  assert.equal(teacher.calls.saved.length, 0);
});

test("missing authorization is rejected", async () => {
  const response = await handleTeacherGeminiKeyRequest(
    new Request("https://example.test", { method: "GET" }),
    deps(),
  );
  assert.equal(response.status, 401);
});
