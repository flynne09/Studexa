const { onObjectFinalized } = require("firebase-functions/v2/storage");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { defineSecret } = require("firebase-functions/params");
const { generateQuizQuestions, QuizGenerationError, validateRequest, isRepeatedFact } = require("./quiz_generator");
const geminiApiKey = defineSecret("GEMINI_API_KEY");
const path = require("path");
const fs = require("fs");
const os = require("os");

const pdfParse = require("pdf-parse");
const mammoth = require("mammoth");
const officeParser = require("officeparser");
const { google } = require("googleapis");

admin.initializeApp();

/**
 * Helper to parse PPTX files using officeparser safely.
 */
async function parsePptx(filePathOrBuffer) {
  if (typeof officeParser.parseOfficeAsync === "function") {
    return await officeParser.parseOfficeAsync(filePathOrBuffer);
  }
  return new Promise((resolve, reject) => {
    try {
      const res = officeParser.parseOffice(filePathOrBuffer, (data, err) => {
        if (err) return reject(err);
        resolve(data);
      });
      if (res && typeof res.then === "function") {
        res.then(resolve).catch(reject);
      }
    } catch (e) {
      reject(e);
    }
  });
}

/**
 * Converts a PPTX or DOCX file to PDF using Google Drive API v3 and stores it in Firebase Storage.
 */
async function convertOfficeToPdf(bucket, teacherId, materialId, localFilePath, fileType) {
  const auth = new google.auth.GoogleAuth({
    scopes: [
      "https://www.googleapis.com/auth/drive",
      "https://www.googleapis.com/auth/drive.file",
    ],
  });
  const drive = google.drive({ version: "v3", auth });

  const targetMimeType =
    fileType === "pptx"
      ? "application/vnd.google-apps.presentation"
      : "application/vnd.google-apps.document";

  const sourceMimeType =
    fileType === "pptx"
      ? "application/vnd.openxmlformats-officedocument.presentationml.presentation"
      : "application/vnd.openxmlformats-officedocument.wordprocessingml.document";

  let driveFileId = null;
  const tempPdfPath = path.join(os.tmpdir(), `${materialId}_preview.pdf`);

  try {
    console.log(`Uploading ${fileType} to Google Drive for preview conversion: ${localFilePath}`);
    const fileMetadata = {
      name: `studexa_preview_${materialId}`,
      mimeType: targetMimeType,
    };
    const media = {
      mimeType: sourceMimeType,
      body: fs.createReadStream(localFilePath),
    };

    const driveFile = await drive.files.create({
      requestBody: fileMetadata,
      media: media,
      fields: "id",
    });

    driveFileId = driveFile.data.id;
    console.log(`Uploaded to Drive with ID: ${driveFileId}. Exporting as application/pdf...`);

    const dest = fs.createWriteStream(tempPdfPath);
    const exportRes = await drive.files.export(
      {
        fileId: driveFileId,
        mimeType: "application/pdf",
      },
      { responseType: "stream" }
    );

    await new Promise((resolve, reject) => {
      exportRes.data
        .on("error", reject)
        .pipe(dest)
        .on("finish", resolve)
        .on("error", reject);
    });

    console.log(`Drive export complete. Uploading preview.pdf to Firebase Storage...`);
    const destinationStoragePath = `uploads/${teacherId}/${materialId}/preview.pdf`;

    await bucket.upload(tempPdfPath, {
      destination: destinationStoragePath,
      metadata: {
        contentType: "application/pdf",
        customMetadata: {
          teacherId: teacherId,
          materialId: materialId,
          isConvertedPreview: "true",
        },
      },
    });

    console.log(`Successfully stored preview PDF at ${destinationStoragePath}`);

    // Try to obtain a download URL or signed URL if supported
    let downloadUrl = null;
    try {
      const fileRef = bucket.file(destinationStoragePath);
      const [signedUrl] = await fileRef.getSignedUrl({
        action: "read",
        expires: "03-01-2030",
      });
      downloadUrl = signedUrl;
    } catch (urlErr) {
      console.warn("Could not generate signed URL for preview PDF:", urlErr.message);
    }

    return {
      convertedPdfRef: destinationStoragePath,
      convertedPdfUrl: downloadUrl,
    };
  } finally {
    if (driveFileId) {
      try {
        console.log(`Deleting temporary Drive file ${driveFileId}`);
        await drive.files.delete({ fileId: driveFileId });
      } catch (delErr) {
        console.warn(`Failed to delete temporary Drive file ${driveFileId}:`, delErr.message);
      }
    }
    if (fs.existsSync(tempPdfPath)) {
      try {
        fs.unlinkSync(tempPdfPath);
      } catch (cleanupErr) {
        console.warn(`Failed to remove temp PDF ${tempPdfPath}:`, cleanupErr.message);
      }
    }
  }
}

/**
 * Structural table / column header keywords commonly found in data grids.
 */
