# Studexa Project Understanding

Snapshot: 2026-09-10, BSCS-3A Flutter/Firebase project. This describes the inspected working tree, including pre-existing uncommitted changes, rather than only the last Git commit. Investigation began with [IMPLEMENTATION_LOG.md](docs/IMPLEMENTATION_LOG.md) and [IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md).

Evidence scope: static repository investigation. No live Firebase, OAuth, Drive, or Gemini requests, deployment, package installation, app execution, or test-suite execution was performed. Historical results/timings are attributed to the log, not newly verified. Runtime implications that were not exercised are identified accordingly. Secret values are not reproduced. Only this document and the requested log session entry were written.

## 1. Project structure

### Architecture and repository boundaries

Studexa uses stateful Flutter screens, constructor-supplied models, service objects, local `setState`, and Firestore `StreamBuilder`/subscriptions. There is no separate repository/use-case layer or global state-management framework. `main()` initializes Firebase and launches `MyApp`; `MaterialApp.home` is `SplashScreen`. Navigation uses `Navigator` with `MaterialPageRoute`/`PageRouteBuilder`, not a registered `/teacher` and `/student` route table.

Data access is concentrated in `lib/services/`. **`getAppFirestore()` selects database ID `default` (without parentheses)** when Firebase is initialized. Its fallback is `FirebaseFirestore.instance` if construction cannot proceed; it does not retry failed asynchronous requests against another database. The Node backend instead calls `admin.firestore()` without selecting that named database. This distinction affects every cloud flow below.

Android is the primary target. `DefaultFirebaseOptions` configures Android, iOS, web, and Windows for project `studexa-b5e55`; macOS/Linux throw `UnsupportedError`. Platform directories are `android/`, `ios/`, `web/`, and `windows/`. Configuration presence does not prove working flows on all platforms. `pubspec.yaml` declares Dart `^3.12.2` and dependencies for Firebase Auth/Firestore/Storage, Google Sign-In, file picking, HTTP, ZIP parsing, PDF creation/viewing/printing, external-file opening, and temporary paths. `assets/images/studexa_logo.png` supplies branding.

`firebase.json` references `firestore.rules`, `storage.rules`, and `functions/`; it does not explicitly select database `default` for rules deployment. No `.firebaserc` or checked-in Firestore indexes file was found. `docs/` contains the plan, log, implementation prompt, and Phase 1 Word document. `test/` holds unit/widget/simulated-journey suites plus `test/fixtures/sample_materials/research_ppt_export.pdf`.

### Full lib/ source inventory

All 36 Dart files present under `lib/`, including the ignored local Gemini configuration, are listed here. Private widget helpers remain in their owning screen files.

| File | Main symbol(s) and responsibility |
| --- | --- |
| `lib/main.dart` | `main`, `MyApp`: initialize Firebase, configure the Material 3 navy theme, and open splash. |
| `lib/firebase_options.dart` | `DefaultFirebaseOptions`: generated platform-specific Firebase initialization options. |
| `lib/config/gemini_config.dart` | `GeminiConfig`: local ignored client API-key/model configuration, present in this checkout. |
| `lib/config/gemini_config.template.dart` | `GeminiConfig`: copyable placeholder-key template with model string `gemini-3.6-flash`. |
| `lib/models/user_profile.dart` | `UserProfile`: identity/role serialization and `isTeacher`/`isStudent` predicates. |
| `lib/models/class_model.dart` | `ClassModel`, `ClassMember`: class metadata and membership snapshots. |
| `lib/models/material_model.dart` | `MaterialModel`: original file/text/extraction/preview metadata, state getters, MIME mapping, and error descriptions. |
| `lib/models/quiz_model.dart` | `QuizQuestionType`, `QuizQuestion`, `QuizModel`: five question formats, answer keys, lifecycle, and source reference. |
| `lib/models/quiz_assignment_model.dart` | `QuizAssignmentModel`: assignment deadline/manual closure and client-clock availability. |
| `lib/models/quiz_attempt_model.dart` | `QuizAttemptModel`: saved answers, scores, percentage, breakdown, and 70% pass predicate. |
| `lib/services/firestore_provider.dart` | `getAppFirestore`: named-database selection and injectable Firestore instance. |
| `lib/services/auth_service.dart` | `AuthService`, `AuthRoleMismatchException`: email/Google auth, profile writes, role checks, logout, and error mapping. |
| `lib/services/class_service.dart` | `ClassService`, `ClassJoinException`: class creation, codes, enrollment batches, and class/member streams. |
| `lib/services/material_service.dart` | `MaterialService`, `MaterialValidationException`: validation, local extraction, parallel original upload, retrieval/retry, and deletion/cleanup. |
| `lib/services/quiz_service.dart` | `QuizService`: direct Gemini generation, local fallback, validation/deduplication, quiz CRUD, and streams. |
| `lib/services/assignment_service.dart` | `AssignmentService`, `QuizUnavailableException`: assignment controls, submission checks, attempts, and per-attempt drafts. |
| `lib/services/pdf_export_service.dart` | `PdfExportService`: A4 exam/answer-key generation and `Printing.layoutPdf` integration. |
| `lib/utils/document_text_extractor.dart` | `DocumentTextExtractor`, `DocumentExtractionResult`: PDF/OpenXML/TXT parsing, PDF recovery, header filtering, and structured errors. |
| `lib/utils/scoring_utils.dart` | `ScoringUtils`, `EnumerationResult`: normalization, Levenshtein matching, and enumeration partial credit. |
| `lib/widgets/google_logo.dart` | `GoogleLogo`, `_GoogleLogoPainter`: draw the Google icon locally with `CustomPainter`. |
| `lib/widgets/google_sign_in_button.dart` | `GoogleSignInButton`, `AuthDivider`: Google auth button/loading state and OR divider. |
| `lib/screens/splash_screen.dart` | `SplashScreen`, `_navigateToApp`: animate branding, recover profile, and route by role. |
| `lib/screens/auth/role_selection_screen.dart` | `RoleSelectionScreen`, `_RoleCard`: select Teacher/Student and open role-specific login. |
| `lib/screens/auth/login_screen.dart` | `LoginScreen`: email/Google login validation, errors, and dashboard routing. |
| `lib/screens/auth/register_screen.dart` | `RegisterScreen`: role-selectable email/Google registration and dashboard routing. |
| `lib/screens/teacher/teacher_home_screen.dart` | `TeacherHomeScreen`: profile/logout, live owned classes, class creation/code dialogs, and upload shortcuts. |
| `lib/screens/teacher/teacher_class_details_screen.dart` | `TeacherClassDetailsScreen`, `_KeepAliveTab`: Materials/Quizzes/Students tabs, code copying, material actions, and class-locked upload. |
| `lib/screens/teacher/upload_generate_quiz_screen.dart` | `UploadGenerateQuizScreen`: pick/retry/reuse a material, configure types/count, and independently generate Actual or Practice drafts. |
| `lib/screens/teacher/quiz_detail_screen.dart` | `QuizDetailScreen`: inspect/edit, finalize Actual, publish Practice, open monitoring, print, and delete. |
| `lib/screens/teacher/quiz_monitoring_screen.dart` | `QuizMonitoringScreen`: deadline/open/close controls, latest-attempt analytics, roster completion, and saved answer review. |
| `lib/screens/teacher/teacher_results_screen.dart` | `TeacherResultsScreen`: legacy roster-based results layout with placeholder score/submission content; no current lib navigation caller found. |
| `lib/screens/student/student_home_screen.dart` | `StudentHomeScreen`: profile/logout, Join Class, and enrolled classes leading to class details. |
| `lib/screens/student/join_class_screen.dart` | `JoinClassScreen`, `_handleJoin`: join-code submission and confirmation/error state. |
| `lib/screens/student/student_class_details_screen.dart` | `StudentClassDetailsScreen`: live class/materials/people, published Practice availability, start/retake, and saved review. |
| `lib/screens/student/answer_quiz_screen.dart` | `AnswerQuizScreen`: five inputs, queue/skip/flag/grid, drafts, second-attempt shuffle, scoring, submission, and results. |
| `lib/screens/materials/material_viewer_screen.dart` | `MaterialViewerScreen`: original PDF/converted Office preview, conversion listener, extracted text, and external-original fallback. |

