# Studexa Phase 1 End-to-End Implementation Prompt

## Master instruction

You are implementing the **Studexa Phase 1 MVP as a complete working system**, not a UI mockup. Work from the approved Phase 1 project documentation and existing project files. The target is the **Week 11 milestone: the primary screen flows and minimum MVP feature set must be functional, with navigation between major screens working and the core user journey demonstrable on Android**.

### NON-NEGOTIABLE WORKFLOW RULE

**Before doing ANY task:**
1. Read `IMPLEMENTATION_LOG.md` completely enough to understand the current status, completed work, current blockers, decisions, changed files, tests, and the exact `NEXT TASK`.
2. Inspect the current codebase before changing anything. Do not assume a file, architecture, package, collection, function, route, screen, or service exists.
3. Continue from the logged `NEXT TASK` when one exists. Do not redo completed work unless the log or current code shows it is broken.
4. If the log conflicts with the actual code, inspect the code, resolve the discrepancy, and record the correction in the log before continuing.

**After EVERY task or meaningful checkpoint:**
1. Test or verify what you changed.
2. Update `IMPLEMENTATION_LOG.md` immediately.
3. Record exactly what was completed, what changed, where it changed, verification performed, errors/blockers, decisions, and the next task.
4. The log is persistent project memory. Never leave the project in a state where another AI cannot determine what has already been done and where to continue.

At the beginning and end of every working session, leave the log in a resumable state.

---

# 1. Project source of truth

The implementation must follow the supplied Phase 1 documentation for **Studexa: Class-Based Quiz Generation and Practice App**.

Core project identity:
- Application: **Studexa**
- Tagline: **Turn Class Materials into Quizzes Practice Smarter, Together**
- Platform: **Flutter mobile application**, primarily Android
- Users: **Teacher** and **Student**
- Backend/data platform requested for this implementation: **Firebase**
- AI service: **Gemini API**, called from the secure backend only
- File processing: **server-side Cloud Functions**

The Phase 1 documentation defines the core teacher/student workflow, quiz generation from PDF/PPTX/DOCX materials, five question types, forgiving answer matching, Enumeration partial credit, class join codes, Practice Quiz assignment/deadlines/closing, teacher monitoring, and Actual Quiz PDF export. fileciteturn0file0L407-L564

The documentation also defines teacher and student user stories covering authentication, classes, material upload, AI/manual Actual Quiz creation, Practice Quiz generation, quiz editing, assignment, closing, PDF export, monitoring, joining classes, taking quizzes, scoring, and historical results. fileciteturn0file0L569-L687 fileciteturn0file0L688-L781

Use the supplied wireframes and descriptions as the UI/UX reference. The documented screens include Log In, Home, Configure Quiz Options, Answer & Submit Quiz, View Quiz History, and Check Answers & Score. fileciteturn0file0L827-L871

---

# 2. Week 11 implementation target

The Week 11 target is a **working MVP build with functional primary screen flows and a demonstrable core user journey**.

Do not spend the majority of the implementation time on low-priority polish, animations, advanced architecture, or out-of-scope features. The MVP must be able to demonstrate the end-to-end flow below.

## Primary end-to-end flow

### Teacher flow
1. Register/log in as Teacher.
2. Create a class.
3. Receive a unique class join code.
4. Upload a supported study material: PDF, PPTX, or DOCX.
5. See upload/extraction status and failure states.
6. Generate an Actual Quiz using Gemini, or create one manually.
7. Generate a Practice Quiz from the same material and Actual Quiz reference, with different wording.
8. Review and edit generated questions, answers, options, and title.
9. Publish/finalize the quizzes.
10. Assign the Practice Quiz to a class with an optional deadline.
11. Manually close the Practice Quiz when needed.
12. View student completion status and scores.
13. Export the finalized Actual Quiz as a printable PDF.

### Student flow
1. Register/log in as Student.
2. Join a class with a valid join code.
3. View joined class(es) and assigned Practice Quizzes.
4. See deadline/closed/unavailable state correctly.
5. Open an available Practice Quiz.
6. Answer all supported question types.
7. Submit the Practice Quiz.
8. Have the answers checked automatically.
9. View score and detailed results.
10. Continue to access historical results after a quiz is closed.

