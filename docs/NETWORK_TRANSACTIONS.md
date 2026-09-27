# Studexa – Network Transactions & Week 12 Code Map

> **Last updated:** 2026-09-25
>
> **Backend:** Supabase (Auth, Postgres, Storage, Edge Functions)
>
> **AI:** Google Gemini API (called from Edge Functions, not from the Flutter client)
>
> **Firebase:** ❌ Not used. The project was fully migrated to Supabase.

---

## Quick Reference Summary

| # | Requirement | Service | Flutter Client Code | Backend Code |
|---|---|---|---|---|
| 1 | API Integration (AI) | Gemini REST API | `lib/services/quiz_generation_client.dart` | `supabase/functions/_shared/quiz_generator.mjs` |
| 2 | API Integration (Auth) | Supabase Auth | `lib/services/auth_service.dart` | Built-in Supabase Auth |
| 3 | Database Integration | Supabase Postgres (PostgREST) | All `lib/services/*.dart` | `supabase/migrations/*.sql` |
| 4 | File Upload | Supabase Storage | `lib/services/material_service.dart` | Storage bucket `study-materials` |
| 5 | Take Quiz | Supabase Realtime + Postgres | `lib/screens/student/answer_quiz_screen.dart` | RLS policies on `quizzes` |
| 6 | Submit Quiz | Edge Function `submit-quiz-attempt` | `lib/services/assignment_service.dart` | `supabase/functions/_shared/submit_quiz_attempt_edge.mjs` |
| 7 | Teacher Gemini Key | Edge Function `teacher-gemini-key` | `lib/services/teacher_gemini_key_service.dart` | `supabase/functions/_shared/teacher_gemini_key_edge.mjs` |

---

## 1. API Integration

### 1.1 Supabase Initialization

| Item | File | Lines |
|---|---|---|
| `Supabase.initialize()` | `lib/main.dart` | L10–L14 |
| URL + publishable key config | `lib/config/supabase_config.dart` | L6–L24 |
| Edge Function endpoints | `lib/config/integration_config.dart` | L3–L21 |

**How it works:**
- `main.dart` L10 checks `SupabaseConfig.isConfigured` then calls `Supabase.initialize(url, publishableKey)`.
- Every service (Auth, Class, Material, Quiz, Assignment) obtains its `SupabaseClient` via `Supabase.instance.client`.
- No Firebase SDK is imported or initialized anywhere in the app.

### 1.2 Supabase Auth API

| Operation | File | Method | Lines |
|---|---|---|---|
| Email registration | `lib/services/auth_service.dart` | `registerWithEmail()` | L76–L104 |
| Email login | `lib/services/auth_service.dart` | `signInWithEmail()` | L106–L122 |
| Google sign-in | `lib/services/auth_service.dart` | `signInWithGoogle()` | L124–L153 |
| Role claim (RPC) | `lib/services/auth_service.dart` | `_claimAndLoadProfile()` | L155–L193 |
| Get profile | `lib/services/auth_service.dart` | `getCurrentUserProfile()` | L195–L205 |
| Sign out | `lib/services/auth_service.dart` | `signOut()` | L207–L212 |
| Auth state stream | `lib/services/auth_service.dart` | `authStateChanges` | L64–L74 |

### 1.3 Gemini AI API (Quiz Generation)

The Gemini API is **never called directly from the Flutter app**. The flow is:

```
Flutter Client                  Supabase Edge Function              Google Gemini
     |                                 |                                |
     |-- HTTP POST /generate-quiz ---->|                                |
     |   (Bearer: Supabase JWT)        |-- REST POST to Gemini -------->|
     |                                 |   (x-goog-api-key: teacher's   |
     |                                 |    personal key or backup key) |
     |                                 |<-- JSON quiz questions --------|
     |<-- { quizId, quiz } ------------|                                |
```

| Component | File | Lines | Details |
|---|---|---|---|
| Client sends HTTP POST | `lib/services/quiz_generation_client.dart` | L46–L171 | `generate()` method, bearer token from Supabase session |
| Batch sending logic | `lib/services/quiz_generation_client.dart` | L173–L287 | `_sendBatch()`, adds `apikey` header for Supabase host |
| Edge Function entry | `supabase/functions/generate-quiz/index.ts` | L1–L6 | `Deno.serve(handleQuizRequest)` |
| Edge Function handler | `supabase/functions/_shared/quiz_edge.mjs` | L342–L388 | Auth verification, Postgres store, credential logic |
| Gemini API call | `supabase/functions/_shared/quiz_generator.mjs` | L185–L280 | `generateSingleBatch()`, calls `generativelanguage.googleapis.com` |
| Model pool (failover) | `supabase/functions/_shared/quiz_generator.mjs` | L13–L21 | `DEFAULT_MODELS`: gemini-3.5-flash-lite → 3.1-flash-lite → flash-lite-latest → 3-flash-preview → 3.5-flash → 3.6-flash → flash-latest |
| Question validation | `supabase/functions/_shared/quiz_generator.mjs` | L135–L181 | Excerpt grounding, structure checks, stem dedup |