### Cloud Functions directory

| File | Responsibility |
| --- | --- |
| `functions/index.js` | Entire backend: three exported v2 functions plus extraction, Drive conversion, Gemini, filtering, and fallback helpers. |
| `functions/package.json` | Node **20** entry point `index.js`, dependency ranges, and emulator/shell/deploy/log scripts. |
| `functions/package-lock.json` | Resolved npm dependency graph, not additional application behavior. |

Installed `functions/node_modules/` files are third-party dependencies, not additional Studexa functions. Section 4 inventories every export.

## 2. Data model

### Conventions and relationships

The following keys come from actual serializers and write payloads. Unless listed, `id` is the document ID passed into a model, **not a stored field**. Flutter exposes timestamps as `DateTime`; writes use `Timestamp` or server-timestamp sentinels. Several deserializers also accept timestamp strings. Optional fields can be absent or null depending on the writer.

Relationships:

- Firebase Auth UID → `users/{uid}`.
- `classes.teacherId` → teacher UID; `classes/{classId}/members/{uid}` records teacher/student membership.
- `users/{uid}/joinedClasses/{classId}` mirrors student enrollment for dashboard discovery.
- `materials.classId`/`teacherId` → class/uploader; file references → Storage.
- `quizzes.materialId`/`classId`/`teacherId` → source/class/teacher; optional `sourceQuizId` → reference quiz.
- `quizAssignments.quizId`/`classId`/`teacherId` → quiz/class/teacher.
- `attempts.quizId`/`classId`/`studentId` → quiz/class/student; optional `assignmentId` is not populated by the current answering screen.
- Drafts are separate user-subcollection records, not submitted attempts.

These are string references, not enforced foreign keys. Actual and Practice share **one `quizzes` collection**, embedding answer keys alongside questions.

### users/{uid}

Fields: string `uid`, `email`, `displayName`, `role`; optional string `photoUrl`; timestamps `createdAt` and `updatedAt`. Serializer lowercases email/role; intended roles are `teacher`/`student`. `UserProfile` does not expose `updatedAt` even though `toMap` writes it.

Writer/reader: `lib/services/auth_service.dart` → `registerWithEmail`, `_saveUserProfile`, `signInWithEmail`, `signInWithGoogle`, `getCurrentUserProfile`. Model: `lib/models/user_profile.dart`. Avatar-only Google synchronization updates `photoUrl` without updating `updatedAt`.

Consumers: splash, auth handlers, teacher/student dashboards. Roles come from Firestore, not custom Auth claims; changing a profile role does not synchronize membership-role snapshots.

### classes/{classId}

Fields: strings `name`, uppercase `joinCode`, `teacherId`, `teacherName`, `section`, `subject`, `status`, `recentQuiz`; integer `rosterCount`; timestamps `createdAt`, `updatedAt`.

`ClassModel` defaults section/subject to empty, status to `active`, count to 0, recentQuiz to `No quizzes yet`. `createClass` writes those defaults. Joining requires status exactly `active`; no current service/UI operation archives a class, edits section/subject, or updates `recentQuiz`.

Writer: `ClassService.createClass` and the separate counter update in `joinClassByCode`. Readers: `generateUniqueJoinCode`, `joinClassByCode`, `getTeacherClassesStream`, `getStudentJoinedClassesStream`, `streamClass`, `getClassById` in `lib/services/class_service.dart`. Model: `lib/models/class_model.dart`.

Consumers: dashboards/class details, upload selector, and `QuizDetailScreen._loadClassDetails` for export context.

### classes/{classId}/members/{uid}

Fields: `userId`, `role`, `displayNameSnapshot`, `joinedAt`; student enrollment also writes `emailSnapshot`. Teacher creation omits email; `ClassMember` defaults it to empty.

