import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:studexa/models/material_model.dart';
import 'package:studexa/screens/materials/material_viewer_screen.dart';

import 'package:open_filex/open_filex.dart';
import 'package:studexa/services/material_service.dart';

class _FakeMaterialService extends MaterialService {
  _FakeMaterialService(this.result);

  final MaterialDownloadResult result;
  int prepareCalls = 0;

  @override
  Future<MaterialDownloadResult> prepareMaterialForExternalOpen(
    MaterialModel material,
  ) async {
    prepareCalls++;
    return result;
  }
}

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

  group('MaterialViewerScreen Tests', () {
    testWidgets('opens DOCX with its Office MIME type', (tester) async {
      final file = File('test-temp/lesson.docx');
      final service = _FakeMaterialService(
        MaterialDownloadResult(
          status: MaterialDownloadStatus.ready,
          file: file,
          message: 'ready',
        ),
      );
      final material = MaterialModel(
        id: 'mat_external_docx',
        teacherId: 't1',
        classId: 'c1',
        fileName: 'lesson.docx',
        fileType: 'docx',
        fileRef: 'uploads/t1/mat_external_docx/lesson.docx',
        storageProvider: 'supabase',
        storageUploadStatus: 'completed',
        status: 'ready',
        createdAt: DateTime.now(),
      );
      String? openedMimeType;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => MaterialViewerScreen.openExternal(
                  context: context,
                  material: material,
                  materialService: service,
                  fileOpener: (path, mimeType) async {
                    openedMimeType = mimeType;
                    expect(path, file.path);
                    return ResultType.done;
                  },
                ),
                child: const Text('Open material'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open material'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(service.prepareCalls, 1);
      expect(
        openedMimeType,
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
      expect(find.text('File opened'), findsOneWidget);
    });

    testWidgets('offers extracted text when no app can open PPTX', (
      tester,
    ) async {
      final file = File('test-temp/slides.pptx');
      final service = _FakeMaterialService(
        MaterialDownloadResult(
          status: MaterialDownloadStatus.ready,
          file: file,
          message: 'ready',
        ),
      );
      final material = MaterialModel(
        id: 'mat_external_pptx',
        teacherId: 't1',
        classId: 'c1',
        fileName: 'slides.pptx',
        fileType: 'pptx',
        fileRef: 'uploads/t1/mat_external_pptx/slides.pptx',
        storageProvider: 'supabase',
        storageUploadStatus: 'completed',
        status: 'ready',
        extractedText: 'Extracted presentation content.',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => MaterialViewerScreen.openExternal(
                  context: context,
                  material: material,
                  materialService: service,
                  fileOpener: (_, _) async => ResultType.noAppToOpen,
                ),
                child: const Text('Open material'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open material'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('No app can open PPTX'), findsOneWidget);
      expect(find.text('View Extracted Text'), findsOneWidget);

      await tester.tap(find.text('View Extracted Text'));
      await tester.pumpAndSettle();

      expect(find.text('Extracted presentation content.'), findsOneWidget);
      expect(find.text('Extracted Material Text'), findsOneWidget);
    });

    testWidgets(
      'renders converting state with quick actions for pending PPTX',
      (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final material = MaterialModel(
          id: 'mat_pptx_pending',
          teacherId: 't1',
          classId: 'c1',
          fileName: 'Lecture_Slides.pptx',
          fileType: 'pptx',
          fileRef: 'uploads/t1/mat_pptx_pending/Lecture_Slides.pptx',
          status: 'ready',
          conversionStatus: 'pending',
          extractedText: 'Slide 1: Introduction to Research Methods.',
          createdAt: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(home: MaterialViewerScreen(material: material)),
        );
        await tester.pump();

        expect(find.text('Lecture_Slides.pptx'), findsOneWidget);
        expect(find.text('Generating In-App Preview'), findsOneWidget);
        expect(find.text('Open Original (PPTX)'), findsOneWidget);
        expect(find.text('View Extracted Text'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsWidgets);
      },
    );

    testWidgets(
      'renders conversion failed state with fallback options for failed DOCX',
      (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final material = MaterialModel(
          id: 'mat_docx_failed',
          teacherId: 't1',
          classId: 'c1',
          fileName: 'Syllabus.docx',
          fileType: 'docx',
          fileRef: 'uploads/t1/mat_docx_failed/Syllabus.docx',
          status: 'ready',
          conversionStatus: 'failed',
          extractedText: 'Course outline: Introduction to Algorithms.',
          createdAt: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(home: MaterialViewerScreen(material: material)),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Syllabus.docx'), findsOneWidget);
        expect(find.text('Preview Conversion Failed'), findsWidgets);
        expect(find.text('Open Original (DOCX)'), findsOneWidget);
        expect(find.text('View Extracted Text'), findsOneWidget);
        expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      },
    );

    testWidgets('toggles between preview and extracted text view', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final material = MaterialModel(
        id: 'mat_pptx_toggle',
        teacherId: 't1',
        classId: 'c1',
        fileName: 'Algorithms.pptx',
        fileType: 'pptx',
        fileRef: 'uploads/t1/mat_pptx_toggle/Algorithms.pptx',
        status: 'ready',
        conversionStatus: 'pending',
        extractedText: 'Algorithm analysis involves asymptotic bounds.',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(home: MaterialViewerScreen(material: material)),
      );
      await tester.pump();

      // Tap 'View Extracted Text' button in the converting view
      final viewTextBtn = find.text('View Extracted Text');
      expect(viewTextBtn, findsOneWidget);
      await tester.tap(viewTextBtn);
      await tester.pump(const Duration(milliseconds: 200));

      // Now extracted text is shown
      expect(
        find.text('Algorithm analysis involves asymptotic bounds.'),
        findsOneWidget,
      );
      expect(find.text('Extracted Material Text'), findsOneWidget);

      // Tap 'View Preview' in AppBar
      final viewPreviewBtn = find.text('View Preview');
      expect(viewPreviewBtn, findsOneWidget);
      await tester.tap(viewPreviewBtn);
      await tester.pump(const Duration(milliseconds: 200));

      // Returns to preview/converting view
      expect(find.text('Generating In-App Preview'), findsOneWidget);
    });

    testWidgets(
      'renders properly without RenderFlex overflow on desktop (1440x900)',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final material = MaterialModel(
          id: 'mat_desktop',
          teacherId: 't1',
          classId: 'c1',
          fileName: 'Comprehensive_Research_Guide_Volume_1.pptx',
          fileType: 'pptx',
          fileRef:
              'uploads/t1/mat_desktop/Comprehensive_Research_Guide_Volume_1.pptx',
          status: 'ready',
          conversionStatus: 'pending',
          extractedText: 'Comprehensive Research Guide content.',
          createdAt: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(home: MaterialViewerScreen(material: material)),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(
          find.text('Comprehensive_Research_Guide_Volume_1.pptx'),
          findsOneWidget,
        );
        expect(find.text('Open Original (PPTX)'), findsOneWidget);
      },
    );

    testWidgets(
      'renders directly with extracted text if initialShowExtractedText is true',
      (tester) async {
        final material = MaterialModel(
          id: 'mat_initial_text',
          teacherId: 't1',
          classId: 'c1',
          fileName: 'Notes.pdf',
          fileType: 'pdf',
          fileRef: 'uploads/t1/mat_initial_text/Notes.pdf',
          status: 'ready',
          extractedText: 'This is pre-extracted content.',
          createdAt: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MaterialViewerScreen(
              material: material,
              initialShowExtractedText: true,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('This is pre-extracted content.'), findsOneWidget);
        expect(find.text('View PDF'), findsOneWidget);
      },
    );
  });
}
