# Studexa Phase 1 Master Implementation Plan

This document records the Phase 1 plan and historical milestones. The 2026-09-11 integration revision below supersedes earlier client-side Gemini/fallback descriptions. See [INTEGRATION_REPORT.md](INTEGRATION_REPORT.md) for current implementation, evidence, changed files, and deployment limitations. Later milestone narratives and their test counts remain historical records.

---

## 1. System Architecture Overview

```mermaid
flowchart TD
    subgraph Client["Flutter Client (Android, iOS, web, Windows scaffolds)"]
        TeacherUI["Teacher Screens (Classes, Materials, Quizzes, Monitoring)"]
        StudentUI["Student Screens (Enrolled Classes, Materials, Practice, Results)"]
        Extractor["DocumentTextExtractor (PDF, DOCX, PPTX On-Device)"]
        QuizGen["QuizService + QuizGenerationClient (authenticated HTTP)"]
        Scoring["ScoringUtils (Typo-Tolerance, Enumeration Partial Credit)"]
    end

    subgraph Firebase["Firebase Platform"]
        Auth["Firebase Authentication (Role-based Email/Password)"]
        Firestore["Cloud Firestore (named database: default)"]
        Functions["Cloud Functions v2 (configured Node 20)"]
    end

    subgraph Supabase["Supabase Platform"]
        Storage["Private Storage (study-materials/uploads/{teacherId}/...)"]
    end

    subgraph External["AI Services"]
        Gemini["Google Gemini API (server secret; default gemini-3.6-flash)"]
    end

    TeacherUI -->|Auth & Token| Auth
    StudentUI -->|Auth & Token| Auth
    TeacherUI -->|On-Device Text Extraction| Extractor
    Extractor -->|Direct Ready Text| Firestore
    TeacherUI -->|Non-Blocking Parallel Upload| Storage
    Auth -->|Firebase ID Token| Storage
    TeacherUI -->|Generate Quiz Request| QuizGen
    QuizGen -->|Firebase ID token and material IDs| Functions
    Functions -->|Read owned material and Actual reference| Firestore
    Functions -->|Strict prompt, selected types and exact count| Gemini
    Gemini -->|Schema-validated questions| Functions
    Functions -->|Persist validated draft quiz| Firestore
    TeacherUI <-->|Real-Time Streams| Firestore
    StudentUI <-->|Real-Time Streams| Firestore
    StudentUI -->|Submit Attempts & Drafts| Firestore
    StudentUI -->|Deterministic Grading| Scoring
```

---

## 2. Core Architectural Decisions & Deviations

1. **Server-only Gemini credentials (2026-09-11 integration revision)**:
   - `QuizService.generateQuiz` uses `QuizGenerationClient` and the existing `generateQuizHttp` function with a Firebase ID token. The server verifies teacher/class/material ownership and reads material text from the named Firestore database `default` (not `(default)`).
   - `functions/quiz_generator.js` defaults to `gemini-3.6-flash`, with a server-only `GEMINI_MODEL` override. `defineSecret('GEMINI_API_KEY')` binds the key to both generation functions. Local emulator value: ignored `functions/.secret.local`. Production secret version 1, both generation functions, extractText and named-database rules were deployed with user confirmation on 2026-09-11.
   - Invalid counts/types/content, malformed or incomplete responses, provider errors and timeouts fail explicitly. Runtime generation never fills missing questions with offline fixtures. Historical deterministic helpers remain for compatibility and separate tests.
   - Historical claims that client key restrictions prevent leakage or that this architecture needs no enabled Cloud Functions billing are superseded. Live CLI inspection found all three existing functions; billing/quota availability still governs service operation.

2. **On-Device Text Extraction (FR-05 Academic MVP Resolution)**:
   - High-performance on-device extraction engine (`DocumentTextExtractor`) parses PDF, DOCX, and PPTX directly in Flutter.
   - Saves extracted text immediately to Firestore with `status: 'ready'`, decoupling quiz creation from cloud cold starts or storage upload failures.

3. **Decoupled Parallel Upload Pipeline (Supabase Storage revision, 2026-09-17)**:
   - Private Supabase Storage upload is initiated concurrently with client-side text extraction and authorized with the current Firebase ID token.
   - The UI never waits on network upload timeouts (formerly 15s–30s). As soon as text extraction completes (~1.3s) and the Firestore document is saved, the teacher is unblocked immediately to configure and generate quizzes.
   - Storage upload runs in the background and updates `storageUploadStatus`; private object paths are retained instead of expiring URLs.
   - The legacy Firebase Storage trigger no longer receives new uploads. New DOCX/PPTX files therefore use external-app and extracted-text fallback unless preview conversion is later ported to another backend.