Writers: `ClassService.createClass` adds teacher membership; `joinClassByCode` adds student membership. Reader: `getClassMembersStream`. Model: `ClassMember` in `lib/models/class_model.dart`. Consumers: class rosters/people, `QuizMonitoringScreen`, legacy `TeacherResultsScreen`. Member documents determine the monitoring roster, not the best-effort counter. No leave/remove flow was found.

### users/{uid}/joinedClasses/{classId}

Fields: `classId`, `className`, `teacherName`, `teacherId`, `joinCode`, `joinedAt`.

Writer: `ClassService.joinClassByCode`, batched with the student member. Reader: `getStudentJoinedClassesStream` watches the mirror, fetches each root class, and falls back to these snapshots if missing/unreadable. The actual keys are **not** the log's `classNameSnapshot`/`teacherNameSnapshot`/`joinCodeSnapshot`.

There is no standalone mirror model; records become `ClassModel` for `StudentHomeScreen`. Root class fetches are not ongoing per-class subscriptions, so the mirror stream alone does not react to root class edits.

### materials/{materialId}

| Fields | Actual use |
| --- | --- |
| `teacherId`, `classId`, `fileName`, `fileType`, `fileRef` | Uploader/class/original identity; upload supports `pdf`, `pptx`, `docx`. |
| `downloadUrl` | Optional original Storage download URL populated after upload. |
| `status` | Current upload writes `ready`/`failed`; model also recognizes `pending`/`processing`. |
| `extractedText` | Text in the document itself; no chunk collection. |
| `errorReason` | Nullable string: `empty_file`, `unsupported_format`, `parse_error`, `no_extractable_text`, `file_bytes_unavailable`. Formatter also recognizes `file_too_large`, although oversize validation throws before document creation. |
| `createdAt`, `fileSizeBytes` | Client creation timestamp and byte count for normal upload; size optional in model. |
| `extractedAt` | Optional; successful retry/server extraction writes it, initial successful client upload does not. |
| `conversionStatus` | PDF starts `completed`; Office starts `pending`; server writes `completed`/`failed`. Model comment also lists `unsupported`, with no writer found. |
| `convertedPdfRef`, `convertedPdfUrl`, `convertedAt` | Optional preview path, signed URL (possibly null), and conversion timestamp. |

Client writer/reader: `lib/services/material_service.dart` → `uploadStudyMaterial`, `retryMaterialExtraction`, `deleteMaterial`, `streamMaterial`, `streamClassMaterials`, `streamTeacherMaterials`. File retrieval helpers consume original/preview references. `QuizService.generateQuiz` reads text/name unless preloaded.

Server writer/reader: `functions/index.js` → `extractText` reads readiness and merge-writes extraction/conversion fields; `processQuizGeneration` reads text/name. A server merge can create a partial record if it runs without/before a client document; server writes do not provide all class/teacher/name/creation fields.

Consumers: upload readiness listener, teacher/student material lists, `MaterialViewerScreen._listenForConversion`, and generation from a preselected ready material.

Storage paths:

- Original: `uploads/{teacherId}/{materialId}/{fileName}`; metadata has teacher/material/class IDs and MIME content type.
- Preview: `uploads/{teacherId}/{materialId}/preview.pdf`; helper supplies PDF/preview identity metadata.
- Server temporary files use `os.tmpdir`; client external opening uses a sanitized filename in `getTemporaryDirectory()`.

`MaterialService.deleteMaterial` deletes the material document immediately, concurrently attempts original/preview/cache cleanup, deletes associated **draft** quizzes, and clears `materialId` on non-draft quizzes. It is best-effort cleanup, not an atomic cascade.

### quizzes/{quizId} and embedded questions

Fields: `classId`, `teacherId`, `materialId`, `type`, `title`, `status`, `generationMethod`, nullable `sourceQuizId`, `questions`, numeric `totalPoints`, timestamps `createdAt`/`updatedAt`, optional `publishedAt`.

- `type`: `actual`/`practice`.
- Writers create `draft`; Actual finalization writes `finalized`; Practice publishing writes `published`. Model also recognizes `closed`, but closing an assignment does not change quiz status. No `archived` writer was found.
- Active generation writes method `gemini`/`fallback`. Model supports `manual`, but no manual-create flow or writer selecting it was found. Gemini questions supplemented with fallback can retain label `gemini`.
- `totalPoints` is summed at generation/edit. Published questions remain mutable; no quiz version is stored.

Every `QuizQuestion.toMap` writes:

| Field | Value |
| --- | --- |
| `id` | String question key; accepted client questions are renumbered `q_1`, `q_2`, … |
| `type` | Stored strings **`multiple_choice`, `true_false`, `fill_blank`, `identification`, `enumeration`**, not Dart enum camelCase. |
| `question` | Prompt string. |
| `options` | String array, including empty arrays for non-choice questions. |
| `correctAnswer` | String; MCQ generally uses full labelled option; enumeration may use comma-separated items. |
| `enumerationAnswers` | Expected enumeration string array. |
| `explanation` | Feedback string. |
| `points` | Number, normally 1; fallback enumeration uses item count. |

Writer/reader: `lib/services/quiz_service.dart` → `generateQuiz`, `updateQuiz`, `publishQuiz`, `finalizeQuiz`, `deleteQuiz`, `getQuiz`, `streamQuiz`, `streamClassQuizzes`, `streamTeacherQuizzes`. `MaterialService._cleanupMaterialQuizzes` deletes/unlinks records. Node `processQuizGeneration` creates drafts and optionally reads a source quiz.

Consumers: teacher class/detail/export, student class/answering, and monitoring receiving a model. Student listing queries class + Practice type, then filters published status **in Flutter** after receiving documents. Answer keys are used for client scoring.

### quizAssignments/{assignmentId}

Fields: `quizId`, `classId`, `teacherId`, **`quizTitle`**, boolean `isClosed`, `createdAt`; optional `deadline`/`closedAt` timestamps.

