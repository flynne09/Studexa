import 'package:flutter_test/flutter_test.dart';
import 'package:studexa/models/material_model.dart';
import 'package:studexa/services/material_service.dart';

void main() {
  group('MaterialModel Tests', () {
    test('serializes and deserializes properly', () {
      final now = DateTime.now();
      final model = MaterialModel(
        id: 'mat_001',
        teacherId: 'teacher_abc',
        classId: 'class_xyz',
        fileName: 'Biology_Chapter1.pdf',
        fileType: 'pdf',
        fileRef: 'uploads/teacher_abc/mat_001/Biology_Chapter1.pdf',
        status: 'ready',
        errorReason: null,
        extractedText: 'Chapter 1: The Cell is the fundamental unit of life.',
        createdAt: now,
        extractedAt: now,
        fileSizeBytes: 1024 * 500, // 500 KB
      );

      final map = model.toMap();
      expect(map['teacherId'], 'teacher_abc');
      expect(map['classId'], 'class_xyz');
      expect(map['fileName'], 'Biology_Chapter1.pdf');
      expect(map['fileType'], 'pdf');
      expect(map['status'], 'ready');
      expect(map['extractedText'], contains('fundamental unit of life'));
      expect(map['fileSizeBytes'], 1024 * 500);

      final deserialized = MaterialModel.fromMap(map, 'mat_001');
      expect(deserialized.id, 'mat_001');
      expect(deserialized.teacherId, 'teacher_abc');
      expect(deserialized.classId, 'class_xyz');
      expect(deserialized.fileName, 'Biology_Chapter1.pdf');
      expect(deserialized.fileType, 'pdf');
      expect(deserialized.status, 'ready');
      expect(deserialized.isReady, isTrue);
      expect(deserialized.isProcessing, isFalse);
      expect(deserialized.hasFailed, isFalse);
    });

    test('state getters function correctly', () {
      final processingModel = MaterialModel(
        id: 'mat_proc',
        teacherId: 't1',
        classId: 'c1',
        fileName: 'slides.pptx',
        fileType: 'pptx',
        fileRef: 'ref',
        status: 'processing',
        createdAt: DateTime.now(),
      );
      expect(processingModel.isProcessing, isTrue);
      expect(processingModel.isReady, isFalse);
      expect(processingModel.hasFailed, isFalse);

      final failedModel = MaterialModel(
        id: 'mat_failed',
        teacherId: 't1',
        classId: 'c1',
        fileName: 'corrupt.docx',
        fileType: 'docx',
        fileRef: 'ref',
        status: 'failed',
        errorReason: 'no_extractable_text',
        createdAt: DateTime.now(),
      );
      expect(failedModel.hasFailed, isTrue);
      expect(failedModel.isReady, isFalse);
      expect(failedModel.isProcessing, isFalse);
      expect(failedModel.formattedError, contains('OCR is not supported'));
    });

    test('content types are correctly mapped for PDF, DOCX, and PPTX', () {
      final pdf = MaterialModel(
        id: '1',
        teacherId: 't',
        classId: 'c',
        fileName: 'doc.pdf',
        fileType: 'pdf',
        fileRef: 'r',
        status: 'ready',
        createdAt: DateTime.now(),
      );
      expect(pdf.contentType, 'application/pdf');

      final docx = MaterialModel(
        id: '2',
        teacherId: 't',
        classId: 'c',
        fileName: 'doc.docx',
        fileType: 'docx',
        fileRef: 'r',
        status: 'ready',
        createdAt: DateTime.now(),
      );
      expect(docx.contentType, contains('wordprocessingml'));

      final pptx = MaterialModel(
        id: '3',
        teacherId: 't',
        classId: 'c',
        fileName: 'doc.pptx',
        fileType: 'pptx',
        fileRef: 'r',
        status: 'ready',
        createdAt: DateTime.now(),
      );
      expect(pptx.contentType, contains('presentationml'));
    });

    test('formattedFileSize displays accurate scale', () {
      final bModel = MaterialModel(
        id: '1',
        teacherId: 't',
        classId: 'c',
        fileName: 'small.txt',
        fileType: 'pdf',
        fileRef: 'r',
        status: 'ready',
        createdAt: DateTime.now(),
        fileSizeBytes: 512,
      );
      expect(bModel.formattedFileSize, '512 B');

      final kbModel = MaterialModel(
        id: '2',
        teacherId: 't',
        classId: 'c',
        fileName: 'medium.pdf',
        fileType: 'pdf',
        fileRef: 'r',
        status: 'ready',
        createdAt: DateTime.now(),
        fileSizeBytes: 2048,
      );
      expect(kbModel.formattedFileSize, '2.0 KB');

      final mbModel = MaterialModel(
        id: '3',
        teacherId: 't',
        classId: 'c',
        fileName: 'large.pdf',
        fileType: 'pdf',
        fileRef: 'r',
        status: 'ready',
        createdAt: DateTime.now(),
        fileSizeBytes: 1024 * 1024 * 15,
      );
      expect(mbModel.formattedFileSize, '15.0 MB');
    });
  });

  group('MaterialService File Validation Tests', () {
    test('accepts valid PDF, PPTX, and DOCX within 50MB', () {
      expect(
        () => MaterialService.validateFile(
          fileName: 'notes.pdf',
          extension: 'pdf',
          byteLength: 1024 * 1024 * 5, // 5 MB
        ),
        returnsNormally,
      );

      expect(
        () => MaterialService.validateFile(
          fileName: 'slides.pptx',
          extension: '.PPTX', // with dot and uppercase
          byteLength: 1024 * 1024 * 20, // 20 MB
        ),
        returnsNormally,
      );

      expect(
        () => MaterialService.validateFile(
          fileName: 'assignment.docx',
          extension: 'docx',
          byteLength: 5000,
        ),
        returnsNormally,
      );
    });

    test('rejects unsupported file formats', () {
      expect(
        () => MaterialService.validateFile(
          fileName: 'photo.jpg',
          extension: 'jpg',
          byteLength: 1000,
        ),
        throwsA(isA<MaterialValidationException>().having(
          (e) => e.message,
          'message',
          contains('Unsupported file format ".jpg"'),
        )),
      );

      expect(
        () => MaterialService.validateFile(
          fileName: 'sheet.xlsx',
          extension: 'xlsx',
          byteLength: 1000,
        ),
        throwsA(isA<MaterialValidationException>()),
      );
    });

    test('rejects 0-byte empty file', () {
      expect(
        () => MaterialService.validateFile(
          fileName: 'empty.pdf',
          extension: 'pdf',
          byteLength: 0,
        ),
        throwsA(isA<MaterialValidationException>().having(
          (e) => e.message,
          'message',
          contains('empty (0 bytes)'),
        )),
      );
    });

    test('rejects file larger than 50MB', () {
      const oversized = 51 * 1024 * 1024; // 51 MB
      expect(
        () => MaterialService.validateFile(
          fileName: 'huge.pdf',
          extension: 'pdf',
          byteLength: oversized,
        ),
        throwsA(isA<MaterialValidationException>().having(
          (e) => e.message,
          'message',
          contains('exceeds the 50 MB upload limit'),
        )),
      );
    });

    test('rejects material upload with empty classId', () {
      expect(
        () => MaterialService.validateUploadRequest(
          classId: '   ',
          fileName: 'lecture.pdf',
          extension: 'pdf',
          byteLength: 1024,
        ),
        throwsA(isA<MaterialValidationException>().having(
          (e) => e.message,
          'message',
          contains('A target class must be selected'),
        )),
      );
    });

    test('userFriendlyErrorReason matches formattedError', () {
      final model = MaterialModel(
        id: 'mat_err',
        teacherId: 't1',
        classId: 'c1',
        fileName: 'scan.pdf',
        fileType: 'pdf',
        fileRef: 'ref',
        status: 'failed',
        errorReason: 'no_extractable_text',
        createdAt: DateTime.now(),
      );
      expect(model.userFriendlyErrorReason, model.formattedError);
    });
  });
}
