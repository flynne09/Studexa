# Studexa API and Device Integration Report

Implementation/deployment verified on 2026-09-11; final evidence review completed on 2026-09-12 against the current working tree. This report distinguishes source inspection, automated tests, real provider calls, and deployed application verification. The initial local pass made no production changes. After explicit user confirmation, Secret Manager version 1, all three existing functions and named-database rules were deployed on 2026-09-11. Production verification uses isolated temporary accounts and documents; its results and cleanup are recorded below. Existing UI, navigation, document extraction, scoring conventions, and icons were preserved; no packages were added.

## A. Integrations Found

“WORKING” below is scoped to the evidence stated, not a claim that every platform or production account has been exercised.

| Integration and packages | Classification after changes | Implementation and evidence |
| --- | --- | --- |
| Firebase initialization: `firebase_core` | WORKING: web startup verified | `lib/main.dart`, `lib/firebase_options.dart`; release web rendered role selection in Chrome with no uncaught exceptions. Initialization failures show retry UI. |
| Email/password Auth: `firebase_auth` | WORKING: production Auth REST and automated tests | `AuthService.registerWithEmail`, `signInWithEmail`, `signOut`, `getCurrentUserProfile`; emulator and production REST signup/login/profile checks passed with temporary accounts. Splash restores Firebase session/profile and routes by role. Physical-device persistence/logout still need a walkthrough. |
| Google OAuth: `google_sign_in`, `firebase_auth` | PARTIALLY IMPLEMENTED | `AuthService.signInWithGoogle` and login/register actions exist. Successful production OAuth/consent/release signing configuration was not verified. Historical Week 11 deferral remains; Windows support is not established by a Windows scaffold. |
| Database: `cloud_firestore`, server `firebase-admin` | WORKING in production REST and emulators; rules deployed | `getAppFirestore()` targets the named database **`default`**, without parentheses. Live CLI inspection confirmed that database in `studexa-b5e55`. Classes, enrollment, materials, quizzes, assignments, attempts and drafts use Firestore. |
| System document selection: `file_picker` | PARTIALLY VERIFIED | `UploadGenerateQuizScreen` restricts selection to PDF/DOCX/PPTX, reads bytes/path and reports cancellation/errors. Validation and extraction tests pass and Android/web compile. Actual native picker interaction was not exercised without an Android device. |
| Local extraction: `syncfusion_flutter_pdf`, `archive`, Dart XML/text processing | WORKING in fixture tests | `DocumentTextExtractor` handles text PDFs, DOCX and PPTX. Regression includes presentation-exported PDF with null catalog entries. Empty/scanned/corrupt inputs have distinct failure paths. OCR is NOT REQUIRED for this Phase 1 scope. |
| Original file upload: `firebase_storage` | WORKING for live DOCX upload/download; native picker unverified | `MaterialService.uploadStudyMaterial` starts Storage upload alongside extraction, saves ready text to Firestore, and attaches the download URL in background. A production DOCX upload and byte-for-byte download passed with a temporary teacher account; its Storage object and Firebase records were subsequently deleted. Failure does not prevent generation from already saved text. |
| Quiz HTTP API: Dart `http`, Firebase HTTPS function, Node native `fetch`, Gemini | WORKING: deployed endpoint, real Gemini and production Firestore | `QuizGenerationClient.generate` → `generateQuizHttp` → `processQuizGeneration` → `generateQuizQuestions`. Authenticated emulator and production calls generated and persisted Actual 10 and Practice 10 questions with an Actual reference; neither live-generation run used a mock provider. |
| Quiz/result/history persistence | WORKING in production REST, emulator and widget tests | `QuizService`, `AssignmentService`, `AnswerQuizScreen`, `QuizMonitoringScreen`; published Practice access, ownership, saved attempts and teacher/student history reads verified. Results wait for save acknowledgement. Whole signed-in release UI journey remains unverified. |
| PDF viewing/export and device printing: `syncfusion_flutter_pdfviewer`, `pdf`, `printing` | WORKING in automated tests; native print unverified | `MaterialViewerScreen`, `PdfExportService`, `QuizDetailScreen`; PDF generation/widget tests pass. Actual exams remain printable teacher reference material. No printer/device print dialog tested. |
| Temporary files/external document viewer: `path_provider`, `open_filex` | PARTIALLY VERIFIED | `MaterialService` uses app-private temporary files; viewer launches external Office apps where available and offers extracted text. Device app availability and launch were not tested. |
| Optional server extraction/Office preview: `pdf-parse`, `mammoth`, `officeparser`, `googleapis` | PARTIALLY IMPLEMENTED: live extraction passed; Office preview failed | `extractText` extracted 1,005 characters from the uploaded DOCX and wrote a server timestamp to named Firestore. `convertOfficeToPdf` finished with conversionStatus failed. Ready PDFs short-circuit extraction; Office files short-circuit only when ready text and a completed conversion already exist. |
| Local state/persistence | WORKING within tested scope | `AssignmentService` maintains in-memory draft cache plus Firestore draft documents; Firebase SDK manages auth/cache behavior. No SQLite/Hive/shared_preferences integration was found or added. |
| Camera, GPS, sensors, push notifications | NOT REQUIRED | No dependency or application flow requires these capabilities. No permissions or packages added for them. |