The Week 11 demonstration must prioritize this flow over secondary features.

---

# 3. Required architecture

Implement the system as a real client/backend/database architecture.

## Frontend

Use the existing Flutter project if one exists. Preserve the current project structure and visual language where possible.

The Flutter app should contain clear separation for:
- Authentication
- Role routing
- Teacher screens/features
- Student screens/features
- Quiz UI/state
- Firebase repositories/services
- Backend callable/HTTP functions
- Models/entities
- Shared validation/utilities
- Error/loading/empty states

Do not place Gemini secrets or privileged Firebase Admin credentials in Flutter code.

## Firebase services

Use Firebase as the application backend:
- Firebase Authentication for account registration/login and Google sign-in if supported by the current project/configuration.
- Cloud Firestore for application data.
- Firebase Storage for uploaded study materials and generated/processed files.
- Firebase Cloud Functions for secure server-side processing, file text extraction, Gemini API calls, fallback generation, scoring-related server logic where appropriate, and PDF generation/export where appropriate.
- Firebase App Check may be added if compatible with the existing setup, but do not let it block the Week 11 core flow.

## Backend security rule

The Gemini API key must never be placed in Flutter, Firestore documents, client configuration, logs, or public source code. The mobile app must call a secure backend function that owns the Gemini credential.

The Phase 1 documentation explicitly requires the Gemini key not to be exposed to the mobile app. fileciteturn0file0L540-L564

---

# 4. Suggested Firebase data model

Use Firestore collections/subcollections similar to the following. Adapt names to the existing codebase if an established naming convention already exists, but record the final schema in `IMPLEMENTATION_LOG.md`.

```text
users/{uid}
  role: "teacher" | "student"
  displayName
  email
  photoUrl?
  createdAt
  updatedAt

classes/{classId}
  name
  joinCode
  teacherId
  status
  createdAt
  updatedAt

classes/{classId}/members/{uid}
  userId
  role: "teacher" | "student"
  joinedAt
  displayNameSnapshot

materials/{materialId}
  classId
  teacherId
  fileName
  fileType
  storagePath
  extractionStatus: "pending" | "processing" | "completed" | "failed"
  extractionError?
  extractedTextPath?
  createdAt
  updatedAt

quizzes/{quizId}
  classId?
  teacherId
  materialId
  type: "actual" | "practice"
  title
  status: "draft" | "finalized" | "published" | "closed"
  generationMethod: "gemini" | "manual" | "fallback"
  sourceQuizId?
  questions[]
  createdAt
  updatedAt
  publishedAt?

quizAssignments/{assignmentId}
  quizId
  classId
  teacherId
  deadline?
  isClosed
  createdAt
  closedAt?

attempts/{attemptId}
  quizId
  assignmentId
  classId
  studentId
  answers[]
  score
  totalPoints
  submittedAt
  resultSummary

quizQuestion/embedded or subcollection strategy
  questionId
  type
  questionText
  options[]?
  correctAnswer / correctAnswers
  points
  metadata

users/{uid}/joinedClasses/{classId}
  classId
  joinedAt

users/{uid}/attempts/{attemptId}
  quizId
  assignmentId
  classId
  score
  submittedAt
```

Do not blindly implement duplicate denormalized collections. Choose one consistent source of truth and document the final decision.

Minimum rules:
- Teachers can manage only classes/materials/quizzes/assignments they own.
- Students can read only classes they joined and Practice Quizzes assigned to those classes.
- Students must never receive Actual Quiz answer keys through normal student-facing reads.
- Students can create/read only their own attempts.
- Closed/deadline-expired assignments must reject new attempts on the server, not only in the UI.
- Teacher roster/result reads must be restricted to the relevant teacher/class.

---

# 5. Authentication and role system

Implement:
- Email/password registration
- Email/password login
- Google authentication if project configuration supports it
- Logout
- User profile/role document creation
- Teacher/Student role enforcement
- Role-aware route guarding

