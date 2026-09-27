import assert from "node:assert/strict";
import { test } from "node:test";
import { postgresClient } from "../_shared/postgres_rest.mjs";

test("Postgres REST carries the Supabase user token and maps quiz columns", async () => {
  const calls = [];
  const mockFetch = async (url, options) => {
    calls.push({ url: String(url), options });
    if (options?.method === "POST") {
      const body = JSON.parse(options.body);
      return new Response(JSON.stringify([{ ...body, updated_at: "2026-09-24T01:00:00Z" }]), { status: 201 });
    }
    if (options?.method === "PATCH") {
      const body = JSON.parse(options.body);
      return new Response(JSON.stringify([{ id: "00000000-0000-4000-8000-000000000001", ...body, updated_at: "2026-09-24T02:00:00Z" }]), { status: 200 });
    }
    return new Response(JSON.stringify([{ id: "teacher", role: "teacher" }]), { status: 200 });
  };
  const store = postgresClient("supabase-user-token", mockFetch, {
    url: "https://example.supabase.co",
    apiKey: "publishable-key",
  });
  const profile = await store.get("profiles", "teacher");
  assert.equal(profile.data.role, "teacher");
  const created = await store.create("quizzes", "00000000-0000-4000-8000-000000000001", {
    classId: "00000000-0000-4000-8000-000000000002",
    type: "actual",
    requestedQuestionCount: 10,
  });
  assert.equal(created.data.requestedQuestionCount, 10);
  await store.update("quizzes", created.id, { totalPoints: 2 }, created.updateTime);
  assert.ok(calls.every((call) => call.options.headers.Authorization === "Bearer supabase-user-token"));
  const createBody = JSON.parse(calls[1].options.body);
  assert.equal(createBody.quiz_type, "actual");
  assert.equal(createBody.requested_question_count, 10);
  assert.match(calls[2].url, /updated_at=eq\./);
});

test("generation session lookup is class scoped", async () => {
  const calls = [];
  const store = postgresClient("token", async (url, options) => {
    calls.push({ url: String(url), options });
    return new Response("[]", { status: 200 });
  }, { url: "https://example.supabase.co", apiKey: "key" });
  assert.equal(await store.findQuizBySession("class-1", "session-1"), null);
  assert.match(calls[0].url, /class_id=eq\.class-1/);
  assert.match(calls[0].url, /generation_session_id=eq\.session-1/);
});
