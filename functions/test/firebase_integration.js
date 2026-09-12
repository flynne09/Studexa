// Runs against disposable emulators only. Never points at a production database.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const project = "demo-studexa";
const base = `http://127.0.0.1:8080/v1/projects/${project}/databases/default/documents`;
const full = (path) => `projects/${project}/databases/default/documents/${path}`;
let checks = 0;
let fixtureServer;
function value(v) {
  if (v === null) return { nullValue: null };
  if (typeof v === "string") return { stringValue: v };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") return { doubleValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(value) } };
  return { mapValue: { fields: fields(v) } };
}
const fields = (data) => Object.fromEntries(Object.entries(data).map(([key, v]) => [key, value(v)]));
async function call(path, user, method = "GET", body, expected = 200) {
  const response = await fetch(base + path, { method,
    headers: { Authorization: `Bearer ${user.token}`, "Content-Type": "application/json" },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  assert.equal(response.status, expected, `${method} ${path}: ${await response.clone().text()}`);
  checks++;
  return response.json();
}
const put = (path, data, user, expected = 200) => call(`/${path}`, user, "PATCH", { fields: fields(data) }, expected);
async function account(role) {
  const email = `integration-${role}-${Date.now()}@example.test`;
  const password = "Emulator-only-passphrase-2026";
  const endpoint = `http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:`;
  const signup = await fetch(`${endpoint}signUp?key=emulator-only`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password, returnSecureToken: true }) });
  assert.equal(signup.status, 200);
  const data = await signup.json();
  const login = await fetch(`${endpoint}signInWithPassword?key=emulator-only`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password, returnSecureToken: true }) });
  assert.equal(login.status, 200);
  const session = await login.json();
  assert.equal(session.localId, data.localId);
  checks += 2;
  const user = { uid: data.localId, token: session.idToken };
  await put(`users/${user.uid}`, { uid: user.uid, email, displayName: role, role: role === "teacher" ? "teacher" : "student" }, user);
  return user;
}