Acceptance requirements:
- A Teacher account cannot open Student-only screens.
- A Student account cannot open Teacher-only screens.
- Refreshing/restarting the app preserves authenticated state according to Firebase Auth behavior.
- Sign-out returns to the authentication entry screen.

---

# 6. Class management

Teacher:
- Create class with a name.
- Generate a unique join code.
- Display the join code.
- Display current roster.

Student:
- Enter a join code.
- Validate it securely.
- Reject invalid/unavailable codes clearly.
- Add the student to the class roster.
- Show the class in the student's class list.

Join-code generation must prevent collisions. Do not depend only on client-side random generation without server-side validation.

---

# 7. Study-material upload and extraction

Supported files:
- PDF
- PPTX
- DOCX

Reject unsupported file types before processing.

Upload pipeline:
1. Flutter selects file.
2. Validate type and reasonable size before upload.
3. Upload to Firebase Storage.
4. Create/update the material record in Firestore.
5. Trigger or call a Cloud Function.
6. Cloud Function downloads the file securely.
7. Extract text server-side.
8. Store the extracted text securely for quiz generation.
9. Update extraction status.
10. Notify/show the Teacher of success or failure.

Known Phase 1 limitation: scanned/image-only PDFs that require OCR are out of scope. Do not add OCR unless the project already contains a working implementation. The documentation explicitly lists OCR for scanned/image PDFs as out of scope. fileciteturn0file0L67-L112

Handle:
- Unsupported file
- Empty file
- Unreadable document
- Extraction failure
- Storage failure
- Function timeout/failure

Never expose raw privileged processing paths to untrusted clients.

---

# 8. Quiz generation

Support exactly these five question types for Phase 1:
1. Multiple Choice
2. True/False
3. Fill-in-the-Blank
4. Identification
5. Enumeration

The documentation requires the Teacher to select question type(s) and quantity when generating a quiz. fileciteturn0file0L457-L490

## Actual Quiz

Teacher can:
- Generate using Gemini.
- Write manually without AI.
- Review/edit.
- Finalize.
- Export as printable PDF.

Actual Quiz must remain a teacher/reference artifact and must not become an in-app student assessment.

## Practice Quiz

Teacher can:
- Generate using Gemini.
- Require an existing Actual Quiz as contextual reference.
- Cover the same material/topics.
- Use different wording/phrasing from the Actual Quiz.
- Review/edit.
- Finalize/publish.
- Assign to a class.

If Gemini fails or is unavailable, use a non-AI fallback generator for the requested quiz. The documentation explicitly requires this fallback behavior. fileciteturn0file0L439-L458

## Gemini implementation rules

The backend should:
- Receive only the necessary request data.
- Fetch source text server-side when possible.
- Validate generated JSON against a strict schema.
- Reject malformed output safely.
- Normalize the generated question structure before storing it.
- Avoid exposing the full Actual Quiz answer key to student clients.
- Enforce requested question type and question count.
- Mark generation method as Gemini or fallback.
- Store generation failures for troubleshooting without logging secrets.

Use structured JSON output where supported by the chosen Gemini integration. Do not depend on free-form model text that requires fragile parsing.

---

# 9. Quiz editing and publishing

Teacher must be able to edit:
- Quiz title
- Question text
- Question type where practical
- Options
- Correct answer(s)
- Enumeration items
- Point values if the data model supports them

Maintain draft/finalized/published/closed state clearly.

Teacher edits must persist in Firestore.

AI-generated content should be marked internally as generated and optionally teacher-edited, so the system can distinguish AI output from reviewed content.

The documentation requires quizzes to remain draft until the teacher explicitly publishes/finalizes them. fileciteturn0file0L628-L638

---

# 10. Practice Quiz assignment and availability

Teacher can assign a finalized Practice Quiz to a selected class.

Assignment fields:
- class
- quiz
- optional deadline
- open/closed state
- created/closed timestamps

Availability logic:
- Available when published and not manually closed and not past deadline.
- Unavailable for new attempts when manually closed.
- Unavailable for new attempts after deadline.
- Historical attempts/results remain visible after closing or expiry.