`createAssignment` uses an auto-ID/server creation timestamp. Closing writes `isClosed: true`/`closedAt`; reopening deletes `closedAt`; `updateDeadline(null)` deletes deadline. There is no uniqueness constraint on class+quiz.

Writer/reader: `lib/services/assignment_service.dart` → `createAssignment`, `closeAssignment`, `reopenAssignment`, `updateDeadline`, `streamClassAssignments`, `getAssignmentForQuiz`, `submitAttempt`. Model: `lib/models/quiz_assignment_model.dart`.

UI writers are `QuizMonitoringScreen._toggleAssignmentStatus` and `_setDeadline`, creating an assignment lazily. Publishing does not create one. Student class details reads availability. `isExpired` uses `DateTime.now().isAfter(deadline)`; `isOpen` checks closure only; `isAvailable` checks both.

### attempts/{attemptId}: submitted results

Fields: `quizId`, nullable `assignmentId`, `classId`, `studentId`, `studentName`, `answers`, numeric `score`/`totalPoints`/`percentage`, `submittedAt`, **`breakdown`**.

`answers` maps question IDs to strings/string arrays. `AnswerQuizScreen._evaluateAndShowResults` first adds positional compatibility keys `q_0` through `q_{n-1}`, then real question IDs; later real-ID entries win on overlap. Use actual IDs when interpreting shuffled attempts.

`breakdown` is an array of maps: `questionId`, `question` (prompt snapshot), `userAnswer` (stringified, including lists), `correctAnswer`, `earned`, `points`, `isCorrect`. It does not persist enumeration found/missing/extra, explanations, or a quiz version. There is no current `resultSummary` or submitted `attemptNumber` field.

Writer: `AnswerQuizScreen` constructs grades; `AssignmentService.submitAttempt` checks availability/count, generates an ID, and writes with server `submittedAt`. It does not recompute grades. The screen omits `assignmentId`, so it is written null.

Readers: `streamClassQuizAttempts` (newest-first), `streamStudentClassAttempts` (no explicit sort), and submission's count query. Consumers: teacher monitoring/student class review. `QuizAttemptModel.isPassed` uses 70%; immediate results use 75% for the trophy, a separate visual threshold.

### users/{uid}/attempts/draft_{quizId}_attempt_{attemptNumber}: drafts

Fields: `quizId`, `studentId`, integer `attemptNumber`, `answers`, `isDraft: true`, `updatedAt`.

Writer/reader/deleter: `AssignmentService.saveDraftAnswers`, `getDraftAnswers`, `clearDraftAnswers`; UI callers: `AnswerQuizScreen._persistDraftAnswers`/`_loadDraftAnswersFromService`. Writes merge; read/write/delete have two-second timeouts and swallowed errors. Cache is **per service instance**, keyed by student+quiz+attempt.

The ID includes the attempt number, unlike the plan's `draft_{quizId}`. Only answers are saved, not current question, queue/shuffle order, flags, skipped set, or random seed. These drafts are separate from top-level submitted attempts.

### Checked-in rule boundaries

| Resource | Actual permissions |
| --- | --- |
| User root | Any authenticated user can read any profile; own UID can create/update without role/field restriction; delete denied. |
| Own joinedClasses/drafts | Own UID can read/write matching subcollections. |
| Classes | Any authenticated user can read/create/update; delete requires matching `teacherId`. |
| Members | Any authenticated user can read/delete; create/update requires caller UID equal to member document ID, not a verified code/role. |
| Materials/quizzes | Any authenticated user can read/create/update; delete requires matching `teacherId`. |
| Assignments | Any authenticated user can read/create/update/delete. |
| Submitted attempts | Any authenticated user can read; create requires payload `studentId == request.auth.uid`; update/delete denied. No score/deadline/membership/type/count validation. |
| Storage upload path | Any authenticated user can read; write requires UID matching path teacherId and size strictly below 50 MiB; delete requires matching UID. No profile-role/enrollment check. |

Sources: `firestore.rules` and `storage.rules`. Their comments and the log's stronger security claims are not enforcement. Admin function access is not constrained by these client rules. Deployed rule contents/database targeting were not checked.

## 3. Core flows

### Upload → extraction → Actual/Practice generation → publication

