import assert from "node:assert/strict";
import { test } from "node:test";
import { generateQuizQuestions, validateQuestions, isRepeatedFact } from "../_shared/quiz_generator.mjs";

const extractedText = "A process is a program in execution. The kernel manages CPU scheduling. RAM holds active programs and data. A scheduler selects the next process to execute.";
const question = {
  type: "identification", question: "What is a program in execution called?", options: [],
  correctAnswer: "process", enumerationAnswers: [],
  explanation: "A program in execution is a process.",
  sourceExcerpt: "A process is a program in execution.",
};

test("ported Gemini prompt, grounding and duplicate guard remain active", async () => {
  const request = { extractedText, questionTypes: ["identification"], questionCount: 1, isActual: true };
  const generated = await generateQuizQuestions(request, {
    apiKey: "test-key", candidateModels: ["test-model"], maxRounds: 1,
    fetchImpl: async (url, init) => {
      assert.match(url, /test-model:generateContent/);
      assert.equal(init.headers["x-goog-api-key"], "test-key");
      const body = JSON.parse(init.body);
      assert.match(body.systemInstruction.parts[0].text, /sourceExcerpt of at least 15 characters/);
      assert.equal(JSON.parse(body.contents[0].parts[0].text).studyMaterial, extractedText);
      return new Response(JSON.stringify({ candidates: [{ finishReason: "STOP",
        content: { parts: [{ text: JSON.stringify({ questions: [question] }) }] } }] }), { status: 200 });
    },
  });
  assert.equal(generated[0].correctAnswer, "process");
  assert.equal(isRepeatedFact({ ...question, question: "Identify a program currently executing." }, question), true);
  assert.throws(() => validateQuestions([{ ...question, sourceExcerpt: "Imaginary fact not in material" }], request), { code: "data-loss" });
});