Do not enforce this only in Flutter. Cloud Functions or Firestore security/data-layer validation must prevent invalid new attempts.

---

# 11. Student quiz engine and scoring

The student quiz screen must support all five question types.

The quiz UI should include the documented primary interactions, including progress information and a flag-for-review control where the approved design contains it. Flagging does not skip the requirement to answer a question before submission. fileciteturn0file0L849-L854

## Free-text matching

Before comparison:
- trim whitespace
- lowercase
- normalize punctuation as defined by the implementation

Minor typos should be tolerated for longer free-text answers according to the Phase 1 acceptance criteria. fileciteturn0file0L736-L747

Use a deterministic similarity method. Do not use an LLM for ordinary answer checking in Phase 1.

## Enumeration

- Match answers item-by-item.
- Order should not matter.
- Score should be proportional to correct matched items.
- Extra incorrect items must not lower the score.
- Results must identify Found, Missing, and Extra/not-counted items.

The Phase 1 documentation explicitly defines this partial-credit behavior. fileciteturn0file0L748-L769

## Submission

On submit:
1. Validate assignment availability.
2. Validate required answers.
3. Score answers deterministically.
4. Persist the attempt.
5. Return the score/result summary.
6. Show the Student a result screen.
7. Keep historical results accessible after closure.

Avoid trusting a client-provided score. Recalculate score on the server or from a trusted server-side scoring function.

---

# 12. Teacher monitoring

Teacher can view, for a selected class and assigned Practice Quiz:
- student list
- completed/not completed status
- individual score
- class-wide summary

Do not expose students from unrelated classes.

The documentation requires results to be specific to the class and quiz being viewed. fileciteturn0file0L676-L687

---

# 13. Actual Quiz PDF export

Provide a manual export action for a finalized Actual Quiz.

The exported PDF must reflect the Teacher's final edited version and must not be regenerated automatically on every edit. fileciteturn0file0L665-L674

The PDF should be printer-friendly and include at minimum:
- Studexa title/header
- quiz title
- class information when available
- numbered questions
- answer choices where applicable
- sufficient spacing for paper use

Keep the Actual Quiz answer key private unless a teacher-only export explicitly needs it.

---

# 14. Navigation and screen implementation

Implement the major screens needed for the Week 11 flow.

At minimum, the functional navigation should cover:

### Shared
- Splash/loading/auth check
- Login
- Register
- Role setup/selection if required by the current design

### Teacher
- Teacher Home/Dashboard
- Create Class
- Class Detail / Roster / Join Code
- Upload Material
- Material Processing Status
- Quiz Configuration
- Actual Quiz creation/editing
- Practice Quiz creation/editing
- Assign Practice Quiz
- Assignment/Quiz management
- Monitor Students / Scores
- Actual Quiz PDF export action

### Student
- Student Home/Dashboard
- Join Class
- Class Detail
- Assigned Practice Quizzes
- Quiz Instructions/Start
- Answer Quiz
- Results / Check Answers & Score
- Quiz History / Past Attempts

Use bottom navigation, tabs, stacks, or another navigation method only if consistent with the existing design. The important requirement is that major flows are reliable and recoverable.

The supplied wireframes show the main visual flow around login, home, quiz configuration, answering, history, and results. fileciteturn0file0L827-L871

---

# 15. UI and UX rules

Do not redesign the project from scratch unless the current code has no usable implementation.

Implement the approved Phase 1 design as closely as the existing assets/code allow.

Every network/backend-driven screen should have:
- loading state
- success state
- empty state where appropriate
- actionable error state
- retry path where appropriate

Forms must validate input before sending requests.

Do not use fake hardcoded success responses for core features.

Do not build decorative screens that are not connected to the backend.

---

# 16. Out-of-scope protections

Do NOT spend Phase 1 implementation time on:
- live simultaneous/Kahoot-style quizzes
- OCR for scanned/image PDFs
- images/video/audio study-material ingestion
- semantic LLM grading of free-text answers
- taking/scoring Actual Quizzes inside the app
- automatic comparison of paper Actual Quiz scores with app Practice Quiz scores
- unnecessary social features
- unrelated study tools such as flashcards or AI chat
- multi-device synchronization beyond normal Firebase Auth/session behavior

