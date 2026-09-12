import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:studexa/screens/auth/login_screen.dart';
import 'package:studexa/screens/auth/register_screen.dart';
import 'package:studexa/screens/auth/role_selection_screen.dart';
import 'package:studexa/theme/app_theme.dart';

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

  Widget buildApp(Widget child, {Key? boundaryKey}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: RepaintBoundary(
        key: boundaryKey,
        child: child,
      ),
    );
  }

  Future<void> captureScreenshot(WidgetTester tester, GlobalKey boundaryKey, String filename) async {
    await tester.runAsync(() async {
      final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 1.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final dir = Directory(r'C:\Users\FLYNNE EJ\.gemini\antigravity\brain\b67e6326-7873-4bee-8301-e3bdf7e5f251');
          final file = File('${dir.path}/$filename');
          await file.writeAsBytes(byteData.buffer.asUint8List());
        }
      }
    });
  }

  group('Batch 1: Visual Design & Responsive Verification (375px & 1440px)', () {
    testWidgets('RoleSelectionScreen renders without overflow on 375px and 1440px', (tester) async {
      // 1. Mobile Viewport (375x812)
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;

      final key375 = GlobalKey();
      await tester.pumpWidget(buildApp(const RoleSelectionScreen(), boundaryKey: key375));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Choose Your Role'), findsOneWidget);
      expect(find.text('Teacher'), findsOneWidget);
      expect(find.text('Student'), findsOneWidget);
      await captureScreenshot(tester, key375, 'batch1_role_selection_375px.png');

      // 2. Desktop Viewport (1440x900)
      tester.view.physicalSize = const Size(1440, 900);
      final key1440 = GlobalKey();
      await tester.pumpWidget(buildApp(const RoleSelectionScreen(), boundaryKey: key1440));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final constrainedBoxFinder = find.byType(ConstrainedBox);
      expect(constrainedBoxFinder, findsWidgets);
      await captureScreenshot(tester, key1440, 'batch1_role_selection_1440px.png');

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('LoginScreen renders without overflow on 375px and 1440px', (tester) async {
      // 1. Mobile Viewport (375x812)
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;

      final key375 = GlobalKey();
      await tester.pumpWidget(buildApp(const LoginScreen(role: 'Student'), boundaryKey: key375));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Create Quizzes from Your\nStudy Materials'), findsOneWidget);
      expect(find.text('Logging in as Student'), findsOneWidget);
      expect(find.text('Log In'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      await captureScreenshot(tester, key375, 'batch1_login_375px.png');

      // 2. Desktop Viewport (1440x900)
      tester.view.physicalSize = const Size(1440, 900);
      final key1440 = GlobalKey();
      await tester.pumpWidget(buildApp(const LoginScreen(role: 'Student'), boundaryKey: key1440));
      await tester.pump();

      expect(tester.takeException(), isNull);
      await captureScreenshot(tester, key1440, 'batch1_login_1440px.png');

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('RegisterScreen renders without overflow on 375px and 1440px', (tester) async {
      // 1. Mobile Viewport (375x812)
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;

      final key375 = GlobalKey();
      await tester.pumpWidget(buildApp(const RegisterScreen(role: 'Teacher'), boundaryKey: key375));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Create Your Account'), findsOneWidget);
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);
      expect(find.text('Register'), findsOneWidget);
      await captureScreenshot(tester, key375, 'batch1_register_375px.png');

      // 2. Desktop Viewport (1440x900)
      tester.view.physicalSize = const Size(1440, 900);
      final key1440 = GlobalKey();
      await tester.pumpWidget(buildApp(const RegisterScreen(role: 'Teacher'), boundaryKey: key1440));
      await tester.pump();

      expect(tester.takeException(), isNull);
      await captureScreenshot(tester, key1440, 'batch1_register_1440px.png');

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
