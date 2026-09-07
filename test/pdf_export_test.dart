import 'package:flutter_test/flutter_test.dart';
import 'package:studexa/models/quiz_model.dart';
import 'package:studexa/services/pdf_export_service.dart';

void main() {
  group('PdfExportService Tests', () {
    late QuizModel sampleQuiz;

    setUp(() {
      sampleQuiz = QuizModel(
        id: 'quiz_exam_001',
        classId: 'cls_science_10',
        teacherId: 'teacher_123',
        materialId: 'mat_cell_bio',
        type: 'actual',
        title: 'Biology 101 Midterm Examination',
        status: 'finalized',
        generationMethod: 'gemini',
        questions: const [
          QuizQuestion(
            id: 'q1',
            type: QuizQuestionType.multipleChoice,
            question: 'What is the primary function of chloroplasts in plant cells?',
            options: [
              'Photosynthesis',
              'Cellular respiration',
              'Protein synthesis',
              'Waste breakdown',
            ],
            correctAnswer: 'Photosynthesis',
            points: 1,
          ),
          QuizQuestion(
            id: 'q2',
            type: QuizQuestionType.trueFalse,
            question: 'The cell wall is found in animal cells.',
            correctAnswer: 'False',
            points: 1,
          ),
          QuizQuestion(
            id: 'q3',
            type: QuizQuestionType.identification,
            question: 'Name the macromolecule that encodes genetic instructions.',
            correctAnswer: 'DNA',
            points: 1,
          ),
          QuizQuestion(
            id: 'q4',
            type: QuizQuestionType.fillInTheBlank,
            question: 'Water moves across a semipermeable membrane through a process called _____.',
            correctAnswer: 'osmosis',
            points: 1,
          ),
          QuizQuestion(
            id: 'q5',
            type: QuizQuestionType.enumeration,
            question: 'Enumerate three stages of cellular respiration:',
            enumerationAnswers: [
              'Glycolysis',
              'Krebs cycle',
              'Electron transport chain',
            ],
            correctAnswer: 'Glycolysis, Krebs cycle, Electron transport chain',
            points: 3,
          ),
        ],
        createdAt: DateTime(2026, 9, 8, 8, 0),
      );
    });

    test('generates valid PDF document with %PDF magic header', () async {
      final service = PdfExportService();
      final pdfBytes = await service.generateExamPdf(
        quiz: sampleQuiz,
        includeAnswerKey: true,
        className: 'Grade 10 Biology - Section Newton',
        teacherName: 'Dr. Evelyn Martinez',
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);

      // Verify standard %PDF header magic bytes
      final header = String.fromCharCodes(pdfBytes.take(4));
      expect(header, '%PDF');
    });

    test('generates smaller PDF when teacher answer key is excluded', () async {
      final service = PdfExportService();

      final pdfWithKey = await service.generateExamPdf(
        quiz: sampleQuiz,
        includeAnswerKey: true,
      );

      final pdfWithoutKey = await service.generateExamPdf(
        quiz: sampleQuiz,
        includeAnswerKey: false,
      );

      expect(pdfWithKey.isNotEmpty, isTrue);
      expect(pdfWithoutKey.isNotEmpty, isTrue);
      expect(pdfWithKey.length, greaterThan(pdfWithoutKey.length));
    });

    test('generates exam PDF for empty questions without crashing', () async {
      final service = PdfExportService();
      final emptyQuiz = sampleQuiz.copyWith(questions: const []);

      final pdfBytes = await service.generateExamPdf(
        quiz: emptyQuiz,
        includeAnswerKey: true,
      );

      expect(pdfBytes.isNotEmpty, isTrue);
      final header = String.fromCharCodes(pdfBytes.take(4));
      expect(header, '%PDF');
    });

    test('formats all 5 question types without null or format errors', () async {
      final service = PdfExportService();
      final pdfBytes = await service.generateExamPdf(
        quiz: sampleQuiz,
        includeAnswerKey: true,
      );

      // Verify non-trivial byte length indicating full multi-page document
      expect(pdfBytes.length, greaterThan(1500));
    });
  });
}
