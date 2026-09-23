import assert from "node:assert/strict";
import { test } from "node:test";
import { handleQuizRequest } from "../_shared/quiz_edge.mjs";
import { FirestoreError } from "../_shared/firestore_rest.mjs";
import { QuizGenerationError } from "../_shared/quiz_generator.mjs";

const text = "Cellular respiration produces ATP by oxidizing glucose molecules in eukaryotic cells. Mitochondria supply energy to the cell.";
const copy = (value) => structuredClone(value);
const base = () => ({
  users: { teacher: { role: "teacher" }, student: { role: "student" } },
  classes: { class1: { teacherId: "teacher" } },
  materials: { material1: { teacherId: "teacher", classId: "class1", status: "ready", extractedText: text, fileName: "Cells.pdf" } },
  quizzes: {},
});

function fixture(seed = base()) {
  const records = copy(seed);
  const versions = new Map();
  const key = (collection, id) => `${collection}/${id}`;
  const store = {
    async findQuizBySession(classId, sessionId) {
      const match = Object.entries(records.quizzes).find(([, quiz]) =>
        quiz.classId === classId && quiz.generationSessionId === sessionId);
      if (!match) return null;
      const [id, data] = match;
      return { id, data: copy(data), updateTime: String(versions.get(key("quizzes", id)) || 1) };
    },
    async get(collection, id) {
      const data = records[collection]?.[id];
      return data ? { data: copy(data), updateTime: String(versions.get(key(collection, id)) || 1) } : null;
    },
    async create(collection, id, data) {
      if (records[collection][id]) throw new FirestoreError(409, "Already exists");
      records[collection][id] = copy(data);
      versions.set(key(collection, id), 1);
      return { data: copy(data), updateTime: "1" };
    },
    async update(collection, id, changes, updateTime) {
      if (String(versions.get(key(collection, id)) || 1) !== updateTime) throw new FirestoreError(412, "Conflict");
      Object.assign(records[collection][id], copy(changes));
      versions.set(key(collection, id), Number(updateTime) + 1);
      return { data: copy(records[collection][id]), updateTime: String(Number(updateTime) + 1) };
    },
    async teacherEdit(id, change) {
      Object.assign(records.quizzes[id], copy(change));
      const docKey = key("quizzes", id);
      versions.set(docKey, (versions.get(docKey) || 1) + 1);
    },
  };
  let serial = 0;
  const generate = async (request) => Array.from({ length: request.questionCount }, (_, index) => {
    const n = ++serial;
    const unique = "code" + n.toString().split("").map((digit) => String.fromCharCode(97 + Number(digit))).join("");
    return {
      id: `q_${index + 1}`, type: request.questionTypes[index % request.questionTypes.length],
      question: `Define ${unique}?`, correctAnswer: `answer_${unique}`,
      sourceExcerpt: `Evidence about ${unique}`, options: [], enumerationAnswers: [],
      explanation: "Supported by the material.", points: 1,
    };
  });
  return { records, store, generate };
}

function body(overrides = {}) {
  return {
    classId: "class1", materialId: "material1", quizType: "actual",
    questionTypes: ["identification"], questionCount: 10,
    clientSessionId: "session_1234567890abcdef", batchRequestId: "batch_1234567890abcdef",
    mode: "initial", ...overrides,
  };
}

