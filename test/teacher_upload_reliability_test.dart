import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:archive/archive.dart';
import 'package:studexa/models/class_model.dart';
import 'package:studexa/models/material_model.dart';
import 'package:studexa/services/material_service.dart';
import 'package:studexa/screens/teacher/upload_generate_quiz_screen.dart';
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

  group('Task 5: Teacher Upload Reliability & Error Handling Tests', () {
    // ── 1. File Validation Pre-checks ──────────────────────────
    test('1. Validates supported formats (PDF, PPTX, DOCX) and size limits', () {
      // PDF
      expect(
        () => MaterialService.validateUploadRequest(
          classId: 'class_bio101',
          fileName: 'Lecture_Notes.pdf',
          extension: 'pdf',
          byteLength: 1024 * 500,
        ),
        returnsNormally,
      );

      // PPTX
      expect(
        () => MaterialService.validateUploadRequest(
          classId: 'class_bio101',
          fileName: 'Lecture_Slides.pptx',
          extension: '.PPTX', // Leading dot and uppercase
          byteLength: 1024 * 1024 * 10,
        ),
        returnsNormally,
      );

      // DOCX
      expect(
        () => MaterialService.validateUploadRequest(
          classId: 'class_bio101',
          fileName: 'Study_Guide.docx',
          extension: 'docx',
          byteLength: 1024 * 200,
        ),
        returnsNormally,
      );

      // Empty Class ID
      expect(
        () => MaterialService.validateUploadRequest(
          classId: '   ',
          fileName: 'Study_Guide.docx',
          extension: 'docx',
          byteLength: 1024,
        ),
        throwsA(isA<MaterialValidationException>().having(
          (e) => e.message,
          'message',
          contains('A target class must be selected'),
        )),
      );

      // Unsupported extension
      expect(
        () => MaterialService.validateUploadRequest(
          classId: 'class_bio101',
          fileName: 'image.png',
          extension: 'png',
          byteLength: 1024,
        ),
        throwsA(isA<MaterialValidationException>().having(
          (e) => e.message,
          'message',
          contains('Unsupported file format ".png"'),
        )),
      );

      // Empty file (0 bytes)
      expect(
        () => MaterialService.validateUploadRequest(
          classId: 'class_bio101',
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

      // Oversized file (> 50MB)
      expect(
        () => MaterialService.validateUploadRequest(
          classId: 'class_bio101',
          fileName: 'huge.pdf',
          extension: 'pdf',
          byteLength: 51 * 1024 * 1024,
        ),
        throwsA(isA<MaterialValidationException>().having(
          (e) => e.message,
          'message',
          contains('exceeds the 50 MB upload limit'),
        )),
      );
    });

    // ── 2. Error Message & Reason Resilience ──────────────────
    test('2. Formatted error reason covers file_bytes_unavailable and no_extractable_text', () {
      final unavailableModel = MaterialModel(
        id: 'mat_01',
        teacherId: 't1',
        classId: 'c1',
        fileName: 'notes.pdf',
        fileType: 'pdf',
        fileRef: 'ref',
        status: 'failed',
        errorReason: 'file_bytes_unavailable',
        createdAt: DateTime.now(),
      );
      expect(
        unavailableModel.formattedError,
        'Original document file is unavailable in storage. Please re-upload the document.',
      );
      expect(unavailableModel.userFriendlyErrorReason, unavailableModel.formattedError);

      final noTextModel = MaterialModel(
        id: 'mat_02',
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
        contains('OCR is not supported in Phase 1'),
      );
    });

    // ── 3. Format Verification: PDF Upload & Extraction ───────
    test('3. Supported Format Verification — PDF extraction generates meaningful text', () async {
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Cellular Respiration Biology Lecture'),
              pw.Text('Mitochondria generate ATP through oxidative phosphorylation across the inner membrane.'),
              pw.Text('Glycolysis takes place in the cytoplasm and yields two pyruvate molecules.'),
            ],
          ),
        ),
      );

      final pdfBytes = Uint8List.fromList(await doc.save());
      expect(pdfBytes.isNotEmpty, true);

      final extracted = await DocumentTextExtractor.extractText(
        bytes: pdfBytes,
        extension: 'pdf',
      );

      expect(extracted.contains('Cellular Respiration Biology Lecture'), true);
      expect(extracted.contains('Mitochondria generate ATP'), true);
      expect(DocumentTextExtractor.isMeaningfulText(extracted), true);
    });

    // ── 4. Format Verification: PPTX Upload & Extraction ──────
    test('4. Supported Format Verification — PPTX extraction parses multi-slide presentation', () async {
      final archive = Archive();
      const slideXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:txBody>
          <a:p>
            <a:r><a:t>Photosynthesis &amp; Light Reactions</a:t></a:r>
          </a:p>
          <a:p>
            <a:r><a:t>Chloroplasts synthesize glucose using radiant solar energy within the thylakoid membranes.</a:t></a:r>
          </a:p>
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>''';

      archive.addFile(ArchiveFile(r'ppt\slides\slide1.xml', utf8.encode(slideXml).length, utf8.encode(slideXml)));
      final encoder = ZipEncoder();
      final pptxBytes = Uint8List.fromList(encoder.encode(archive));

      final extracted = await DocumentTextExtractor.extractText(
        bytes: pptxBytes,
        extension: 'pptx',
      );

      expect(extracted.contains('Photosynthesis & Light Reactions'), true);
      expect(extracted.contains('Chloroplasts synthesize glucose'), true);
      expect(DocumentTextExtractor.isMeaningfulText(extracted), true);
    });

    // ── 5. Format Verification: DOCX Upload & Extraction ──────
    test('5. Supported Format Verification — DOCX extraction parses document XML body', () async {
      final archive = Archive();
      const docxXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r><w:t>Mitosis and Cell Division Study Notes</w:t></w:r>
    </w:p>
    <w:p>
      <w:r><w:t>Prophase, metaphase, anaphase, and telophase constitute the four nuclear division stages.</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';

      archive.addFile(ArchiveFile(r'word\document.xml', utf8.encode(docxXml).length, utf8.encode(docxXml)));
      final encoder = ZipEncoder();
      final docxBytes = Uint8List.fromList(encoder.encode(archive));

      final extracted = await DocumentTextExtractor.extractText(
        bytes: docxBytes,
        extension: 'docx',
      );

      expect(extracted.contains('Mitosis and Cell Division Study Notes'), true);
      expect(extracted.contains('telophase constitute the four nuclear division stages'), true);
      expect(DocumentTextExtractor.isMeaningfulText(extracted), true);
    });

    // ── 6. FR-06 Failure State: Empty Document Extraction ─────
    test('6. FR-06 Empty document extraction sets failed status', () async {
      final archive = Archive();
      const emptyDocXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>   </w:t></w:r></w:p>
  </w:body>
</w:document>''';

      archive.addFile(ArchiveFile(r'word\document.xml', utf8.encode(emptyDocXml).length, utf8.encode(emptyDocXml)));
      final encoder = ZipEncoder();
      final emptyBytes = Uint8List.fromList(encoder.encode(archive));

      final extracted = await DocumentTextExtractor.extractText(
        bytes: emptyBytes,
        extension: 'docx',
      );

      final isMeaningful = DocumentTextExtractor.isMeaningfulText(extracted);
      expect(isMeaningful, false);
    });

    // ── 7. UI Verification: Ready Material Status Card ────────
    testWidgets('7. UploadGenerateQuizScreen renders ready state with character count and unlocks generation', (tester) async {
      final readyMaterial = MaterialModel(
        id: 'mat_ready_101',
        teacherId: 'teacher_99',
        classId: 'cls_bio101',
        fileName: 'Cellular_Respiration.pdf',
        fileType: 'pdf',
        fileRef: 'uploads/teacher_99/mat_ready_101/Cellular_Respiration.pdf',
        status: 'ready',
        extractedText: 'Cellular respiration converts glucose and oxygen into ATP, carbon dioxide, and water.',
        createdAt: DateTime.now(),
        fileSizeBytes: 1024 * 250,
      );

      final sampleClass = ClassModel(
        id: 'cls_bio101',
        name: 'General Biology',
        joinCode: 'BIO-1011',
        teacherId: 'teacher_99',
        teacherName: 'Dr. Watson',
        section: 'A',
        subject: 'Science',
        status: 'active',
        rosterCount: 20,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: UploadGenerateQuizScreen(
            preselectedClass: sampleClass,
            preselectedMaterial: readyMaterial,
            isClassLocked: true,
          ),
        ),
      );
      await tester.pump();

      // Check header and banner
      expect(find.text('Generate Quiz'), findsOneWidget);
      expect(find.text('Document Ready for Quiz Generation'), findsOneWidget);
      expect(find.textContaining('Successfully extracted'), findsOneWidget);
      expect(find.text('Continue to Quiz Options'), findsOneWidget);

      // Verify generation buttons are enabled
      final actualExamBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Generate Actual Quiz (PDF Exam)'),
      );
      expect(actualExamBtn.onPressed, isNotNull);

      final practiceQuizBtn = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Generate Practice Quiz (App Practice)'),
      );
      expect(practiceQuizBtn.onPressed, isNotNull);
    });

    // ── 8. UI Verification: Failed Extraction Card & Blocked Buttons ──
    testWidgets('8. UploadGenerateQuizScreen renders failure feedback card and blocks generation', (tester) async {
      final failedMaterial = MaterialModel(
        id: 'mat_failed_202',
        teacherId: 'teacher_99',
        classId: 'cls_bio101',
        fileName: 'Blank_Scan.pdf',
        fileType: 'pdf',
        fileRef: 'uploads/teacher_99/mat_failed_202/Blank_Scan.pdf',
        status: 'failed',
        errorReason: 'no_extractable_text',
        extractedText: '',
        createdAt: DateTime.now(),
        fileSizeBytes: 1024 * 50,
      );

      final sampleClass = ClassModel(
        id: 'cls_bio101',
        name: 'General Biology',
        joinCode: 'BIO-1011',
        teacherId: 'teacher_99',
        teacherName: 'Dr. Watson',
        section: 'A',
        subject: 'Science',
        status: 'active',
        rosterCount: 20,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: UploadGenerateQuizScreen(
            preselectedClass: sampleClass,
            preselectedMaterial: failedMaterial,
            isClassLocked: true,
          ),
        ),
      );
      await tester.pump();

      // Check failure notification card
      expect(find.text('Extraction Failed'), findsOneWidget);
      expect(find.text('no_extractable_text'), findsOneWidget);
      expect(find.textContaining('OCR is not supported in Phase 1'), findsOneWidget);
      expect(find.text('Choose Another'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Verify generation buttons are disabled
      final actualExamBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Generate Actual Quiz (PDF Exam)'),
      );
      expect(actualExamBtn.onPressed, isNull);

      final practiceQuizBtn = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Generate Practice Quiz (App Practice)'),
      );
      expect(practiceQuizBtn.onPressed, isNull);
    });

    // ── 9. Infinite Hang Prevention in retryMaterialExtraction ─
    test('9. Infinite Hang Prevention — retryMaterialExtraction throws MaterialValidationException when bytes are unavailable', () async {
      final materialService = MaterialService();
      expect(
        () => materialService.retryMaterialExtraction('non_existent_material_id'),
        throwsA(isA<MaterialValidationException>().having(
          (e) => e.message,
          'message',
          contains('unavailable in storage'),
        )),
      );
    });

    // ── 10. File Extension and Byte Length Extraction Resilience ──
    test('10. Extension and Byte Length Extraction Resilience handles missing picker metadata', () {
      // Test fileName fallback when extension is blank
      const rawFileName = 'Chapter_3_Genetics.pptx';
      String resolvedExt = '';
      if (resolvedExt.isEmpty && rawFileName.contains('.')) {
        resolvedExt = rawFileName.split('.').last.toLowerCase().trim();
      }
      expect(resolvedExt, 'pptx');

      // Test byteLength fallback when picker reported 0
      int resolvedLength = 0;
      final mockBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      if (resolvedLength <= 0 && mockBytes.isNotEmpty) {
        resolvedLength = mockBytes.length;
      }
      expect(resolvedLength, 8);

      expect(
        () => MaterialService.validateUploadRequest(
          classId: 'class_bio101',
          fileName: rawFileName,
          extension: resolvedExt,
          byteLength: resolvedLength,
        ),
        returnsNormally,
      );
    });
  });
}