Cloud Functions inventory (all in `functions/index.js`):

| Export | Trigger / configured region | Calls |
| --- | --- | --- |
| `generateQuizHttp` | HTTPS POST, `us-central1` default, CORS enabled, 180-second function timeout | Firebase Auth token verification; Admin Firestore ownership/material reads and quiz save; Gemini via `quiz_generator.js`; Secret Manager `GEMINI_API_KEY`. |
| `generateQuiz` | Authenticated callable v2, `us-central1` default, 180 seconds | Same `processQuizGeneration` and server secret; retained existing endpoint. Flutter currently uses the HTTP export. |
| `extractText` | Storage object-finalized v2, explicitly `us-east1`, 300 seconds | Storage download/upload, Admin Firestore status/text/preview writes, PDF/DOCX/PPTX parsers, optional Google Drive import/export and cleanup. Ignores generated preview files. Region matches the existing live function. |

## B. Problems Found

The initial source review found concrete breaks in the intended integration:

1. Gemini was called from Flutter using an ignored but hardcoded Dart key. Ignoring a file does not prevent embedding its contents in an application build. Old docs incorrectly treated client restrictions as removal of the secret.
2. Client generation could return fallback/backfilled academic questions after AI failure; selected question types were not reliably included in the API request. Partial/invalid responses could appear successful. Some fallback content was unrelated to the uploaded material.
3. Backend code defaulted to `(default)` while the app/live project used `default`. The HTTP endpoint also accepted body-supplied teacher identity without a valid Firebase token.
4. A real Gemini success then exposed another backend fault: the running Functions process could not resolve `admin.firestore.FieldValue.serverTimestamp`. Quiz saving failed after generation. Explicit modular `FieldValue` imports corrected this; the real handler → Gemini → Firestore sequence subsequently passed.
5. Student results were displayed before Firestore submission completed. Failed writes could lose the working answers, rapid retries could create duplicate records, and disposal could recreate cleared drafts. Assignment IDs were not always resolved into saved results.
6. Interrupted-registration recovery could overwrite an existing profile/role. Startup/profile failures could route as if signed out rather than identify a retryable service error.
7. Material byte buffers and required fields needed validation; database/URL/download operations could stall. Extracted-text-only viewer startup unnecessarily initiated preview work.
8. Android release lacked an explicit Internet permission. APK inspection additionally found four unnecessary storage/media permissions merged from `open_filex`.
9. Original Firestore access was broader than the documented isolation. New published-Practice queries and atomic enrollment writes were needed to work with tightened rules. A follow-up on 2026-09-12 found that the teacher class-only quiz query was incorrectly denied by those rules; the deployed correction authorizes the class owner, and the teacher screen now distinguishes query errors from an empty list.
10. Old docs described Gemini 1.5/direct client calls, blanket Spark-only assumptions and earlier test counts as current. Those claims now have explicit superseding notes.