const STRUCTURAL_HEADER_KEYWORDS = new Set([
  "no", "no.", "num", "num.", "number", "name", "attribute", "attributes",
  "value", "values", "field", "fields", "col", "column", "header", "row",
  "description", "remarks", "category", "categories", "status", "type",
  "types", "item", "items", "parameter", "parameters", "date", "key",
  "default", "null", "extra"
]);

/**
 * Strips table header artifacts and data grid structural labels from extracted text,
 * preserving factual content inside table cells while preventing structural headers
 * from leaking into generated questions.
 */
function stripTableHeaderArtifacts(text) {
  if (!text) return "";
  const lines = text.split("\n");
  const cleaned = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) {
      cleaned.push(line);
      continue;
    }

    // Standalone column or header indicators
    if (/^(?:Column|Header|Col|Row)\s+[A-Za-z0-9]+:?$/i.test(trimmed)) continue;
    if (/^Table\s+\d+:?$/i.test(trimmed)) continue;

    // Sequence of column labels: "Column A | Column B | Column C"
    if (/^(?:(?:Column|Header|Col)\s+[A-Za-z0-9]+(?:\s*[\|\:\t\,]\s*|\s{2,}))+(?:(?:Column|Header|Col)\s+[A-Za-z0-9]+)?$/i.test(trimmed)) continue;

    // Multi-column structural header row separated by delimiters (|, \t, spaces, commas)
    if (trimmed.includes("|") || trimmed.includes("\t") || /\s{2,}/.test(trimmed) || (trimmed.includes(",") && !trimmed.includes("."))) {
      const segments = trimmed
        .split(/[\|\t]|\s{2,}|,/)
        .map((s) => s.trim().toLowerCase())
        .filter((s) => s.length > 0);

      if (segments.length >= 2) {
        let matching = 0;
        for (const seg of segments) {
          const cleanedSeg = seg.replace(/[^a-z0-9\.]/g, "");
          const isColHeader = /^(?:column|header|col|row)[a-z0-9]*$/i.test(cleanedSeg) ||
            /^(?:column|header|col|row)\s+[a-z0-9]+$/i.test(seg);
          if (STRUCTURAL_HEADER_KEYWORDS.has(cleanedSeg) || isColHeader) {
            matching++;
          }
        }
        if (matching >= 2 && matching >= segments.length * 0.6) {
          continue;
        }
      }
    }

    cleaned.push(line);
  }

  return cleaned.join("\n");
}

/**
 * Checks if a generated question inappropriately tests table/column structure.
 */
function isTableHeaderQuestion(q) {
  if (!q) return false;
  const prompt = (q.question || "").toLowerCase().trim();
  const answer = (q.correctAnswer || "").toLowerCase().trim().replace(/^[a-d]\.\s*/, "");

  if (/\b(in\s+(?:the\s+)?(?:table|column|row)|which\s+column|what\s+is\s+(?:the\s+)?(?:header|column|attribute)|listed\s+in\s+column|under\s+column|title\s+of\s+column)\b/i.test(prompt)) {
    return true;
  }
  if (/\b(?:column|header|col|row)\s+[a-z0-9]+\b/i.test(prompt)) {
    if (prompt.includes("what") || prompt.includes("which") || prompt.includes("identify")) {
      return true;
    }
  }
  if (/^(?:column\s+[a-z0-9]+|header\s+[a-z0-9]+|row\s+[a-z0-9]+|col\s+[a-z0-9]+|attribute|attributes|value|values|field|fields|no\.?|num\.?|number|description|remarks|category|type)$/i.test(answer)) {
    return true;
  }

  return false;
}

/**
 * Checks if a generated question tests irrelevant, filler, or non-academic boilerplate content.
 */
function isFillerOrBoilerplateQuestion(q) {
  if (!q) return false;
  const prompt = (q.question || "").toLowerCase().trim();
  const answer = (q.correctAnswer || "").toLowerCase().trim().replace(/^[a-d]\.\s*/, "");

  const fillerPromptPattern = /(?:\b(?:copyright|all\s+rights\s+reserved|creative\s+commons|licensed\s+under|authors?|written\s+by|who\s+is\s+the\s+author|who\s+is\s+the\s+instructor|who\s+is\s+the\s+professor|instructors?|emails?|office\s+hours|syllabus|grading\s+policy|course\s+code|prerequisite|homework\s+assignment|due\s+date|welcome\s+to|in\s+this\s+lecture|today\x27s\s+lecture|previous\s+slide|next\s+slide|thank\s+you\s+for\s+(?:listening|attending)|summary\s+of\s+today|slide\s+\d+|page\s+\d+|figure\s+\d+|table\s+\d+|chapter\s+\d+|\d+(?:st|nd|rd|th)?\s+edition|edition|references|acknowledgments?)\b|any\s+questions\?)/i;
  if (fillerPromptPattern.test(prompt)) return true;

  if (/\b(?:on slide|in chapter|on page|published in|publication date|file name)\b/i.test(prompt)) {
    return true;
  }

  const fillerAnswerPattern = /^(?:all rights reserved|copyright|creative commons|welcome|thank you|any questions|dr\.\s+\w+|prof\.\s+\w+|professor|instructor|syllabus|office hours|slide\s+\d+|page\s+\d+|chapter\s+\d+|https?:\/\/\S+|www\.\S+|\S+@\S+)$/i;
  if (fillerAnswerPattern.test(answer)) return true;

  if (answer.includes("@") || answer.includes("http://") || answer.includes("https://") || answer.includes("www.")) {
    return true;
  }

  return false;
}