These are outside the defined Phase 1 scope. fileciteturn0file0L67-L112

---

# 17. Implementation order

Follow this order unless the existing project structure makes another sequence technically necessary. If deviating, record why in the log.

### Phase A — Project inspection and foundation
- Read `IMPLEMENTATION_LOG.md`.
- Inspect Flutter project and current dependencies.
- Inspect Firebase configuration.
- Identify existing routes, models, services, assets, and screens.
- Confirm Android build configuration.
- Add only required dependencies.
- Record the current state in the log.

### Phase B — Firebase foundation
- Configure Firebase Auth.
- Configure Firestore.
- Configure Storage.
- Configure Cloud Functions.
- Establish environment/secret handling.
- Create initial Firestore schema conventions.
- Write/validate security rules.

### Phase C — Authentication and roles
- Register/login.
- Google login when supported/configured.
- Role creation and role-aware navigation.
- Logout.

### Phase D — Class management
- Teacher class creation.
- Unique join code.
- Student join flow.
- Roster.

### Phase E — Material pipeline
- Upload PDF/PPTX/DOCX.
- Storage metadata.
- Extraction Cloud Function.
- Processing status.
- Failure handling.

### Phase F — Quiz generation and editing
- Question model.
- Configuration UI.
- Actual Quiz AI generation.
- Actual Quiz manual creation.
- Practice Quiz generation using Actual Quiz reference.
- Gemini fallback generator.
- Teacher review/edit.
- Publish/finalize.

### Phase G — Practice assignment and student quiz
- Assignment.
- Deadline/close rules.
- Student quiz UI.
- Scoring.
- Enumeration partial credit.
- Result screen.
- History.

### Phase H — Teacher monitoring and PDF export
- Completion/score monitoring.
- Actual Quiz PDF export.

### Phase I — Week 11 integration test
Execute at least one realistic end-to-end test:
- create teacher
- create class
- create student
- student joins class
- teacher uploads a small valid test document
- extraction succeeds
- teacher generates/finalizes quizzes
- teacher assigns Practice Quiz
- student opens and submits it
- scoring/result works
- teacher sees completion and score
- teacher exports Actual Quiz PDF

Fix blockers that prevent the core journey from completing.

---

# 18. Testing requirements

Do not claim a task is complete solely because code compiles.

For each meaningful implementation:
- run formatter/analyzer
- run relevant unit/widget/integration tests
- run Firebase Emulator tests when feasible
- run `flutter analyze`
- build/run the Android app when feasible
- verify Firestore rules
- verify unauthenticated and wrong-role access is denied

Create deterministic unit tests for:
- join-code validation
- quiz availability/deadline/closed status
- free-text normalization
- typo tolerance
- Enumeration matching
- Enumeration partial credit
- scoring totals

Create at least one integration test for the core user journey when the project setup allows it.

Record all verification results in `IMPLEMENTATION_LOG.md`.

---

# 19. Definition of Done for Week 11

The MVP is considered ready only when all of the following are true:

- Flutter app launches on a supported Android setup.
- Firebase Authentication works.
- Teacher and Student roles work.
- Teacher can create a class and receive a join code.
- Student can join the class.
- Teacher can upload PDF/PPTX/DOCX.
- Server-side extraction works for supported text-based documents.
- Teacher can create Actual Quiz through AI or manually.
- Teacher can create Practice Quiz based on the Actual Quiz/material.
- Gemini failure has a fallback path.
- Teacher can edit generated quiz content.
- Teacher can publish/finalize the Practice Quiz.
- Teacher can assign the Practice Quiz.
- Deadline and manual-close logic works.
- Student can view assigned Practice Quizzes.
- Student can answer all five question types.
- Student can submit.
- Answers are checked correctly, including typo tolerance and Enumeration partial credit.
- Student can view results.
- Historical attempts remain available after closure.
- Teacher can see completion and scores.
- Teacher can export a finalized Actual Quiz to PDF.
- Major screens are connected through working navigation.
- No core feature is represented by a fake hardcoded response.
- Security rules prevent cross-user/cross-class data access.
- Gemini credentials are server-side only.
- `IMPLEMENTATION_LOG.md` contains an accurate final status and reproduction steps.