Remaining limitations are not disguised as completed features:

- **Deployment completed on 2026-09-11.** The existing public URL now serves the updated authenticated backend and server secret. The new rules require the rebuilt client for atomic enrollment and published-Practice queries.
- Gemini returned several real HTTP 503 high-demand responses before the final successful run. One bounded retry is implemented; service capacity is outside the application. Live 30/50-question generation was not verified. Exact count validation tests cover those counts with explicit fixtures.
- Source-excerpt and answer-term checks reject unsupported text, but do not prove every question is pedagogically correct or every True/False inference is sound. Teacher review remains necessary. Duplicate validation rejects normalized identical stems, not all semantic paraphrases.
- Roles are selected during initial registration; there is no institutional teacher approval system. Scores, deadlines and the two-attempt limit are still client-enforced. Published Practice documents contain answer keys. These academic MVP choices are not secure server-side exam grading.
- Class documents remain discoverable to signed-in users for join-code lookup. Membership rules are not a cryptographic join-code gate; a modified client knowing a class ID can request membership. Existing Storage reads allow **any authenticated user**, despite an older comment implying enrollment-only access. Storage rules were not changed.
- A timed-out Firestore operation may later complete; stable attempt IDs prevent duplicate documents, but an acknowledged-late attempt may need to be reopened from history rather than resubmitted. Draft persistence remains best-effort with an in-memory fallback.
- Exactly 50 MiB passes the client size check while existing Storage rules require less than 50 MiB. Optional original upload can fail at that boundary; extracted text can still be used.
- Optional Office-to-PDF preview failed in the production DOCX check, while extraction remained ready with 1,005 characters. The Drive API is enabled. Scoped log searches ultimately returned HTTP 200 with no matching entries (an earlier lookup hit HTTP 429), so the underlying conversion error could not be established and is not guessed. Original-file download and extracted-text viewing remain available. Scanned/image-only PDFs require a different document because OCR is out of scope.
- Android device selection/opening/printing, Google OAuth, production session persistence, iOS compilation and the full signed-in production journey remain unverified. Windows build is blocked by host symlink support. Existing Android release configuration uses development signing, not store-release signing.

## C. Changes Made

All versioned files added or modified for this integration pass:

