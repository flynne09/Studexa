import assert from "node:assert/strict";
import { test } from "node:test";
import { firestoreClient } from "../_shared/firestore_rest.mjs";

test("Firestore REST uses the named database, user token, typed fields and update precondition", async () => {
  const calls = [];
  const mockFetch = async (url, options) => {
    calls.push({ url: String(url), options });
    if (options?.method === "POST") {
      return new Response(JSON.stringify({
        fields: JSON.parse(options.body).fields,
        updateTime: "2026-09-20T01:00:00Z",
      }), { status: 200 });
    }
    if (options?.method === "PATCH") {
      return new Response(JSON.stringify({
        fields: JSON.parse(options.body).fields,
        updateTime: "2026-09-20T02:00:00Z",
      }), { status: 200 });
    }
    return new Response(JSON.stringify({
      fields: { role: { stringValue: "teacher" } },
      updateTime: "2026-09-20T01:00:00Z",
    }), { status: 200 });
  };
  const store = firestoreClient("firebase-user-token", mockFetch);
  const user = await store.get("users", "teacher");
  assert.equal(user.data.role, "teacher");
  const created = await store.create("quizzes", "gen_123", {
    title: "Cells", questions: [{ id: "q_1", points: 1 }],
    requestedQuestionCount: 50, extraGenerationAttempted: false,
    createdAt: "2026-09-20T01:00:00Z",
  });
  assert.equal(created.data.questions[0].id, "q_1");
  assert.equal(created.data.requestedQuestionCount, 50);
  await store.update("quizzes", "gen_123", { totalPoints: 2, updatedAt: "2026-09-20T02:00:00Z" }, created.updateTime);
  assert.ok(calls.every((call) => call.url.includes("/databases/default/documents/")));
  assert.ok(calls.every((call) => call.options.headers.Authorization === "Bearer firebase-user-token"));
  const createBody = JSON.parse(calls[1].options.body);
  assert.equal(createBody.fields.createdAt.timestampValue, "2026-09-20T01:00:00Z");
  assert.equal(createBody.fields.requestedQuestionCount.integerValue, "50");
  const updateUrl = new URL(calls[2].url);
  assert.equal(updateUrl.searchParams.get("currentDocument.updateTime"), created.updateTime);
  assert.deepEqual(updateUrl.searchParams.getAll("updateMask.fieldPaths"), ["totalPoints", "updatedAt"]);
});

test("initial quiz lookup uses a class-scoped query so an absent quiz is readable", async () => {
  const calls = [];
  const store = firestoreClient("firebase-user-token", async (url, options) => {
    calls.push({ url: String(url), options });
    return new Response(JSON.stringify([{ readTime: "2026-09-20T01:00:00Z" }]), { status: 200 });
  });
  assert.equal(await store.findQuizBySession("class1", "session1"), null);
  const [{ url, options }] = calls;
  assert.ok(url.endsWith("/documents:runQuery"));
  assert.equal(options.headers.Authorization, "Bearer firebase-user-token");
  const filters = JSON.parse(options.body).structuredQuery.where.compositeFilter.filters;
  assert.deepEqual(filters.map((filter) => filter.fieldFilter.field.fieldPath), ["classId", "generationSessionId"]);
  assert.deepEqual(filters.map((filter) => filter.fieldFilter.value.stringValue), ["class1", "session1"]);
});