### 1.4 Teacher Gemini Key Management API

| Operation | File | Method | Lines |
|---|---|---|---|
| GET status | `lib/services/teacher_gemini_key_service.dart` | `getStatus()` | L60 |
| PUT save & verify | `lib/services/teacher_gemini_key_service.dart` | `saveAndVerify()` | L62–L63 |
| DELETE remove key | `lib/services/teacher_gemini_key_service.dart` | `remove()` | L65 |
| HTTP request logic | `lib/services/teacher_gemini_key_service.dart` | `_request()` | L67–L150 |
| Edge Function entry | `supabase/functions/teacher-gemini-key/index.ts` | L1–L4 | `Deno.serve(handleTeacherGeminiKeyRequest)` |
| Edge Function handler | `supabase/functions/_shared/teacher_gemini_key_edge.mjs` | full file | GET/PUT/DELETE with Vault integration |

---

## 2. Database Integration

### 2.1 Database: Supabase Postgres (via PostgREST)

All database operations use the `supabase_flutter` SDK which calls the PostgREST API under the hood. Tables are protected by Row Level Security (RLS).

### 2.2 Tables & Collections

| Table | Purpose | Service File |
|---|---|---|
| `profiles` | User profiles (id, role, display_name) | `auth_service.dart` L198–L204 |
| `classes` | Teacher-created classes | `class_service.dart` L56–L115 |
| `class_members` | Class enrollment records | `class_service.dart` L63–L68 |
| `materials` | Uploaded study documents, extracted text, and explicit posted/draft state | `material_service.dart` |
| `quizzes` | Generated/manual quiz data | `quiz_service.dart` L21–L72, L442–L576 |
| `quiz_assignments` | Teacher-assigned quizzes for classes | `assignment_service.dart` L39–L106 |
| `quiz_attempts` | Student quiz submissions with scores | `assignment_service.dart` L108–L176 |
| `quiz_drafts` | Autosaved student answers | `assignment_service.dart` L181–L237 |

### 2.3 CRUD Operations

#### CREATE (Insert)

| What | File | Method | Lines |
|---|---|---|---|
| Create class (RPC) | `class_service.dart` | `createClass()` | L37–L54 |
| Join class (RPC) | `class_service.dart` | `joinClassByCode()` | L70–L89 |
| Upload material | `material_service.dart` | `uploadStudyMaterial()` | L249–L258 |
| Create assignment | `assignment_service.dart` | `createAssignment()` | L39–L58 |
| Save draft answers | `assignment_service.dart` | `saveDraftAnswers()` | L181–L199 |
| Submit attempt (Edge Fn) | `assignment_service.dart` | `submitAttempt()` | L108–L152 |
| Append manual question (RPC) | `quiz_service.dart` | `appendManualQuestion()` | L455–L476 |

#### READ (Select / Stream)

| What | File | Method | Lines |
|---|---|---|---|
| Get user profile | `auth_service.dart` | `getCurrentUserProfile()` | L195–L205 |
| Stream teacher classes | `class_service.dart` | `getTeacherClassesStream()` | L56–L61 |
| Stream student classes | `class_service.dart` | `getStudentJoinedClassesStream()` | L92–L97 |
| Stream class members | `class_service.dart` | `getClassMembersStream()` | L63–L68 |
| Get class by ID | `class_service.dart` | `getClassById()` | L106–L115 |
| Stream class materials | `material_service.dart` | `streamClassMaterials()` | L476–L485 |
| Stream teacher materials | `material_service.dart` | `streamTeacherMaterials()` | L488–L502 |
| Stream single material | `material_service.dart` | `streamMaterial()` | L467–L473 |
| Stream class quizzes | `quiz_service.dart` | `streamClassQuizzes()` | L21–L39 |
| Stream teacher quizzes | `quiz_service.dart` | `streamTeacherQuizzes()` | L42–L51 |
| Stream single quiz | `quiz_service.dart` | `streamQuiz()` | L54–L62 |
| Get single quiz | `quiz_service.dart` | `getQuiz()` | L65–L72 |
| Stream class assignments | `assignment_service.dart` | `streamClassAssignments()` | L80–L91 |
| Stream quiz attempts | `assignment_service.dart` | `streamClassQuizAttempts()` | L154–L164 |
| Stream student attempts | `assignment_service.dart` | `streamStudentClassAttempts()` | L166–L176 |
| Get draft answers | `assignment_service.dart` | `getDraftAnswers()` | L201–L220 |

