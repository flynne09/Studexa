import { QuizGenerationError, generateQuizQuestions, isRepeatedFact, validateRequest } from "./quiz_generator.mjs";
import { isFillerOrBoilerplateQuestion, isTableHeaderQuestion } from "./question_filters.mjs";
import { FirestoreError, firestoreClient } from "./firestore_rest.mjs";
import { FirebaseIdentityError, FIREBASE_WEB_API_KEY, verifyFirebaseToken } from "./firebase_identity.mjs";
import { CredentialStoreError, teacherCredentialStore } from "./teacher_credentials.mjs";

const TYPES = ["multiple_choice", "true_false", "fill_blank", "identification", "enumeration"];
const BATCH_SIZE = 10;
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const validId = (value) => typeof value === "string" && value.trim().length > 0 &&
  value.length <= 1500 && !value.includes("/");
const validRequestId = (value) => typeof value === "string" && /^[a-zA-Z0-9_-]{16,80}$/.test(value);
const fail = (code, message) => { throw new QuizGenerationError(code, message); };

function json(status, body) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

function publicQuiz(id, data) {
  return { success: true, quizId: id, quiz: { id, ...data } };
}

function ensureExistingQuiz(quiz, expected, teacherId) {
  if (!quiz || quiz.teacherId !== teacherId || quiz.classId !== expected.classId ||
      quiz.materialId !== expected.materialId || quiz.type !== expected.quizType ||
      quiz.status !== "draft" || quiz.generationMethod !== "gemini" ||
      !Number.isInteger(quiz.requestedQuestionCount) ||
      !Array.isArray(quiz.selectedQuestionTypes) || !Array.isArray(quiz.questions)) {
    fail("failed-precondition", "This draft changed. Reopen it before generating more questions.");
  }
}

function chooseBatchTypes(types, existing, remaining) {
  const missing = types.filter((type) => !existing.some((question) => question.type === type));
  if (missing.length) return missing.slice(0, Math.min(BATCH_SIZE, remaining));
  const batchSize = Math.min(BATCH_SIZE, remaining);
  if (batchSize >= types.length) return types;
  return [...types].sort((a, b) =>
    existing.filter((q) => q.type === a).length - existing.filter((q) => q.type === b).length,
  ).slice(0, batchSize);
}

const backupEligible = (error) => error instanceof QuizGenerationError &&
  ["resource-exhausted", "deadline-exceeded", "unavailable"].includes(error.code);

function usageFromStatus(source, reason, status = {}) {
  return {
    source,
    backupReason: reason || null,
    graceRemaining: Number.isInteger(status.graceRemaining) ? status.graceRemaining : null,
    fallbackRemainingToday: Number.isInteger(status.fallbackRemainingToday)
      ? status.fallbackRemainingToday
      : null,
  };
}

async function generateForSession(request, uid, clientSessionId, options) {
  const run = (apiKey) => options.generate(request, {
    apiKey,
    candidateModels: options.candidateModels,
    timeoutMs: 38000,
    maxRounds: 1,
    fetchImpl: options.fetchImpl,
    rejectQuestion: (q) => isTableHeaderQuestion(q) || isFillerOrBoilerplateQuestion(q),
  });

  // Test and local compatibility path. Production always provides the private
  // credential store and therefore never treats the shared key as personal.
  if (!options.credentialStore) {
    if (!options.backupApiKey) fail("backup-unavailable", "Quiz generation is temporarily unavailable. Ask your administrator to check the backup service.");
    return { questions: await run(options.backupApiKey), usage: usageFromStatus("backup", "legacy"), finish: async () => {} };
  }

  const credentials = options.credentialStore;
  const existingBackup = await credentials.getBackupSession(uid, clientSessionId);
  let reservation = existingBackup && ["reserved", "used"].includes(existingBackup.state)
    ? existingBackup
    : null;
  const useBackup = async (reason) => {
    if (!options.backupApiKey) fail("backup-unavailable", "The Studexa backup is unavailable. Add or update your Gemini API key and try again.");
    if (!reservation) reservation = await credentials.reserveBackup(uid, clientSessionId, reason);
    if (!reservation?.allowed) {
      fail(reason === "grace" ? "personal-key-required" : "backup-limit-reached",
        reason === "grace"
          ? "Your three temporary generations have been used. Add your personal Gemini API key to continue."
          : "Today’s two Studexa backup sessions have been used. Try your personal key again tomorrow or update it now.");
    }
    try {
      const questions = await run(options.backupApiKey);
      return {
        questions,
        usage: usageFromStatus("backup", reservation.reason || reason, reservation),
        finish: async (success) => credentials.finishBackup(uid, clientSessionId, success),
      };
    } catch (error) {
      if (reservation.state === "reserved") await credentials.finishBackup(uid, clientSessionId, false);
      if (error instanceof QuizGenerationError && error.code === "credential-rejected") {
        fail("backup-unavailable", "The Studexa backup is unavailable. Add or update your Gemini API key and try again.");
      }
      throw error;
    }
  };

  if (reservation) return useBackup(reservation.reason);
  const personal = await credentials.getCredential(uid);
  if (!personal?.apiKey) return useBackup("grace");
  if (personal.status !== "valid") {
    fail("personal-key-invalid", "Your saved Gemini API key needs to be replaced before generating another quiz.");
  }
  try {
    return {
      questions: await run(personal.apiKey),
      usage: usageFromStatus("personal", null, await credentials.status(uid)),
      finish: async () => {},
    };
  } catch (error) {
    if (backupEligible(error)) {
      const reason = error.code === "resource-exhausted" ? "personal_quota" : "provider_unavailable";
      return useBackup(reason);
    }
    if (error instanceof QuizGenerationError && error.code === "credential-rejected") {
      await credentials.markInvalid(uid);
      fail("personal-key-invalid", "Google rejected your saved Gemini API key. Replace it in Gemini API Settings.");
    }
    throw error;
  }
}

