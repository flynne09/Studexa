# Studexa Project Understanding

Snapshot: 2026-09-27. This document describes the current working tree and the
Supabase-only beta runtime. The encrypted recovery archive was verified before
the clean beta cutover. Firebase Auth, Firestore, and Storage data are zero and
their deployed rules are deny-all. Supabase Auth, application tables, private
Teacher credential/allowance records, and `study-materials` objects were also
verified at zero after the reset. The verified Android release was then installed
on a physical phone; native Google sign-in created the first real beta Teacher
account/profile. All application tables, private Gemini state, and Storage
objects remain zero after disposable live verification. Historical Firebase code remains under
`functions/` because Google blocks Function deletion without project billing;
the updated Flutter application has no Firebase dependency or call path.

## 1. Project structure

### Runtime architecture

`lib/main.dart` initializes `Supabase` and opens `SplashScreen`. The Flutter
screens use service objects plus `StreamBuilder`/subscriptions; the services
query Postgres through `supabase_flutter` and refresh on Supabase Realtime
events. Authentication is Supabase Auth, original files use private Supabase
Storage, personal Gemini keys use Supabase Vault, and sensitive generation and
scoring run in Supabase Edge Functions.

Android is the required release target. Existing `ios/`, `web/`, and `windows/`
scaffolds remain. Android and iOS register the native email-confirmation callback
`com.example.studexa://login-callback/`. `google_sign_in` supplies native Google
account selection and exchanges Google tokens for a Supabase session.

### Screens

| File | Main responsibility |
|---|---|
| `lib/screens/splash_screen.dart` | Restore the Supabase session/profile and route to role selection, Teacher Home, or Student Home. |
| `lib/screens/auth/role_selection_screen.dart` | Choose Teacher or Student before login/registration. |
| `lib/screens/auth/login_screen.dart` | Email/password or native Google login while enforcing the selected role. |
| `lib/screens/auth/register_screen.dart` | Register email/password with immutable role metadata and explain email confirmation. |
| `lib/screens/teacher/teacher_home_screen.dart` | Stream owned classes, expose account actions, create classes, and open Teacher workflows. |
| `lib/screens/teacher/teacher_class_details_screen.dart` | Show a Teacher's roster, materials, quizzes, assignments, and class actions. |
| `lib/screens/teacher/upload_generate_quiz_screen.dart` | Upload/extract a material, select quiz settings, and coordinate Actual then Practice generation. |
| `lib/screens/teacher/quiz_detail_screen.dart` | Review a draft/final quiz, add manual questions, Generate More, publish, assign, and export. |
| `lib/screens/teacher/manual_question_dialog.dart` | Validate and construct one Teacher-authored question of any supported type. |
| `lib/screens/teacher/quiz_monitoring_screen.dart` | Monitor assignment state and Student submissions. |
| `lib/screens/teacher/teacher_results_screen.dart` | Display class/quiz attempt results and summary metrics. |
| `lib/screens/teacher/gemini_api_settings_screen.dart` | Guide Teachers through Google AI Studio and manage a masked personal Gemini key. |
| `lib/screens/student/student_home_screen.dart` | Stream joined classes and expose the Student account menu/join action. |
| `lib/screens/student/join_class_screen.dart` | Validate an uppercase join code and invoke atomic enrollment. |
| `lib/screens/student/student_class_details_screen.dart` | Show class material, published Practice quizzes, assignments, and prior attempts. |
| `lib/screens/student/answer_quiz_screen.dart` | Restore/save a draft, navigate questions, submit to server scoring, and show results. |
| `lib/screens/materials/material_viewer_screen.dart` | Render PDFs or download/open authenticated DOCX/PPTX originals in a compatible app. |

### Services and utilities