4. **Deterministic Multi-Layered Scoring & Typos**:
   - Length-tiered Levenshtein distance tolerance: $\le 4$ chars $\to 0$ typos; $5-8$ chars $\to 1$ typo; $\ge 9$ chars $\to 2$ typos.
   - Proportional partial credit on Enumeration questions without penalizing extraneous or out-of-order answers.

---

## 3. Database & Storage Schemas

### Cloud Firestore Collections

#### `users/{uid}`
```text
uid: string (matches Auth UID)
email: string
displayName: string
role: "teacher" | "student"
photoUrl?: string
createdAt: Timestamp
```

#### `classes/{classId}`
```text
id: string
name: string
joinCode: string (format: [A-Z]{3}-[A-Z0-9]{4})
teacherId: string
teacherName: string
status: "active" | "archived"
createdAt: Timestamp
updatedAt: Timestamp
```

#### `classes/{classId}/members/{uid}`
```text
userId: string
role: "teacher" | "student"
joinedAt: Timestamp
displayNameSnapshot: string
```

#### `materials/{materialId}`
```text
id: string
teacherId: string
classId: string
fileName: string
fileType: "pdf" | "pptx" | "docx" | "txt"
fileRef: string (Supabase object path: uploads/{teacherId}/{materialId}/{fileName})
storageProvider: "supabase" (legacy records default to "firebase")
storageBucket: "study-materials"
storageUploadStatus: "uploading" | "completed" | "failed"
downloadUrl?: string (legacy Firebase direct download URL only)
status: "ready" | "failed" | "processing"
errorReason?: string ("no_extractable_text" | "parse_error" | "file_too_large" | "empty_file")
extractedText: string
conversionStatus: "completed" | "pending" | "failed" | "unsupported"
convertedPdfRef?: string (uploads/{teacherId}/{materialId}/preview.pdf)
convertedPdfUrl?: string (download URL for converted preview)
convertedAt?: Timestamp
fileSizeBytes: number
createdAt: Timestamp
extractedAt?: Timestamp
```

#### `quizzes/{quizId}`
```text
id: string
classId: string
teacherId: string
materialId: string
type: "actual" | "practice"
title: string
status: "draft" | "published" | "archived"
generationMethod: "gemini" | "manual" | "fallback"
totalPoints: number
questions: Array<{
  id: string,
  type: "multipleChoice" | "trueFalse" | "fillInTheBlank" | "identification" | "enumeration",
  question: string,
  options?: string[],
  correctAnswer: string,
  enumerationAnswers?: string[],
  explanation?: string,
  points: number
}>
createdAt: Timestamp
updatedAt: Timestamp
```

#### `quizAssignments/{assignmentId}`
```text
id: string
quizId: string
classId: string
teacherId: string
deadline?: Timestamp
isClosed: boolean
createdAt: Timestamp
closedAt?: Timestamp
```

#### `attempts/{attemptId}`
```text
id: string
quizId: string
assignmentId?: string
classId: string
studentId: string
studentName: string
answers: Map<string, dynamic>
score: number
totalPoints: number
percentage: number
submittedAt: Timestamp
resultSummary?: string
```

#### `users/{uid}/attempts/draft_{quizId}`
```text
answers: Map<string, dynamic>
updatedAt: Timestamp
```

---

## 4. Completed Foundation Modules (Phases A – J)

- **Phase A: Project Baseline & Security**: Rules for Firestore and Storage, initialization configuration.
- **Phase B: Role-Based Authentication**: Email/password registration, login, role routing (`/teacher`, `/student`), session persistence on splash.
- **Phase C: Scoring Engine**: Deterministic typo tolerance, prefix cleaning (`A.`, `1.`), case insensitivity, enumeration partial scoring.
- **Phase D: Class Management**: Class creation, unique join codes, student membership synchronization, real-time roster listener.
- **Phase E: Material Upload & Text Extraction**: Multi-format validation, on-device `DocumentTextExtractor` supporting PDF, DOCX, and PPTX.
- **Phase F: AI Quiz Generation (current revision)**: authenticated server Gemini generation with strict validation across all five question types; secure production deployment completed on 2026-09-11. Prior direct/fallback behavior is historical.
- **Phase G: Quiz Assignment & Teacher Monitoring**: Assignment publishing with deadlines, student attempt tracking, real-time monitoring dashboard with average/highest scores.
- **Phase H: Printable PDF Exam Export**: Professional examination formatting via `pdf` and `printing`, student answer sheets, and confidential teacher answer keys.
- **Phase I: Unified In-App Document Preview**: Google Drive API v3 background office-to-PDF conversion for PPTX/DOCX preview inside `SfPdfViewer`.
- **Phase J: Resilient Layout & Mobile Polish**: 360dp / 320dp narrow viewport overflow fixes, profile cards, cached Firestore stream performance.

---

