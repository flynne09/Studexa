import assert from "node:assert/strict";
import { test } from "node:test";
import { handleSubmitQuizAttempt, scoreQuiz } from "../_shared/submit_quiz_attempt_edge.mjs";

const questions = [
  { id: "q_1", type: "multiple_choice", question: "CPU?", correctAnswer: "A. Processor", points: 1 },
  { id: "q_2", type: "identification", question: "Memory?", correctAnswer: "Register", points: 1 },
  { id: "q_3", type: "enumeration", question: "Parts", correctAnswer: "", enumerationAnswers: ["ALU", "Control Unit"], points: 2 },
];

test("server scoring preserves exact, typo-tolerant and partial enumeration behavior", () => {
  const result = scoreQuiz(questions, {
    q_1: "A. Processor",
    q_2: "Registe",
    q_3: ["ALU", "extra"],
  });
  assert.equal(result.totalPoints, 4);
  assert.equal(result.score, 3);
  assert.equal(result.percentage, 75);
});

test("submission authenticates, reads an authorized quiz and persists server score", async () => {
  let saved;
  const request = new Request("https://example.test/submit", {
    method: "POST",
    headers: { Authorization: "Bearer user-token", "Content-Type": "application/json" },
    body: JSON.stringify({
      quizId: "00000000-0000-4000-8000-000000000001",
      classId: "00000000-0000-4000-8000-000000000002",
      clientAttemptId: "00000000-0000-4000-8000-000000000003",
      answers: { q_1: "A. Processor" },
    }),
  });
  const response = await handleSubmitQuizAttempt(request, {
    verifyToken: async () => ({ id: "00000000-0000-4000-8000-000000000004" }),
    store: { get: async () => ({ updateTime: "2026-09-24T00:00:00Z", data: { classId: "00000000-0000-4000-8000-000000000002", questions: [questions[0]] } }) },
    saveAttempt: async (params) => { saved = params; return { id: "attempt", score: params.p_score }; },
  });
  assert.equal(response.status, 200);
  assert.equal(saved.p_score, 1);
  assert.equal(saved.p_student_id, "00000000-0000-4000-8000-000000000004");
  assert.equal(saved.p_quiz_updated_at, "2026-09-24T00:00:00Z");
});

test("student cannot submit a quiz hidden by RLS", async () => {
  const request = new Request("https://example.test/submit", {
    method: "POST",
    headers: { Authorization: "Bearer user-token", "Content-Type": "application/json" },
    body: JSON.stringify({
      quizId: "00000000-0000-4000-8000-000000000001",
      classId: "00000000-0000-4000-8000-000000000002",
      clientAttemptId: "00000000-0000-4000-8000-000000000003",
      answers: {},
    }),
  });
  const response = await handleSubmitQuizAttempt(request, {
    verifyToken: async () => ({ id: "student" }),
    store: { get: async () => null },
  });
  assert.equal(response.status, 404);
});