| File | Change |
| --- | --- |
| `.gitignore` | Ignore local secret/environment/service-account files. |
| `android/app/src/main/AndroidManifest.xml` | Add Internet permission; remove imported READ_EXTERNAL_STORAGE and READ_MEDIA_IMAGES/VIDEO/AUDIO through manifest merger directives. |
| `firebase.json` | Target named Firestore database `default`. |
| `firebase.emulators.json` (new) | Separate disposable demo Auth/Firestore/Functions emulator configuration. |
| `firestore.rules` | Profile role immutability, ownership/membership boundaries, published Practice access, atomic enrollment roster increment, own/teacher attempt access, create-only results; follow-up adds class-owner reads so teacher class-only quiz queries work. |
| `functions/index.js` | Require verified identity and ownership, bind server secret, use named database and modular timestamps, persist validated API questions, remove runtime fallback from generation, map safe errors, pin existing extraction region. |
| `functions/quiz_generator.js` (new) | Gemini request/schema, source grounding, exact count/types, shape/answer validation, safe errors, 90-second provider deadline and one transient retry. |
| `functions/test/quiz_generator.test.js` (new) | 11 API-boundary tests with explicit transport fixtures. |
| `functions/test/firebase_integration.js` (new) | Disposable Auth/Firestore checks; optional real-provider generation and explicitly separate handler-fixture mode. Never points at production Firebase. |
| `lib/config/integration_config.dart` (new) | Public HTTPS endpoint configuration through `QUIZ_GENERATION_URL`; no private key. |
| `lib/config/gemini_config.template.dart` | Replace obsolete client-key instructions with server configuration guidance. |
| `lib/services/quiz_generation_client.dart` (new) | Firebase bearer token, canonical request types, safe endpoint validation, bounded request, response validation and friendly errors. |
| `lib/services/quiz_service.dart` | Delegate generation to server client; add published-only query option; retain historical offline helpers outside runtime generation. |
| `lib/services/auth_service.dart` | Guard existing profiles during registration recovery; validate roles, bound profile operations and surface failures. |
| `lib/services/class_service.dart` | Commit membership/joined-class/roster increment atomically. |
| `lib/services/material_service.dart` | Validate resolved bytes and names, bound database/file requests, keep Storage URL work in background and persist extraction timestamps. |
| `lib/services/assignment_service.dart` | Await bounded result write with stable ID and resolved assignment; sort history newest first. |
| `lib/main.dart` | Retryable Firebase initialization error screen. |
| `lib/screens/splash_screen.dart` | Guard navigation and expose retry on session/profile lookup failure. |
| `lib/screens/materials/material_viewer_screen.dart` | Start preview download only when the preview is requested. |
| `lib/screens/teacher/teacher_class_details_screen.dart` | Follow-up: show quiz stream errors with Retry instead of an incorrect empty state; injectable quiz stream for regression tests. |
| `lib/screens/teacher/upload_generate_quiz_screen.dart` | Link Practice generation to the Actual quiz for the same material in the current upload session. |
| `lib/screens/student/answer_quiz_screen.dart` | Saving state, retained answers on failure, clear drafts after acknowledgement, prevent draft resurrection/repeated submit, exact choice grading, pending enumeration commit, no empty-quiz demo substitution. |
| `lib/screens/student/student_class_details_screen.dart` | Query only published Practice and allow completed-result review after closure/deadline. |
| `test/quiz_generation_client_test.dart` (new) | 13 authentication/transport/response/error contract tests. |
| `test/quiz_submission_integration_test.dart` (new) | Two widget tests for pending/successful/failed persistence and draft lifecycle using explicit test doubles. |
| `test/teacher_performance_test.dart` | Follow-up: verify teacher Actual-draft/Practice display and load-error UI. |
| `test/quiz_test.dart` | Remove obsolete direct-key/no-key fallback test; other historical helper tests remain. |
| `docs/IMPLEMENTATION_PLAN.md` | Update current architecture and mark prior milestone descriptions/test counts as historical. |
| `docs/IMPLEMENTATION_LOG.md` | Separate per-task SESSION HISTORY entries, current status, evidence and remaining steps. |
| `docs/INTEGRATION_REPORT.md` (new) | This A-F review and reproducible verification/configuration record. |

Ignored local changes: existing Gemini value moved to `functions/.secret.local`; `lib/config/gemini_config.dart` now contains comments without the value. Build/test evidence and Chrome temporary profile are under ignored `build/integration-evidence/`. No credentials are reproduced in this report. `pubspec.yaml`, lockfiles, icons, Storage rules and extraction algorithm were not modified.

## D. Integration Flow

