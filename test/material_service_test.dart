import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:studexa/models/material_model.dart';
import 'package:studexa/services/material_service.dart';

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
        throwsA(
          isA<MaterialValidationException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported file format ".jpg"'),
          ),
        ),
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
        throwsA(
          isA<MaterialValidationException>().having(
            (e) => e.message,
            'message',
            contains('empty (0 bytes)'),
          ),
        ),
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
        throwsA(
          isA<MaterialValidationException>().having(
            (e) => e.message,
            'message',
            contains('exceeds the 50 MB upload limit'),
          ),
        ),
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
        throwsA(
          isA<MaterialValidationException>().having(
            (e) => e.message,
            'message',
            contains('A target class must be selected'),
          ),
        ),
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

      final unavailable = MaterialModel(
        id: 'mat_unavail',
        teacherId: 't1',
        classId: 'c1',
        fileName: 'file.docx',
        fileType: 'docx',
        fileRef: 'ref',
        status: 'failed',
        errorReason: 'file_bytes_unavailable',
        createdAt: DateTime.now(),
      );
      expect(
        unavailable.formattedError,
        contains('Original document file is unavailable'),
      );
    });

    test(
      'formattedError accurately distinguishes parse_error from no_extractable_text',
      () {
        final parseErrorModel = MaterialModel(
          id: 'mat_parse',
          teacherId: 't1',
          classId: 'c1',
          fileName: 'corrupt.pdf',
          fileType: 'pdf',
          fileRef: 'ref',
          status: 'failed',
          errorReason: 'parse_error',
          createdAt: DateTime.now(),
        );
        expect(
          parseErrorModel.formattedError,
          "This file couldn't be processed — try re-exporting it or use a different format.",
        );

        final noTextModel = MaterialModel(
          id: 'mat_notext',
          teacherId: 't1',
          classId: 'c1',
          fileName: 'scanned_image.pdf',
          fileType: 'pdf',
          fileRef: 'ref',
          status: 'failed',
          errorReason: 'no_extractable_text',
          createdAt: DateTime.now(),
        );
        expect(
          noTextModel.formattedError,
          'No extractable text found in this file. Please ensure the document contains readable text and is not a scanned image (OCR is not supported in Phase 1).',
        );
      },
    );

    test('supports downloadUrl serialization and copyWith', () {
      final model = MaterialModel(
        id: 'mat_dl',
        teacherId: 't1',
        classId: 'c1',
        fileName: 'lesson.pdf',
        fileType: 'pdf',
        fileRef: 'uploads/t1/mat_dl/lesson.pdf',
        downloadUrl:
            'https://firebasestorage.googleapis.com/v0/b/bucket/o/lesson.pdf?alt=media',
        status: 'ready',
        createdAt: DateTime.now(),
      );

      final map = model.toMap();
      expect(map['downloadUrl'], contains('firebasestorage.googleapis.com'));

      final restored = MaterialModel.fromMap(map, 'mat_dl');
      expect(restored.downloadUrl, contains('firebasestorage.googleapis.com'));

      final copied = restored.copyWith(downloadUrl: 'https://new-url.com');
      expect(copied.downloadUrl, 'https://new-url.com');
      expect(copied.fileName, 'lesson.pdf');
    });

    test('supports Supabase storage metadata serialization', () {
      final model = MaterialModel(
        id: 'mat_supabase',
        teacherId: 'teacher_1',
        classId: 'class_1',
        fileName: 'lesson.pdf',
        fileType: 'pdf',
        fileRef: 'uploads/teacher_1/mat_supabase/lesson.pdf',
        storageProvider: 'supabase',
        storageBucket: 'study-materials',
        storageUploadStatus: 'uploading',
        conversionStatus: 'completed',
        status: 'ready',
        createdAt: DateTime.now(),
      );

      final restored = MaterialModel.fromMap(model.toMap(), model.id);

      expect(restored.storageProvider, 'supabase');
      expect(restored.storageBucket, 'study-materials');
      expect(restored.storageUploadStatus, 'uploading');
      expect(restored.fileRef, model.fileRef);
      expect(restored.downloadUrl, isNull);
    });

    test(
      'MaterialService deleteMaterial signature accepts optional fileName and convertedPdfRef for cleanup',
      () async {
        final service = MaterialService();
        try {
          await service.deleteMaterial(
            materialId: 'test_mat_123',
            fileRef: 'uploads/t1/test_mat_123/lesson.pptx',
            fileName: 'lesson.pptx',
            convertedPdfRef: 'uploads/t1/test_mat_123/preview.pdf',
          );
        } catch (e) {
          // Expected when running outside live Firebase environment
          expect(e, isNotNull);
        }
      },
    );

    test(
      'supports converted PDF fields and conversionStatus serialization',
      () {
        final now = DateTime.now();
        final model = MaterialModel(
          id: 'mat_conv_01',
          teacherId: 't1',
          classId: 'c1',
          fileName: 'presentation.pptx',
          fileType: 'pptx',
          fileRef: 'uploads/t1/mat_conv_01/presentation.pptx',
          convertedPdfRef: 'uploads/t1/mat_conv_01/preview.pdf',
          convertedPdfUrl: 'https://storage.googleapis.com/test/preview.pdf',
          conversionStatus: 'completed',
          convertedAt: now,
          status: 'ready',
          createdAt: now,
        );

        expect(model.hasConvertedPdf, isTrue);
        expect(model.isConverting, isFalse);
        expect(model.conversionFailed, isFalse);

        final map = model.toMap();
        expect(map['convertedPdfRef'], 'uploads/t1/mat_conv_01/preview.pdf');
        expect(
          map['convertedPdfUrl'],
          'https://storage.googleapis.com/test/preview.pdf',
        );
        expect(map['conversionStatus'], 'completed');

        final deserialized = MaterialModel.fromMap(map, 'mat_conv_01');
        expect(
          deserialized.convertedPdfRef,
          'uploads/t1/mat_conv_01/preview.pdf',
        );
        expect(
          deserialized.convertedPdfUrl,
          'https://storage.googleapis.com/test/preview.pdf',
        );
        expect(deserialized.conversionStatus, 'completed');
        expect(deserialized.hasConvertedPdf, isTrue);

        final converting = deserialized.copyWith(conversionStatus: 'pending');
        expect(converting.isConverting, isTrue);
        expect(converting.hasConvertedPdf, isFalse);

        final failed = deserialized.copyWith(conversionStatus: 'failed');
        expect(failed.conversionFailed, isTrue);
        expect(failed.hasConvertedPdf, isFalse);
      },
    );
  });
}