async function reconcileSavedBackup(quiz, uid, clientSessionId, options) {
  if (!quiz?.backupUsed || !options.credentialStore) return quiz;
  const session = await options.credentialStore.getBackupSession(uid, clientSessionId);
  if (!session) return quiz;
  const status = session.state === "reserved"
    ? await options.credentialStore.finishBackup(uid, clientSessionId, true)
    : await options.credentialStore.status(uid);
  return {
    ...quiz,
    backupGraceRemaining: status.graceRemaining,
    backupFallbackRemainingToday: status.fallbackRemainingToday,
  };
}

async function processGeneration(body, uid, store, options) {
  const { classId, materialId, quizType, sourceQuizId, clientSessionId, batchRequestId } = body;
  const mode = body.mode || "initial";
  if (![classId, materialId].every(validId) || !["actual", "practice"].includes(quizType) ||
      (sourceQuizId != null && !validId(sourceQuizId)) || !validRequestId(clientSessionId) ||
      !validRequestId(batchRequestId) || !["initial", "automatic", "extra", "extra_continue"].includes(mode) ||
      (mode === "initial" && body.continueQuizId != null) ||
      (mode !== "initial" && !validId(body.continueQuizId))) {
    fail("invalid-argument", "Choose a class, material, and valid quiz type.");
  }

  const [profile, classDoc, materialDoc] = await Promise.all([
    store.get("users", uid), store.get("classes", classId), store.get("materials", materialId),
  ]);
  if (!classDoc || !materialDoc) fail("not-found", "The selected class or material no longer exists.");
  const material = materialDoc.data;
  if (profile?.data.role !== "teacher" || classDoc.data.teacherId !== uid ||
      material.teacherId !== uid || material.classId !== classId) {
    fail("permission-denied", "Only the teacher who owns this class and material may generate its quizzes.");
  }
  if (material.status !== "ready") fail("failed-precondition", "Wait for document text extraction to finish.");
  const extractedText = (material.extractedText || "").trim();
  const quizId = mode === "initial" ? `gen_${clientSessionId}` : body.continueQuizId;
  let existingDoc = mode === "initial"
    ? await store.findQuizBySession(classId, clientSessionId)
    : await store.get("quizzes", quizId);
  let quiz = existingDoc?.data;
  let questionCount = body.questionCount;
  let questionTypes = body.questionTypes;
  let actualSourceId = sourceQuizId || null;
  if (mode === "initial") {
    if (existingDoc) {
      if (existingDoc.id !== quizId || quiz.generationSessionId !== clientSessionId || quiz.teacherId !== uid ||
          quiz.classId !== classId || quiz.materialId !== materialId || quiz.type !== quizType) {
        fail("failed-precondition", "This generation request conflicts with another quiz.");
      }
      return publicQuiz(quizId, await reconcileSavedBackup(quiz, uid, clientSessionId, options));
    }
  } else {
    ensureExistingQuiz(quiz, body, uid);
    if (quiz.completedBatchIds?.includes(batchRequestId)) {
      return publicQuiz(quizId, await reconcileSavedBackup(quiz, uid, clientSessionId, options));
    }
    questionCount = quiz.requestedQuestionCount;
    questionTypes = quiz.selectedQuestionTypes;
    actualSourceId = quiz.sourceQuizId || null;
    if (quiz.questions.length >= questionCount) {
      return publicQuiz(quizId, await reconcileSavedBackup(quiz, uid, clientSessionId, options));
    }
    if (mode === "automatic" &&
        (quiz.generationSessionId !== clientSessionId || quiz.extraGenerationAttempted ||
         (quiz.automaticBatchesAttempted || 0) >= Math.ceil(questionCount / BATCH_SIZE) + 3)) {
      fail("failed-precondition", "Automatic generation for this draft has ended.");
    }
    if (mode === "extra" && quiz.extraGenerationAttempted) {
      fail("failed-precondition", "The one Generate more attempt has already been used.");
    }
    if (mode === "extra_continue" &&
        (!quiz.extraGenerationAttempted || quiz.extraGenerationSessionId !== clientSessionId ||
         (quiz.extraBatchesAttempted || 0) >= Math.ceil(questionCount / BATCH_SIZE) + 3)) {
      fail("failed-precondition", "The Generate more attempt cannot continue.");
    }
  }
  validateRequest({ extractedText, questionTypes, questionCount });
  const previous = quiz?.questions || [];
  const remaining = questionCount - previous.length;
  if (remaining <= 0) {
    return publicQuiz(quizId, await reconcileSavedBackup(quiz, uid, clientSessionId, options));
  }
  const batchCount = Math.min(BATCH_SIZE, remaining);
  const batchTypes = chooseBatchTypes(questionTypes, previous, remaining);
  if (batchTypes.some((type) => !TYPES.includes(type))) {
    fail("invalid-argument", "Choose valid question types.");
  }

  let sourceQuizContext;
  if (actualSourceId) {
    const sourceDoc = await store.get("quizzes", actualSourceId);
    const source = sourceDoc?.data;
    if (quizType === "actual" || !source || source.type !== "actual" ||
        source.classId !== classId || source.teacherId !== uid || source.materialId !== materialId ||
        !Array.isArray(source.questions)) {
      fail("invalid-argument", "Choose the Actual quiz generated from this material as the practice reference.");
    }
    sourceQuizContext = JSON.stringify(source.questions.map(({ question, correctAnswer }) => ({ question, correctAnswer })));
  }
  const generation = await generateForSession({
    extractedText, questionTypes: batchTypes, questionCount: batchCount,
    isActual: quizType === "actual", sourceQuizContext, allowPartial: true,
    existingQuestions: previous,
  }, uid, clientSessionId, options);
  const generated = generation.questions;
  const usageFields = {
    generationCredentialSource: generation.usage.source,
    backupUsed: generation.usage.source === "backup",
    backupUsageReason: generation.usage.backupReason,
    backupGraceRemaining: generation.usage.graceRemaining,
    backupFallbackRemainingToday: generation.usage.fallbackRemainingToday,
  };
  if (mode === "initial") {
    if (!generated.length) {
      await generation.finish(false);
      fail("data-loss", "The AI returned no usable questions. Try another document.");
    }
    const now = new Date().toISOString();
    const fileTitle = (material.fileName || "Study Material").replace(/\.[^/.]+$/, "");
    const data = {
      classId, teacherId: uid, materialId, type: quizType,
      title: `${fileTitle} - ${quizType === "actual" ? "Exam" : "Practice Quiz"}`,
      status: "draft", generationMethod: "gemini", sourceQuizId: actualSourceId,
      questions: generated.map((q, index) => ({ ...q, id: `q_${index + 1}` })),
      requestedQuestionCount: questionCount, selectedQuestionTypes: questionTypes,
      extraGenerationAttempted: false, totalPoints: generated.reduce((sum, q) => sum + (q.points || 1), 0),
      generationSessionId: clientSessionId, completedBatchIds: [batchRequestId],
      automaticBatchesAttempted: 1, extraBatchesAttempted: 0,
      ...usageFields,
      createdAt: now, updatedAt: now,
    };
    try {
      const saved = await store.create("quizzes", quizId, data);
      const status = await generation.finish(true);
      if (status) {
        saved.data.backupGraceRemaining = status.graceRemaining;
        saved.data.backupFallbackRemainingToday = status.fallbackRemainingToday;
      }
      return publicQuiz(quizId, saved.data);
    } catch (error) {
      if (!(error instanceof FirestoreError) || error.status !== 409) {
        await generation.finish(false);
        throw error;
      }
      const duplicate = await store.findQuizBySession(classId, clientSessionId);
      if (duplicate?.id === quizId && duplicate.data.generationSessionId === clientSessionId && duplicate.data.teacherId === uid) {
        await generation.finish(true);
        return publicQuiz(quizId, duplicate.data);
      }
      await generation.finish(false);
      throw error;
    }
  }

  for (let attempt = 0; attempt < 4; attempt++) {
    existingDoc = await store.get("quizzes", quizId);
    quiz = existingDoc?.data;
    ensureExistingQuiz(quiz, body, uid);
    if (quiz.completedBatchIds?.includes(batchRequestId)) {
      return publicQuiz(quizId, await reconcileSavedBackup(quiz, uid, clientSessionId, options));
    }
    if (mode === "automatic" && (quiz.extraGenerationAttempted || quiz.generationSessionId !== clientSessionId)) {
      fail("failed-precondition", "Automatic generation for this draft has ended.");
    }
    if (mode === "extra" && quiz.extraGenerationAttempted) fail("failed-precondition", "The one Generate more attempt has already been used.");
    if (mode === "extra_continue" && quiz.extraGenerationSessionId !== clientSessionId) {
      fail("failed-precondition", "The Generate more attempt cannot continue.");
    }
    const merged = [...quiz.questions];
    for (const candidate of generated) {
      if (merged.length >= questionCount) break;
      if (!merged.some((item) => isRepeatedFact(candidate, item))) merged.push(candidate);
    }
    const renumbered = merged.map((q, index) => ({ ...q, id: `q_${index + 1}` }));
    const changes = {
      questions: renumbered,
      totalPoints: renumbered.reduce((sum, q) => sum + (q.points || 1), 0),
      updatedAt: new Date().toISOString(),
      completedBatchIds: [...(quiz.completedBatchIds || []), batchRequestId],
      ...(mode === "automatic" ? { automaticBatchesAttempted: (quiz.automaticBatchesAttempted || 0) + 1 } : {}),
      ...(mode === "extra" || mode === "extra_continue" ? {
        extraGenerationAttempted: true,
        extraGenerationSessionId: clientSessionId,
        extraBatchesAttempted: (quiz.extraBatchesAttempted || 0) + 1,
      } : {}),
      ...usageFields,
    };
    try {
      await store.update("quizzes", quizId, changes, existingDoc.updateTime);
      const saved = await store.get("quizzes", quizId);
      const status = await generation.finish(true);
      if (status) {
        saved.data.backupGraceRemaining = status.graceRemaining;
        saved.data.backupFallbackRemainingToday = status.fallbackRemainingToday;
      }
      return publicQuiz(quizId, saved.data);
    } catch (error) {
      if (!(error instanceof FirestoreError) || error.status !== 412) {
        await generation.finish(false);
        throw error;
      }
    }
  }
  await generation.finish(false);
  fail("failed-precondition", "This draft changed while generating. Reopen it before trying again.");
}