1. `main` initializes Firebase. `SplashScreen` resolves the current session and `users/{uid}` through `AuthService`; Teacher/Student routes use the saved role. Missing accounts register through Firebase Auth and save their profile. Existing role mismatches sign out instead of changing the role.
2. Teacher creates a class through `ClassService`. Student enters its join code; `joinClassByCode` finds the active class and atomically creates membership, the user's joined-class record and roster increment.
3. Teacher opens `UploadGenerateQuizScreen`, selects PDF/DOCX/PPTX with the system picker, and chooses the class. `MaterialService.uploadStudyMaterial` validates actual bytes and starts extraction plus optional Storage upload. `DocumentTextExtractor` returns meaningful text or an explicit format/empty/corrupt error. A successful `materials/{id}` write makes the material ready; generation does not wait for the original upload URL.
4. Teacher selects count (1–50) and types. UI supports Multiple Choice, True/False, Identification, Fill-in-the-Blank and Enumeration. `QuizService.generateQuiz` calls `QuizGenerationClient.generate`, which posts IDs/types/count and optional Actual reference with a Firebase ID token. The app sends neither the Gemini key nor a trusted teacher identity.
5. `generateQuizHttp` verifies the token. `processQuizGeneration` checks profile role, class/material ownership, readiness, source length and reference ownership in named database `default`. It reads the saved material text itself. Text above 400,000 characters is explicitly rejected rather than silently truncated.
6. `generateQuizQuestions` sends the source as data to Gemini with selected types, exact count and JSON schema. It validates every returned question, choices/answers, distinct stems, source excerpts and representation of each selected type. Invalid output fails without backfilling. Valid questions are saved as a draft quiz with `generationMethod: 'gemini'` and server timestamps, then returned to Flutter for display.
7. Actual is teacher-only exam/reference content, available for review/finalization/PDF export. Practice generated afterward in the same upload session receives that Actual quiz ID if the material matches. The teacher reviews/publishes Practice through `QuizService`; optional assignment/deadline controls use `AssignmentService`. Students query only published Practice in their class.
8. `AnswerQuizScreen` presents questions, preserves skip/requeue, restores per-attempt drafts and allows at most two attempts through the existing client checks. Choice answers use normalized exact matching; free text and enumeration retain `ScoringUtils` typo tolerance/partial credit.
9. Submit enters a saving state and awaits `AssignmentService.submitAttempt`. It checks assignment availability/attempt count and saves answers, score, breakdown and assignment ID to a stable `attempts/{id}`. Only acknowledged success clears the draft and displays results. Failure leaves answers available and displays an error.
10. Student class history and teacher monitoring read the saved attempts through Firestore streams. Results remain reviewable after a quiz is closed; new submissions are blocked by the existing client availability checks.

## E. Testing Results and Configuration

| Check actually performed | Result / scope |
| --- | --- |
| `flutter pub get` | Passed; no new dependencies or lockfile changes. Flutter 3.47.3 / Dart 3.13.3 on this host. |
| `flutter analyze` | Passed with no issues after Dart changes. |
| `flutter test --concurrency=1 --reporter expanded` | **167/167 passed.** Includes real document fixtures, scoring, navigation and explicit service/widget test doubles. Earlier parallel test run exposed a preview timer issue (fixed) and PDF timing contention under build load; unchanged timing assertion passed serially. |
| `node --check functions/index.js` and generator/test syntax checks | Passed. |
| `node --test functions/test/quiz_generator.test.js` | **11/11 passed.** Includes 10/30/50 exact-count fixtures, invalid responses, selected types, credentials, quota, network and timeout errors. These fixtures are not proof of live Gemini output. |
| Auth/Firestore emulator script without generation | **32 checks passed**: registration/login, profiles, class join, ownership/access, history and drafts. |
| Emulator script `--backend-fixture` | **38 checks passed** including actual HTTP handler, Auth token verification, Admin Firestore persistence and Actual reference; explicit Gemini fixture, not live API proof. |
| Emulator script `--generate` after timestamp fix | **38 checks passed with real Gemini**: unauthorized request denied, student denied generation, teacher Actual 10 questions generated/saved/read, Practice 10 generated/saved with Actual reference. Firebase was emulated; Gemini was live. |
| Earlier standalone live Gemini call | 10 valid Multiple Choice/True-False/Identification questions, source excerpts validated. Subsequent failures included provider 503 high demand; final handler run succeeded after the timestamp repair. |
| Authorized production deployment | Secret Manager version 1 created; generateQuizHttp/us-central1, generateQuiz/us-central1 and extractText/us-east1 updated; named-database rules published. Post-deployment artifact-policy warning described below. |
| Production REST integration check | **12 check groups passed**: cleanup authority, unauthenticated teacherId denial, teacher/student signup/login/profiles, immutable role, create/join class, save/read material, student generation denial, Actual 10 generation/persistence/denial, Practice 10 generation/publish/query, assignment/result/history access and duplicate denial, draft save/clear. Used real Firebase and Gemini. Temporary records and both accounts deleted; each tracked Firestore document read back as 404. |
| Production Storage/trigger check | **4 check groups passed**: temporary teacher Auth/profile, DOCX upload, byte-for-byte download, deployed DOCX extraction plus named-database timestamp. Extracted 1,005 characters. Optional Office preview returned failed and is not included among passed checks. Object/profile/class/material removed, document/object reads verified absent; separate Auth lookup found zero remaining accounts across all three test users. |
| Teacher visibility correction (2026-09-12) | Prior teacher classId-only query reproduced HTTP 403. Corrected rules passed **36 emulator checks**, **18 targeted Flutter tests**, clean analyzer and **8 production check groups**, including unrelated-teacher/student denials. Rules-only deployment succeeded; temporary Firebase resources removed. Prior main-flow tests did not cover this query. |
| Firestore deployment dry-run | `firebase deploy --only firestore:rules --project studexa-b5e55 --dry-run --non-interactive --json` passed. Did not publish rules. |
| Android release | `flutter build apk --release` passed; final APK **70.6 MB**, `build/app/outputs/flutter-apk/app-release.apk`. Final AAPT inspection confirms Internet access and no broad storage/media permissions. No connected Android device/emulator for installation/picker checks. This APK predates the teacher Retry UI addition; the server-side visibility correction applies immediately to its existing query. |
| Web release and run | `flutter build web --release` passed, output `build/web`. Served locally in installed headless Chrome; role selection rendered, one Flutter view, no uncaught JS exceptions. Screenshot inspected. No signed-in production UI actions performed. |
| Windows release | Attempted; blocked by host symlink support / Developer Mode. Host settings were not changed. |
| iOS | Not compiled: Windows host has no Xcode/macOS. |
| Secret scan | Current Dart files, web output and decompressed final APK contain no occurrence of the locally configured Gemini secret. Firebase public client configuration remains intentionally present. |

