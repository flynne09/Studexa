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
    assert.match(body.systemInstruction.parts[0].text, /sourceExcerpt of at least 15 characters/);
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

const choiceQuestion = {
  ...question, type: "multiple_choice", question: "What does the kernel do?",
  options: ["A. Scheduling the CPU for active programs", "B. Stores permanent files", "C. Compiles source code", "D. Displays web pages"],
  correctAnswer: "A. Scheduling the CPU for active programs",
  sourceExcerpt: "The kernel manages CPU scheduling.",
};
const choiceRequest = { ...request, questionTypes: ["multiple_choice"] };
const withChoice = (answer) => ({ ...choiceQuestion, correctAnswer: `A. ${answer}`, options: [`A. ${answer}`, ...choiceQuestion.options.slice(1)] });

test("accepts explanatory MCQ paraphrases grounded in their excerpt", () => {
  assert.ok(!text.toLowerCase().includes(choiceQuestion.correctAnswer.slice(3).toLowerCase()));
  const result = validateQuestions([choiceQuestion], choiceRequest);
  assert.equal(result[0].correctAnswer, choiceQuestion.correctAnswer);
  assert.equal(result[0].sourceExcerpt, choiceQuestion.sourceExcerpt);
});

test("rejects MCQ phrases supported only elsewhere or by incidental matches", () => {
  for (const answer of [
    "Holding data and active programs in RAM", // Paraphrases elsewhere, not the cited evidence.
    "Scheduling intergalactic voyages and cosmic adventures", // One shared term is insufficient.
    "The and with through", // No meaningful terms.
  ]) {
    assert.throws(() => validateQuestions([withChoice(answer)], choiceRequest), { code: "data-loss" });
  }
});

test("preserves verbatim long subject names when the definition excerpt omits the name", () => {
  const q = withChoice("Research in computer science");
  q.sourceExcerpt = "A systematic and rigorous process of inquiry aimed at generating new knowledge.";
  const req = { ...choiceRequest, extractedText: `Research in computer science\n${q.sourceExcerpt}` };
  assert.equal(validateQuestions([q], req)[0].correctAnswer, q.correctAnswer);
});

test("short MCQ terms must appear as whole words in the material", () => {
  for (const answer of ["kernel", "CPU scheduling", "RAM"]) {
    assert.equal(validateQuestions([withChoice(answer)], choiceRequest).length, 1);
  }
  for (const answer of ["mitochondria", "gram"]) {
    assert.throws(() => validateQuestions([withChoice(answer)], choiceRequest), { code: "data-loss" });
  }
});

test("MCQ choices need distinct nonempty text, ordered labels and a full matching answer", () => {
  for (const patch of [
    { options: ["A. kernel", "B. Kernel!", "C. process", "D. RAM"], correctAnswer: "A. kernel" },
    { options: ["A. kernel", "B. !!!", "C. process", "D. RAM"], correctAnswer: "A. kernel" },
    { options: ["B. kernel", "A. scheduler", "C. process", "D. RAM"], correctAnswer: "B. kernel" },
    { correctAnswer: "A" },
    { sourceExcerpt: "The kernel controls imaginary space voyages." },
    { sourceExcerpt: "CPU scheduling" },
  ]) {
    assert.throws(() => validateQuestions([{ ...choiceQuestion, ...patch }], choiceRequest), { code: "data-loss" });
  }
});

test("keeps distinct technical options such as C, C++ and C#", () => {
  const q = { ...withChoice("kernel"), options: ["A. kernel", "B. C", "C. C++", "D. C#"] };
  assert.equal(validateQuestions([q], choiceRequest).length, 1);
});

test("generates a complete ten-question MCQ and True/False batch from a provider fixture", async () => {
  const questions = Array.from({ length: 10 }, (_, index) => index % 2 === 0
    ? { ...choiceQuestion, question: `Kernel task ${index + 1}: which operation is supported?` }
    : { ...question, type: "true_false", question: `Statement ${index + 1}: a process is a program in execution.`,
      options: ["True", "False"], correctAnswer: "True" });
  const result = await generateQuizQuestions({ ...request, questionTypes: ["multiple_choice", "true_false"], questionCount: 10 }, options(async () => response(questions)));
  assert.equal(result.length, 10);
  assert.equal(result.filter((q) => q.type === "multiple_choice").length, 5);
  assert.equal(result.filter((q) => q.type === "true_false").length, 5);
});

test("does not automatically retry rate-limited requests on the same model", async () => {
  let calls = 0;
  await assert.rejects(generateQuizQuestions(request, {
    ...options(async () => {
      calls++;
      return new Response("quota exceeded", { status: 429 });
    }),
    candidateModels: ["gemini-3.5-flash"],
  }), { code: "resource-exhausted", message: "The AI service has reached its request limit. Please try again later." });
  assert.equal(calls, 1);
});

test("automatically rotates models when a model hits quota or demand spikes", async () => {
  let calls = 0;
  const modelsTried = [];
  const result = await generateQuizQuestions(request, {
    ...options(async (url) => {
      calls++;
      const modelName = url.match(/models\/([^:]+):/)?.[1];
      modelsTried.push(modelName);
      if (modelName === "gemini-3.5-flash") {
        return new Response("quota exceeded", { status: 429 });
      }
      return response();
    }),
    candidateModels: ["gemini-3.5-flash", "gemini-3.6-flash"],
  });
  assert.equal(result.length, 1);
  assert.equal(calls, 2);
  assert.deepEqual(modelsTried, ["gemini-3.5-flash", "gemini-3.6-flash"]);
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

test("batches generation in chunks of 10 for counts > 10", async () => {
  let batchCalls = 0;
  let qCounter = 0;
  const mockFetch = async (url, init) => {
    batchCalls++;
    const body = JSON.parse(init.body);
    const count = body.generationConfig.responseSchema.properties.questions.minItems;
    assert.ok(count <= 10, "Each batch must request <= 10 questions");
    const batchQs = Array.from({ length: count }, () => {
      qCounter++;
      return {
        ...question,
        question: `Unique question number ${qCounter} for batching`,
      };
    });
    return response(batchQs);
  };

  const res30 = await generateQuizQuestions({ ...request, questionCount: 30 }, options(mockFetch));
  assert.equal(res30.length, 30);
  assert.equal(batchCalls, 3); // 3 batches of 10

  batchCalls = 0;
  qCounter = 0;
  const res50 = await generateQuizQuestions({ ...request, questionCount: 50 }, options(mockFetch));
  assert.equal(res50.length, 50);
  assert.equal(batchCalls, 5); // 5 batches of 10
});