(async () => {
  const teacher = await account("teacher");
  const student = await account("student");
  const stranger = await account("stranger");
  await put(`users/${student.uid}`, { uid: student.uid, role: "teacher" }, student, 403);
  await call(`/users/${teacher.uid}`, student, "GET", null, 403);
  const classId = `integration-${Date.now()}`;
  const classData = { teacherId: teacher.uid, teacherName: "Integration teacher", name: "Integration class", joinCode: "INT-1234", status: "active", rosterCount: 0 };
  await call(":commit", teacher, "POST", { writes: [
    { update: { name: full(`classes/${classId}`), fields: fields(classData) } },
    { update: { name: full(`classes/${classId}/members/${teacher.uid}`), fields: fields({ userId: teacher.uid, role: "teacher" }) } },
  ] });
  await call(":runQuery", student, "POST", { structuredQuery: { from: [{ collectionId: "classes" }], where: { fieldFilter: { field: { fieldPath: "joinCode" }, op: "EQUAL", value: value("INT-1234") } } } });
  await call(":commit", student, "POST", { writes: [
    { update: { name: full(`classes/${classId}/members/${student.uid}`), fields: fields({ userId: student.uid, role: "student" }) } },
    { update: { name: full(`users/${student.uid}/joinedClasses/${classId}`), fields: fields({ classId }) } },
    { update: { name: full(`classes/${classId}`), fields: fields({ ...classData, rosterCount: 1 }) } },
  ] });
  await put(`classes/${classId}`, { ...classData, teacherId: student.uid }, student, 403);
  const materialId = `${classId}-material`;
  const source = fs.readFileSync("test/quiz_test.dart", "utf8").match(/const richLectureText = '''([\s\S]*?)'''/)[1];
  await put(`materials/${materialId}`, { classId, teacherId: teacher.uid, status: "ready", fileName: "lecture.docx", extractedText: source }, teacher);
  await call(`/materials/${materialId}`, student);
  await call(`/materials/${materialId}`, stranger, "GET", null, 403);
  await put(`materials/${materialId}`, { classId, teacherId: student.uid }, student, 403);
  const quizId = `${classId}-practice`;
  const quiz = { classId, teacherId: teacher.uid, materialId, type: "practice", status: "published", title: "Emulator fixture", questions: [] };
  await put(`quizzes/${quizId}`, quiz, teacher);
  await put(`quizzes/${classId}-actual`, { ...quiz, type: "actual", status: "draft" }, teacher);
  await call(`/quizzes/${classId}-actual`, student, "GET", null, 403);
  await call(`/quizzes/${quizId}`, stranger, "GET", null, 403);
  const filter = (field, v) => ({ fieldFilter: { field: { fieldPath: field }, op: "EQUAL", value: value(v) } });
  // TeacherClassDetailsScreen queries by classId only, including Actual/drafts.
  const classQuizQuery = { structuredQuery: { from: [{ collectionId: "quizzes" }], where: filter("classId", classId) } };
  const teacherQuizzes = await call(":runQuery", teacher, "POST", classQuizQuery);
  assert.deepEqual(teacherQuizzes.filter((row) => row.document).map((row) => row.document.name).sort(),
    [full(`quizzes/${quizId}`), full(`quizzes/${classId}-actual`)].sort());
  await call(":runQuery", student, "POST", classQuizQuery, 403);
  await call(":runQuery", stranger, "POST", classQuizQuery, 403);
  await call(":runQuery", teacher, "POST", { structuredQuery: { from: [{ collectionId: "quizzes" }], where: filter("teacherId", teacher.uid) } });
  await call(":runQuery", student, "POST", { structuredQuery: { from: [{ collectionId: "quizzes" }], where: { compositeFilter: { op: "AND", filters: [filter("classId", classId), filter("type", "practice"), filter("status", "published")] } } } });
  const attemptId = `${student.uid}_${quizId}_attempt_1`;
  const attempt = { classId, quizId, studentId: student.uid, score: 1, totalPoints: 1, percentage: 100, answers: { q_1: "process" } };
  await put(`attempts/${attemptId}`, attempt, student);
  await call(`/attempts/${attemptId}`, student);
  await call(`/attempts/${attemptId}`, teacher);
  await call(`/attempts/${attemptId}`, stranger, "GET", null, 403);
  await put(`attempts/${attemptId}`, attempt, student, 403);
  await call(":runQuery", student, "POST", { structuredQuery: { from: [{ collectionId: "attempts" }], where: { compositeFilter: { op: "AND", filters: [filter("classId", classId), filter("studentId", student.uid)] } } } });
  await put(`users/${student.uid}/attempts/draft_${quizId}_attempt_1`, { answers: { q_1: "process" } }, student);
  await call(`/users/${student.uid}/attempts/draft_${quizId}_attempt_1`, student, "DELETE");
  const fixtureBackend = process.argv.includes("--backend-fixture");
  if (process.argv.includes("--generate") || fixtureBackend) {
    const endpoint = `http://127.0.0.1:5001/${project}/us-central1/generateQuizHttp`;
    let invoke = (token, body) => fetch(endpoint, { method: "POST", headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(body), signal: AbortSignal.timeout(160000) });
    if (fixtureBackend) {
      // Explicit transport fixture: exercises real handler/auth/database persistence,
      // never counts as evidence of a successful live Gemini request.
      assert.equal(process.env.GCLOUD_PROJECT, project);
      assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
      assert.ok(process.env.FIREBASE_AUTH_EMULATOR_HOST);
      process.env.GEMINI_API_KEY = "test-fixture-not-a-real-key";
      const originalFetch = global.fetch;
      global.fetch = (url, options) => {
        if (!String(url).startsWith("https://generativelanguage.googleapis.com/")) return originalFetch(url, options);
        const questions = source.trim().split(/\r?\n/).slice(0, 10).map((sentence) => ({
          type: "true_false", question: sentence, correctAnswer: "True", options: ["True", "False"],
          enumerationAnswers: [], explanation: sentence, sourceExcerpt: sentence,
        }));
        return Promise.resolve(Response.json({ candidates: [{ finishReason: "STOP", content: { parts: [{ text: JSON.stringify({ questions }) }] } }] }));
      };
      const handler = require("../index").generateQuizHttp;
      fixtureServer = require("node:http").createServer(async (req, res) => {
        const chunks = [];
        for await (const chunk of req) chunks.push(chunk);
        req.body = JSON.parse(Buffer.concat(chunks).toString());
        res.status = (value) => { res.statusCode = value; return res; };
        res.json = (value) => { res.setHeader("Content-Type", "application/json"); res.end(JSON.stringify(value)); return res; };
        await handler(req, res);
      });
      await new Promise((resolve) => fixtureServer.listen(0, "127.0.0.1", resolve));
      invoke = (token, body) => originalFetch(`http://127.0.0.1:${fixtureServer.address().port}`, {
        method: "POST", headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify(body), signal: AbortSignal.timeout(30000),
      });
    }
    assert.equal((await invoke(null, { teacherId: teacher.uid })).status, 401);
    const body = { classId, materialId, quizType: "actual", questionTypes: fixtureBackend ? ["true_false"] : ["multiple_choice", "true_false", "identification"], questionCount: 10 };
    assert.equal((await invoke(student.token, body)).status, 403);
    const actualResponse = await invoke(teacher.token, body);
    assert.equal(actualResponse.status, 200, await actualResponse.clone().text());
    const actual = await actualResponse.json();
    assert.equal(actual.quiz.questions.length, 10);
    await call(`/quizzes/${actual.quizId}`, teacher);
    const practiceResponse = await invoke(teacher.token, { ...body, quizType: "practice", sourceQuizId: actual.quizId });
    assert.equal(practiceResponse.status, 200, await practiceResponse.clone().text());
    const practice = await practiceResponse.json();
    assert.equal(practice.quiz.sourceQuizId, actual.quizId);
    assert.equal(practice.quiz.questions.length, 10);
    checks += 5;
    if (!fixtureBackend) {
      fs.mkdirSync("build/integration-evidence", { recursive: true });
      fs.writeFileSync("build/integration-evidence/emulated-backend-live-gemini.json", JSON.stringify({ actual: actual.quiz, practice: practice.quiz }, null, 2));
    }
  }
  console.log(JSON.stringify({ firebaseEmulators: true, assertionsPassed: checks, fixtureBackend, liveGemini: process.argv.includes("--generate") }));
})().catch((error) => { console.error(error.message); process.exitCode = 1; }).finally(async () => {
  if (fixtureServer) {
    fixtureServer.closeAllConnections();
    fixtureServer.close();
    const { getApps, deleteApp } = require("firebase-admin/app");
    await Promise.all(getApps().map(deleteApp));
  }
});