| File | Main responsibility |
|---|---|
| `lib/services/auth_service.dart` | Supabase signup/login/logout/session profile handling, Google token exchange, and immutable role claim. |
| `lib/services/class_service.dart` | Class/create/join RPC calls plus class and roster Postgres/Realtime streams. |
| `lib/services/material_service.dart` | Validate, extract, upload, stream, download/cache, and delete private study material. |
| `lib/services/quiz_service.dart` | Stream/save/update quizzes, publish/finalize drafts, append manual questions, and local validation helpers. |
| `lib/services/quiz_generation_client.dart` | Authenticate and coordinate bounded/idempotent `generate-quiz` requests. |
| `lib/services/teacher_gemini_key_service.dart` | Invoke Teacher key status/save/remove operations without retaining the complete key. |
| `lib/services/assignment_service.dart` | Stream assignments/attempts, persist Student drafts, invoke authoritative submission, and manage assignment state. |
| `lib/services/pdf_export_service.dart` | Generate/print/share Teacher quiz PDFs and optional answer keys locally. |
| `lib/utils/document_text_extractor.dart` | Extract readable text on-device from PDF, DOCX, and PPTX bytes. |
| `lib/utils/scoring_utils.dart` | Shared client presentation helpers for exact, tolerant, and enumeration scoring behavior. |
| `lib/config/supabase_config.dart` | Public Supabase URL/key, Google Web client ID, Storage bucket, and callback constants. |
| `lib/config/integration_config.dart` | Edge Function endpoint configuration. |
| `lib/config/gemini_config.template.dart` | Historical/local Gemini template; production credentials live server-side. |

### Models

| File | Main responsibility |
|---|---|
| `lib/models/user_profile.dart` | Provider-neutral authenticated user and Supabase profile/role records. |
| `lib/models/class_model.dart` | Class metadata, join code, status, roster count, and member snapshots. |
| `lib/models/material_model.dart` | Material file, Storage, extraction, conversion, and error state. |
| `lib/models/quiz_model.dart` | Actual/Practice quiz, questions, generation batching, source, and credential-use metadata. |
| `lib/models/quiz_assignment_model.dart` | Published quiz assignment, deadline, and open/closed state. |
| `lib/models/quiz_attempt_model.dart` | Student attempt number, answers, authoritative score, breakdown, and submission time. |

### Shared UI

`lib/theme/app_theme.dart` owns the navy/teal Material 3 palette. `app_feedback.dart`
shows consistent success/error feedback. `home_account_menu.dart` centralizes the
Teacher/Student profile and logout menu. `gemini_api_generation_guard.dart`
prompts for a personal key or temporary allowance. The remaining widgets supply
Google branding, backgrounds, and sign-in controls.

### Backend directories

- `supabase/migrations/` is the versioned schema, RLS, Storage policy, Vault,
  Realtime, credential lifecycle, applied clean-reset history, and explicit
  material-posting policy.
- `supabase/functions/` contains the three active Edge entry points and their
  shared Auth/PostgREST/Gemini/scoring modules.
- `supabase/tests/database_policy_test.sql` contains the 38-case pgTAP policy
  suite. `tool/run_linked_pgtap.mjs` runs it against the linked schema inside a
  forced-rollback transaction without requiring Docker.
- `functions/` contains the pre-migration Firebase Functions source. Updated
  APKs do not call it; deployed legacy endpoints remain until shutdown.
- `tool/` contains recovery export/encryption, live Supabase verification, and
  legacy cleanup utilities. These scripts accept temporary credentials at run
  time and do not embed them.

## 2. Data model

The authoritative schema is the ordered history under `supabase/migrations/`,
including the full backend, credential lifecycle, class-section, clean-reset,
and material-posting migrations. UUIDs use Supabase Auth identities.

### `profiles`

Fields: `id` (FK `auth.users`), `email`, `display_name`, nullable immutable
`role` (`teacher`/`student`), `photo_url`, `created_at`, `updated_at`.

- Written automatically by `handle_new_studexa_user`; role is set once by
  `claim_studexa_role`.
- Read by `AuthService`, Edge authorization, and account UI.
- RLS exposes only the caller's profile. Direct client role updates are not
  granted.

### `classes`

Fields: `id`, `teacher_id`, `name`, unique uppercase `join_code`, Teacher name,
`section`, `subject`, `status`, `roster_count`, `recent_quiz`, and timestamps.