## 5. Practice Quiz UX & Accuracy Adjustments Pass (Tasks 1 – 7)

### Task 1 — Unanswered Questions Indicator
- **Problem**: Students had no live visibility into which questions were skipped or remained unanswered during Practice Quizzes.
- **Implementation**:
  - Added interactive `_buildQuestionNavigationStrip()` in `AnswerQuizScreen` with live status badges:
    - Green checkmark (`#4CAF50`): Question answered.
    - Orange outline / clock (`#FFA726`): Question skipped or unanswered.
    - Navy border (`#1A237E`): Current active question.
  - Added full-quiz **Grid View Modal** allowing direct out-of-order navigation to any question with live completion counts.
- **Verification**: `test/quiz_skip_submit_guard_test.dart` (5/5 passed).

### Task 2 — In-Progress Quiz Draft Persistence
- **Problem**: Leaving a quiz in progress (accidental back button, tab switch, or phone call) discarded all entered answers.
- **Implementation**:
  - Implemented dual-layer persistence in `AssignmentService` (`saveDraftAnswers`, `getDraftAnswers`, `clearDraftAnswers`) storing answers in Firestore subcollection `users/{uid}/attempts/draft_{quizId}` with an in-memory fallback cache.
  - Integrated `PopScope` on `AnswerQuizScreen` to auto-persist answers on exit.
  - Automatically restores saved answers on quiz resume and purges drafts upon final quiz submission.
- **Verification**: `test/quiz_draft_persistence_test.dart` (1/1 passed).

### Task 3 — Partial Enumeration Progress and Submission
- **Problem**: Typing an enumeration answer without clicking "Add" discarded the text; students could not proceed or submit with partial items.
- **Implementation**:
  - Updated `_saveCurrentAnswer()` to auto-commit any pending text in `_enumerationController` before navigation or submission.
  - Enhanced `_addEnumerationItem()` to parse multi-item text pasted with commas or newlines.
  - Added live partial credit feedback chip in `_buildEnumerationInput()` showing `X of Y items answered`.
  - Allowed submitting quizzes with partial enumeration answers for proportional partial credit.
- **Verification**: `test/quiz_partial_enumeration_test.dart` (2/2 passed).

### Task 4 — Fill-in-the-Blank Gemini Accuracy
- **Problem**: Fill-in-the-blank questions generated long phrases, masked whole sentences, or lacked clear context clues.
- **Implementation**:
  - Refined Gemini prompt directives in `lib/services/quiz_service.dart` and `functions/index.js` to strictly require single 1–2 word key concepts as the blank.
  - Required surrounding context with standard `_______` blank notation.
  - Added `ScoringUtils.cleanFillInTheBlankAnswer()` stripping leading articles (`the`, `a`, `an`), surrounding quotes, commas, and trailing periods.
  - Upgraded question validation to enforce `_______` placeholders and reject multi-word blanks (> 3 words).
- **Verification**: `test/quiz_fill_in_blank_accuracy_test.dart` (3/3 passed).

### Task 5 — Table/Column Headers Treated as Quiz Content
- **Problem**: Tabular text from slides/documents caused column headers (`Column A`, `Header 1`, `Attribute`, `Value`, `No.`) to become quiz questions or answers.
- **Implementation**:
  - **Extraction Layer**: Added `stripTableHeaderArtifacts` in `DocumentTextExtractor` and `functions/index.js` to detect and strip structural header rows while preserving table cell contents and academic sentences.
  - **Prompt Layer**: Added Directive 3 `STRICTLY FORBID TABLE/COLUMN HEADERS & STRUCTURAL LABELS` forbidding questions testing column names, header labels, or table coordinates.
  - **Validation Layer**: Added `QuizService.isTableHeaderQuestion()` in client and Cloud Function to detect structural prompts/answers, purging and backfilling valid questions.
  - **Fallback Engine**: Added `structuralBlacklist` preventing structural keywords from becoming candidate terms.
- **Verification**: `test/quiz_table_header_filter_test.dart` (4/4 passed).

### Task 6 — Filter Out Irrelevant & Filler Content
- **Problem**: Textbooks and lecture presentations leaked copyright notices, professor emails, ISBNs, book editions, and lecture transitions ("Thank you for listening") into questions.
- **Implementation**:
  - **Prompt Layer**: Enhanced Directive 2 `STRICTLY FORBID NON-ACADEMIC BOILERPLATE, METADATA & ADMINISTRATIVE TRIVIA` in both client and Cloud Function prompts.
  - **Validation Layer**: Added `QuizService.isFillerOrBoilerplateQuestion()` and JS equivalent detecting author/instructor info, email addresses, URLs, slide/page metadata, lecture transitions, and grading policies.
  - **Fallback Engine**: Fixed non-word regex boundaries in `metadataRegex` and `metadataSentenceRegex` and added author/email/ISBN tokens to candidate blacklists.