/**
 * Storage-triggered Cloud Function (2nd gen) that triggers on upload to
 * uploads/{teacherId}/{materialId}/{filename}.
 * Extracts text from PDF, DOCX, and PPTX files and updates Firestore materials/{materialId}.
 */
exports.extractText = onObjectFinalized(
  {
    region: "us-east1",
    cpu: 1,
    memory: "1GiB",
    timeoutSeconds: 300,
  },
  async (event) => {
    const fileObject = event.data;
    const filePath = fileObject.name; // e.g. uploads/teacher123/mat456/notes.pdf

    if (!filePath) {
      console.log("No file path found in event.");
      return;
    }

    // Path pattern: uploads/{teacherId}/{materialId}/{filename}
    const pathSegments = filePath.split("/");
    if (pathSegments.length < 4 || pathSegments[0] !== "uploads") {
      console.log(`Ignoring file outside 'uploads/{teacherId}/{materialId}/': ${filePath}`);
      return;
    }

    const teacherId = pathSegments[1];
    const materialId = pathSegments[2];
    const fileName = pathSegments.slice(3).join("/");
    const extension = path.extname(fileName).toLowerCase().replace(".", "");

    // Ignore generated preview files to prevent recursive trigger execution
    if (fileName === "preview.pdf" || fileName.endsWith("/preview.pdf") || fileName.includes("_preview.pdf")) {
      console.log(`Ignoring preview PDF file: ${filePath}`);
      return;
    }

    console.log(`Processing file: ${fileName} (materialId: ${materialId}, teacherId: ${teacherId})`);

    const firestore = getFirestore(process.env.FIRESTORE_DATABASE_ID || "default");
    const materialRef = firestore.collection("materials").doc(materialId);

    // Map extension to supported fileType: "pdf" | "pptx" | "docx"
    let fileType = null;
    if (extension === "pdf") {
      fileType = "pdf";
    } else if (extension === "docx") {
      fileType = "docx";
    } else if (extension === "pptx") {
      fileType = "pptx";
    }

    // Check for unsupported format
    if (!fileType) {
      console.warn(`Unsupported file format '${extension}' for ${filePath}`);
      await materialRef.set(
        {
          status: "failed",
          errorReason: "unsupported_format",
          fileRef: filePath,
          fileType: extension || "unknown",
          conversionStatus: "failed",
        },
        { merge: true }
      );
      return;
    }

    // Short-circuit if client-side on-device extraction already completed successfully
    try {
      const existingDoc = await materialRef.get();
      if (existingDoc.exists) {
        const docData = existingDoc.data();
        if (docData && docData.status === "ready" && docData.extractedText && docData.extractedText.length >= 20) {
          console.log(`Client-side extraction already completed for materialId: ${materialId} (${docData.extractedText.length} chars). Skipping redundant download & extraction.`);
          if (fileType === "pdf") {
            if (docData.conversionStatus !== "completed") {
              await materialRef.set({ conversionStatus: "completed" }, { merge: true });
            }
            return;
          }
          if ((fileType === "pptx" || fileType === "docx") && docData.conversionStatus === "completed") {
            return;
          }
        }
      }
    } catch (checkErr) {
      console.warn("Could not check existing material doc:", checkErr.message);
    }

    const bucket = admin.storage().bucket(fileObject.bucket);
    const tempFilePath = path.join(os.tmpdir(), `${materialId}_${path.basename(fileName)}`);

    try {
      // Download the file from Firebase Storage to Cloud Function /tmp
      await bucket.file(filePath).download({ destination: tempFilePath });
      const fileBuffer = fs.readFileSync(tempFilePath);

      let rawExtractedText = "";

      // Route to matching extraction library
      if (fileType === "pdf") {
        const parsed = await pdfParse(fileBuffer);
        rawExtractedText = parsed.text || "";
      } else if (fileType === "docx") {
        const parsed = await mammoth.extractRawText({ buffer: fileBuffer });
        rawExtractedText = parsed.value || "";
      } else if (fileType === "pptx") {
        rawExtractedText = await parsePptx(tempFilePath);
      }

      const sanitizedText = stripTableHeaderArtifacts(rawExtractedText || "");
      const trimmedText = sanitizedText.trim();

      // Validate non-trivial content (not empty or near-empty)
      if (trimmedText.length < 20) {
        console.warn(`No extractable text found in file ${filePath} (length: ${trimmedText.length})`);
        await materialRef.set(
          {
            status: "failed",
            errorReason: "no_extractable_text",
            fileRef: filePath,
            fileType: fileType,
            conversionStatus: "failed",
          },
          { merge: true }
        );
        return;
      }

      // Success: write status "ready", extractedText, and extractedAt
      await materialRef.set(
        {
          status: "ready",
          extractedText: trimmedText,
          extractedAt: FieldValue.serverTimestamp(),
          fileRef: filePath,
          fileType: fileType,
        },
        { merge: true }
      );

      console.log(`Successfully extracted ${trimmedText.length} characters for materialId: ${materialId}`);

      // Perform office-to-PDF conversion for PPTX / DOCX preview rendering
      if (fileType === "pdf") {
        await materialRef.set(
          {
            conversionStatus: "completed",
          },
          { merge: true }
        );
      } else if (fileType === "pptx" || fileType === "docx") {
        try {
          console.log(`Starting preview conversion for ${fileType} material: ${materialId}`);
          const conversionResult = await convertOfficeToPdf(
            bucket,
            teacherId,
            materialId,
            tempFilePath,
            fileType
          );
          await materialRef.set(
            {
              conversionStatus: "completed",
              convertedPdfRef: conversionResult.convertedPdfRef,
              convertedPdfUrl: conversionResult.convertedPdfUrl || null,
              convertedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
          console.log(`Successfully completed preview conversion for materialId: ${materialId}`);
        } catch (convError) {
          console.warn(`Office preview conversion failed for ${materialId}:`, convError.message);
          await materialRef.set(
            {
              conversionStatus: "failed",
            },
            { merge: true }
          );
        }
      }
    } catch (parseError) {
      console.error(`Parse error encountered while processing ${filePath}:`, parseError);
      await materialRef.set(
        {
          status: "failed",
          errorReason: "parse_error",
          fileRef: filePath,
          fileType: fileType,
          conversionStatus: "failed",
        },
        { merge: true }
      );
    } finally {
      // Clean up temporary file
      if (fs.existsSync(tempFilePath)) {
        try {
          fs.unlinkSync(tempFilePath);
        } catch (cleanupErr) {
          console.warn(`Failed to remove temp file ${tempFilePath}:`, cleanupErr);
        }
      }
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// Quiz Generation Engine (Gemini AI + Deterministic Non-AI Fallback)
// ─────────────────────────────────────────────────────────────────────────────

const VALID_QUESTION_TYPES = [
  "multiple_choice",
  "true_false",
  "fill_blank",
  "identification",
  "enumeration",
];

/**
 * Normalizes question type aliases from client representation.
 */
function normalizeQuestionType(typeStr) {
  if (!typeStr) return "multiple_choice";
  const lower = typeStr.toLowerCase().trim().replace(/[\s\-\/]/g, "_");
  if (lower.includes("multiple") || lower.includes("mcq")) return "multiple_choice";
  if (lower.includes("true") || lower.includes("false") || lower.includes("tf")) return "true_false";
  if (lower.includes("fill") || lower.includes("blank")) return "fill_blank";
  if (lower.includes("ident")) return "identification";
  if (lower.includes("enum")) return "enumeration";
  return "multiple_choice";
}

/**
 * Deterministic Non-AI Fallback Generator.
 * Extracts concepts, definitions, and facts from the material text and generates
 * questions across all requested types without relying on external AI.
 */
function generateFallbackQuizQuestions(extractedText, questionTypes, questionCount, isActual) {
  const normalizedTypes = (questionTypes && questionTypes.length > 0)
    ? questionTypes.map(normalizeQuestionType)
    : ["multiple_choice", "true_false", "fill_blank", "identification", "enumeration"];

  // Split text into candidate sentences
  const rawSentences = extractedText
    .split(/(?<=[.!?])\s+/)
    .map((s) => s.trim().replace(/\s+/g, " "))
    .filter((s) => s.length >= 25 && s.length <= 250);

  // Filter out table headers, structural labels, metadata, and filler boilerplate from candidate sentences
  const structuralSentenceRegex = /^(?:column|header|col|row)\s+[a-z0-9]+:?/i;
  const metadataSentenceRegex = /(?:\b(?:column\s+[a-z0-9]+|header\s+[a-z0-9]+|table\s+\d+|course|syllabus|page\s+\d+|figure\s+\d+|chapter\s+\d+|slide\s+\d+|\d+(?:st|nd|rd|th)?\s+edition|edition|copyright|all\s+rights\s+reserved|creative\s+commons|license|licensed\s+under|authors?|emails?|isbn|office\s+hours|grading\s+policy|welcome\s+to|in\s+this\s+lecture|thank\s+you\s+for\s+(?:listening|attending)|summary\s+of\s+today|references|further\s+reading|acknowledgments?)\b|any\s+questions\?|attribute\s*\||no\.\s+name\b|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/i;

  const filteredSentences = rawSentences.filter(
    (s) => !structuralSentenceRegex.test(s) && !metadataSentenceRegex.test(s)
  );

  const sentences = filteredSentences.length >= 5
    ? filteredSentences
    : [
        "Cellular respiration produces ATP by oxidizing glucose molecules in eukaryotic cells.",
        "Mitochondria are double-membraned organelles known as the powerhouse of the cell.",
        "Glycolysis occurs in the cytoplasm and breaks down glucose into two molecules of pyruvate.",
        "The citric acid cycle, also known as the Krebs cycle, takes place inside the mitochondrial matrix.",
        "Adenosine triphosphate (ATP) serves as the primary energy currency for cellular reactions.",
        "Photosynthesis converts light energy into chemical energy stored in carbohydrates.",
        "Enzymes are biological catalysts that lower activation energy without being consumed.",
        "DNA stores genetic information within the cell nucleus using four nucleotide bases.",
      ];

  // Structural blacklist to prevent column/table labels, metadata, and filler words from becoming candidate terms
  const structuralBlacklist = new Set([
    "column", "header", "attribute", "attributes", "value", "values",
    "field", "fields", "table", "tables", "row", "rows", "item", "items",
    "category", "categories", "no", "number", "type", "types", "description",
    "remarks", "date", "col",
    "copyright", "reserved", "author", "authors", "professor", "instructor", "syllabus",
    "lecture", "slide", "page", "chapter", "university", "college", "homework",
    "summary", "reference", "references", "license", "acknowledgment",
    "acknowledgments", "welcome", "reading", "hours", "grading", "policy",
    "edition", "editions", "email", "emails", "isbn"
  ]);

  // Extract key candidate terms (nouns, capitalized words, phrases after definitions)
  const candidateTerms = [];
  const definitionRegex = /([A-Z][a-zA-Z\s]{2,25})\s+(?:is defined as|is a|is an|refers to|represents|serves as|means)\s+([^.!?]+)/gi;
  let defMatch;
  while ((defMatch = definitionRegex.exec(extractedText)) !== null) {
    const term = defMatch[1].trim();
    if (term.length > 2 && !candidateTerms.includes(term) && !structuralBlacklist.has(term.toLowerCase())) {
      candidateTerms.push(term);
    }
  }

  // Extract capitalized non-initial words or distinctive words
  for (const s of sentences) {
    const words = s.split(/\s+/);
    for (let i = 1; i < words.length; i++) {
      const clean = words[i].replace(/[^a-zA-Z]/g, "");
      if (clean.length >= 4 && /^[A-Z]/.test(words[i]) && !candidateTerms.includes(clean) && !structuralBlacklist.has(clean.toLowerCase())) {
        candidateTerms.push(clean);
      }
    }
  }

  // Pad terms if needed with plausible academic domain concepts
  const fallbackTerms = [
    "Mitochondria",
    "Ribosome",
    "Chloroplast",
    "Nucleus",
    "Enzyme",
    "Glucose",
    "ATP",
    "Cytoplasm",
    "Endoplasmic Reticulum",
    "Golgi Apparatus",
    "Glycolysis",
    "Phosphorylation"
  ];
  for (const ft of fallbackTerms) {
    if (!candidateTerms.includes(ft)) candidateTerms.push(ft);
  }

  const questions = [];
  const targetCount = Math.max(1, questionCount || 10);

  for (let i = 0; i < targetCount; i++) {
    const qIndex = i + 1;
    const qType = normalizedTypes[i % normalizedTypes.length];
    const sentence = sentences[i % sentences.length];
    const term = candidateTerms[i % candidateTerms.length];

    if (qType === "multiple_choice") {
      // Pick sentence and mask a key word
      const words = sentence.split(" ");
      let targetWord = term;
      let displaySentence = sentence;
      if (sentence.includes(term)) {
        displaySentence = sentence.replace(term, "_______");
      } else {
        const nounWord = words.find((w) => w.length >= 5 && /^[a-zA-Z]+$/.test(w)) || words[0];
        targetWord = nounWord.replace(/[^a-zA-Z]/g, "");
        displaySentence = sentence.replace(nounWord, "_______");
      }

      // Generate 3 distractors from candidate academic concepts
      const distractors = candidateTerms.filter((t) => t.toLowerCase() !== targetWord.toLowerCase()).slice(0, 3);

      const allOptions = [targetWord, ...distractors].sort(() => 0.5 - Math.random());
      const optionLetters = ["A", "B", "C", "D"];
      const formattedOptions = allOptions.map((opt, idx) => `${optionLetters[idx]}. ${opt}`);
      const correctOptionIndex = allOptions.indexOf(targetWord);
      const correctAnswer = formattedOptions[correctOptionIndex];

      questions.push({
        id: `q_${qIndex}`,
        type: "multiple_choice",
        question: isActual
          ? `Fill in the blank: ${displaySentence}`
          : `Practice question: In the context of the study material, complete the statement: "${displaySentence}"`,
        options: formattedOptions,
        correctAnswer: correctAnswer,
        enumerationAnswers: [],
        explanation: `The correct answer is ${targetWord} as stated in the material: "${sentence}".`,
        points: 1.0,
      });
    } else if (qType === "true_false") {
      const isTrue = i % 2 === 0;
      let statement = sentence;
      if (!isTrue) {
        // Deterministically negate sentence
        if (statement.includes(" is ")) {
          statement = statement.replace(" is ", " is not ");
        } else if (statement.includes(" are ")) {
          statement = statement.replace(" are ", " are not ");
        } else if (statement.includes(" can ")) {
          statement = statement.replace(" can ", " cannot ");
        } else {
          statement = `It is false that ${statement.charAt(0).toLowerCase() + statement.slice(1)}`;
        }
      }

      questions.push({
        id: `q_${qIndex}`,
        type: "true_false",
        question: isActual
          ? `Determine whether the following statement is True or False: "${statement}"`
          : `Concept Check: Is the following statement accurate based on your reading? "${statement}"`,
        options: ["True", "False"],
        correctAnswer: isTrue ? "True" : "False",
        enumerationAnswers: [],
        explanation: isTrue
          ? `This statement is directly verified in the source text: "${sentence}".`
          : `This statement is false. The original material states: "${sentence}".`,
        points: 1.0,
      });
    } else if (qType === "fill_blank") {
      const words = sentence.split(" ");
      const keyword = words.find((w) => w.length >= 5 && !/^(about|which|their|there|these|those)$/i.test(w)) || term;
      const cleanKeyword = keyword.replace(/[^a-zA-Z]/g, "");
      const blankedPrompt = sentence.replace(new RegExp(`\\b${cleanKeyword}\\b`, "i"), "_______");

      questions.push({
        id: `q_${qIndex}`,
        type: "fill_blank",
        question: isActual
          ? `Complete the statement: ${blankedPrompt}`
          : `Fill in the missing term from the lesson: ${blankedPrompt}`,
        options: [],
        correctAnswer: cleanKeyword,
        enumerationAnswers: [],
        explanation: `The missing term is "${cleanKeyword}". Full context: "${sentence}".`,
        points: 1.0,
      });
    } else if (qType === "identification") {
      questions.push({
        id: `q_${qIndex}`,
        type: "identification",
        question: isActual
          ? `Identify the term or concept described: "${sentence}"`
          : `What key term matches this definition or description: "${sentence}"?`,
        options: [],
        correctAnswer: term,
        enumerationAnswers: [],
        explanation: `The concept being described is "${term}".`,
        points: 1.0,
      });
    } else if (qType === "enumeration") {
      // Pick 3 candidate terms to enumerate
      const enumList = candidateTerms.slice(i, i + 3);
      if (enumList.length < 3) {
        enumList.push(...candidateTerms.slice(0, 3 - enumList.length));
      }

      questions.push({
        id: `q_${qIndex}`,
        type: "enumeration",
        question: isActual
          ? `Enumerate ${enumList.length} key components, elements, or concepts discussed regarding: "${sentence}"`
          : `Practice Enumeration: List any ${enumList.length} key terms or factors covered in this section:`,
        options: [],
        correctAnswer: enumList.join(", "),
        enumerationAnswers: enumList,
        explanation: `Expected items include: ${enumList.join(", ")}.`,
        points: enumList.length * 1.0,
      });
    }
  }

  return questions;
}

/**
 * Core processor authorizing quiz generation and persisting only validated AI output.
 */
async function processQuizGeneration({ teacherId, classId, materialId, quizType, questionTypes, questionCount, sourceQuizId, allowPartialDraft = false, continueQuizId }) {
  const validId = (value) => typeof value === "string" && value.trim().length > 0 && !value.includes("/") && value.length <= 1500;
  if (![teacherId, classId, materialId].every(validId) ||
      !["actual", "practice"].includes(quizType) || (sourceQuizId != null && !validId(sourceQuizId)) ||
      (continueQuizId != null && !validId(continueQuizId))) {
    throw new QuizGenerationError("invalid-argument", "Choose a class, material, and valid quiz type.");
  }
  const firestore = getFirestore(process.env.FIRESTORE_DATABASE_ID || "default");
  const [profileDoc, classDoc, materialDoc] = await Promise.all([
    firestore.collection("users").doc(teacherId).get(),
    firestore.collection("classes").doc(classId).get(),
    firestore.collection("materials").doc(materialId).get(),
  ]);
  if (!materialDoc.exists || !classDoc.exists) throw new QuizGenerationError("not-found", "The selected class or material no longer exists.");
  const materialData = materialDoc.data();
  if (profileDoc.data()?.role !== "teacher" || classDoc.data().teacherId !== teacherId ||
      materialData.teacherId !== teacherId || materialData.classId !== classId) {
    throw new QuizGenerationError("permission-denied", "Only the teacher who owns this class and material may generate its quizzes.");
  }
  const extractedText = (materialData.extractedText || "").trim();
  const quizRef = continueQuizId ? firestore.collection("quizzes").doc(continueQuizId) : firestore.collection("quizzes").doc();
  let previousQuestions = [];
  let previousQuiz;
  if (continueQuizId) {
    const existingDoc = await quizRef.get();
    previousQuiz = existingDoc.data();
    if (!allowPartialDraft || !previousQuiz || previousQuiz.teacherId !== teacherId ||
        previousQuiz.classId !== classId || previousQuiz.materialId !== materialId ||
        previousQuiz.type !== quizType || previousQuiz.status !== "draft" ||
        !Number.isInteger(previousQuiz.requestedQuestionCount) ||
        !Array.isArray(previousQuiz.selectedQuestionTypes) || previousQuiz.extraGenerationAttempted) {
      throw new QuizGenerationError("failed-precondition", "This draft cannot generate more questions. Review the saved questions or start a new quiz.");
    }
    questionCount = previousQuiz.requestedQuestionCount;
    questionTypes = previousQuiz.selectedQuestionTypes;
    sourceQuizId = previousQuiz.sourceQuizId || null;
    previousQuestions = Array.isArray(previousQuiz.questions) ? previousQuiz.questions : [];
    if (previousQuestions.length >= questionCount) {
      throw new QuizGenerationError("failed-precondition", "This draft already contains the requested number of questions.");
    }
  }
  validateRequest({ extractedText, questionTypes, questionCount });
  if (materialData.status !== "ready") throw new QuizGenerationError("failed-precondition", "Wait for document text extraction to finish.");
  const isActual = quizType === "actual";
  let sourceQuizContext;
  if (sourceQuizId) {
    const sourceDoc = await firestore.collection("quizzes").doc(sourceQuizId).get();
    const source = sourceDoc.data();
    if (isActual || !source || source.type !== "actual" || source.classId !== classId ||
        source.teacherId !== teacherId || source.materialId !== materialId) {
      throw new QuizGenerationError("invalid-argument", "Choose the Actual quiz generated from this material as the practice reference.");
    }
    sourceQuizContext = JSON.stringify(source.questions.map(({ question, correctAnswer }) => ({ question, correctAnswer })));
  }
  const missingCount = questionCount - previousQuestions.length;
  const generationTypes = continueQuizId && missingCount < questionTypes.length
    ? [...questionTypes].sort((a, b) => previousQuestions.filter((q) => q.type === a).length - previousQuestions.filter((q) => q.type === b).length).slice(0, missingCount)
    : questionTypes;
  if (continueQuizId) {
    await firestore.runTransaction(async (transaction) => {
      const current = await transaction.get(quizRef);
      if (!current.exists || current.data().extraGenerationAttempted || current.data().status !== "draft" ||
          current.data().questions.length !== previousQuestions.length) {
        throw new QuizGenerationError("failed-precondition", "This draft changed. Reopen it before generating more questions.");
      }
      transaction.update(quizRef, { extraGenerationAttempted: true });
    });
  }
  let newQuestions;
  try {
    newQuestions = await generateQuizQuestions({
      extractedText, questionTypes: generationTypes, questionCount: missingCount, isActual, sourceQuizContext,
      allowPartial: allowPartialDraft === true, existingQuestions: previousQuestions,
    }, {
      apiKey: geminiApiKey.value(),
      rejectQuestion: (q) => isTableHeaderQuestion(q) || isFillerOrBoilerplateQuestion(q),
    });
  } catch (error) {
    if (continueQuizId) await quizRef.update({ extraGenerationAttempted: false });
    throw error;
  }
  if (continueQuizId) {
    await firestore.runTransaction(async (transaction) => {
      const latestDoc = await transaction.get(quizRef);
      const latest = latestDoc.data();
      if (!latest || latest.status !== "draft" || !latest.extraGenerationAttempted) {
        throw new QuizGenerationError("failed-precondition", "This draft changed. Reopen it before generating more questions.");
      }
      const merged = [...(latest.questions || [])];
      for (const candidate of newQuestions) {
        if (merged.length >= questionCount) break;
        if (!merged.some((existing) => isRepeatedFact(candidate, existing))) merged.push(candidate);
      }
      const renumbered = merged.map((q, index) => ({ ...q, id: `q_${index + 1}` }));
      transaction.update(quizRef, {
        questions: renumbered,
        totalPoints: renumbered.reduce((total, q) => total + (q.points || 1.0), 0),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    const saved = (await quizRef.get()).data();
    return {
      success: true,
      quizId: quizRef.id,
      quiz: { id: quizRef.id, ...saved,
        createdAt: saved.createdAt?.toDate?.()?.toISOString?.() || new Date().toISOString(),
        updatedAt: new Date().toISOString() },
    };
  }
  const questions = newQuestions.map((q, index) => ({ ...q, id: `q_${index + 1}` }));
  const fileTitle = (materialData.fileName || "Study Material").replace(/\.[^/.]+$/, "");
  const generatedTitle = `${fileTitle} - ${isActual ? "Exam" : "Practice Quiz"}`;
  const generationMethod = "gemini";

  const totalPoints = questions.reduce((acc, q) => acc + (q.points || 1.0), 0);

  const quizPayload = {
    classId: classId,
    teacherId: teacherId,
    materialId: materialId,
    type: isActual ? "actual" : "practice",
    title: generatedTitle,
    status: "draft",
    generationMethod: generationMethod,
    sourceQuizId: sourceQuizId || null,
    questions: questions,
    requestedQuestionCount: questionCount,
    selectedQuestionTypes: questionTypes,
    extraGenerationAttempted: Boolean(continueQuizId),
    totalPoints: totalPoints,
    ...(!continueQuizId ? { createdAt: FieldValue.serverTimestamp() } : {}),
    updatedAt: FieldValue.serverTimestamp(),
  };

  await quizRef.set(quizPayload);

  return {
    success: true,
    quizId: quizRef.id,
    quiz: {
      id: quizRef.id,
      ...quizPayload,
      createdAt: previousQuiz?.createdAt?.toDate?.()?.toISOString?.() || new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
  };
}

function publicGenerationError(error) {
  if (!(error instanceof QuizGenerationError)) {
    console.warn("Quiz backend failure", { kind: error.name, code: error.code || "unknown" });
  }
  return error instanceof QuizGenerationError ? error : {
    code: "unavailable", message: "Could not save or retrieve the quiz. Please check your connection and try again.",
  };
}

/**
 * Callable Cloud Function (2nd Gen) for quiz generation.
 */
exports.generateQuiz = onCall(
  {
    cpu: 1,
    memory: "512MiB",
    timeoutSeconds: 180,
    secrets: [geminiApiKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be authenticated to generate quizzes.");
    }

    const { classId, materialId, quizType, questionTypes, questionCount, sourceQuizId, allowPartialDraft, continueQuizId } = request.data || {};
    const teacherId = request.auth.uid;

    try {
      return await processQuizGeneration({
        teacherId,
        classId,
        materialId,
        quizType,
        questionTypes,
        questionCount,
        sourceQuizId,
        allowPartialDraft,
        continueQuizId,
      });
    } catch (error) {
      const failure = publicGenerationError(error);
      console.warn("Quiz generation failed", { code: failure.code });
      throw new HttpsError(failure.code, failure.message);
    }
  }
);

/**
 * HTTP Cloud Function (2nd Gen) for standard REST/HTTP quiz generation calls.
 */
exports.generateQuizHttp = onRequest(
  {
    cpu: 1,
    memory: "512MiB",
    timeoutSeconds: 180,
    secrets: [geminiApiKey],
    cors: true,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).json({ error: "Method not allowed. Use POST." });
    }

    let teacherId = null;
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith("Bearer ")) {
      try {
        const idToken = authHeader.split("Bearer ")[1];
        const decoded = await admin.auth().verifyIdToken(idToken);
        teacherId = decoded.uid;
      } catch (tokenErr) {
        return res.status(401).json({ error: "Invalid authorization token." });
      }
    }

    if (!teacherId) {
      return res.status(401).json({ error: "Authentication required." });
    }

    if (!req.body || typeof req.body !== "object" || Array.isArray(req.body)) {
      return res.status(400).json({ error: "Request must contain a JSON object." });
    }
    try {
      const result = await processQuizGeneration({
        teacherId,
        classId: req.body.classId,
        materialId: req.body.materialId,
        quizType: req.body.quizType,
        questionTypes: req.body.questionTypes,
        questionCount: req.body.questionCount,
        sourceQuizId: req.body.sourceQuizId,
        allowPartialDraft: req.body.allowPartialDraft,
        continueQuizId: req.body.continueQuizId,
      });
      return res.status(200).json(result);
    } catch (error) {
      const failure = publicGenerationError(error);
      const statuses = { "invalid-argument": 400, "permission-denied": 403, "not-found": 404,
        "failed-precondition": 412, "data-loss": 422, "resource-exhausted": 429,
        "deadline-exceeded": 504, unavailable: 503 };
      console.warn("HTTP quiz generation failed", { code: failure.code });
      return res.status(statuses[failure.code] || 500).json({ error: failure.message, code: failure.code });
    }
  }
);

