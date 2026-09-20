import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:studexa/models/class_model.dart';
import 'package:studexa/models/user_profile.dart';
import 'package:studexa/screens/teacher/teacher_home_screen.dart';

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

  group('TeacherHomeScreen - Classroom Workflow Removal Verification', () {
    final mockTeacher = UserProfile(
      uid: 'teacher_123',
      email: 'dr.stone@university.edu',
      displayName: 'Dr. Elizabeth Stone',
      role: 'teacher',
      createdAt: DateTime(2026, 1, 1),
    );

    final mockClass = ClassModel(
      id: 'class_1',
      name: 'BSCS 3A - Mobile Computing',
      section: 'Block A',
      joinCode: 'MOB301',
      teacherId: 'teacher_123',
      teacherName: 'Dr. Elizabeth Stone',
      rosterCount: 28,
      createdAt: DateTime(2026, 1, 15),
      updatedAt: DateTime(2026, 1, 15),
    );

    Widget buildTestApp({Key? boundaryKey, Size size = const Size(375, 812)}) {
      return MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: const EdgeInsets.only(top: 44, bottom: 34),
        ),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true),
          home: RepaintBoundary(
            key: boundaryKey,
            child: TeacherHomeScreen(
              initialProfile: mockTeacher,
              initialClassesStream: Stream.value([mockClass]),
            ),
          ),
        ),
      );
    }

    testWidgets('Verify screen on 375px viewport (AFTER check: Classroom Workflow removed)', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final boundaryKey = GlobalKey();
      await tester.pumpWidget(buildTestApp(boundaryKey: boundaryKey, size: const Size(375, 812)));
      await tester.pump();

      // Ensure no layout errors on 375px width
      expect(tester.takeException(), isNull);

      // Verify core header and dashboard sections remain intact
      expect(find.text('Teacher Account'), findsOneWidget);
      expect(find.text('My Classes & Materials'), findsOneWidget);
      expect(find.text('Dr. Elizabeth Stone'), findsOneWidget);
      expect(find.text('Upload Material'), findsOneWidget);
      expect(find.text('Create Class'), findsOneWidget);
      expect(find.text('BSCS 3A - Mobile Computing'), findsOneWidget);

      // Verify Classroom Workflow card is completely removed
      expect(find.text('Classroom Workflow'), findsNothing);
      expect(find.byIcon(Icons.lightbulb_outline), findsNothing);

      // Capture after screenshot to artifacts directory
      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final file = File(r'C:\Users\FLYNNE EJ\.gemini\antigravity\brain\b67e6326-7873-4bee-8301-e3bdf7e5f251\after_removal_375px.png');
            await file.writeAsBytes(byteData.buffer.asUint8List());
          }
        }
      });
    });
  });
}
