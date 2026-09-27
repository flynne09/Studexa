#!/usr/bin/env node

import fs from "node:fs/promises";
import crypto from "node:crypto";

const [projectUrl, keyFile, mode, modeValue] = process.argv.slice(2);
if (!projectUrl || !keyFile) {
  console.error(
    "Usage: node tool/verify_live_supabase_cutover.mjs <project-url> <private-key-json|->",
  );
  process.exit(2);
}

async function readStdin() {
  let value = "";
  process.stdin.setEncoding("utf8");
  for await (const chunk of process.stdin) value += chunk;
  return value;
}

const keyText = keyFile === "-" ? await readStdin() : await fs.readFile(keyFile, "utf8");
const keyRecords = JSON.parse(keyText.replace(/^\uFEFF/, ""));
const anonKey = keyRecords.find((item) => item.name === "anon")?.api_key ||
  keyRecords.find((item) => item.type === "publishable")?.api_key;
const serviceKey = keyRecords.find((item) => item.name === "service_role")?.api_key ||
  keyRecords.find((item) => item.type === "secret")?.api_key;
if (!anonKey || !serviceKey) throw new Error("The live Supabase API keys are unavailable.");

const runId = `${Date.now()}-${crypto.randomBytes(4).toString("hex")}`;
const password = `Stdx-${crypto.randomBytes(18).toString("base64url")}!7`;
const users = [];
let teacherToken = "";
let studentToken = "";
let outsiderToken = "";
let classId = "";
let materialId = "";
let storagePath = "";

function check(condition, message) {
  if (!condition) throw new Error(message);
  console.log(`PASS ${message}`);
}