#### UPDATE

| What | File | Method | Lines |
|---|---|---|---|
| Update quiz | `quiz_service.dart` | `updateQuiz()` | L442–L453 |
| Publish quiz | `quiz_service.dart` | `publishQuiz()` | L545–L557 |
| Finalize quiz | `quiz_service.dart` | `finalizeQuiz()` | L560–L571 |
| Close assignment | `assignment_service.dart` | `closeAssignment()` | L60–L65 |
| Reopen assignment | `assignment_service.dart` | `reopenAssignment()` | L67–L72 |
| Update deadline | `assignment_service.dart` | `updateDeadline()` | L74–L78 |
| Storage upload status | `material_service.dart` | background `unawaited` in `uploadStudyMaterial()` | L278–L297 |
| Retry extraction | `material_service.dart` | `retryMaterialExtraction()` | L505–L551 |
| Post material to Students | `material_service.dart` | `postMaterial()` | Current implementation |
| Unpost material from Students | `material_service.dart` | `unpostMaterial()` | Current implementation |

#### DELETE

| What | File | Method | Lines |
|---|---|---|---|
| Delete quiz | `quiz_service.dart` | `deleteQuiz()` | L574–L576 |
| Delete material + storage | `material_service.dart` | `deleteMaterial()` | L555–L592 |
| Clear draft answers | `assignment_service.dart` | `clearDraftAnswers()` | L222–L237 |
| Cleanup material quizzes | `material_service.dart` | `_cleanupMaterialQuizzes()` | L623–L653 |

---

## 3. Upload Functionality

### Upload Flow

```
Teacher picks file (FilePicker)
        |
        v
validateUploadRequest() ──── check: PDF/DOCX/PPTX, ≤50 MB
        |
        v
  ┌─────┴──────┐
  |            |
  v            v
Extract text   Upload to Supabase Storage
on-device      bucket: "study-materials"
(DocumentTextExtractor)  path: uploads/{uid}/{materialId}/{filename}
  |            |
  └─────┬──────┘
        v
INSERT INTO materials ──── status='ready' or 'failed', is_posted=false
        |
        v
Background: update storage_upload_status
        |
        v
Teacher confirms Post Material ──── is_posted=true, posted_at=now()
        |
        v
Student RLS/stream exposes only posted + ready + completed materials
```

| Step | File | Method/Lines |
|---|---|---|
| File picker UI | `upload_generate_quiz_screen.dart` | `_pickFile()` ~L158 |
| Validation | `material_service.dart` | `validateFile()` L65–L97, `validateUploadRequest()` L100–L117 |
| Storage upload | `material_service.dart` | `uploadStudyMaterial()` L183–L201 |
| Text extraction | `utils/document_text_extractor.dart` | `DocumentTextExtractor.extract()` |
| DB insert | `material_service.dart` | L249–L258 |
| Background status update | `material_service.dart` | L274–L300 |
| Post/unpost update | `material_service.dart` | `postMaterial()` / `unpostMaterial()` |

---

## 4. Take Quiz Flow

```
Student → student_class_details_screen → sees assignments
        |
        v
Taps quiz → answer_quiz_screen (loads quiz from Supabase)
        |
        v
Answers questions → auto-save drafts to quiz_drafts table
        |
        v
Submit → calls AssignmentService.submitAttempt()
```

| Step | File | Lines |
|---|---|---|
| View assignments | `lib/screens/student/student_class_details_screen.dart` | streams via `AssignmentService` |
| Load quiz | `lib/screens/student/answer_quiz_screen.dart` | L1–L50 (init) |
| Auto-save drafts | `lib/services/assignment_service.dart` | `saveDraftAnswers()` L181–L199 |
| Answer recording | `lib/screens/student/answer_quiz_screen.dart` | Widget event handlers |

---

## 5. Submit Quiz Flow

```
Student taps Submit
        |
        v
AssignmentService.submitAttempt()
        |
        v
Supabase Edge Function: submit-quiz-attempt
        |
        v
Server-side scoring (exact, typo-tolerant, partial enumeration)
        |
        v
studexa_save_scored_attempt (RPC, service_role only)
        |
        v
INSERT quiz_attempts + DELETE matching quiz_draft
        |
        v
Return scored attempt to client → show results
```