- **Verification**: `test/quiz_filler_content_filter_test.dart` (5/5 passed across 3 sample materials).

### Task 7 — Slow PDF Upload Optimization
- **Problem**: Uploading a PDF blocked the UI for 7–17+ seconds with a loading spinner due to serial Firebase Storage timeouts and redundant Cloud Function extraction.
- **Implementation**:
  - **Parallel Pipeline**: Initiated Firebase Storage upload concurrently with client-side text extraction in `MaterialService.uploadStudyMaterial`.
  - **Instant Time-to-Ready**: As soon as client extraction completes (~1.3s) and the Firestore document is saved with `status: 'ready'`, returned `readyModel` immediately so the teacher can generate quizzes without waiting.
  - **Background Persistence**: Storage upload completes in the background and populates `downloadUrl` without blocking the teacher.
  - **Cloud Function Short-Circuit**: Added early document check in `exports.extractText` (`functions/index.js`) to skip redundant file downloads and re-extractions when client-side extraction already succeeded.
  - **Fast Byte Check**: Added fast token presence checks in `_sanitizePdfBytes` in `DocumentTextExtractor`.
- **Verification**:
  - Blocking wait time reduced from **7.0s – 17.0s** to **~1.3s – 1.65s** (75%–90% reduction).
  - `test/pdf_upload_optimization_test.dart` (4/4 passed).
  - Full 10-suite regression test (68/68 passed).
  - `flutter analyze` clean (0 errors, 0 warnings, 0 lints).

---

## Current deployment verification (2026-09-11; reviewed 2026-09-12)

Teacher visibility correction (2026-09-12): quiz read rules explicitly authorize the class owner using classId, matching TeacherClassDetailsScreen's class-only query. TeacherId-only queries and student published-Practice restrictions remain. Verified with failing-before/passing-after emulator queries, 18 targeted Flutter tests and 8 production check groups; corrected rules are deployed. Query errors now have a Retry state rather than an empty-class message.

- User-approved Secret Manager version 1, both generation functions, extractText and named-database rules are live.
- Production Auth/database/Gemini verification passed 12 check groups, including Actual 10 and Practice 10 questions, publish/query and result/history persistence. Temporary test accounts and documents were removed.
- Production DOCX Storage upload/download and server extraction passed, yielding 1,005 characters and a Firestore server timestamp. Optional Office-to-PDF conversion failed; Drive API is enabled, but scoped logs did not expose a cause. Do not claim previews are fully working.
- Native picker and a signed-in release UI walkthrough still need a connected device. Production REST checks do not execute Flutter scoring or prove native interaction.
- See INTEGRATION_REPORT.md for retained limits, cleanup evidence, Node 20 retirement and artifact-retention follow-ups.

## 6. Historical Verification & Automated Test Matrix

Current 2026-09-11 verification: 167 Flutter tests and 11 Node unit tests passed; 32 Auth/Firestore emulator checks and 38 HTTP handler checks with an explicit provider fixture passed. Android/web release builds passed; Chrome startup rendered correctly. See INTEGRATION_REPORT.md for real Gemini evidence and platform/deployment limits. Counts below describe the earlier milestone only.

| Test File | Target Module / Phase | Tests Passed |
| :--- | :--- | :--- |
| `test/pdf_upload_optimization_test.dart` | Task 7: Fast upload, pre-sanitization, MIME mapping | **4 / 4** |
| `test/quiz_filler_content_filter_test.dart` | Task 6: Non-academic filler & boilerplate filtering | **5 / 5** |
| `test/quiz_table_header_filter_test.dart` | Task 5: Tabular column headers & structural label filtering | **4 / 4** |
| `test/quiz_fill_in_blank_accuracy_test.dart` | Task 4: Single-term blanks, article stripping, placeholder validation | **3 / 3** |
| `test/quiz_partial_enumeration_test.dart` | Task 3: Enumeration auto-commit, comma entry, partial credit | **2 / 2** |
| `test/quiz_draft_persistence_test.dart` | Task 2: In-progress draft saving, restoration, auto-clear | **1 / 1** |
| `test/quiz_skip_submit_guard_test.dart` | Task 1: Unanswered question strip, round-robin skip, submit guard | **5 / 5** |
| `test/document_extraction_test.dart` | Phase E/I: PDF/PPTX/DOCX extraction, `/Outlines null` resiliency | **9 / 9** |
| `test/material_service_test.dart` | Phase E/I: Material validation, error formatting, converted preview | **14 / 14** |
| `test/quiz_test.dart` | Phase F: Jaccard deduplication, question validation, 10/30/50 count | **21 / 21** |
| **Total Test Coverage** | **All 10 Core Regression Suites** | **68 / 68 Passed (100%)** |