- Created transactionally by `create_studexa_class` from `ClassService`.
- The Teacher enters a class name/subject and section. The RPC stores the
  entered section and copies the class name into `subject`.
- Updated/deleted only by the owner; readable by owner or member.
- Deleting the Teacher/Auth identity cascades the class and all descendants.

### `class_members`

Composite key: `(class_id, user_id)`. Other fields: role, display-name/email
snapshots, `joined_at`.

- Teacher membership is inserted with the class.
- Student membership is inserted by `join_studexa_class`.
- The roster trigger increments/decrements only Student memberships.
- Replaces Firestore class subcollection plus duplicated `joinedClasses` data.

### `materials`

Fields: UUID/Teacher/class, `file_name`, `file_type`, unique private `file_ref`,
Storage provider/bucket/upload state, legacy-compatible URL/conversion fields,
extraction `status`, `error_reason`, `extracted_text`, `is_posted`, `posted_at`,
size, and timestamps.

- `MaterialService` writes and streams rows and uploads originals to
  `study-materials/uploads/{uid}/{materialId}/...`.
- The owner can read drafts and posted rows. Students can read only explicitly
  posted, ready rows whose original upload is complete; only the owner can
  write, post/unpost, or delete.
- The pre-delete trigger removes source-bound draft quizzes and nulls the
  material reference on retained finalized/published quizzes.

### `quizzes`

Fields: UUID/class/Teacher/material, `quiz_type` (`actual`/`practice`), title,
type-dependent status, generation method, optional Actual source quiz,
`questions` JSONB, total points, requested count/types, Generate More state,
generation/batch idempotency fields, non-secret credential-source/allowance
metadata, and timestamps.

Each question JSON retains the Flutter shape: ID, type, stem, choices, correct
answer, enumeration answers, explanation, source excerpt, points, and origin.

- `generate-quiz` creates/merges private drafts; `QuizService` publishes or
  finalizes them; `append_manual_quiz_question` adds Teacher questions.
- Teachers can read/write only owned rows.
- Class members can read only published Practice rows. Actual quizzes remain
  Teacher-only.

### `quiz_assignments`

Fields: UUID, quiz/class/Teacher composite relationship, title snapshot,
optional deadline, `is_closed`, created/closed/updated timestamps.

- `AssignmentService` creates and manages rows for owned published quizzes.
- Owner or class member can read; only the owner can write.

### `quiz_attempts`

Fields: server UUID, client idempotency UUID, quiz/optional assignment/class,
Student, name snapshot, attempt number 1 or 2, answers JSONB, score, total,
percentage, breakdown JSONB, and `submitted_at`.

- Only service-role RPC `studexa_save_scored_attempt` inserts attempts.
- Students read their own results; the owning Teacher reads class results.
- Unique constraints enforce one attempt number and one client idempotency key
  per Student/quiz.

### `quiz_drafts`

Composite key: `(student_id, quiz_id, attempt_number)`, with answers JSONB and
`updated_at`.

- Students manage only their own drafts for a joined class's published
  Practice quiz.
- A successful attempt transaction deletes the matching draft.

### Private Gemini credential state

`private.teacher_gemini_credentials` maps a Teacher UUID to one encrypted
`vault.secrets` UUID and stores only last four, validity, and timestamps.
`private.teacher_gemini_backup_sessions` stores Teacher/session/reason/state and
reservation/use times for three lifetime temporary sessions and two UTC-daily
personal-key fallback sessions.

Only service-role RPCs can read/write these tables. Deleting the mapping or Auth
user triggers deletion of the mapped Vault secret. The shared
`GEMINI_API_KEY` remains an Edge Function secret and is not a database row or
client value.

## 3. Core flows

### Teacher upload through Student results

1. A Teacher enters a class name/subject and section. `create_studexa_class`
   stores both, generates the join code, and creates the Teacher membership.