1. **Enter/select a class.** `TeacherHomeScreen` lists owned classes. `TeacherClassDetailsScreen._openUploadScreen` passes the live class with `isClassLocked: true`. A material sheet can pass a ready `preselectedMaterial`. The dashboard upload shortcut selects a class first.
2. **Pick/validate.** `UploadGenerateQuizScreen._pickAndUploadFile` requires an Auth user and class, calls `FilePicker.pickFile` for PDF/PPTX/DOCX, resolves size/bytes/path, and caches bytes/path for retry. `MaterialService.validateUploadRequest` requires nonempty class ID, supported extension, nonzero bytes, and ≤50 × 1024 × 1024 bytes. These checks do not verify teacher profile/ownership.
3. **Start original upload.** `MaterialService.uploadStudyMaterial` allocates ID/path, starts Storage `putData`/`putFile` with metadata, and forwards progress. Screen progress updates are throttled to ≥5% changes or completion.
4. **Extract on-device.** The same service awaits `DocumentTextExtractor.extract`. Its parsing is synchronous inside the async entry point; there is no isolate/`compute` worker. PDF parsing sanitizes null dictionary values with equal-length spaces, then tries lines, whole-document text, individual pages, and raw/FlateDecode streams. DOCX parses ZIP document paragraphs plus footnotes/endnotes. PPTX parses numerically ordered slides, notes, and diagrams with normalized ZIP paths. Cleanup filters structural headers; meaningful text requires ≥25 characters and five alphanumeric words of ≥2 characters. No OCR.
5. **Write readiness.** The client writes the material with `ready`+text or `failed`+reason. PDF preview starts completed, Office pending. Server extraction is not a prerequisite for generation.
6. **Finish original storage separately.** The service gives the upload a 100 ms fast check. If complete, it awaits URL retrieval/update before returning. Otherwise an unawaited worker waits up to 45 seconds, then saves `downloadUrl` on success. Upload failure leaves local readiness intact; it does not fail Office preview status. The screen listens to material updates and enables generation for ready material. Cached retry is a new upload; extraction retry retrieves original bytes and re-parses.
7. **Optional server branch.** If deployed/connected, finalization triggers `extractText`. Ready PDFs with ≥20 text characters are skipped. Office is skipped only when ready and conversion completed; pending Office still gets downloaded/re-extracted before Drive conversion. See database/race caveats below.
8. **Choose quiz settings.** Screen defaults are 10 questions, MCQ and True/False selected, with all five formats selectable. `_generateQuiz(isActual: true/false)` checks readiness/user/class/types and passes preloaded text/name to `QuizService.generateQuiz`.
9. **Call Gemini directly.** Key precedence: explicit argument → nonempty `GeminiConfig.apiKey` → `globalGeminiApiKey` → Dart environment `GEMINI_API_KEY`. `_callGeminiSingleBatch` uses configured model (currently `gemini-3.6-flash` locally/in template), with `gemini-1.5-flash` only if model string is empty. It POSTs to Generative Language `generateContent`, requests JSON, temperature 0.3, with 35-second timeout. Counts ≤15 use one call; larger counts use parallel batches of 10 with overlapping text chunks, max 20,000 characters per request. API/model availability was not tested.
10. **Fallback/validate/save draft.** Missing/failed Gemini invokes `generateLocalFallbackQuestions`. Parsed answers are cleaned; structural/filler questions filtered. `validateAndDeduplicateQuestions` removes invalid/exact/near duplicates using Jaccard >0.70, or same normalized answer with >0.45, and compares MCQ option sets. It attempts fallback backfill, caps count, renumbers IDs, sums points, and writes a draft. Exact count/source grounding are conditional.
11. **Actual and Practice are independent.** Teacher can generate Actual, review it, then separately generate Practice. There is no enforced sequence or automatic pair. UI supplies no `sourceQuizId`; client `generateQuiz` stores a supplied ID but never loads/passes Actual context to Gemini. The wired flow does not ensure Practice derives from Actual questions.
12. **Review/finalize/publish.** `QuizDetailScreen` allows title, prompt, and `correctAnswer` edits. `_finalizeQuiz` validates and sets Actual finalized. `_publishQuiz` validates and sets Practice published plus timestamp; it does not create an assignment. Detail uses its local quiz model, not a live `streamQuiz` subscription.
13. **Set submission controls.** Published Practice offers Monitor Submissions. `QuizMonitoringScreen._toggleAssignmentStatus` creates an open assignment if absent, otherwise closes/reopens; `_setDeadline` creates/updates one. Published quizzes without assignments are treated as available.
14. **Export.** `_exportOrPrintExam` → `PdfExportService.printOrShareExam` → `Printing.layoutPdf` → `generateExamPdf` produces A4 student pages and optional confidential answer key, enabled by default. Export is local, not saved to Firebase. Print is currently visible for either quiz type and any status.

### Student attempt → scoring → results

1. `StudentHomeScreen` reads enrollment mirrors; class opens `StudentClassDetailsScreen`.
2. `_buildQuizzesTab` streams class Practice quizzes, filters published in memory, and joins class assignments/student attempts.
3. If assignment is not closed/expired: 0 attempts offers Start; 1 offers Review #1/Retake #2; ≥2 offers saved review. Closed/expired status is checked before review controls, currently hiding reviews from this list.
4. `AnswerQuizScreen` loads quiz questions and drafts. Attempt 1 keeps original order; attempt 2 shuffles and rotates if the random permutation was unchanged. A parameter ≥3 shows Maximum Attempts Reached. The parameter itself is not an authoritative database count.
5. Answer keys are question IDs. Skip deletes the current answer and moves the question to queue end. Navigation saves input; reaching queue end returns to unanswered questions. Strip/grid support status/direct navigation; flags remain local.
6. Text saves as it changes. Enumeration Add/keyboard submit splits commas/newlines and deduplicates; `_saveCurrentAnswer` commits pending enumeration during navigation/exit/submission. Any nonempty list counts as answered, allowing partial enumeration credit.
7. `_showSubmitConfirmation` requires every question answered. `_evaluateAndShowResults` grades entirely in Flutter:
   - MCQ/True-False: trimmed lowercase equality, or a student string longer than two characters contained in the expected answer.
   - Fill-in/identification: `ScoringUtils.isFreeTextMatch` cleans prefixes/quotes and normalizes case/punctuation/whitespace; expected length ≤4 allows 0 typos, 5–8 allows 1, ≥9 allows 2.
   - Enumeration: `scoreEnumeration` deduplicates expected/student items, matches each expected once with typo tolerance, and awards matched/unique-expected × points. Order and extra incorrect items do not reduce credit. Immediate results retain found/missing/extra.
8. Screen constructs `QuizAttemptModel` and calls `AssignmentService.submitAttempt` **without awaiting**. Service checks the first matching assignment, rejects closed/expired, counts prior attempts and rejects ≥2, then saves supplied grades. Missing assignment is accepted. This is not a transaction/server scoring flow.
9. Regardless of save completion, screen clears draft asynchronously and shows score/percentage/question review. Save errors, including limit/deadline rejection, are caught and debug-logged without user-facing submission failure. A demo/null-quiz path can show results without saving.
10. Done pops result/quiz; Home clears the stack to `StudentHomeScreen`. There is no separate student result screen file.
11. Saved student review uses `_showAttemptReview` and persisted breakdown; it selects the first unsorted attempt without a history selector. Teacher monitoring consumes newest-first attempts, retains latest per student, computes completion count/rate/average/highest percentage, and shows per-roster-student details via `_showStudentAttemptDetails`.

Draft exit handling uses `PopScope`/`dispose`, not an app-lifecycle observer. `dispose` also saves after submission and can recreate a cleared draft.

