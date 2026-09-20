# Week 12 Demonstration Guide: Network Transactions & Code Integration Map

This document serves as the official reference for the Week 12 project demonstration and instructor checking. It maps every network transaction, API call, database operation, and main user flow to its exact location in the codebase.

---

## 1. Quick Reference Summary Table

| Week 12 Requirement | Status | Main File | Main Class / Function / Widget | Primary Lines |
| :--- | :--- | :--- | :--- | :--- |
| **API Integration** | Found | `lib/services/quiz_generation_client.dart` | `QuizGenerationClient.generate()` | Lines 34–148 |
| **Database Integration** | Found | `lib/services/firestore_provider.dart` | `getAppFirestore()` / `FirebaseFirestore` | Lines 4–15 |
| **Upload Study Material** | Found | `lib/screens/teacher/upload_generate_quiz_screen.dart` | `_UploadGenerateQuizScreenState._pickAndUploadFile()` | Lines 158–284 |
| **Take Quiz** | Found | `lib/screens/student/answer_quiz_screen.dart` | `AnswerQuizScreen` / `_AnswerQuizScreenState` | Lines 142–392 |
| **Submit Quiz** | Found | `lib/screens/student/answer_quiz_screen.dart` | `_AnswerQuizScreenState._evaluateAndShowResults()` | Lines 533–665 |
| **Firebase Authentication** | Found | `lib/services/auth_service.dart` | `AuthService` (`signInWithEmail`, `registerWithEmail`, `signInWithGoogle`) | Lines 56–300 |
| **Cloud Firestore** | Found | `lib/services/firestore_provider.dart` & Services | `AuthService`, `ClassService`, `MaterialService`, `QuizService`, `AssignmentService` | Full services |
| **Firebase Storage** | Found | `lib/services/material_service.dart` | `MaterialService.uploadStudyMaterial()` (`_storage.ref().putData`) | Lines 133–170 |
| **AI / Gemini API Integration** | Found | `functions/quiz_generator.js` & `functions/index.js` | `generateSingleBatch()` (`DEFAULT_MODELS`) & `generateQuizHttp` | `quiz_generator.js`: 12–16, 131–202 |
| **Maps / Location** | Not Found | N/A | Not implemented in this codebase | N/A |
| **Other Network Transactions** | Found | `lib/services/assignment_service.dart` | `AssignmentService.submitAttempt()` & `saveDraftAnswers()` | Lines 126–210, 257–285 |

---

## 2. API Integration

* **Status:** Found
* **Main File:** `lib/services/quiz_generation_client.dart`
* **Related Files:**
  * `lib/config/integration_config.dart`
  * `lib/services/quiz_service.dart`
  * `functions/index.js`
  * `functions/quiz_generator.js`
  * `lib/firebase_options.dart`
  * `lib/main.dart`
* **Class / Service:** `QuizGenerationClient` (Frontend) and `generateQuizHttp` / `processQuizGeneration` / `generateQuizQuestions` (Backend)
* **Function / Method:**
  * Frontend: `QuizGenerationClient.generate(...)`
  * Backend: `exports.generateQuizHttp = onRequest(...)` and `processQuizGeneration(...)`
  * AI Provider: `generateSingleBatch(...)`