async function invoke(f, data, token = "teacher", generate = f.generate, credentialStore, backupApiKey = "fixture-key") {
  const request = new Request("https://example.test/generate-quiz", {
    method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  const response = await handleQuizRequest(request, {
    store: f.store, generate, geminiApiKey: backupApiKey,
    credentialStore,
    fetchImpl: async () => new Response(JSON.stringify({ users: [{ localId: token }] }), { status: 200 }),
  });
  return { status: response.status, data: await response.json() };
}

function credentialFixture({ personalKey = null, personalStatus = "valid" } = {}) {
  const sessions = new Map();
  const used = { grace: 0, fallback: 0 };
  const status = () => ({
    configured: personalKey != null,
    status: personalKey == null ? "missing" : personalStatus,
    graceRemaining: Math.max(0, 3 - used.grace),
    fallbackRemainingToday: Math.max(0, 2 - used.fallback),
  });
  return {
    sessions, used,
    async status() { return status(); },
    async getCredential() {
      return personalKey == null ? null : { apiKey: personalKey, status: personalStatus };
    },
    async markInvalid() { personalStatus = "invalid"; },
    async getBackupSession(_uid, id) {
      const item = sessions.get(id);
      return item ? { ...status(), allowed: true, existing: true, ...item } : null;
    },
    async reserveBackup(_uid, id, reason) {
      const group = reason === "grace" ? "grace" : "fallback";
      const allowance = group === "grace" ? 3 : 2;
      if (used[group] + [...sessions.values()].filter((s) =>
        s.group === group && s.state === "reserved").length >= allowance) {
        return { ...status(), allowed: false, reason };
      }
      const item = { allowed: true, existing: false, reason, state: "reserved", group };
      sessions.set(id, item);
      return { ...status(), ...item };
    },
    async finishBackup(_uid, id, success) {
      const item = sessions.get(id);
      if (item?.state === "reserved") {
        item.state = success ? "used" : "failed";
        if (success) used[item.group]++;
      }
      return status();
    },
  };
}

for (const target of [1, 10, 30, 50]) {
  test(`${target} questions are saved in bounded batches`, async () => {
    const f = fixture();
    let result = await invoke(f, body({ questionCount: target }));
    assert.equal(result.status, 200);
    assert.ok(result.data.quiz.questions.length <= 10);
    let batch = 1;
    while (result.data.quiz.questions.length < target) {
      batch++;
      result = await invoke(f, body({
        questionCount: target, mode: "automatic", continueQuizId: result.data.quizId,
        batchRequestId: `batch_${String(batch).padStart(16, "0")}`,
      }));
      assert.equal(result.status, 200);
    }
    assert.equal(result.data.quiz.questions.length, target);
    assert.equal(result.data.quiz.extraGenerationAttempted, false);
    assert.equal(result.data.quiz.automaticBatchesAttempted, Math.ceil(target / 10));
    assert.equal(new Set(result.data.quiz.questions.map((q) => q.id)).size, target);
  });
}

test("invalid token and student role are refused before Gemini", async () => {
  const f = fixture();
  let calls = 0;
  const generator = async () => { calls++; return []; };
  const noToken = await handleQuizRequest(new Request("https://example.test", { method: "POST" }), { store: f.store, generate: generator });
  assert.equal(noToken.status, 401);
  const badToken = await handleQuizRequest(new Request("https://example.test", {
    method: "POST", headers: { Authorization: "Bearer invalid-token" }, body: JSON.stringify(body()),
  }), { store: f.store, generate: generator,
    fetchImpl: () => new Response(JSON.stringify({ error: { message: "INVALID_ID_TOKEN" } }), { status: 400 }) });
  assert.equal(badToken.status, 401);
  assert.equal((await invoke(f, body(), "student", generator)).status, 403);
  assert.equal(calls, 0);
});

test("practice generation uses its Actual reference and rejects unrelated references", async () => {
  const f = fixture();
  const actual = await invoke(f, body());
  let context;
  const practice = await invoke(f, body({
    quizType: "practice", sourceQuizId: actual.data.quizId,
    clientSessionId: "practice_1234567890abcdef", batchRequestId: "practice_batch_1234567890",
  }), "teacher", async (request) => { context = request.sourceQuizContext; return f.generate(request); });
  assert.equal(practice.status, 200);
  assert.match(context, /Define code/);
  const invalid = await invoke(f, body({ quizType: "practice", sourceQuizId: "absent_actual_quiz_123",
    clientSessionId: "invalid_1234567890abcdef" }));
  assert.equal(invalid.status, 400);
});

test("duplicate batch IDs are idempotent and a concurrent manual edit survives", async () => {
  const f = fixture();
  const first = await invoke(f, body({ questionCount: 12 }));
  assert.equal(first.status, 200);
  const id = first.data.quizId;
  const request = body({ questionCount: 12, mode: "automatic", continueQuizId: id, batchRequestId: "followup_1234567890abcdef" });
  let injected = false;
  const added = await invoke(f, request, "teacher", async (args) => {
    if (!injected) {
      injected = true;
      await f.store.teacherEdit(id, { questions: [
        ...first.data.quiz.questions,
        { id: "q_11", type: "identification", question: "Teacher question?", correctAnswer: "manual", origin: "manual", points: 2 },
      ] });
    }
    return [first.data.quiz.questions[0], ...(await f.generate({ ...args, questionCount: 1 }))];
  });
  assert.equal(added.status, 200);
  assert.equal(added.data.quiz.questions.length, 12);
  assert.ok(added.data.quiz.questions.some((q) => q.origin === "manual"));
  assert.equal(added.data.quiz.totalPoints, 13);
  const retry = await invoke(f, request);
  assert.equal(retry.status, 200);
  assert.equal(retry.data.quiz.questions.length, 12);
});

test("repeating an initial request returns its existing draft", async () => {
  const f = fixture();
  const request = body({ questionCount: 10 });
  const first = await invoke(f, request);
  const retry = await invoke(f, request);
  assert.equal(first.status, 200);
  assert.equal(retry.status, 200);
  assert.equal(retry.data.quizId, first.data.quizId);
  assert.equal(retry.data.quiz.questions.length, 10);
  assert.equal(retry.data.quiz.completedBatchIds.length, 1);
});

test("a Firestore update-time conflict retries against the teacher's latest edit", async () => {
  const f = fixture();
  const first = await invoke(f, body({ questionCount: 12 }));
  const id = first.data.quizId;
  const originalUpdate = f.store.update;
  let edited = false;
  f.store.update = async (...args) => {
    if (!edited) {
      edited = true;
      await f.store.teacherEdit(id, { questions: [
        ...first.data.quiz.questions,
        { id: "q_11", type: "identification", question: "Teacher wrote this?", correctAnswer: "manual", origin: "manual", points: 2 },
      ] });
    }
    return originalUpdate(...args);
  };
  const result = await invoke(f, body({ questionCount: 12, mode: "automatic", continueQuizId: id,
    batchRequestId: "conflict_1234567890abcdef" }));
  assert.equal(result.status, 200);
  assert.equal(result.data.quiz.questions.length, 12);
  assert.ok(result.data.quiz.questions.some((q) => q.origin === "manual"));
});

test("Generate more is one action, even when its shortfall needs multiple batches", async () => {
  const f = fixture();
  const first = await invoke(f, body({ questionCount: 25 }), "teacher", async (request) => (await f.generate({ ...request, questionCount: 1 })));
  assert.equal(first.status, 200);
  const id = first.data.quizId;
  const extra = await invoke(f, body({
    questionCount: 25, mode: "extra", continueQuizId: id,
    clientSessionId: "extra_1234567890abcdef", batchRequestId: "extra_batch_1234567890",
  }));
  assert.equal(extra.status, 200);
  assert.equal(extra.data.quiz.extraGenerationAttempted, true);
  const more = await invoke(f, body({
    questionCount: 25, mode: "extra_continue", continueQuizId: id,
    clientSessionId: "extra_1234567890abcdef", batchRequestId: "extra_batch_2222222222",
  }));
  assert.equal(more.status, 200);
  assert.equal(more.data.quiz.questions.length, 21);
  const second = await invoke(f, body({
    questionCount: 25, mode: "extra", continueQuizId: id,
    clientSessionId: "other_1234567890abcdef", batchRequestId: "other_batch_1234567890",
  }));
  assert.equal(second.status, 412);
});

test("three successful temporary sessions are allowed and the fourth is blocked", async () => {
  const f = fixture();
  const credentials = credentialFixture();
  for (let index = 1; index <= 3; index++) {
    const result = await invoke(f, body({
      clientSessionId: `grace_${String(index).padStart(16, "0")}`,
      batchRequestId: `grace_batch_${String(index).padStart(16, "0")}`,
    }), "teacher", f.generate, credentials);
    assert.equal(result.status, 200);
    assert.equal(result.data.quiz.generationCredentialSource, "backup");
    assert.equal(result.data.quiz.backupUsageReason, "grace");
  }
  const blocked = await invoke(f, body({
    clientSessionId: "grace_0000000000000004",
    batchRequestId: "grace_batch_000000000004",
  }), "teacher", f.generate, credentials);
  assert.equal(blocked.status, 412);
  assert.equal(blocked.data.code, "personal-key-required");
});

test("personal key is primary and quota fallback is capped per teacher day", async () => {
  const f = fixture();
  const credentials = credentialFixture({ personalKey: "personal-key" });
  let keys = [];
  const generator = async (request, options) => {
    keys.push(options.apiKey);
    if (options.apiKey === "personal-key") {
      throw new QuizGenerationError("resource-exhausted", "quota");
    }
    return f.generate(request);
  };
  for (let index = 1; index <= 2; index++) {
    const result = await invoke(f, body({
      clientSessionId: `fallback_${String(index).padStart(16, "0")}`,
      batchRequestId: `fallback_batch_${String(index).padStart(16, "0")}`,
    }), "teacher", generator, credentials);
    assert.equal(result.status, 200);
    assert.equal(result.data.quiz.backupUsageReason, "personal_quota");
  }
  const blocked = await invoke(f, body({
    clientSessionId: "fallback_00000000000003",
    batchRequestId: "fallback_batch_0000000003",
  }), "teacher", generator, credentials);
  assert.equal(blocked.status, 429);
  assert.equal(blocked.data.code, "backup-limit-reached");
  assert.deepEqual(keys.slice(0, 2), ["personal-key", "fixture-key"]);
});

test("a rejected personal key is marked invalid and never uses backup", async () => {
  const f = fixture();
  const credentials = credentialFixture({ personalKey: "rejected-personal-key" });
  const keys = [];
  const result = await invoke(f, body(), "teacher", async (_request, options) => {
    keys.push(options.apiKey);
    throw new QuizGenerationError("credential-rejected", "rejected");
  }, credentials);
  assert.equal(result.status, 412);
  assert.equal(result.data.code, "personal-key-invalid");
  assert.deepEqual(keys, ["rejected-personal-key"]);
  assert.equal((await credentials.getCredential()).status, "invalid");
});

test("missing personal and backup credentials returns a structured unavailable error", async () => {
  const f = fixture();
  const credentials = credentialFixture();
  const result = await invoke(f, body(), "teacher", f.generate, credentials, "");
  assert.equal(result.status, 503);
  assert.equal(result.data.code, "backup-unavailable");
});