### Auth/role handling

1. `SplashScreen._navigateToApp` runs after animation timer or skip tap, calls `getCurrentUserProfile`, and selects teacher/student dashboard. Missing/unreadable profile routes to role selection.
2. Role selection passes a role to login; registration has its own selector. Successful auth clears routes with `pushAndRemoveUntil`.
3. `registerWithEmail` validates role, normalizes name/email, creates Auth account, concurrently updates display name and saves profile with a four-second timeout. On `email-already-in-use` it signs in with supplied credentials and writes the requested profile without checking for an existing profile's role.
4. `signInWithEmail` authenticates, loads profile or creates a missing one with requested role, then signs out/throws `AuthRoleMismatchException` if existing role differs.
5. `signInWithGoogle` obtains tokens, signs into Firebase, creates a new selected-role profile or checks existing role. Cancellation returns null. Mismatch signs out both providers; missing stored avatar syncs best effort.
6. Dashboard logout confirms, calls `AuthService.signOut` for Firebase/Google, and clears routes to role selection.
7. Roles are UI/service checks, not global middleware. `authStateChanges` is exposed but has no lib subscriber, dashboard constructors do not enforce role, and rules are permissive. OAuth deployment readiness was not verified.

### Join-code enrollment

1. `TeacherHomeScreen._showCreateClassDialog` calls `ClassService.createClass` with loaded profile identity and nonempty class name.
2. `generateUniqueJoinCode` takes the first name word's letters as a three-letter uppercase prefix, padding with CLS if short, then four characters from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`. It checks candidate codes with Firestore queries up to ten times; final fallback uses a timestamp-derived base-36 suffix without another uniqueness query.
3. `createClass` batches class root and teacher member. Dashboard/class detail offers clipboard copying.
4. `JoinClassScreen._handleJoin` requires code and signed-in Auth user, using Auth name/email snapshots; neither it nor service verifies a Firestore student role.
5. `joinClassByCode` rejects empty/`student_demo` IDs, trims/uppercases code, queries one class, requires active status, and rejects existing membership.
6. One batch writes student member and joinedClasses mirror. Separate best-effort counter increment does not roll back membership on failure.
7. Confirmation and dashboard/roster streams reveal enrollment. There is no server join function, invitation collection, leave flow, transactional uniqueness reservation, or code-verifying membership rule.

## 4. Cloud Functions inventory

All exports are in `functions/index.js` using v2. No scoring/submission, Firestore-trigger, scheduled, or standalone conversion function is exported.

| Export | Trigger/resources | Calls and behavior |
| --- | --- | --- |
| `extractText` | Storage `onObjectFinalized`; CPU 1, 1 GiB, 300 s | Filter upload path/ignore previews; read material readiness; download Storage original; parse PDF/DOCX/PPTX; merge Firestore extraction state; convert Office with Drive and upload preview. No Gemini. |
| `generateQuiz` | Callable `onCall`; CPU 1, 512 MiB, 120 s | Require `request.auth`, use UID as teacherId, forward settings to `processQuizGeneration`, return quiz/ID or `HttpsError`. No teacher/class/material ownership check. |
| `generateQuizHttp` | HTTP `onRequest`; CPU 1, 512 MiB, 120 s; `cors: true` | POST only; verify Bearer Auth token **or accept body teacherId without a Bearer token**; same processor; JSON 200/401/405/500. No Flutter caller found. |

No explicit region/bucket binding is in export options; deployment/trigger state is unknown.

Helpers and downstream calls:

- `parsePptx` prefers `officeParser.parseOfficeAsync`, with callback/promise compatibility fallback.
- `extractText` uses `pdfParse(buffer)`, `mammoth.extractRawText({buffer})`, or `parsePptx(tempPath)`; filters headers and requires ≥20 characters. Success writes ready/text/server extractedAt; failure writes unsupported_format/no_extractable_text/parse_error. Success does not explicitly clear old errorReason. Preview filenames are ignored to avoid recursion.
- Ready PDF and already-converted ready Office return early; pending Office still gets re-extracted.
- `convertOfficeToPdf` is an internal helper. `google.auth.GoogleAuth` requests Drive/Drive-file scopes; Drive v3 imports Office as Slides/Docs, exports PDF to temp disk, uploads preview beside original, and attempts a signed URL expiring `03-01-2030`. It deletes temporary Drive/PDF files in finally; outer extraction deletes original temp file. Conversion failure marks preview failed.
- `processQuizGeneration` checks nonempty IDs, reads source text (≥20 chars), optionally loads source Actual context, reads `process.env.GEMINI_API_KEY`, calls Gemini/fallback, sums points, writes draft, and returns ID/model with ISO response timestamps.
- `generateGeminiQuiz` uses Node global `fetch` against hard-coded `gemini-1.5-flash`, at most 15,000 source characters, JSON MIME and temperature 0.3. It filters structural/filler questions, normalizes answers, and attempts fallback backfill, without Flutter's batching/Jaccard validation.
- `generateFallbackQuizQuestions` is separate JS logic with biology example sentences/terms and `Math.random` option sorting; its “deterministic” comment is not fully accurate.
- `normalizeQuestionType`, `stripTableHeaderArtifacts`, `isTableHeaderQuestion`, and `isFillerOrBoilerplateQuestion` are helpers, not exports.

| External package | Declared range | Responsibility |
| --- | --- | --- |
| `firebase-functions` | `^6.0.0` | v2 triggers and HttpsError. |
| `firebase-admin` | `^13.0.0` | Initialize app, Firestore/Storage, token verification, timestamps. |
| `googleapis` | `^144.0.0` | Drive authentication/import/export/delete. |
| `pdf-parse` | `^1.1.1` | PDF text extraction. |
| `mammoth` | `^1.8.0` | DOCX text extraction. |
| `officeparser` | `^5.1.0` | PPTX text extraction. |