* **Relevant Code Location:**
  * `lib/services/quiz_generation_client.dart`: Lines 34–148 (Attaches the user's `Bearer` ID token and sends an HTTP POST request to the cloud endpoint).
  * `lib/config/integration_config.dart`: Lines 4–8 (Declares `IntegrationConfig.quizGenerationUrl`, default: `https://us-central1-studexa-b5e55.cloudfunctions.net/generateQuizHttp`).
  * `functions/index.js`: Lines 849–901 (2nd Gen HTTP Cloud Function verifying the teacher ID token, validating ownership, and handling CORS).
  * `functions/quiz_generator.js`: Lines 131–202 (Posts to Google Gemini API at `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`).
  * `functions/quiz_generator.js`: Lines 12–16 (Defines candidate model pool with automated rotation: `gemini-3.5-flash`, `gemini-3.6-flash`, `gemini-flash-latest`).
* **Purpose:** Handles end-to-end AI quiz synthesis. The Flutter app delegates quiz generation to a secure serverless backend, protecting API keys and enforcing teacher ownership before calling Gemini.
* **Integration Flow:**
  `UploadGenerateQuizScreen._generateQuiz()` -> `QuizService.generateQuiz()` -> `QuizGenerationClient.generate()` -> HTTP POST with Bearer token -> Cloud Function `generateQuizHttp` -> `generateQuizQuestions()` -> Google Gemini REST endpoint -> Firestore `quizzes` save -> returns generated quiz JSON to Flutter.

---

## 3. Database Integration (Cloud Firestore)

* **Status:** Found
* **Main File:** `lib/services/firestore_provider.dart`
* **Related Files:**
  * `lib/main.dart`
  * `lib/firebase_options.dart`
  * `lib/services/auth_service.dart`
  * `lib/services/class_service.dart`
  * `lib/services/material_service.dart`
  * `lib/services/quiz_service.dart`
  * `lib/services/assignment_service.dart`
* **Class / Service:** `FirebaseFirestore` (obtained via `getAppFirestore()`), plus all feature domain services.
* **Function / Method & Code Locations:**
  * **Initialization:** `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` in `lib/main.dart:10`.
  * **Provider:** `getAppFirestore([FirebaseFirestore? customInstance])` in `lib/services/firestore_provider.dart:4–15` (targets named database `'default'`).
  * **Collections & CRUD Operations:**
    1. **`users` Collection:**
       * Create/Write: `_usersCollection.doc(uid).set(...)` in `AuthService._saveUserProfile` (`lib/services/auth_service.dart:143–157`).
       * Read: `_usersCollection.doc(user.uid).get()` in `AuthService.signInWithEmail` (`lib/services/auth_service.dart:184`).
       * Update: `_usersCollection.doc(user.uid).update({'photoUrl': newPhoto})` in `AuthService.signInWithGoogle` (`lib/services/auth_service.dart:295`).
    2. **`classes` Collection & `classes/{classId}/members` Subcollection:**
       * Create/Write: `batch.set(docRef, newClass.toMap())` and `batch.set(memberRef, ...)` in `ClassService.createClass` (`lib/services/class_service.dart:97–108`).
       * Read/Stream: `_classesCollection.where('teacherId', isEqualTo: teacherId).snapshots()` in `ClassService.getTeacherClassesStream` (`lib/services/class_service.dart:114–129`).
       * Update: `batch.update(classDoc.reference, {'rosterCount': FieldValue.increment(1)})` in `ClassService.joinClassByCode` (`lib/services/class_service.dart:227–231`).
    3. **`users/{studentId}/joinedClasses` Subcollection:**
       * Create/Write: `batch.set(userJoinedClassRef, ...)` in `ClassService.joinClassByCode` (`lib/services/class_service.dart:218–225`).
       * Read/Stream: `_usersCollection.doc(studentId).collection('joinedClasses').snapshots()` in `ClassService.getStudentJoinedClassesStream` (`lib/services/class_service.dart:250–291`).
    4. **`materials` Collection:**
       * Create/Write: `materialDocRef.set(...)` in `MaterialService.uploadStudyMaterial` (`lib/services/material_service.dart:216–220`).
       * Read/Stream: `_firestore.collection('materials').where('classId', isEqualTo: classId).snapshots()` in `MaterialService.streamClassMaterials` (`lib/services/material_service.dart:362–372`).
       * Update: `materialDocRef.update({'status': ..., 'extractedText': ...})` in `MaterialService.retryMaterialExtraction` (`lib/services/material_service.dart:410–415`).
       * Delete: `_firestore.collection('materials').doc(materialId).delete()` in `MaterialService.deleteMaterial` (`lib/services/material_service.dart:447`).
    5. **`quizzes` Collection:**
       * Create/Write: Server-side set in `processQuizGeneration` (`functions/index.js:787`).
       * Read/Stream: `_quizzesCollection.where('classId', isEqualTo: classId).snapshots()` in `QuizService.streamClassQuizzes` (`lib/services/quiz_service.dart:22–44`).
       * Update: `_quizzesCollection.doc(quizId).update({'status': 'published'})` in `QuizService.publishQuiz` (`lib/services/quiz_service.dart:484–488`).
       * Delete: `_quizzesCollection.doc(quizId).delete()` in `QuizService.deleteQuiz` (`lib/services/quiz_service.dart:507`).
    6. **`quizAssignments` Collection:**
       * Create/Write: `docRef.set(...)` in `AssignmentService.createAssignment` (`lib/services/assignment_service.dart:63–66`).
       * Read/Stream: `_assignmentsCollection.where('classId', isEqualTo: classId).snapshots()` in `AssignmentService.streamClassAssignments` (`lib/services/assignment_service.dart:95–111`).
       * Update: `_assignmentsCollection.doc(id).update({'isClosed': true})` in `AssignmentService.closeAssignment` (`lib/services/assignment_service.dart:73–76`).
    7. **`attempts` Collection:**
       * Create/Write: `docRef.set(...)` with `FieldValue.serverTimestamp()` in `AssignmentService._submitAttempt` (`lib/services/assignment_service.dart:188–207`).
       * Read/Stream: `_attemptsCollection.where('classId', isEqualTo: classId)...snapshots()` in `AssignmentService.streamClassQuizAttempts` (`lib/services/assignment_service.dart:217–232`).
    8. **`users/{studentId}/attempts` (Active Draft Answers):**
       * Create/Update: `docRef.set(..., SetOptions(merge: true))` in `AssignmentService.saveDraftAnswers` (`lib/services/assignment_service.dart:275–282`).
       * Read: `docSnapshot = await docRef.get()` in `AssignmentService.getDraftAnswers` (`lib/services/assignment_service.dart:305`).
       * Delete: `await docRef.delete()` in `AssignmentService.clearDraftAnswers` (`lib/services/assignment_service.dart:339`).
* **Purpose:** Provides persistence, querying, multi-document batch operations, and real-time synchronization for all user, academic, and quiz data.

---

## 4. Upload Functionality

* **Status:** Found
* **Main File:** `lib/services/material_service.dart`
* **Related Files:**
  * `lib/screens/teacher/upload_generate_quiz_screen.dart`
  * `lib/utils/document_text_extractor.dart`
  * `lib/models/material_model.dart`
* **Class / Widget:** `UploadGenerateQuizScreen` / `_UploadGenerateQuizScreenState`, `MaterialService`, `DocumentTextExtractor`
* **Function / Method & Locations:**
  * UI Entry Point: `_UploadGenerateQuizScreenState._pickAndUploadFile()` (`lib/screens/teacher/upload_generate_quiz_screen.dart:158–308`).
  * File Picker: `FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf', 'pptx', 'docx'])` (`upload_generate_quiz_screen.dart:179–182`).
  * Validation: `MaterialService.validateUploadRequest()` and `MaterialService.validateFile()` (`lib/services/material_service.dart:37–85`).
  * Processing / Upload: `MaterialService.uploadStudyMaterial()` (`lib/services/material_service.dart:91–258`).
  * Storage Service: `uploadTask = storageRef.putData(resolvedBytes, metadata)` (`lib/services/material_service.dart:152`).
  * Database Record: `materialDocRef.set(...)` in collection `materials` (`lib/services/material_service.dart:216–220`).
* **Purpose:** Validates document extensions (`pdf`, `pptx`, `docx`) and file size (`<= 50MB`), uploads to Firebase Storage, extracts text on-device for instant quiz generation, and saves the material to Firestore.

---

## 5. Main Integration Flow — Upload Study Material

The complete lifecycle from teacher selection to quiz readiness:

```
[Teacher selects document via FilePicker]
               │
               ▼
[Validate format (.pdf, .docx, .pptx), size (<=50MB), and non-empty class ID]
               │
               ▼
[Initiate Firebase Storage upload (putData)] ──► Concurrently run DocumentTextExtractor
               │                                            │
               ▼                                            ▼
[Write Firestore document: 'materials' with status 'ready' & extractedText]
               │
               ▼
[Material stream updates UI] ──► Enables "Generate Quiz" buttons
```

### Step-by-Step Code References:
1. **User selects file:**
   * File: `lib/screens/teacher/upload_generate_quiz_screen.dart`
   * Method: `_UploadGenerateQuizScreenState._pickAndUploadFile()` (lines 178–187) calls `FilePicker.pickFile(...)`.
2. **File is validated:**
   * File: `lib/services/material_service.dart`
   * Method: `MaterialService.validateUploadRequest()` & `validateFile()` (lines 37–85) verifies file extension, file name, positive byte count, 50MB maximum limit, and valid class ID.
3. **File is uploaded and processed:**
   * File: `lib/services/material_service.dart`
   * Method: `MaterialService.uploadStudyMaterial()` (lines 91–258):
     * Storage stream: `_storage.ref().child(storagePath).putData(resolvedBytes, metadata)` (lines 142–167).
     * Local extraction: `DocumentTextExtractor.extract(bytes, extension)` (lines 179–185) from `lib/utils/document_text_extractor.dart`.
4. **API / Service is called:**
   * File: `lib/services/material_service.dart`
   * Method: Background worker (lines 235–245) retrieves `storageRef.getDownloadURL()`. Cloud Storage trigger `extractText` in `functions/index.js` (lines 400–470) also serves as server fallback.
5. **Database / Storage updated:**
   * File: `lib/services/material_service.dart`
   * Method: `materialDocRef.set({...readyModel.toMap(), 'createdAt': FieldValue.serverTimestamp()})` in Firestore `materials` (lines 216–220) and `update({'downloadUrl': url})` (line 241).
6. **Material becomes available to Quiz Feature:**
   * File: `lib/screens/teacher/upload_generate_quiz_screen.dart`
   * Method: Real-time listener `_listenToMaterial()` (lines 422–443) receives document with `status == 'ready'`. The UI unlocks `_generateQuiz()` (lines 466–607).

---

## 6. Main Integration Flow — Take Quiz

The complete student quiz-taking lifecycle:

```
[Student selects Quiz in StudentClassDetailsScreen]
               │
               ▼
[Quiz questions streamed from Firestore collection 'quizzes']
               │
               ▼
[AnswerQuizScreen initializes question queue and loads any cached draft answers]
               │
               ▼
[Student selects / types answers across 5 question types]
               │
               ▼
[Answers saved to in-memory state and Firestore draft attempt]
               │
               ▼
[Student navigates via Next / Prev / Skip / Flag / Question Drawer]
               │
               ▼
[Submit Quiz Confirmation Dialog shown]
```

### Step-by-Step Code References:
1. **User opens/selects a quiz:**
   * File: `lib/screens/student/student_class_details_screen.dart`
   * Method: `_buildPracticeQuizzesTab()` -> "Start Practice Quiz" button `onPressed` (lines 887–920) or "Retake #2" button (lines 860–883) launches `AnswerQuizScreen(quiz: quiz, attemptNumber: 1)`.
2. **Quiz questions are retrieved:**
   * File: `lib/services/quiz_service.dart`
   * Method: `QuizService.streamClassQuizzes(classId, type: 'practice', publishedOnly: true)` (lines 22–44) reads from Firestore `quizzes`, parsed via `QuizModel.fromFirestore()`.
3. **Questions are displayed:**
   * File: `lib/screens/student/answer_quiz_screen.dart`
   * Widget / State: `AnswerQuizScreen` / `_AnswerQuizScreenState.initState()` (lines 142–158) loads questions. `_loadCurrentAnswer()` (lines 250–262) and question builders display the active question.
4. **User selects/types answers:**
   * File: `lib/screens/student/answer_quiz_screen.dart`
   * Method:
     * MCQ / True-False: Direct option tap records selection.
     * Fill-in-the-Blank / Identification: Handled via `_textAnswerController` in `_saveCurrentAnswer()` (lines 264–274).
     * Enumeration: Handled via `_enumInputController` in `_addEnumerationItem()` (lines 405–438).
5. **Answers stored temporarily:**
   * File: `lib/screens/student/answer_quiz_screen.dart` & `lib/services/assignment_service.dart`
   * Method: `_persistDraftAnswers()` (lines 111–121) invokes `AssignmentService.saveDraftAnswers()` (lines 257–285), persisting answers to Firestore `users/{studentId}/attempts/draft_{quizId}_attempt_{attemptNumber}` and in-memory cache.
6. **User proceeds through quiz:**
   * File: `lib/screens/student/answer_quiz_screen.dart`
   * Method:
     * `_goToNext()` (lines 336–371): Advances queue or routes to first unanswered question.
     * `_goToPrevious()` (lines 373–381): Steps backward.
     * `_skipCurrentQuestion()` (lines 306–334): Re-queues current question to the end.
     * `_toggleFlag()` (lines 394–403): Flags question for later review.
     * `_jumpToQuestion()` (lines 383–392): Direct jump from question grid drawer.
7. **Quiz is submitted:**
   * File: `lib/screens/student/answer_quiz_screen.dart`
   * Method: `_goToNext()` on last question or "Submit Quiz" button triggers `_showSubmitConfirmation()` (lines 453–531).

---

## 7. Main Integration Flow — Submit Quiz

What happens when the student presses **Submit**:

```
[User confirms Submit in confirmation dialog]
               │
               ▼
[_evaluateAndShowResults() gathers all user answers]
               │
               ▼
[ScoringUtils grades all 5 types deterministically]
               │
               ▼
[AssignmentService verifies: assignment active, not expired, max 2 attempts]
               │
               ▼
[Write QuizAttemptModel to Firestore collection 'attempts' with server timestamp]
               │
               ▼
[Delete temporary draft in 'users/{studentId}/attempts']
               │
               ▼
[Display results modal dialog with score banner and question-by-question breakdown]
```

### Step-by-Step Code References:
1. **Submit Quiz initiated:**
   * File: `lib/screens/student/answer_quiz_screen.dart`
   * Method: Dialog 'Submit' button invokes `_evaluateAndShowResults()` (lines 522–527 & 533–536).
2. **Collect answers:**
   * File: `lib/screens/student/answer_quiz_screen.dart`
   * Method: `_evaluateAndShowResults()` loops over `_questions`, reading `_userAnswers[q.id]` (lines 540–544).
3. **Validate submission:**
   * File: `lib/screens/student/answer_quiz_screen.dart` & `lib/services/assignment_service.dart`
   * Method:
     * Pre-check: `_showSubmitConfirmation()` verifies `_allQuestionsAnswered` (lines 457–464).
     * Auth verification: `user == null` check (lines 602–613).
     * Backend verification: `AssignmentService._submitAttempt()` (lines 147–185) checks if assignment is closed (`isClosed`), expired (`isExpired`), or if student already has 2 submitted attempts.
4. **Compare / Check answers:**
   * File: `lib/screens/student/answer_quiz_screen.dart` & `lib/utils/scoring_utils.dart`
   * Method:
     * MCQ / True-False: Case-insensitive normalized string match (lines 550–556).
     * Fill-in-the-Blank / Identification: `ScoringUtils.isFreeTextMatch()` in `scoring_utils.dart:27–55`.
     * Enumeration: `ScoringUtils.scoreEnumeration()` in `scoring_utils.dart:58–104`.
5. **Calculate score:**
   * File: `lib/screens/student/answer_quiz_screen.dart`
   * Method: Lines 587–600 sum `totalEarned += earned` and calculate `percentage = totalEarned / totalPossible * 100`.
6. **Save attempt / result:**
   * File: `lib/screens/student/answer_quiz_screen.dart` & `lib/services/assignment_service.dart`
   * Method: Constructs `QuizAttemptModel` (lines 615–645) and calls `_assignmentService.submitAttempt(attempt)` (line 648).
7. **Database transaction:**
   * File: `lib/services/assignment_service.dart`
   * Method: `_submitAttempt()` lines 188–208 writes the attempt to collection `attempts` using `FieldValue.serverTimestamp()`. Draft answers are deleted via `clearDraftAnswers()` (lines 323–342).
8. **Display results:**
   * File: `lib/screens/student/answer_quiz_screen.dart`
   * Method: Lines 678–750 display modal `AlertDialog` with trophy/checkmark header, score percentage, earned points, and expandable question review.

---

## 8. Network Transactions Reference

Comprehensive list of every network request across the entire application:

### 1. Firebase Authentication — Email Registration
* **File:** `lib/services/auth_service.dart`
* **Method:** `AuthService.registerWithEmail()` (lines 56–140)
* **Service Contacted:** Firebase Authentication (`createUserWithEmailAndPassword`) & Cloud Firestore (`users/{uid}`)
* **Data Sent:** Email, password, displayName, role (`teacher` / `student`)
* **Data Received:** `UserCredential`, Firebase `User`, Firestore write ACK
* **Failure Handling:** Catches `FirebaseAuthException` (`email-already-in-use`, `weak-password`, `invalid-email`), implements orphan account recovery, translates messages via `AuthService.getErrorMessage()`, surfaces error via `AppFeedback.error()`.

### 2. Firebase Authentication — Email Login
* **File:** `lib/services/auth_service.dart`
* **Method:** `AuthService.signInWithEmail()` (lines 161–213)
* **Service Contacted:** Firebase Authentication (`signInWithEmailAndPassword`) & Cloud Firestore (`users/{uid}`)
* **Data Sent:** Email, password
* **Data Received:** `UserCredential`, `UserProfile` document snapshot
* **Failure Handling:** Enforces role guarding: if profile role does not match expected role, immediately invokes `_auth.signOut()` and throws `AuthRoleMismatchException`.

### 3. Firebase Authentication — Google Sign-In
* **File:** `lib/services/auth_service.dart`
* **Method:** `AuthService.signInWithGoogle()` (lines 220–300)
* **Service Contacted:** Google Sign-In SDK, Firebase Auth (`signInWithCredential`), Cloud Firestore (`users/{uid}`)
* **Data Sent:** Google OAuth `idToken` and `accessToken`, user profile payload
* **Data Received:** `GoogleSignInAccount`, `AuthCredential`, `UserProfile`
* **Failure Handling:** Returns `null` on cancellation; signs out from Google if role mismatch occurs; catches network timeout errors.

### 4. Upload Study Material (Storage & Firestore)
* **File:** `lib/services/material_service.dart`
* **Method:** `MaterialService.uploadStudyMaterial()` (lines 91–258)
* **Service Contacted:** Firebase Storage (`putData`) & Cloud Firestore (`materials.doc().set`)
* **Data Sent:** Binary document bytes (`Uint8List`), MIME metadata, Firestore document fields
* **Data Received:** Storage `UploadTask` progress snapshot stream, download URL, Firestore write ACK
* **Failure Handling:** 15s timeout guard; cancels storage task if Firestore write fails; surfaces clean user message via `MaterialValidationException`.

### 5. AI Quiz Synthesis (HTTP / Cloud Function to Gemini)
* **File:** `lib/services/quiz_generation_client.dart` (Client) & `functions/index.js` / `functions/quiz_generator.js` (Server)
* **Method:** `QuizGenerationClient.generate()` (lines 34–148)
* **Service Contacted:** Cloud Function REST endpoint (`generateQuizHttp`) -> Google Gemini API (`generativelanguage.googleapis.com/.../generateContent`)
* **Data Sent:** HTTP Headers (`Authorization: Bearer <Firebase_ID_Token>`), JSON body: `{ classId, materialId, quizType, questionTypes, questionCount, sourceQuizId }`
* **Data Received:** JSON: `{ success: true, quizId: "...", quiz: { questions: [...] } }`
* **Failure Handling:** 150-second client timeout; server auto-rotates across candidate models on HTTP `429` (quota) or `503` (unavailable); status codes (400, 401, 403, 404, 412, 422, 429, 504) are translated into user-friendly `QuizGenerationException` messages.

### 6. Submit Quiz Attempt
* **File:** `lib/services/assignment_service.dart`
* **Method:** `AssignmentService.submitAttempt()` (lines 126–210)
* **Service Contacted:** Cloud Firestore (`attempts` collection and `users/{studentId}/attempts`)
* **Data Sent:** `QuizAttemptModel` JSON payload with student answers, points, and score
* **Data Received:** Firestore write confirmation
* **Failure Handling:** 20s timeout; checks assignment availability and attempt limit (throws `QuizUnavailableException`); on failure, answers remain safely in local device state for retry.

### 7. Real-Time Data Streaming (Firestore Snapshots)
* **File:** `lib/services/class_service.dart`, `lib/services/material_service.dart`, `lib/services/quiz_service.dart`, `lib/services/assignment_service.dart`
* **Method:** `getTeacherClassesStream()`, `streamClassMaterials()`, `streamClassQuizzes()`, `streamClassAssignments()`, `streamClassQuizAttempts()`
* **Service Contacted:** Cloud Firestore WebSocket / Long-Polling listener (`snapshots()`)
* **Data Sent:** Query filters (`where()`)
* **Data Received:** Real-time stream of updated document snapshots
* **Failure Handling:** `onError` stream callbacks log errors and display non-blocking `AppFeedback` alerts.

### 8. Download Original Material or Preview PDF
* **File:** `lib/services/material_service.dart`
* **Method:** `MaterialService.getMaterialFileBytes()` (lines 260–292) and `downloadMaterialToTemp()` (lines 330–346)
* **Service Contacted:** HTTP GET (`downloadUrl`) with fallback to Firebase Storage SDK (`getData`)
* **Data Sent:** Storage file URL or bucket path reference
* **Data Received:** Binary file bytes (`Uint8List`)
* **Failure Handling:** Returns `null` on timeout/failure; triggers automatic fallback to the extracted text viewer in `MaterialViewerScreen`.

---

## 9. Other Week 12 API Integrations (Present vs. Not Present)

* **Firebase Authentication:** **Found** — `lib/services/auth_service.dart` (Email/Password & Google Sign-In).
* **Cloud Firestore:** **Found** — `lib/services/firestore_provider.dart` (8 collections and subcollections).
* **Firebase Storage:** **Found** — `lib/services/material_service.dart` (`studexa-b5e55.firebasestorage.app`).
* **Gemini / AI API:** **Found** — `functions/quiz_generator.js` & `functions/index.js` (Google AI Studio REST endpoint).
* **Maps / Google Maps:** **Not Found** — No mapping package or coordinates API integrated.
* **Location Services:** **Not Found** — No GPS or geolocation package used.
* **Push Notifications (FCM):** **Not Found** — No external FCM notification client installed; in-app feedback is used exclusively via `AppFeedback`.
* **HTTP / REST APIs:** **Found** — `package:http` in `lib/services/quiz_generation_client.dart` and `lib/services/material_service.dart`.
* **Google Cloud APIs (Backend):** **Found** — `googleapis` in `functions/index.js` for Google Drive API v3 PPTX/DOCX-to-PDF conversion.

---

## 10. Live Demo Cheatsheet for Instructor Checking

When presenting each feature live on the laptop, open the corresponding file and line number:

| Feature to Show | Screen in App | Exact File to Show in IDE | Key Code Lines |
| :--- | :--- | :--- | :--- |
| **API Call (Gemini/Cloud Function)** | Teacher: Generate Quiz | `lib/services/quiz_generation_client.dart` | Lines 34–148 (`generate`) |
| **Model Pool & Rotation** | Backend Server | `functions/quiz_generator.js` | Lines 12–16, 151–183 |
| **File Picker & Upload** | Teacher: Upload Material | `lib/screens/teacher/upload_generate_quiz_screen.dart` | Lines 179–182, 237–257 |
| **Storage Upload & Validation** | Backend / Storage | `lib/services/material_service.dart` | Lines 37–85, 142–170 |
| **Taking a Quiz** | Student: Answer Quiz Screen | `lib/screens/student/answer_quiz_screen.dart` | Lines 142–158, 264–304 |
| **Scoring & Quiz Submission** | Student: Submit Quiz | `lib/screens/student/answer_quiz_screen.dart` | Lines 533–665 |
| **Saving Attempt to Database** | Student: Submitting Attempt | `lib/services/assignment_service.dart` | Lines 147–210 |
| **Firestore Real-time Streams** | Teacher/Student Class Details | `lib/services/class_service.dart`, `quiz_service.dart` | `quiz_service.dart:22–44` |
| **Role Guarding & Auth** | Login Screen | `lib/services/auth_service.dart` | Lines 161–213, 220–300 |