---

# 20. Required `IMPLEMENTATION_LOG.md` behavior

Treat `IMPLEMENTATION_LOG.md` as a mandatory project control file, not an optional note.

Every work session must leave these sections current:

```md
# Studexa Phase 1 Implementation Log

## CURRENT STATUS
- Overall status: NOT_STARTED / IN_PROGRESS / BLOCKED / MVP_READY / COMPLETE
- Current phase:
- Last completed task:
- Current task:
- NEXT TASK:
- Blockers:
- Last verified:

## PROJECT DECISIONS
- Architecture:
- Firebase services:
- Firestore schema:
- Cloud Functions approach:
- Authentication:
- Gemini integration:
- Scoring approach:

## COMPLETED TASKS
- [x] ...

## IN PROGRESS
- [ ] ...

## BLOCKED
- [ ] ...

## FILES CHANGED
- `path/to/file`: what changed

## FIREBASE / DATABASE CHANGES
- Collection/rule/index/function changes

## TESTS / VERIFICATION
- command or test:
- result:
- date/time:

## KNOWN ISSUES
- issue:
- impact:
- workaround:

## NEXT TASK
Describe one concrete next task another AI can execute immediately.

## SESSION HISTORY
### YYYY-MM-DD HH:MM
- Started with:
- Read log:
- Completed:
- Verified:
- Problems:
- Next task:
```

When updating the log:
- Preserve previous history.
- Update CURRENT STATUS every session.
- Use exact file paths.
- Include exact errors when blocked.
- Include commands/tests actually run.
- Do not claim a test passed if it was not run.
- Do not delete old session history except to correct an explicitly documented factual mistake.

---

# 21. AI execution behavior

When starting:

```text
1. Read IMPLEMENTATION_LOG.md.
2. Inspect repository structure.
3. Compare current code against the logged status.
4. Identify the NEXT TASK.
5. Implement only a coherent task/checkpoint.
6. Test/verify it.
7. Update IMPLEMENTATION_LOG.md.
8. Stop at a clean checkpoint if the task is complete or blocked.
```

When blocked:
- Do not silently skip the task.
- Record the blocker and exact error.
- Complete any independent work that does not depend on the blocker.
- Set a concrete `NEXT TASK`.

When a previous AI stopped mid-task:
- Do not assume the task failed.
- Inspect the code and log.
- Determine what was actually completed.
- Finish only the missing part.

When a feature is intentionally deferred:
- Record it in the log.
- Explain why.
- Do not keep retrying it during unrelated work.

---

# 22. First task to execute now

**Task 1: Establish the project baseline.**

1. Read `IMPLEMENTATION_LOG.md`.
2. Inspect the complete repository structure.
3. Identify the Flutter app entry point, routing, current screens, models, services, Firebase setup, and Cloud Functions/backend setup.
4. Identify which Phase 1 requirements already exist and which are missing.
5. Verify the Android build/toolchain as far as the environment allows.
6. Do NOT start a large feature implementation in the same task.
7. Update `IMPLEMENTATION_LOG.md` with:
   - current architecture
   - existing implementation status
   - discovered files
   - dependencies
   - Firebase status
   - blockers
   - exact `NEXT TASK`
8. Stop at this checkpoint unless a missing project configuration must be fixed to establish the baseline.

After this baseline task, every subsequent AI session must begin by reading the log and continue from its `NEXT TASK`.

---

# 23. Final instruction

**READ `IMPLEMENTATION_LOG.md` FIRST. IMPLEMENT FROM THE CURRENT CODEBASE. VERIFY YOUR WORK. THEN UPDATE `IMPLEMENTATION_LOG.md` BEFORE STOPPING.**

This rule has priority over convenience. The goal is a traceable, resumable, end-to-end Week 11 MVP implementation, not merely a collection of disconnected screens.