export async function handleQuizRequest(request, deps = {}) {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (request.method !== "POST") return json(405, { error: "Use POST." });
  const auth = request.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ") || auth.length <= 7) return json(401, { error: "Sign in again to generate a quiz." });
  const token = auth.slice(7);
  const fetchImpl = deps.fetchImpl || fetch;
  try {
    const uid = await verifyFirebaseToken(token, fetchImpl, deps.firebaseApiKey || FIREBASE_WEB_API_KEY);
    const body = await request.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) fail("invalid-argument", "Request must contain a JSON object.");
    const store = deps.store || firestoreClient(token, fetchImpl);
    const result = await processGeneration(body, uid, store, {
      fetchImpl, generate: deps.generate || generateQuizQuestions,
      backupApiKey: deps.geminiApiKey ?? globalThis.Deno?.env.get("GEMINI_API_KEY"),
      credentialStore: deps.credentialStore || (deps.store ? null : teacherCredentialStore(fetchImpl)),
      candidateModels: deps.candidateModels || [
        globalThis.Deno?.env.get("GEMINI_MODEL") || "gemini-3.5-flash-lite",
        "gemini-3.1-flash-lite",
        "gemini-flash-lite-latest",
      ],
    });
    return json(200, result);
  } catch (error) {
    if (error instanceof SyntaxError) return json(400, { error: "Request must contain valid JSON." });
    if (error instanceof FirebaseIdentityError) return json(error.status, { error: error.message, code: "unauthenticated" });
    if (error instanceof QuizGenerationError) {
      const statuses = { "unauthenticated": 401, "invalid-argument": 400, "permission-denied": 403,
        "not-found": 404, "failed-precondition": 412, "data-loss": 422,
        "resource-exhausted": 429, "deadline-exceeded": 504, unavailable: 503,
        "personal-key-required": 412, "personal-key-invalid": 412,
        "backup-limit-reached": 429, "backup-unavailable": 503,
        "credential-rejected": 412 };
      return json(statuses[error.code] || 500, { error: error.message, code: error.code });
    }
    if (error instanceof CredentialStoreError) {
      return json(503, { error: "Teacher Gemini credentials are temporarily unavailable. Try again.", code: "credential-service-unavailable" });
    }
    if (error instanceof FirestoreError) {
      const status = [401, 403, 404, 409, 412].includes(error.status) ? error.status : 503;
      return json(status, { error: "Could not access the quiz data. Check your session and try again." });
    }
    console.error("Quiz Edge Function failed", { name: error?.name || "Error" });
    return json(503, { error: "The quiz service is temporarily unavailable. Please try again." });
  }
}