| Step | File | Lines |
|---|---|---|
| Client submit call | `assignment_service.dart` | `submitAttempt()` L108–L152 |
| Edge Function entry | `supabase/functions/submit-quiz-attempt/index.ts` | L1–L4 |
| Server scoring logic | `supabase/functions/_shared/submit_quiz_attempt_edge.mjs` | `scoreQuiz()` L70+ |
| Typo-tolerant matching | `supabase/functions/_shared/submit_quiz_attempt_edge.mjs` | `freeTextMatch()` L39–L46, `distance()` L23–L37 |
| Enumeration scoring | `supabase/functions/_shared/submit_quiz_attempt_edge.mjs` | `scoreEnumeration()` L48–L68 |
| Client-side scoring (fallback) | `lib/utils/scoring_utils.dart` | `ScoringUtils` class |

---

## 6. Network Transactions Summary

| # | Transaction | Direction | Protocol | Service | Data Sent | Data Received | Failure Handling |
|---|---|---|---|---|---|---|---|
| 1 | User Registration | Client → Supabase Auth | HTTPS | `auth_service.dart` | email, password, role, display_name | Session + user object | `AuthException` → error message |
| 2 | User Login | Client → Supabase Auth | HTTPS | `auth_service.dart` | email, password | Session + JWT | Role mismatch check, error mapping L232–L271 |
| 3 | Google Sign-In | Client → Google → Supabase | HTTPS | `auth_service.dart` | Google ID/access tokens | Supabase session | Sign out on failure L148–L152 |
| 4 | Class Create/Join | Client → Supabase RPC | HTTPS | `class_service.dart` | name, section / join_code | Class model | `ClassJoinException` L125–L140 |
| 5 | Material Upload | Client → Supabase Storage + Postgres | HTTPS | `material_service.dart` | File bytes + metadata | Material model | Rollback storage on DB failure L259–L271 |
| 6 | Quiz Generation | Client → Edge Fn → Gemini API | HTTPS | `quiz_generation_client.dart` | classId, materialId, types, count | Quiz model with questions | Model rotation, batch retry, `QuizGenerationException` |
| 7 | Quiz Submission | Client → Edge Fn → Postgres | HTTPS | `assignment_service.dart` | quizId, classId, answers | Scored attempt with breakdown | `QuizUnavailableException` L138–L151 |
| 8 | Gemini Key Mgmt | Client → Edge Fn → Vault | HTTPS | `teacher_gemini_key_service.dart` | GET/PUT/DELETE + API key | Status + masked key | `TeacherGeminiKeyException` L39–L45 |
| 9 | Realtime Streams | Client ↔ Supabase Realtime | WSS | All `stream*()` methods | Table subscriptions | Live row changes | Auto-reconnect (SDK-managed) |
| 10 | File Download | Client → Supabase Storage | HTTPS | `material_service.dart` | Storage path | File bytes | Fallback to legacy URL L306–L337 |

---

## 7. Configuration Files

| File | Purpose |
|---|---|
| `lib/config/supabase_config.dart` | Supabase URL, publishable key, storage bucket, auth callback, Google client ID |
| `lib/config/integration_config.dart` | Edge Function endpoint URLs (generate-quiz, teacher-gemini-key, submit-quiz-attempt) |
| `lib/config/gemini_config.dart` | Legacy stub — credentials moved server-side |
| `pubspec.yaml` | Flutter dependencies — `supabase_flutter`, `http`, `file_picker`, etc. |
| `supabase/config.toml` | Supabase CLI local config |
| `supabase/migrations/*.sql` | Database schema, RLS policies, RPCs, triggers |

---

## 8. What is NOT Used

| Technology | Status |
|---|---|
| Firebase (Auth, Firestore, Storage, Functions) | ❌ Fully removed from `pubspec.yaml` and all code |
| Docker | ❌ No Dockerfile or docker-compose anywhere |
| Maps / Location Services | ❌ Not implemented |
| FCM Push Notifications | ❌ Not implemented |
| Local SQLite / Hive | ❌ Not used — all persistence is Supabase |

---

## 9. Live Demo Cheatsheet

