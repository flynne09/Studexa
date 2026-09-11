import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:studexa/models/material_model.dart';
import 'package:studexa/services/material_service.dart';
import 'package:studexa/services/quiz_service.dart';
import 'package:studexa/utils/document_text_extractor.dart';

void setupMockFirebase() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MethodChannelFirebase.appInstances['[DEFAULT]'] = MethodChannelFirebaseApp(
    '[DEFAULT]',
    const FirebaseOptions(
      apiKey: 'mock-key',
      appId: 'mock-id',
      messagingSenderId: 'mock-sender',
      projectId: 'studexa-test',
      storageBucket: 'studexa-test.appspot.com',
    ),
  );
  MethodChannelFirebase.isCoreInitialized = true;
}

void main() {
  setUpAll(() {
    setupMockFirebase();
  });

  group('Task 7 — PDF Upload and Text Extraction Optimization Tests', () {
    test('1. MaterialModel.contentTypeForExtension correctly maps document MIME types', () {
      expect(MaterialModel.contentTypeForExtension('pdf'), 'application/pdf');
      expect(MaterialModel.contentTypeForExtension('.PDF'), 'application/pdf');
      expect(MaterialModel.contentTypeForExtension('docx'), 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
      expect(MaterialModel.contentTypeForExtension('.pptx'), 'application/vnd.openxmlformats-officedocument.presentationml.presentation');
      expect(MaterialModel.contentTypeForExtension('xyz'), 'application/octet-stream');
    });

    test('2. PDF pre-sanitization fast-paths clean documents and safely sanitizes null outlines', () async {
      // Clean document with no null dictionary keywords
      final cleanBytes = Uint8List.fromList(List.filled(1024 * 100, 0x41)); // 100KB of 'A'
      final swClean = Stopwatch()..start();
      final resultClean = await DocumentTextExtractor.extract(bytes: cleanBytes, extension: 'pdf');
      swClean.stop();
      // Since it's not a real PDF, returns parse_error quickly without crashing
      expect(resultClean.isSuccess, isFalse);

      // Real complex PDF fixture with /Outlines null
      final file = File('test/fixtures/sample_materials/research_ppt_export.pdf');
      expect(file.existsSync(), isTrue);
      final pdfBytes = await file.readAsBytes();

      final swExtract = Stopwatch()..start();
      final result = await DocumentTextExtractor.extract(bytes: pdfBytes, extension: 'pdf');
      swExtract.stop();

      expect(result.isSuccess, isTrue);
      expect(result.text.length, greaterThan(5000));
      expect(swExtract.elapsedMilliseconds, lessThan(3500)); // Fast extraction
    });

    test('3. Immediate Quiz Generation from extracted material without waiting for Storage URL', () async {
      final file = File('test/fixtures/sample_materials/research_ppt_export.pdf');
      final pdfBytes = await file.readAsBytes();
      final extractionResult = await DocumentTextExtractor.extract(bytes: pdfBytes, extension: 'pdf');
      expect(extractionResult.isSuccess, isTrue);

      // Verify questions generate directly and deterministically
      final questions = QuizService.generateLocalFallbackQuestions(
        extractedText: extractionResult.text,
        questionTypes: ['multipleChoice', 'trueFalse', 'fillInTheBlank', 'identification', 'enumeration'],
        questionCount: 10,
        isActual: false,
      );

      expect(questions.length, 10);
      for (final q in questions) {
        expect(q.question.isNotEmpty, isTrue);
        expect(q.correctAnswer.isNotEmpty, isTrue);
        expect(QuizService.isTableHeaderQuestion(q), isFalse);
        expect(QuizService.isFillerOrBoilerplateQuestion(q), isFalse);
      }
    });

    test('4. MaterialService validates upload requests fast and prevents invalid uploads before network calls', () {
      expect(
        () => MaterialService.validateUploadRequest(
          classId: 'class_abc',
          fileName: 'lecture.pdf',
          extension: 'pdf',
          byteLength: 1024 * 1024 * 5,
        ),
        returnsNormally,
      );

      expect(
        () => MaterialService.validateUploadRequest(
          classId: '',
          fileName: 'lecture.pdf',
          extension: 'pdf',
          byteLength: 1024,
        ),
        throwsA(isA<MaterialValidationException>()),
      );
    });
  });
}