Built-ins: `path`, `fs`, `os`, Node 20 `fetch`. No Gemini SDK/OCR package is used. No Secret Manager `secrets` binding is declared. `pubspec.yaml` has no Cloud Functions client dependency; current Flutter generation posts to Gemini directly. Generation exports are alternate backend entry points.

## 5. Known constraints and protected pipelines

These consolidate documented decisions/preservation requirements. They are intended boundaries; section 6 records enforcement gaps. The documents do not establish a blanket prohibition on editing all these files in future work.

| Constraint/decision | Source and affected code |
| --- | --- |
| Inspect actual state before work and record evidence-based session history. | Log MANDATORY AI WORKFLOW; this pass adds only the requested history entry rather than rewriting existing status. |
| Actual is paper/reference-only, never student in-app assessment. | Log KNOWN ISSUES/traceability; teacher finalize/export and student Practice filter. |
| On-device extraction is approved FR-05 MVP deviation; Storage/Functions availability must not gate quiz readiness. | Log PROJECT DECISIONS, 2026-09-08 09:16, plan sections 2/5; MaterialService/DocumentTextExtractor. |
| Preserve extracted-text-to-quiz generation when changing previews. | Log 2026-09-09 20:10: “Strictly preserve the extracted-text-to-quiz-generation pipeline without changes or regressions.” |
| Conversion adds previews without replacing originals; keep external/text fallback. | Same session: “Do not delete, replace, or overwrite original PPTX/DOCX files in Firebase Storage.” This applies to conversion, not explicit teacher deletion. |
| Materials remain bound to selected class. | Log 2026-09-08 05:38; locked class parameters and validateUploadRequest. |
| Named Firestore database is default, not (default). | Log 2026-09-07 22:10; getAppFirestore. Backend mismatch remains. |
| Client Gemini key is accepted NFR-03 deviation; ignore local config and keep configuration out of product UI. | Log PROJECT DECISIONS, 2026-09-08 09:16/10:25/10:32; .gitignore/GeminiConfig/upload UI. Console package/SHA restrictions and quotas are documented, not verified here. |
| Preserve fallback when AI/network/quota fails. | Plan Phase F/architecture and log Phase J; both generators, with differing limitations. |
| Preserve academic-concept emphasis, plausible distractors, no metadata/table trivia, distinct Practice wording, and deduplication. | Log 2026-09-08 22:45, 2026-09-09 12:10, 2026-09-10 11:24/11:31/11:40; prompts/filters/fallback. |
| Blanks target unambiguous 1–2-word concepts using seven underscores and cleaned answers. | Plan Task 4/log 2026-09-10 11:24; prompt and QuizService.cleanFillInTheBlankAnswer. |
| Preserve short-answer typo tiers and order-independent enumeration partial credit without extra-item penalties. | Plan section 2/log 2026-09-09 11:51; ScoringUtils. |
| Preserve two-attempt cap, second shuffle, round-robin skip, unanswered indicators, and submit guard. | Log 2026-09-08 22:52 and practice UX sessions; AnswerQuizScreen/AssignmentService. |
| Preserve drafts, partial enumeration, and direct Home after results. | Plan Tasks 2/3; log 2026-09-08 11:36, 2026-09-10 11:05/11:16. Current gaps remain. |
| Preserve equal-length PDF-null recovery and honest extraction errors. | Log 2026-09-09 00:20/00:24/02:11; sanitizer/structured result/permanent fixture. |
| Preserve teacher list/stream performance and narrow-phone work. | Log 2026-09-08 23:00/23:22/23:38; cached streams, list keys/repaint boundaries, keep-alive tabs, progress throttling, profile/logout. |
| Preserve navy/lavender visual language. | Log PROJECT DECISIONS: #1A237E, #F3F0FF → #EFF6FF, #FBF9F8; later sessions add 14dp cards and 360/320dp responsiveness. |
| OCR for scanned/image-only PDFs is out of Phase 1 scope. | Log KNOWN ISSUES; neither extractor implements OCR. |

Other recorded limitations: KNOWN ISSUES reports historical npm `UNABLE_TO_VERIFY_LEAF_SIGNATURE`; this pass did not reproduce it or change TLS settings. It still says Google Sign-In is deferred, whereas the later 2026-09-10 06:45 session/current code implement it. Console readiness remains unknown. IN PROGRESS/BLOCKED say none; that does not supersede the findings below.

## 6. Gaps or inconsistencies

### Integration and access control

1. **Database split.** Flutter requests `default`; Node uses `admin.firestore()` without naming it. Log distinguishes it from `(default)`, while plan calls it “Default Database” and firebase.json does not select the named database for rules. Backend work may therefore use a different database. Deployment was not inspected.
2. **Security checklist overstates enforcement.** Log claims cross-class denial, teacher-only management, hidden Actual keys, and server deadline rejection. Actual rules broadly permit signed-in access, including Actual keys/other attempts/profiles, arbitrary class/material/quiz updates, and non-enrolled Storage reads. Client filtering is not an access boundary.
3. **HTTP auth bypass.** `generateQuizHttp` accepts teacherId without a token; both exports lack role/ownership checks. This is an exposure if deployed, not proof of a reachable endpoint.
4. **Registration role hole.** `registerWithEmail` recovery can overwrite an existing authenticated account's role/name/creation metadata with requested values, unlike login mismatch protection. Own-profile rules also permit role edits; missing-profile login creates requested role.
5. **No global route guard.** Plan's route labels are not middleware. `authStateChanges` is unused by widgets, dashboard constructors do not enforce role, and most action guards require only Auth UID.

### Generation and materials