| Demo Step | What to Show | Where in Code |
|---|---|---|
| **App startup** | Supabase init, splash screen | `lib/main.dart` L10–L14 |
| **Register** | Email signup → Supabase Auth | `auth_service.dart` L76–L104 |
| **Login** | Email/Google sign-in | `auth_service.dart` L106–L153 |
| **Create class** | RPC call → Postgres | `class_service.dart` L37–L54 |
| **Join class** | Student enters code | `class_service.dart` L70–L89 |
| **Upload material** | FilePicker → Storage + Postgres | `material_service.dart` L123–L303 |
| **Text extraction** | On-device PDF/DOCX parsing | `utils/document_text_extractor.dart` |
| **Set Gemini API key** | Teacher settings → Edge Function | `teacher_gemini_key_service.dart` L60–L65 |
| **Generate quiz** | HTTP POST → Edge Fn → Gemini | `quiz_generation_client.dart` L46–L171 |
| **Model failover** | 7 Gemini models rotate on 429/503 | `quiz_generator.mjs` L13–L21, L205–L278 |
| **Edit quiz** | Add/remove questions, manual add | `quiz_service.dart` L442–L476 |
| **Publish quiz** | Status → published | `quiz_service.dart` L545–L557 |
| **Assign quiz** | Create assignment for class | `assignment_service.dart` L39–L58 |
| **Take quiz** | Student answers, auto-save drafts | `answer_quiz_screen.dart` |
| **Submit quiz** | Edge Fn scores server-side | `assignment_service.dart` L108–L152 |
| **View results** | Score, breakdown, attempt history | `teacher_results_screen.dart` |
| **Realtime updates** | `stream*()` methods → live UI | All services: `.stream(primaryKey: ['id'])` |
| **Delete material** | Storage + Postgres + draft cleanup | `material_service.dart` L555–L592 |

---

## 10. Project Structure Overview

```
studexa/
├── lib/
│   ├── main.dart                          # App entry, Supabase init
│   ├── config/
│   │   ├── supabase_config.dart           # Supabase URL & keys
│   │   ├── integration_config.dart        # Edge Function URLs
│   │   └── gemini_config.dart             # Legacy stub
│   ├── models/                            # Data models (class, material, quiz, etc.)
│   ├── screens/
│   │   ├── auth/                          # Login, Register, Role Selection
│   │   ├── student/                       # Student Home, Class Details, Answer Quiz, Join Class
│   │   └── teacher/                       # Teacher Home, Class Details, Upload/Generate, Quiz Detail,
│   │                                      #   Quiz Monitoring, Results, Gemini API Settings
│   ├── services/
│   │   ├── auth_service.dart              # Supabase Auth (email, Google, role)
│   │   ├── class_service.dart             # Classes + members (RPC + streams)
│   │   ├── material_service.dart          # Upload, extraction, Storage, streams
│   │   ├── quiz_service.dart              # Quiz CRUD, generation, validation, local fallback
│   │   ├── quiz_generation_client.dart    # HTTP client to generate-quiz Edge Function
│   │   ├── assignment_service.dart        # Assignments, attempts, drafts, submit via Edge Function
│   │   ├── teacher_gemini_key_service.dart# Gemini API key management via Edge Function
│   │   └── pdf_export_service.dart        # PDF export for quiz results
│   ├── utils/                             # DocumentTextExtractor, ScoringUtils
│   ├── widgets/                           # Shared UI components
│   └── theme/                             # AppTheme
├── supabase/
│   ├── functions/
│   │   ├── generate-quiz/index.ts         # Edge Function: quiz generation
│   │   ├── submit-quiz-attempt/index.ts   # Edge Function: server-side scoring
│   │   ├── teacher-gemini-key/index.ts    # Edge Function: credential management
│   │   ├── _shared/
│   │   │   ├── quiz_generator.mjs         # Gemini API caller, model rotation, validation
│   │   │   ├── quiz_edge.mjs              # Quiz generation request handler
│   │   │   ├── submit_quiz_attempt_edge.mjs # Scoring logic (exact, typo, enumeration)
│   │   │   ├── teacher_gemini_key_edge.mjs  # Key CRUD + Vault
│   │   │   ├── teacher_credentials.mjs    # Personal key + backup session store
│   │   │   ├── postgres_rest.mjs          # PostgREST client for Edge Functions
│   │   │   ├── supabase_identity.mjs      # JWT verification helper
│   │   │   └── question_filters.mjs       # Table-header & filler detection
│   │   └── test/                          # Unit tests for Edge Function modules
│   └── migrations/                        # SQL migrations (schema, RLS, RPCs, triggers)
├── pubspec.yaml                           # Flutter dependencies (supabase_flutter, http, etc.)
└── docs/
    └── NETWORK_TRANSACTIONS.md            # ← This file
```
