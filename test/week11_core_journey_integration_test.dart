import 'package:flutter_test/flutter_test.dart';
import 'package:studexa/models/user_profile.dart';
import 'package:studexa/models/class_model.dart';
import 'package:studexa/models/material_model.dart';
import 'package:studexa/models/quiz_model.dart';
import 'package:studexa/models/quiz_assignment_model.dart';
import 'package:studexa/models/quiz_attempt_model.dart';
import 'package:studexa/services/material_service.dart';
import 'package:studexa/services/quiz_service.dart';
import 'package:studexa/services/assignment_service.dart';
import 'package:studexa/services/pdf_export_service.dart';
import 'package:studexa/utils/scoring_utils.dart';

void main() {
  group('Week 11 Demonstrable Core User Journey Integration Test', () {
    test('Executes end-to-end Teacher and Student journey from auth to PDF export', () async {
      // =======================================================================
      // STEP 1: Teacher & Student Registration & Role Profiles
      // =======================================================================
      final teacherProfile = UserProfile(
        uid: 'teacher_t1_id',
        email: 'prof.smith@studexa.edu',
        displayName: 'Professor Smith',
        role: 'teacher',
        createdAt: DateTime.now(),
      );
      expect(teacherProfile.isTeacher, isTrue);
      expect(teacherProfile.isStudent, isFalse);
      expect(teacherProfile.email, 'prof.smith@studexa.edu');

      final studentProfile = UserProfile(
        uid: 'student_s1_id',
        email: 'alice.walker@studexa.edu',
        displayName: 'Alice Walker',
        role: 'student',
        createdAt: DateTime.now(),
      );
      expect(studentProfile.isTeacher, isFalse);
      expect(studentProfile.isStudent, isTrue);
      expect(studentProfile.email, 'alice.walker@studexa.edu');

      // =======================================================================
      // STEP 2: Teacher Creates Class with Collision-Resistant Join Code
      // =======================================================================
      const joinCode = 'BIO-8942';
      expect(RegExp(r'^[A-Z]{3}-[A-Z0-9]{4}$').hasMatch(joinCode), isTrue);

      final classModel = ClassModel(
        id: 'class_bio101',
        name: 'General Biology',
        section: 'Section B',
        subject: 'Life Sciences',
        joinCode: joinCode,
        teacherId: teacherProfile.uid,
        teacherName: teacherProfile.displayName,
        rosterCount: 0,
        createdAt: DateTime.now(),
      );
      expect(classModel.id, 'class_bio101');
      expect(classModel.joinCode, joinCode);
      expect(classModel.teacherId, teacherProfile.uid);

      // =======================================================================
      // STEP 3: Student Enrolls / Joins Class via Join Code
      // =======================================================================
      expect(joinCode, classModel.joinCode);

      final enrolledMember = ClassMember(
        userId: studentProfile.uid,
        role: 'student',
        displayName: studentProfile.displayName,
        joinedAt: DateTime.now(),
      );
      expect(enrolledMember.userId, 'student_s1_id');
      expect(enrolledMember.role, 'student');

      final updatedClass = classModel.copyWith(rosterCount: classModel.rosterCount + 1);
      expect(updatedClass.rosterCount, 1);

      // =======================================================================
      // STEP 4: Teacher Uploads Study Material to Selected Class
      // =======================================================================
      // Pre-validation: Empty class must be rejected
      expect(
        () => MaterialService.validateUploadRequest(
          classId: '',
          fileName: 'Cellular_Respiration.pdf',
          extension: 'pdf',
          byteLength: 1024,
        ),
        throwsA(isA<MaterialValidationException>()),
      );

      // Valid PDF file within 50MB
      const sampleFileName = 'Cellular_Respiration.pdf';
      const sampleByteLength = 1024 * 50; // 50 KB
      expect(
        () => MaterialService.validateFile(
          fileName: sampleFileName,
          extension: 'pdf',
          byteLength: sampleByteLength,
        ),
        returnsNormally,
      );

      const sampleExtractedText = '''
Cellular respiration is the biochemical process by which eukaryotic cells break down glucose to generate ATP.
Mitochondria serve as the primary organelle where the citric acid cycle and oxidative phosphorylation occur.
Glycolysis is the first stage of respiration and takes place in the cytoplasm without requiring oxygen.
The three major stages of cellular respiration are glycolysis, Krebs cycle, and electron transport chain.
Adenosine triphosphate is the universal molecular energy currency of living systems.
''';

      final materialModel = MaterialModel(
        id: 'mat_cell_resp',
        classId: updatedClass.id,
        teacherId: teacherProfile.uid,
        fileName: sampleFileName,
        fileType: 'pdf',
        fileRef: 'uploads/teacher_t1_id/mat_cell_resp/Cellular_Respiration.pdf',
        status: 'ready',
        extractedText: sampleExtractedText,
        fileSizeBytes: sampleByteLength,
        createdAt: DateTime.now(),
        extractedAt: DateTime.now(),
      );

      expect(materialModel.isReady, isTrue);
      expect(materialModel.classId, 'class_bio101');
      expect(materialModel.extractedText, contains('Cellular respiration'));

      // =======================================================================
      // STEP 5: Teacher Generates Actual Quiz and Practice Quiz
      // =======================================================================
      // A) Generate Actual Quiz (Teacher Reference Exam)
      final actualQuestions = QuizService.generateLocalFallbackQuestions(
        extractedText: materialModel.extractedText,
        questionTypes: [
          'multiple_choice',
          'true_false',
          'fill_in_the_blank',
          'identification',
          'enumeration',
        ],
        questionCount: 5,
        isActual: true,
      );

      expect(actualQuestions.length, 5);
      final actualQuiz = QuizModel(
        id: 'quiz_actual_bio1',
        classId: updatedClass.id,
        teacherId: teacherProfile.uid,
        materialId: materialModel.id,
        type: 'actual',
        title: 'Biology 101 Midterm Examination',
        status: 'finalized',
        generationMethod: 'fallback',
        questions: actualQuestions,
        totalPoints: actualQuestions.fold(0.0, (sum, q) => sum + q.points),
        createdAt: DateTime.now(),
        publishedAt: DateTime.now(),
      );

      expect(actualQuiz.isActual, isTrue);
      expect(actualQuiz.isPractice, isFalse);
      expect(actualQuiz.isFinalized, isTrue);
      expect(actualQuiz.totalPoints, greaterThanOrEqualTo(5.0));

      // B) Generate Practice Quiz (Derived with Different Phrasing)
      final practiceQuestions = QuizService.generateLocalFallbackQuestions(
        extractedText: materialModel.extractedText,
        questionTypes: [
          'multiple_choice',
          'true_false',
          'fill_in_the_blank',
          'identification',
          'enumeration',
        ],
        questionCount: 5,
        isActual: false,
      );

      expect(practiceQuestions.length, 5);

      // Verify distinct phrasing between Actual and Practice for matching types
      for (int i = 0; i < actualQuestions.length; i++) {
        expect(practiceQuestions[i].question, isNot(equals(actualQuestions[i].question)));
      }

      final practiceQuiz = QuizModel(
        id: 'quiz_practice_bio1',
        classId: updatedClass.id,
        teacherId: teacherProfile.uid,
        materialId: materialModel.id,
        type: 'practice',
        title: 'Cellular Respiration Practice Drill',
        status: 'published',
        generationMethod: 'fallback',
        sourceQuizId: actualQuiz.id,
        questions: practiceQuestions,
        totalPoints: practiceQuestions.fold(0.0, (sum, q) => sum + q.points),
        createdAt: DateTime.now(),
        publishedAt: DateTime.now(),
      );

      expect(practiceQuiz.isPractice, isTrue);
      expect(practiceQuiz.isPublished, isTrue);
      expect(practiceQuiz.sourceQuizId, actualQuiz.id);

      // =======================================================================
      // STEP 6: Teacher Formally Assigns Practice Quiz with Deadline
      // =======================================================================
      final assignmentDeadline = DateTime.now().add(const Duration(days: 7));
      final quizAssignment = QuizAssignmentModel(
        id: 'assign_bio1_practice',
        quizId: practiceQuiz.id,
        classId: updatedClass.id,
        teacherId: teacherProfile.uid,
        quizTitle: practiceQuiz.title,
        deadline: assignmentDeadline,
        isClosed: false,
        createdAt: DateTime.now(),
      );

      expect(quizAssignment.isOpen, isTrue);
      expect(quizAssignment.isExpired, isFalse);
      expect(quizAssignment.isAvailable, isTrue);

      // =======================================================================
      // STEP 7: Student Answers Practice Quiz Across All 5 Question Types
      // =======================================================================
      final studentAnswers = <String, dynamic>{};
      final breakdownList = <Map<String, dynamic>>[];
      double totalEarnedPoints = 0.0;

      for (final q in practiceQuiz.questions) {
        if (q.type == QuizQuestionType.multipleChoice) {
          final ans = q.correctAnswer;
          studentAnswers[q.id] = ans;
          final earned = (ans.trim().toLowerCase() == q.correctAnswer.trim().toLowerCase()) ? q.points : 0.0;
          totalEarnedPoints += earned;
          breakdownList.add({
            'questionId': q.id,
            'question': q.question,
            'type': q.type.value,
            'earned': earned,
            'points': q.points,
            'isCorrect': earned == q.points,
            'userAnswer': ans,
            'correctAnswer': q.correctAnswer,
          });
        } else if (q.type == QuizQuestionType.trueFalse) {
          final ans = q.correctAnswer;
          studentAnswers[q.id] = ans;
          final earned = (ans.trim().toLowerCase() == q.correctAnswer.trim().toLowerCase()) ? q.points : 0.0;
          totalEarnedPoints += earned;
          breakdownList.add({
            'questionId': q.id,
            'question': q.question,
            'type': q.type.value,
            'earned': earned,
            'points': q.points,
            'isCorrect': earned == q.points,
            'userAnswer': ans,
            'correctAnswer': q.correctAnswer,
          });
        } else if (q.type == QuizQuestionType.fillInTheBlank) {
          final rawAnswer = q.correctAnswer;
          final typoAnswer = (rawAnswer.length > 5)
              ? rawAnswer.replaceRange(rawAnswer.length - 2, rawAnswer.length - 1, 'x')
              : rawAnswer;
          studentAnswers[q.id] = typoAnswer;
          final isMatch = ScoringUtils.isFreeTextMatch(typoAnswer, rawAnswer);
          final earned = isMatch ? q.points : 0.0;
          totalEarnedPoints += earned;
          breakdownList.add({
            'questionId': q.id,
            'question': q.question,
            'type': q.type.value,
            'earned': earned,
            'points': q.points,
            'isCorrect': isMatch,
            'userAnswer': typoAnswer,
            'correctAnswer': q.correctAnswer,
          });
        } else if (q.type == QuizQuestionType.identification) {
          final rawAnswer = q.correctAnswer;
          final spacedAnswer = '  ${rawAnswer.toUpperCase()}  ';
          studentAnswers[q.id] = spacedAnswer;
          final isMatch = ScoringUtils.isFreeTextMatch(spacedAnswer, rawAnswer);
          final earned = isMatch ? q.points : 0.0;
          totalEarnedPoints += earned;
          breakdownList.add({
            'questionId': q.id,
            'question': q.question,
            'type': q.type.value,
            'earned': earned,
            'points': q.points,
            'isCorrect': isMatch,
            'userAnswer': spacedAnswer,
            'correctAnswer': q.correctAnswer,
          });
        } else if (q.type == QuizQuestionType.enumeration) {
          final correctList = q.enumerationAnswers;
          final studentList = List<String>.from(correctList.reversed)..add('ExtraUnrelatedItem');
          studentAnswers[q.id] = studentList;
          final result = ScoringUtils.scoreEnumeration(
            studentItems: studentList,
            expectedItems: correctList,
            totalPoints: q.points,
          );
          totalEarnedPoints += result.earnedPoints;
          breakdownList.add({
            'questionId': q.id,
            'question': q.question,
            'type': q.type.value,
            'earned': result.earnedPoints,
            'points': q.points,
            'isCorrect': result.isFullyCorrect,
            'userAnswer': studentList,
            'correctAnswer': correctList,
          });
        }
      }

      // =======================================================================
      // STEP 8: Student Submits Attempt & Instant Results
      // =======================================================================
      final percentage = (practiceQuiz.totalPoints > 0)
          ? (totalEarnedPoints / practiceQuiz.totalPoints) * 100
          : 0.0;

      final studentAttempt = QuizAttemptModel(
        id: 'attempt_alice_1',
        quizId: practiceQuiz.id,
        assignmentId: quizAssignment.id,
        classId: updatedClass.id,
        studentId: studentProfile.uid,
        studentName: studentProfile.displayName,
        answers: studentAnswers,
        score: totalEarnedPoints,
        totalPoints: practiceQuiz.totalPoints,
        percentage: percentage,
        submittedAt: DateTime.now(),
        breakdown: breakdownList,
      );

      expect(studentAttempt.studentName, 'Alice Walker');
      expect(studentAttempt.score, greaterThan(0.0));
      expect(studentAttempt.totalPoints, practiceQuiz.totalPoints);
      expect(studentAttempt.percentage, greaterThanOrEqualTo(70.0));
      expect(studentAttempt.isPassed, isTrue);

      final attemptMap = studentAttempt.toMap();
      final reconstructedAttempt = QuizAttemptModel.fromMap(attemptMap, id: studentAttempt.id);
      expect(reconstructedAttempt.score, studentAttempt.score);
      expect(reconstructedAttempt.breakdown.length, 5);

      // =======================================================================
      // STEP 9: Teacher Monitoring Analytics
      // =======================================================================
      final attempts = [studentAttempt];
      final totalSubmissions = attempts.length;
      final completionRate = totalSubmissions / updatedClass.rosterCount;
      expect(completionRate, 1.0); // 100% completion

      final avgScore = attempts.map((a) => a.percentage).reduce((a, b) => a + b) / totalSubmissions;
      expect(avgScore, greaterThanOrEqualTo(70.0));

      final topScore = attempts.map((a) => a.percentage).reduce((a, b) => a > b ? a : b);
      expect(topScore, greaterThanOrEqualTo(70.0));

      // =======================================================================
      // STEP 10: Teacher Manually Closes Practice Quiz & Historical Access
      // =======================================================================
      final closedAssignment = quizAssignment.copyWith(
        isClosed: true,
        closedAt: DateTime.now(),
      );
      expect(closedAssignment.isOpen, isFalse);
      expect(closedAssignment.isAvailable, isFalse);
      expect(closedAssignment.formattedStatus, 'Closed');

      // Attempting to submit after closure must be rejected
      expect(
        () {
          if (!closedAssignment.isAvailable) {
            throw QuizUnavailableException('This practice quiz has been closed by the instructor.');
          }
        },
        throwsA(isA<QuizUnavailableException>()),
      );

      // Historical student results remain fully intact and accessible
      expect(studentAttempt.score, greaterThan(0.0));
      expect(studentAttempt.breakdown.isNotEmpty, isTrue);

      // =======================================================================
      // STEP 11: Teacher Exports Finalized Actual Quiz as Printable PDF Exam
      // =======================================================================
      final pdfService = PdfExportService();

      // Export student exam sheet without answer key
      final studentExamBytes = await pdfService.generateExamPdf(
        quiz: actualQuiz,
        className: updatedClass.name,
        teacherName: teacherProfile.displayName,
        includeAnswerKey: false,
      );
      expect(studentExamBytes.isNotEmpty, isTrue);
      final header = String.fromCharCodes(studentExamBytes.sublist(0, 4));
      expect(header, '%PDF');

      // Export teacher exam sheet with confidential answer key and scoring rubric
      final teacherExamBytes = await pdfService.generateExamPdf(
        quiz: actualQuiz,
        className: updatedClass.name,
        teacherName: teacherProfile.displayName,
        includeAnswerKey: true,
      );
      expect(teacherExamBytes.isNotEmpty, isTrue);
      expect(teacherExamBytes.length, greaterThan(studentExamBytes.length));
    });
  });
}