2. `UploadGenerateQuizScreen` calls
   `MaterialService.uploadStudyMaterial`. The client validates bytes, extracts
   readable text on-device, uploads the original privately, and inserts a ready
   material row.
3. The generation guard calls `teacher-gemini-key` GET. A Teacher with no
   personal key may choose one of three lifetime temporary sessions.
4. `QuizGenerationClient` sends a Supabase access token and deterministic
   session/batch IDs to `generate-quiz`.
5. The gateway and handler verify the session. The handler checks Teacher role,
   class ownership, material ownership/readiness, and any Actual reference.
6. The function uses the Teacher Vault key first. With no key it atomically
   reserves a grace session; eligible temporary personal-key failures may use
   the shared backup subject to the two-per-UTC-day limit.
7. Gemini receives untrusted material/reference data plus a strict schema. The
   server validates verbatim source excerpts, supported answers, selected types,
   non-boilerplate content, and same-fact duplicates.
8. Up to ten accepted questions are conditionally saved per request. Repeated
   session/batch IDs return the existing draft. Automatic continuation repeats
   bounded batches until the requested count or a supported partial draft.
9. The Teacher reviews the Actual draft, may add manual questions or use the
   one-time Generate More action, then finalizes it.
10. Practice generation references that Actual quiz and follows the same
    private draft/idempotency flow. The Teacher publishes and optionally creates
    an assignment/deadline.
11. A joined Student streams the published Practice quiz, saves answers in
    `quiz_drafts`, and submits through `submit-quiz-attempt`.
12. The Edge Function scores against the current quiz. The transaction checks
    quiz version, membership, deadline/closed state, idempotency, and the
    two-attempt limit before saving the authoritative result.
13. The Student reads their result; the owning Teacher sees both attempts and
    monitoring metrics through RLS-protected streams.

### Auth and role handling

1. The start screen captures the expected role.
2. Email signup stores role/name metadata and requires confirmation. The Auth
   trigger creates the profile before the first application query.
3. Native Google login exchanges Google ID/access tokens with Supabase.
4. Both paths call `claim_studexa_role`: a missing role is claimed once; an
   existing opposite role raises `AuthRoleMismatchException`, signs out, and
   returns the user to the correct-role decision.
5. `SplashScreen` restores a Supabase session and loads the profile to select
   Teacher or Student Home. Logout clears Supabase and Google sessions and the
   navigation stack.

### Join-code enrollment

1. The Teacher RPC creates a unique `ABC-1234`-style uppercase code.
2. `JoinClassScreen` normalizes the Student's input and calls
   `join_studexa_class`.
3. The RPC verifies a Student role, locks the active class, rejects missing,
   inactive, or duplicate enrollment, and inserts one Student membership.
4. The roster trigger increments the count in the same transaction.
5. Realtime class/member changes refresh both dashboards. RLS gives the new
   member access to that class's materials, published Practice quizzes, and
   assignments.

## 4. Cloud Functions inventory

### Active Supabase Edge Functions

| Function | Trigger | Services/libraries | Responsibility |
|---|---|---|---|
| `generate-quiz` | Authenticated HTTP POST | Supabase Auth REST, PostgREST, Vault RPCs, Gemini REST; shared `quiz_generator.mjs`, filters, credential store | Authorize Teacher ownership, select personal/backup credential, generate/validate/deduplicate bounded quiz batches, preserve/retry one draft. |
| `teacher-gemini-key` | Authenticated HTTP GET/PUT/DELETE | Supabase Auth REST, PostgREST, Vault RPCs, Gemini REST validation | Return masked state, validate and save/replace a Teacher key, or remove key and Vault secret. |
| `submit-quiz-attempt` | Authenticated HTTP POST | Supabase Auth REST, PostgREST, service-role scoring RPC | Read the Student-visible quiz, calculate authoritative score, and persist an atomic/idempotent attempt. |

All three are deployed `ACTIVE` with gateway `verify_jwt = true`. They also call
Auth `getUser()` instead of trusting decoded request claims alone.

### Legacy Firebase Functions blocked from retirement

