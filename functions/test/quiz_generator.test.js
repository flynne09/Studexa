const { test } = require("node:test");
const assert = require("node:assert/strict");
const { generateQuizQuestions, validateQuestions } = require("../quiz_generator");

const text = "A process is a program in execution. The kernel manages CPU scheduling. RAM holds active programs and data. A scheduler selects the next process to execute.";
const question = { type: "identification", question: "What is a program in execution called?", options: [], correctAnswer: "process", enumerationAnswers: [], explanation: "A program in execution is a process.", sourceExcerpt: "A process is a program in execution." };
const request = { extractedText: text, questionTypes: ["identification"], questionCount: 1, isActual: true };
const response = (questions = [question]) => new Response(JSON.stringify({ candidates: [{ finishReason: "STOP", content: { parts: [{ text: JSON.stringify({ questions }) }] } }] }));
const options = (fetchImpl) => ({ apiKey: "test-only-not-a-real-key", fetchImpl });

test("request includes selected type/count, full material, schema and header key", async () => {
  const result = await generateQuizQuestions(request, options(async (url, init) => {
    assert.ok(!url.includes("key="));
    assert.equal(init.headers["x-goog-api-key"], "test-only-not-a-real-key");
    const body = JSON.parse(init.body);
    assert.match(body.systemInstruction.parts[0].text, /Allowed types ONLY: identification/);
    assert.equal(JSON.parse(body.contents[0].parts[0].text).studyMaterial, text);
    assert.equal(body.generationConfig.responseSchema.properties.questions.maxItems, 1);
    return response();
  }));
  assert.equal(result[0].correctAnswer, "process");
  assert.equal(result[0].id, "q_1");
});

test("rejects missing key before any network request", async () => {
  await assert.rejects(generateQuizQuestions(request), { code: "failed-precondition" });
});
test("rejects empty material and invalid counts/types", async () => {
  for (const patch of [{ extractedText: "" }, { questionCount: 0 }, { questionCount: 51 }, { questionTypes: ["unknown"] }]) {
    await assert.rejects(generateQuizQuestions({ ...request, ...patch }, options(() => { throw new Error("Must not call API"); })));
  }
});
test("rejects wrong count, unselected type, duplicate stems and fabricated evidence", () => {
  for (const raw of [[], [{ ...question, type: "true_false" }], [{ ...question, sourceExcerpt: "Invented biology reference from another document" }], [{ ...question, correctAnswer: "mitochondria" }]]) {
    assert.throws(() => validateQuestions(raw, request), { code: "data-loss" });
  }
  assert.throws(() => validateQuestions([question, question], { ...request, questionCount: 2 }), { code: "data-loss" });
});
test("rejects invalid MCQ choices and answers", () => {
  const req = { ...request, questionTypes: ["multiple_choice"] };
  assert.throws(() => validateQuestions([{ ...question, type: "multiple_choice", options: ["process", "kernel"] }], req), { code: "data-loss" });
});
test("filters boilerplate without substituting fallback questions", async () => {
  await assert.rejects(generateQuizQuestions(request, { ...options(async () => response()), rejectQuestion: () => true }), { code: "data-loss" });
});
test("keeps exact counts for 10, 30 and 50 valid questions", () => {
  for (const count of [10, 30, 50]) {
    const raw = Array.from({ length: count }, (_, index) => ({ ...question, question: `Definition number ${index + 1}: identify the execution concept.` }));
    assert.equal(validateQuestions(raw, { ...request, questionCount: count }).length, count);
  }
});
test("maps rejected credentials, rate limit and server failures safely", async () => {
  for (const [status, code] of [[403, "failed-precondition"], [404, "failed-precondition"], [429, "resource-exhausted"], [500, "unavailable"]]) {
    await assert.rejects(generateQuizQuestions(request, options(async () => new Response("upstream secret details", { status }))), (error) => error.code === code && !error.message.includes("secret details"));
  }
});
test("maps network errors and timeouts", async () => {
  await assert.rejects(generateQuizQuestions(request, options(async () => { throw new TypeError("fetch failed"); })), { code: "unavailable" });
  await assert.rejects(generateQuizQuestions(request, options(async () => { throw new DOMException("timeout", "TimeoutError"); })), { code: "deadline-exceeded" });
});
test("rejects malformed, missing and truncated candidate data", async () => {
  for (const payload of ["not json", "{}", JSON.stringify({ candidates: [{ finishReason: "MAX_TOKENS" }] })]) {
    await assert.rejects(generateQuizQuestions(request, options(async () => new Response(payload))), { code: "data-loss" });
  }
});
test("practice request includes the Actual reference as data", async () => {
  await generateQuizQuestions({ ...request, isActual: false, sourceQuizContext: "Reference quiz" }, options(async (_, init) => {
    const body = JSON.parse(init.body);
    assert.match(body.systemInstruction.parts[0].text, /PRACTICE/);
    assert.equal(JSON.parse(body.contents[0].parts[0].text).referenceActualQuiz, "Reference quiz");
    return response();
  }));
});