6. **Actual → Practice linkage unwired.** Independent UI actions supply no sourceQuizId; client generateQuiz never passes reference context. Different fallback wording is not an enforced cross-quiz distinction. Server supports reference context only when explicitly supplied.
7. **Gemini ignores selected type list in its prompt.** Flutter `_callGeminiSingleBatch` accepts questionTypes but never interpolates it; JS computes unused typesDesc. Prompts enumerate all five schema types and validators do not reject unselected types. Fallback does use selections.
8. **Grounding/count guarantees incomplete.** Flutter fallback adds biology/computing samples below eight clean sentences and always adds mixed-domain distractors; JS substitutes biology below five and pads biology terms. Enumeration may use generic terms. Finite generation/backfill can return fewer than requested with no final exact-count rejection. This conflicts with “100% grounded” and guaranteed counts.
9. **Validation weaker than prompts.** Client dedup accepts ≥2 MCQ options, answer substring matches, three-underscore blanks and up to three-word answers. Publish/finalize lacks blank placement/word-limit, filler/header, and duplicate checks. JS lacks Flutter Jaccard logic. JSON MIME is not a supplied enforced JSON response schema.
10. **Gemini model drift.** Plan/log summary says 1.5 Flash; local/template config says `gemini-3.6-flash`; Node hardcodes `gemini-1.5-flash`. Availability/key restrictions/quotas are unverified. Direct requests set Content-Type only; documented console restrictions are not established by code.
11. **Office preview can override successful local extraction.** Pending Office gets re-extracted server-side; parsing failure changes ready material to failed and prevents conversion. This contradicts the protected separation. Early return fully skips only PDF/already-converted Office.
12. **Upload/trigger race.** Storage begins before client material set. A fast trigger can create/modify partial data, then the non-merge client set can overwrite conversion/text fields; server can likewise overwrite client readiness. Initial client upload omits extractedAt, and PDF early return never backfills it. The race applies if both writers reach the same database.
13. **Instant/offline/nonblocking claims are conditional.** Material/quiz Firestore sets and fast-path URL retrieval/update have no explicit deadlines; Storage getData also lacks an explicit timeout. Parsing uses the UI isolate. Background timeout does not cancel upload. Office can remain pending if upload/trigger/Drive never succeeds. Historical timing claims are not runtime bounds.
14. **Header delimiters can disappear before filtering.** `DocumentTextExtractor._cleanText` collapses tabs/multiple spaces before the filter that uses those delimiters for some header detection; standalone helper tests do not prove full-pipeline handling.
15. **Manual/full editing incomplete.** Log checks Actual manual creation, but no manual-create path/writer exists. `_editQuestion` edits prompt/correctAnswer only, not options/enumeration arrays/explanation/points/type. Enumeration can keep an old scoring array after answer-string edits. Print accepts either quiz type/status; published questions lack versioning.

### Attempts, results, and enrollment

16. **Publish and assignment are separate.** Publication changes only quiz status; monitoring lazily creates assignments, absence means available. Duplicates are possible; unordered limit(1) lookup and newest-first student assignment stream can choose different controlling records.
17. **Results do not prove saved submission.** Results/draft clearing happen before save finishes; deadline/limit/persistence failures are debug-only. There is no server scoring.
18. **Limits/deadlines not authoritative.** Client reads followed by writes can race, allowing concurrent excess attempts or closure between check/save. Rules do not enforce limits/deadlines; service does not check published Practice type, membership, complete answers, or assignmentId consistency.
19. **Draft cleanup/resume incomplete.** PopScope/dispose unconditionally save after clear, recreating submitted drafts. Cache is per instance and cannot survive restart/new service when Firestore fails. No lifecycle observer saves pending enumeration on backgrounding; queue/flags/position are not saved. Draft test reuses one injected service and checks clearing before exiting results.
20. **Typed final enumeration can leave Submit disabled.** Enumeration input has no onChanged committing text; enabled state reads saved answers before _saveCurrentAnswer. With no committed item, merely typing on the final question requires Add/keyboard submit or another navigation action despite auto-commit intent.
21. **Past-results/history UI incomplete.** Closed/expired branch hides saved review; open review selects first unsorted attempt with no full-history selector. Teacher monitoring uses latest per student. TeacherResultsScreen is unreferenced legacy placeholder content, not the working monitoring screen.
22. **Deletion not a full cascade.** Quiz deletion leaves assignments/attempts/drafts. Material deletion unlinks retained quizzes and may leave dangling sourceQuizId; cleanup errors are swallowed. Removing a published quiz also removes the student's main route to its retained attempts.
23. **Enrollment uniqueness/counters best effort.** Code generation uses query-then-create; timestamp fallback is unchecked and not guaranteed four characters. Concurrent joins can pass duplicate checks and increment count twice. Member records are roster authority; joined-class fallback snapshots may outlive root classes.

### Documentation and verification

24. **Schema drift.** Plan lists stored IDs that serializers omit, TXT upload (extractor-only support), camelCase stored types, archived quiz status, resultSummary instead of breakdown, wrong draft ID/fields, and omits sourceQuizId/publishedAt/other fields. Log lists wrong joinedClasses snapshot keys. Section 2 is the actual code schema.
25. **Historical summaries conflict.** Google Sign-In is implemented despite deferred KNOWN ISSUES. Early token-refresh/retry claims were superseded by concurrent writes/four-second timeout. Plan attributes cleanFillInTheBlankAnswer to ScoringUtils; it is in QuizService. Preview log says 100 MB retrieval; current service uses 50 MiB. Phase I/J names differ between plan/log; CURRENT STATUS, standalone NEXT TASK, and test counts are not mutually current.
26. **Tests do not establish deployed integration.** `test/week11_core_journey_integration_test.dart` simulates models/helpers, not live teacher/student Firebase traffic. AssignmentService defaults Firestore off under FLUTTER_TEST, bypassing submission checks/persistence. Draft test explicitly uses useFirestore:false. `test/pdf_upload_optimization_test.dart` tests MIME mapping, local extraction time, fallback, and validation, not real Storage/Firestore/Functions timing. Plan's 68/68 is ten selected suites, not all 23 current test files. No rule-emulator integration suite was found. Historical “production-ready”/passing counts are not evidence for these untested paths.

All findings remain documentation-only. Deployed databases/rules/functions, billing tier, OAuth enablement, Drive permissions, Gemini availability, network performance, and the current full test result remain explicitly unresolved by this repository-only pass.