async function request(path, {
  method = "GET", token = "", service = false, body, headers = {}, timeoutMs = 30000,
} = {}) {
  const key = service ? serviceKey : anonKey;
  const response = await fetch(`${projectUrl}${path}`, {
    method,
    headers: {
      apikey: key,
      Authorization: `Bearer ${token || key}`,
      ...(body !== undefined && !Buffer.isBuffer(body) ? { "Content-Type": "application/json" } : {}),
      ...headers,
    },
    body: body === undefined ? undefined : Buffer.isBuffer(body) ? body : JSON.stringify(body),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const text = await response.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch (_) { data = text; }
  return { status: response.status, data, text };
}

async function createUser(label, role) {
  const email = `studexa-cutover-${label}-${runId}@example.test`;
  const result = await request("/auth/v1/admin/users", {
    method: "POST", service: true,
    body: {
      email, password, email_confirm: true,
      user_metadata: { display_name: `Cutover ${label}`, studexa_role: role },
    },
  });
  check(result.status === 200 && result.data?.id, `${label} temporary Auth user is created`);
  users.push(result.data.id);
  return { id: result.data.id, email };
}

async function signIn(email) {
  const result = await request("/auth/v1/token?grant_type=password", {
    method: "POST", body: { email, password },
  });
  check(result.status === 200 && result.data?.access_token, `${email.split("@")[0]} signs in`);
  return result.data.access_token;
}

async function rpc(name, token, body) {
  return request(`/rest/v1/rpc/${name}`, { method: "POST", token, body });
}

async function edge(name, token, body, method = "POST", timeoutMs = 30000) {
  return request(`/functions/v1/${name}`, {
    method, token, body: body === undefined ? undefined : body, timeoutMs,
  });
}

async function generateWithTransientRetries(token, body) {
  let result;
  for (let attempt = 1; attempt <= 3; attempt++) {
    result = await edge("generate-quiz", token, body, "POST", 140000);
    if (result.status === 200 || ![429, 503, 504].includes(result.status)) return result;
    console.log(`RETRY generation attempt ${attempt} returned HTTP ${result.status} (${result.data?.code || "unknown"})`);
    if (attempt < 3) await new Promise((resolve) => setTimeout(resolve, 2000));
  }
  return result;
}

function isCutoverFixtureEmail(email) {
  return /^studexa-cutover-(teacher|student|outsider)-[0-9]+-[a-f0-9]+@example\.test$/i.test(
    String(email || ""),
  );
}

async function deleteAdminUser(id) {
  let lastResult;
  for (let attempt = 1; attempt <= 3; attempt++) {
    lastResult = await request(`/auth/v1/admin/users/${encodeURIComponent(id)}`, {
      method: "DELETE",
      service: true,
    });
    if ([200, 204, 404].includes(lastResult.status)) return;
    if (attempt < 3) await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(
    `Could not delete temporary Auth user (${lastResult?.status || "unknown"}).`,
  );
}

async function cleanupStaleCutoverUsers() {
  const before = await request("/auth/v1/admin/users?page=1&per_page=1000", {
    service: true,
  });
  if (before.status !== 200 || !Array.isArray(before.data?.users)) {
    throw new Error("Could not inventory temporary Auth users for cleanup.");
  }
  const staleUsers = before.data.users.filter((user) =>
    isCutoverFixtureEmail(user.email)
  );
  for (const user of staleUsers) await deleteAdminUser(user.id);

  const after = await request("/auth/v1/admin/users?page=1&per_page=1000", {
    service: true,
  });
  const remaining = (after.data?.users || []).filter((user) =>
    isCutoverFixtureEmail(user.email)
  );
  if (after.status !== 200 || remaining.length > 0) {
    throw new Error("Temporary Auth user cleanup did not reach zero.");
  }
  return staleUsers.length;
}

async function auditAuthUsers() {
  const result = await request("/auth/v1/admin/users?page=1&per_page=1000", {
    service: true,
  });
  if (result.status !== 200 || !Array.isArray(result.data?.users)) {
    throw new Error("Could not inventory Auth users.");
  }
  return result.data.users.map((user) => ({
    emailHash: crypto
      .createHash("sha256")
      .update(String(user.email || "").toLowerCase())
      .digest("hex")
      .slice(0, 12),
    createdAt: user.created_at || null,
    lastSignInAt: user.last_sign_in_at || null,
    provider: user.app_metadata?.provider || null,
    role: user.user_metadata?.studexa_role || null,
    cutoverFixture: isCutoverFixtureEmail(user.email),
  }));
}

async function deviceVerificationClasses(name) {
  if (!/^Studexa Device Verification [0-9]{6}$/.test(String(name || ""))) {
    throw new Error("Device verification class name is invalid.");
  }
  return request(
    `/rest/v1/classes?name=eq.${encodeURIComponent(name)}` +
      `&section=eq.${encodeURIComponent("QA-DEVICE")}` +
      "&select=id,name,subject,section",
    {service: true},
  );
}

async function cleanup() {
  if (storagePath) {
    const storageDelete = await request(`/storage/v1/object/study-materials/${storagePath.split("/").map(encodeURIComponent).join("/")}`, {
      method: "DELETE", service: true,
    });
    if (![200, 204, 404].includes(storageDelete.status)) {
      throw new Error(`Temporary Storage cleanup failed (${storageDelete.status}).`);
    }
  }
  if (classId && teacherToken) {
    const classDelete = await request(`/rest/v1/classes?id=eq.${encodeURIComponent(classId)}`, {
      method: "DELETE", token: teacherToken,
    });
    if (classDelete.status !== 204) {
      throw new Error(`Temporary class cleanup failed (${classDelete.status}).`);
    }
  }
  await cleanupStaleCutoverUsers();
}

if (mode === "--cleanup-only") {
  const removed = await cleanupStaleCutoverUsers();
  console.log(JSON.stringify({success: true, removedTemporaryUsers: removed}));
}

if (mode === "--audit-auth") {
  const authUsers = await auditAuthUsers();
  console.log(JSON.stringify({success: true, count: authUsers.length, authUsers}));
}

if (mode === "--audit-device-class") {
  const result = await deviceVerificationClasses(modeValue);
  const rows = Array.isArray(result.data) ? result.data : [];
  console.log(JSON.stringify({
    success: result.status === 200 && rows.length === 1 &&
      rows[0].subject === modeValue && rows[0].section === "QA-DEVICE",
    count: rows.length,
    subjectMatchesName: rows[0]?.subject === modeValue,
    sectionMatches: rows[0]?.section === "QA-DEVICE",
  }));
  if (result.status !== 200 || rows.length !== 1 ||
      rows[0].subject !== modeValue || rows[0].section !== "QA-DEVICE") {
    process.exitCode = 1;
  }
}

if (mode === "--cleanup-device-class") {
  const result = await request(
    `/rest/v1/classes?name=eq.${encodeURIComponent(modeValue)}` +
      `&section=eq.${encodeURIComponent("QA-DEVICE")}` +
      "&select=id",
    {
      method: "DELETE",
      service: true,
      headers: {Prefer: "return=representation"},
    },
  );
  const verify = await deviceVerificationClasses(modeValue);
  const remaining = Array.isArray(verify.data) ? verify.data.length : -1;
  console.log(JSON.stringify({
    success: result.status === 200 && remaining === 0,
    deleted: Array.isArray(result.data) ? result.data.length : 0,
    remaining,
  }));
  if (result.status !== 200 || remaining !== 0) process.exitCode = 1;
}

async function runFullVerification() {
try {
  const teacher = await createUser("teacher", "teacher");
  const student = await createUser("student", "student");
  const outsider = await createUser("outsider", "teacher");
  [teacherToken, studentToken, outsiderToken] = await Promise.all([
    signIn(teacher.email), signIn(student.email), signIn(outsider.email),
  ]);

  const teacherProfile = await request(`/rest/v1/profiles?id=eq.${teacher.id}`, { token: teacherToken });
  const studentProfile = await request(`/rest/v1/profiles?id=eq.${student.id}`, { token: studentToken });
  check(teacherProfile.status === 200 && teacherProfile.data?.[0]?.role === "teacher", "Auth trigger creates the Teacher profile and role");
  check(studentProfile.status === 200 && studentProfile.data?.[0]?.role === "student", "Auth trigger creates the Student profile and role");

  const claimTeacher = await rpc("claim_studexa_role", teacherToken, { p_role: "teacher" });
  const mismatch = await rpc("claim_studexa_role", teacherToken, { p_role: "student" });
  check(claimTeacher.status === 200 && claimTeacher.data?.role === "teacher", "Teacher role claim is idempotent");
  check(mismatch.status >= 400, "Teacher role cannot be changed to Student");

  const createClass = await rpc("create_studexa_class", teacherToken, {
    p_name: "Cutover Verification",
    p_section: "Verification Section",
  });
  check(createClass.status === 200 && createClass.data?.id && createClass.data?.join_code, "Teacher creates a class and join code atomically");
  check(createClass.data?.subject === "Cutover Verification", "Class subject matches its class name");
  check(createClass.data?.section === "Verification Section", "Class section is stored");
  classId = createClass.data.id;
  const join = await rpc("join_studexa_class", studentToken, { p_join_code: createClass.data.join_code });
  const duplicateJoin = await rpc("join_studexa_class", studentToken, { p_join_code: createClass.data.join_code });
  check(join.status === 200 && join.data?.id === classId, "Student joins the class by code");
  check(duplicateJoin.status >= 400, "Duplicate enrollment is rejected");
  const outsiderClasses = await request("/rest/v1/classes?select=id", { token: outsiderToken });
  check(outsiderClasses.status === 200 && outsiderClasses.data?.length === 0, "Unrelated Teacher cannot read the class");

  materialId = crypto.randomUUID();
  storagePath = `uploads/${teacher.id}/${materialId}/lesson.pdf`;
  const upload = await request(`/storage/v1/object/study-materials/${storagePath.split("/").map(encodeURIComponent).join("/")}`, {
    method: "POST", token: teacherToken, body: Buffer.from("%PDF-1.4 Studexa cutover verification"),
    headers: { "Content-Type": "application/pdf", "x-upsert": "false" },
  });
  check([200, 201].includes(upload.status), "Teacher uploads only to the owned private Storage prefix");

  const extractedText = [
    "Operating systems coordinate computer hardware and software resources.",
    "A process is a program in execution, while a thread is a unit of CPU utilization.",
    "Virtual memory lets a process use an address space larger than physical memory.",
    "The scheduler selects a ready process for the processor.",
    "Mutual exclusion prevents concurrent access to a critical section.",
    "A semaphore is a synchronization primitive controlled through wait and signal operations.",
    "Deadlock can require mutual exclusion, hold and wait, no preemption, and circular wait.",
  ].join(" ");
  const materialInsert = await request("/rest/v1/materials?select=*", {
    method: "POST", token: teacherToken,
    headers: { Prefer: "return=representation" },
    body: {
      id: materialId, teacher_id: teacher.id, class_id: classId,
      file_name: "lesson.pdf", file_type: "pdf", file_ref: storagePath,
      storage_upload_status: "completed", status: "ready", extracted_text: extractedText,
      file_size_bytes: 38,
    },
  });
  check(materialInsert.status === 201 && materialInsert.data?.[0]?.id === materialId, "Teacher saves extracted material metadata");
  const encodedObject = storagePath.split("/").map(encodeURIComponent).join("/");
  const studentDownloadBeforePost = await request(
    `/storage/v1/object/authenticated/study-materials/${encodedObject}`,
    { token: studentToken },
  );
  check(
    studentDownloadBeforePost.status >= 400,
    "Enrolled Student cannot read an unposted material object",
  );
  const postMaterial = await request(`/rest/v1/materials?id=eq.${materialId}&select=*`, {
    method: "PATCH",
    token: teacherToken,
    headers: { Prefer: "return=representation" },
    body: { is_posted: true, posted_at: new Date().toISOString() },
  });
  check(
    postMaterial.status === 200 && postMaterial.data?.[0]?.is_posted === true,
    "Teacher posts the ready material",
  );
  const studentDownload = await request(
    `/storage/v1/object/authenticated/study-materials/${encodedObject}`,
    { token: studentToken },
  );
  const outsiderDownload = await request(`/storage/v1/object/authenticated/study-materials/${encodedObject}`, { token: outsiderToken });
  check(studentDownload.status === 200, "Enrolled Student reads the posted private material object");
  check(outsiderDownload.status >= 400, "Unrelated Teacher cannot read the private material object");

  const keyStatus = await edge("teacher-gemini-key", teacherToken, undefined, "GET");
  const studentKeyStatus = await edge("teacher-gemini-key", studentToken, undefined, "GET");
  const rejectedValue = "definitely-invalid-gemini-key-1234567890";
  const invalidKey = await edge("teacher-gemini-key", teacherToken, { apiKey: rejectedValue }, "PUT", 45000);
  check(keyStatus.status === 200 && keyStatus.data?.status?.configured === false && keyStatus.data?.status?.graceRemaining === 3, "Teacher key status begins with three temporary generations");
  check(studentKeyStatus.status === 403, "Student cannot access Teacher Gemini settings");
  check(invalidKey.status === 400 && !invalidKey.text.includes(rejectedValue), "Invalid personal key is rejected without echoing it");

  const studentGeneration = await edge("generate-quiz", studentToken, {
    classId, materialId, quizType: "actual", questionTypes: ["identification"], questionCount: 1,
    clientSessionId: `student_${runId.replace(/[^a-zA-Z0-9]/g, "")}`.slice(0, 70),
    batchRequestId: `student_batch_${runId.replace(/[^a-zA-Z0-9]/g, "")}`.slice(0, 70), mode: "initial",
  });
  check(studentGeneration.status === 403, "Student quiz generation is rejected before Gemini is called");

  const compactRunId = runId.replace(/[^a-zA-Z0-9]/g, "");
  const actualBody = {
    classId, materialId, quizType: "actual", questionTypes: ["identification"], questionCount: 1,
    clientSessionId: `actual_${compactRunId}`.slice(0, 70),
    batchRequestId: `actual_batch_${compactRunId}`.slice(0, 70), mode: "initial",
  };
  const actual = await generateWithTransientRetries(teacherToken, actualBody);
  if (actual.status !== 200) {
    console.error("Actual generation diagnostic", JSON.stringify({
      status: actual.status,
      code: actual.data?.code || null,
      error: actual.data?.error || "No structured error returned",
    }));
  }
  check(actual.status === 200 && actual.data?.quizId && actual.data?.quiz?.questions?.length === 1, "Teacher generates a live Actual quiz through Gemini");
  check(actual.data.quiz.generationCredentialSource === "backup", "Teacher without a key uses the protected Studexa backup");
  const actualRetry = await edge("generate-quiz", teacherToken, actualBody, "POST", 45000);
  check(actualRetry.status === 200 && actualRetry.data?.quizId === actual.data.quizId, "Actual generation retry is idempotent");

  const manual = await rpc("append_manual_quiz_question", teacherToken, {
    p_quiz_id: actual.data.quizId,
    p_question: {
      type: "true_false", question: "A process is a program in execution.",
      correctAnswer: "True", options: ["True", "False"], points: 1,
    },
  });
  check(manual.status === 200 && manual.data?.questions?.length === 2 && manual.data.questions[1]?.origin === "manual", "Manual question coexists with generated questions");

  const practiceBody = {
    classId, materialId, quizType: "practice", sourceQuizId: actual.data.quizId,
    questionTypes: ["identification"], questionCount: 1,
    clientSessionId: `practice_${compactRunId}`.slice(0, 70),
    batchRequestId: `practice_batch_${compactRunId}`.slice(0, 70), mode: "initial",
  };
  const practice = await generateWithTransientRetries(teacherToken, practiceBody);
  if (practice.status !== 200) {
    console.error("Practice generation diagnostic", JSON.stringify({
      status: practice.status,
      code: practice.data?.code || null,
      error: practice.data?.error || "No structured error returned",
    }));
  }
  check(practice.status === 200 && practice.data?.quiz?.questions?.length === 1, "Teacher generates a live Practice quiz from the Actual reference");
  check(practice.data.quiz.backupGraceRemaining === 1, "Two successful sessions consume exactly two temporary allowances");

  const publish = await request(`/rest/v1/quizzes?id=eq.${practice.data.quizId}&select=*`, {
    method: "PATCH", token: teacherToken, headers: { Prefer: "return=representation" },
    body: { status: "published", published_at: new Date().toISOString() },
  });
  check(publish.status === 200 && publish.data?.[0]?.status === "published", "Teacher publishes the Practice quiz");
  const assignment = await request("/rest/v1/quiz_assignments?select=*", {
    method: "POST", token: teacherToken, headers: { Prefer: "return=representation" },
    body: {
      quiz_id: practice.data.quizId, class_id: classId, teacher_id: teacher.id,
      quiz_title: practice.data.quiz.title,
    },
  });
  check(assignment.status === 201 && assignment.data?.[0]?.id, "Teacher assigns the published Practice quiz");

  const studentQuiz = await request(`/rest/v1/quizzes?id=eq.${practice.data.quizId}&select=*`, { token: studentToken });
  check(studentQuiz.status === 200 && studentQuiz.data?.length === 1, "Enrolled Student reads the published Practice quiz");
  const question = studentQuiz.data[0].questions[0];
  const answers = { [question.id]: question.correctAnswer };
  const draft = await request("/rest/v1/quiz_drafts", {
    method: "POST", token: studentToken,
    body: { student_id: student.id, quiz_id: practice.data.quizId, attempt_number: 1, answers },
  });
  check(draft.status === 201, "Student saves an answer draft");

  const firstAttemptId = crypto.randomUUID();
  const firstAttemptBody = { quizId: practice.data.quizId, classId, clientAttemptId: firstAttemptId, answers };
  const firstAttempt = await edge("submit-quiz-attempt", studentToken, firstAttemptBody, "POST", 45000);
  const firstRetry = await edge("submit-quiz-attempt", studentToken, firstAttemptBody, "POST", 45000);
  check(firstAttempt.status === 200 && firstAttempt.data?.attempt?.attempt_number === 1 && Number(firstAttempt.data.attempt.percentage) === 100, "Edge Function scores and saves the first attempt authoritatively");
  check(firstRetry.status === 200 && firstRetry.data?.attempt?.id === firstAttempt.data.attempt.id, "Attempt retry is idempotent");
  const secondAttempt = await edge("submit-quiz-attempt", studentToken, {
    ...firstAttemptBody, clientAttemptId: crypto.randomUUID(),
  }, "POST", 45000);
  const thirdAttempt = await edge("submit-quiz-attempt", studentToken, {
    ...firstAttemptBody, clientAttemptId: crypto.randomUUID(),
  }, "POST", 45000);
  check(secondAttempt.status === 200 && secondAttempt.data?.attempt?.attempt_number === 2, "Second attempt is accepted");
  check(thirdAttempt.status === 409, "Third attempt is rejected by the transactional two-attempt limit");

  const teacherAttempts = await request(`/rest/v1/quiz_attempts?quiz_id=eq.${practice.data.quizId}`, { token: teacherToken });
  const outsiderAttempts = await request(`/rest/v1/quiz_attempts?quiz_id=eq.${practice.data.quizId}`, { token: outsiderToken });
  check(teacherAttempts.status === 200 && teacherAttempts.data?.length === 2, "Owning Teacher reads both Student results");
  check(outsiderAttempts.status === 200 && outsiderAttempts.data?.length === 0, "Unrelated Teacher cannot read Student results");

  const deleteMaterial = await request(`/rest/v1/materials?id=eq.${materialId}`, { method: "DELETE", token: teacherToken });
  const preservedPractice = await request(`/rest/v1/quizzes?id=eq.${practice.data.quizId}`, { token: teacherToken });
  const removedDraftActual = await request(`/rest/v1/quizzes?id=eq.${actual.data.quizId}`, { token: teacherToken });
  check(deleteMaterial.status === 204, "Teacher deletes the source material record");
  check(preservedPractice.data?.[0]?.material_id === null, "Published Practice quiz survives material deletion without an orphan reference");
  check(removedDraftActual.data?.length === 0, "Draft Actual quiz is removed with its deleted material");

  console.log(JSON.stringify({ success: true, runId, temporaryUsers: users.length }));
} finally {
  await cleanup();
}
}

const knownModes = new Set([
  "--cleanup-only",
  "--audit-auth",
  "--audit-device-class",
  "--cleanup-device-class",
]);
if (mode && !knownModes.has(mode)) throw new Error(`Unknown mode: ${mode}`);
if (!mode) await runFullVerification();