Evidence files in ignored `build/integration-evidence/`: `flutter-tests-serial.log`, `flutter-analyze.log`, `android-build-final.log`, `web-build-final.log`, `windows-build.log`, `rules-dry-run.log`, `firebase-backend-final.log`, `gemini-live.json`, `emulated-backend-live-gemini.json`, `web-smoke.json`, `web-startup.png`. Production evidence additionally includes production-deployment.log, secret-deployment.log, production-verification.log/.json, storage-verification.log/.json and storage-trigger-check.json. These are local artifacts, not committed test fixtures. The full 38-check live run exited successfully. Local Functions tests used host Node 25; production redeployment succeeded using the existing Node 20 runtime.

### Secure configuration and completed deployment

- The existing key is already in ignored `functions/.secret.local` as `GEMINI_API_KEY=<real value>` for emulator use. Do not place it in Dart, assets, `--dart-define`, tracked JSON, screenshots or commits. Do not paste it into the report.
- Production Secret Manager version 1 and the three existing functions were deployed after user confirmation. Firebase documents explicit function bindings in [Configure your environment](https://firebase.google.com/docs/functions/config-env). The following commands describe the completed setup and future redeployment; the private value was passed through a temporary ignored file and removed immediately:

```powershell
firebase functions:secrets:set GEMINI_API_KEY --project studexa-b5e55
firebase deploy --only "functions:generateQuizHttp,functions:generateQuiz,functions:extractText,firestore:rules" --project studexa-b5e55
```

- `firebase.json` selects database `default`; `extractText` is pinned to its current `us-east1` region. The stricter rules require the updated published-Practice query and atomic enrollment client, so deployment must be coordinated with updated builds. No deletion/migration of existing data is required by these changes.
- The Flutter public endpoint defaults to `https://us-central1-studexa-b5e55.cloudfunctions.net/generateQuizHttp`. `QUIZ_GENERATION_URL` may override an HTTPS backend URL, never a key. The production client intentionally rejects plain HTTP; the emulator integration script tests local HTTP separately and does not change release configuration.
- The default server model is `gemini-3.6-flash`; optional server environment `GEMINI_MODEL` changes it. A tested `gemini-2.5-flash` request returned model-unavailable 404 despite its appearance in the model list, so availability must be checked by an actual generation request. No alternate model was silently selected after 503 errors.
- Firebase public application identifiers/API keys are distinct from the private Gemini key; see [Firebase API keys](https://firebase.google.com/docs/projects/api-keys). No service-account private key is needed in Flutter.
- For this host's trusted proxy, use `NODE_USE_SYSTEM_CA=1`; keep TLS verification enabled and clear `DEBUG` when running CLI verification. Emulators require Java 21 here (available in Android Studio's `jbr`). Windows builds additionally require host symlink support.
- Document selection uses Android's user-mediated file access, which does not require broad system storage permissions: [Android Storage Access Framework](https://developer.android.com/training/data-storage/shared/documents-files). Native file picking still needs a physical-device/emulator walkthrough.

Reproduce disposable checks from the repo root with the existing installed tools:

```powershell
firebase emulators:exec --only "auth,firestore" --project demo-studexa --config firebase.emulators.json "node functions/test/firebase_integration.js"
firebase emulators:exec --only "auth,firestore" --project demo-studexa --config firebase.emulators.json "node functions/test/firebase_integration.js --backend-fixture"
firebase emulators:exec --only "auth,firestore,functions" --project demo-studexa --config firebase.emulators.json "node functions/test/firebase_integration.js --generate"
```

The last command uses the real Gemini key/provider and may consume quota. These three reproducible commands confine Firebase accounts/documents to `demo-studexa` emulators. The separately authorized one-off production scripts created isolated temporary Firebase resources and removed them; they live only under ignored build/integration-evidence and are not default tests.

The remaining native application demonstration is: install the APK → register/login Teacher and Student → create/join class → pick a text PDF and a DOCX → generate selected counts/types → review Actual and publish Practice → answer and submit → reload student history and teacher monitoring → sign out/in to verify session/data recovery. Also test an unsupported/scanned document and a network failure. No test doubles should replace services during that demonstration.

## F. Rubric Verification

**API or device feature integration complete:** The core API/backend integration is implemented, deployed and verified with real Firebase Auth, named Firestore, Storage DOCX upload/download/extraction, and Gemini. Optional Office-to-PDF preview remains unsuccessful. Production checks demonstrated Actual/Practice generation, publication, and result/history persistence with temporary accounts. Native file-picker interaction and a full signed-in release UI journey remain unverified; the REST check is not presented as a physical-device walkthrough.

**Integrated application build demonstrating successful API/device functionality:** Android and web release builds exist; web startup was run successfully, and the configured production endpoint now passes the real-service integration check. These provide build and live API evidence. A single released application session demonstrating login, native file selection, generation, client-side scoring and history has not been completed and is not claimed. Install the current APK for the remaining device demonstration. Production test scores were explicit persistence inputs, not a substitute for executing Flutter scoring; scoring is covered by the automated Flutter suite.

Deployment operations note: all three function updates and Firestore rule publication succeeded. The CLI then exited 1 because us-east1 lacked an Artifact Registry cleanup policy; it explicitly reported successful deployment. Existing artifact retention was not changed. Firebase explains these policies under [Manage functions](https://firebase.google.com/docs/functions/manage-functions). Node 20 remains the reviewed runtime, but its decommission date is 2026-10-30; migrate before then to keep redeployment available. See the [Cloud Run functions runtime schedule](https://docs.cloud.google.com/functions/docs/runtime-support).

Teacher visibility follow-up evidence: teacher-quizzes-before.log, teacher-quizzes-after.log, teacher-quiz-widget-tests.log, teacher-quiz-analyze.log, teacher-quiz-rules-deploy.log and teacher-visibility-production.log/.json under ignored build/integration-evidence. The current query fix requires no client rebuild; existing failed listeners should be restarted by leaving/reopening the class. The new Retry/error presentation requires hot restart or a rebuilt client.
