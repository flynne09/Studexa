import { PostgresStoreError, postgresClient } from "./postgres_rest.mjs";
import { SupabaseIdentityError, verifySupabaseToken } from "./supabase_identity.mjs";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (status, body) => new Response(JSON.stringify(body), {
  status,
  headers: { ...CORS, "Content-Type": "application/json" },
});

const cleanExpected = (value) => String(value ?? "").trim()
  .replace(/^([A-Za-z]{1,2}|\d{1,3})[.)\-:]\s+/, "")
  .replace(/^[-*•‣◦⁃∙]\s*/, "")
  .replace(/^["']|["']$/g, "").trim();

const normalize = (value) => cleanExpected(value).toLowerCase()
  .replace(/[^\w\s]/g, "").replace(/\s+/g, " ").trim();

function distance(left, right) {
  if (left === right) return 0;
  if (!left.length) return right.length;
  if (!right.length) return left.length;
  let previous = Array.from({ length: right.length + 1 }, (_, index) => index);
  let current = new Array(right.length + 1).fill(0);
  for (let i = 0; i < left.length; i++) {
    current[0] = i + 1;
    for (let j = 0; j < right.length; j++) {
      current[j + 1] = Math.min(current[j] + 1, previous[j + 1] + 1, previous[j] + (left[i] === right[j] ? 0 : 1));
    }
    [previous, current] = [current, previous];
  }
  return previous[right.length];
}

function freeTextMatch(student, expected) {
  const actual = normalize(student);
  const target = normalize(expected);
  if (actual === target) return true;
  if (!actual || !target) return false;
  const allowed = target.length <= 4 ? 0 : target.length <= 8 ? 1 : 2;
  return distance(actual, target) <= allowed;
}

function scoreEnumeration(studentItems, expectedItems, points) {
  const remaining = [];
  for (const item of expectedItems) {
    const clean = cleanExpected(item);
    if (clean && !remaining.some((value) => normalize(value) === normalize(clean))) remaining.push(clean);
  }
  const students = [];
  const seen = new Set();
  for (const item of studentItems) {
    const text = String(item).trim();
    const key = normalize(text);
    if (key && !seen.has(key)) { seen.add(key); students.push(text); }
  }
  let found = 0;
  for (const item of students) {
    const index = remaining.findIndex((expected) => freeTextMatch(item, expected));
    if (index >= 0) { found++; remaining.splice(index, 1); }
  }
  const expectedCount = found + remaining.length;
  return expectedCount ? found / expectedCount * points : 0;
}

export function scoreQuiz(questions, answers) {
  let score = 0;
  let totalPoints = 0;
  const breakdown = [];
  for (const question of questions) {
    const points = Number(question.points || 1);
    const answer = answers[question.id];
    let earned = 0;
    if (["multiple_choice", "true_false"].includes(question.type)) {
      earned = String(answer ?? "").trim().toLowerCase() === String(question.correctAnswer ?? "").trim().toLowerCase() ? points : 0;
    } else if (["fill_blank", "identification"].includes(question.type)) {
      earned = freeTextMatch(answer, question.correctAnswer) ? points : 0;
    } else if (question.type === "enumeration") {
      const expected = Array.isArray(question.enumerationAnswers) && question.enumerationAnswers.length
        ? question.enumerationAnswers
        : String(question.correctAnswer || "").split(/[\n,]/).map((value) => value.trim()).filter(Boolean);
      earned = scoreEnumeration(Array.isArray(answer) ? answer : [], expected, points);
    }
    totalPoints += points;
    score += earned;
    breakdown.push({
      questionId: question.id,
      question: question.question,
      userAnswer: Array.isArray(answer) ? answer.join(", ") : String(answer ?? ""),
      correctAnswer: question.correctAnswer || (question.enumerationAnswers || []).join(", "),
      earned,
      points,
      isCorrect: Math.abs(earned - points) < 0.000001,
    });
  }
  const percentage = totalPoints > 0 ? score / totalPoints * 100 : 0;
  return { score, totalPoints, percentage, breakdown };
}

function secretKey() {
  const keys = globalThis.Deno?.env.get("SUPABASE_SECRET_KEYS");
  if (keys) {
    try { return JSON.parse(keys).default || ""; } catch (_) { return ""; }
  }
  return globalThis.Deno?.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
}

async function saveAttempt(params, fetchImpl = fetch) {
  const url = globalThis.Deno?.env.get("SUPABASE_URL") || "";
  const key = secretKey();
  if (!url || !key) throw new Error("Attempt persistence is not configured.");
  const response = await fetchImpl(`${url}/rest/v1/rpc/studexa_save_scored_attempt`, {
    method: "POST",
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify(params),
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    const message = String(error.message || "Could not save this attempt.");
    const status = /maximum 2 attempts|closed|deadline|unavailable|quiz changed/i.test(message) ? 409 : 403;
    throw new PostgresStoreError(status, message);
  }
  const body = await response.json();
  return Array.isArray(body) ? body[0] : body;
}

export async function handleSubmitQuizAttempt(request, deps = {}) {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (request.method !== "POST") return json(405, { error: "Use POST." });
  const auth = request.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "Sign in again before submitting." });
  const fetchImpl = deps.fetchImpl || fetch;
  try {
    const token = auth.slice(7);
    const user = await (deps.verifyToken || verifySupabaseToken)(token, fetchImpl, deps.authOptions);
    const uid = user.id || user;
    const body = await request.json();
    if (!body || typeof body !== "object" || !/^[0-9a-f-]{36}$/i.test(body.quizId || "") ||
        !/^[0-9a-f-]{36}$/i.test(body.classId || "") || !/^[0-9a-f-]{36}$/i.test(body.clientAttemptId || "") ||
        !body.answers || typeof body.answers !== "object" || Array.isArray(body.answers)) {
      return json(400, { error: "The quiz attempt is incomplete." });
    }
    const store = deps.store || postgresClient(token, fetchImpl);
    const quizDoc = await store.get("quizzes", body.quizId);
    if (!quizDoc || !quizDoc.updateTime || quizDoc.data.classId !== body.classId || !Array.isArray(quizDoc.data.questions)) {
      return json(404, { error: "This quiz is no longer available." });
    }
    const scored = scoreQuiz(quizDoc.data.questions, body.answers);
    const attempt = await (deps.saveAttempt || saveAttempt)({
      p_student_id: uid,
      p_quiz_id: body.quizId,
      p_class_id: body.classId,
      p_client_attempt_id: body.clientAttemptId,
      p_answers: body.answers,
      p_score: scored.score,
      p_total_points: scored.totalPoints,
      p_percentage: scored.percentage,
      p_breakdown: scored.breakdown,
      p_quiz_updated_at: quizDoc.updateTime,
    }, fetchImpl);
    return json(200, { success: true, attempt });
  } catch (error) {
    if (error instanceof SyntaxError) return json(400, { error: "Request must contain valid JSON." });
    if (error instanceof SupabaseIdentityError) return json(error.status, { error: error.message });
    if (error instanceof PostgresStoreError) return json(error.status, { error: error.message });
    console.error("Attempt submission failed", { name: error?.name || "Error" });
    return json(503, { error: "Studexa could not save this attempt. Try again." });
  }
}