`functions/index.js` still defines `generateQuizHttp`, callable `generateQuiz`,
and Storage-finalize `extractText`. They use `firebase-admin`, Google Gemini REST,
`pdf-parse`, `mammoth`, `officeparser`, and Google Drive conversion helpers.
The updated app never calls them. Deletion was attempted individually after
Firebase accounts/data were removed and deny-all rules were deployed. Google
returned HTTP 403 for each write because the project has no billing account, so
the deployments remain only as inaccessible legacy infrastructure.

## 5. Known constraints and protected pipelines

- Firebase has no role in the updated client runtime. Do not restore Firebase
  Flutter packages, `firebase_options.dart`, Google Services Gradle wiring, or
  `google-services.json`.
- Keep Firebase shutdown rules and audit scripts as evidence while the
  billing-blocked legacy Function deployments still exist.
- Original DOCX/PPTX/PDF files remain private in Supabase Storage. Do not replace
  Office originals with converted/extracted content.
- Text extraction remains on-device; Supabase Storage has no Firebase-style
  finalize trigger.
- Actual quizzes remain Teacher-only. Students receive only published Practice
  rows for joined classes.
- Preserve the Actual-to-Practice order, 1–50 selection, 10-question bounded
  requests, deterministic idempotency IDs, partial drafts, duplicate filtering,
  manual-question coexistence, and one-time Generate More rule.
- A personal Gemini key is primary. Complete keys remain only in Vault and are
  never returned. The shared Edge secret is backup only; grace and fallback
  counters are atomic and per Teacher/session.
- Attempt scoring remains server-authoritative with two attempts, membership,
  deadline, closed-state, current-quiz, and idempotency enforcement.
- Roles are immutable after the initial claim. Class creation and join-code
  enrollment remain transactional RPCs.
- The recovery snapshot is outside Git and encrypted with AES-256-GCM; its key
  is separately protected with Windows DPAPI. The archive records the three
  legacy Firebase Storage object paths and billing-denied download results;
  their bytes could not be recovered before the objects were deleted.
- The clean reset is complete. Preserve the schema, RLS policies, Auth provider
  configuration, private bucket configuration, migrations, and server-side
  shared Gemini secret while beta accounts begin from an empty state.

## 6. Gaps or inconsistencies

1. **Legacy Firebase endpoints remain deployed because deletion is billing-blocked.**
   Exact deletion attempts for `generateQuiz`, `generateQuizHttp`, and
   `extractText` returned HTTP 403. The updated APK cannot call them, Firebase
   Auth/data are empty, and Firestore/Storage are deny-all.
2. **Published Practice rows contain embedded answers.** RLS prevents
   unauthorized class access and scoring is authoritative, but an enrolled
   Student receives the full `questions` JSONB, including correct-answer fields.
   Hiding answers from direct API inspection would require a sanitized Student
   view/RPC or a normalized question/answer schema; that redesign is not part of
   the behavior-preserving migration.
3. **The linked database suite passes, while local Docker remains unavailable.**
   All 38 pgTAP cases passed twice against the linked schema through the
   rollback-only runner, and a separate audit confirmed zero fixture residue.
   Docker Desktop remains unable to start its engine, but it is no longer needed
   for the linked policy gate.
4. **Platform verification is incomplete outside Android/web.** Web release
   compilation passed. Windows build requires Developer Mode for plugin symlinks,
   and iOS cannot be compiled on this Windows host. No platform support was
   added or removed.
5. **The physical-phone acceptance combined UI and live backend evidence.** The
   installed APK hash matched the release, cold launch and native Google Teacher
   sign-in succeeded, and real UI class creation saved the correct subject and
   section. The production verifier separately completed class join, private
   posted-material access, real Gemini Actual→Practice generation, manual
   questions, publishing, assignment, Student draft/attempts, authoritative
   scoring, results authorization, and cleanup. The phone disconnected before
   the final cleaned-class Realtime refresh could be observed, but the linked
   count audit proved one real Auth/profile row and zero application, private
   Gemini, and Storage rows.
