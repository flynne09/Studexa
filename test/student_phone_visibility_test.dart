import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:studexa/models/user_profile.dart';
import 'package:studexa/screens/student/student_home_screen.dart';

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

  group('Student Profile & Logout Phone Visibility Tests', () {
    final mockStudent = UserProfile(
      uid: 'student_123',
      email: 'student.sample@university.edu',
      displayName: 'Alex Morgan',
      role: 'student',
      createdAt: DateTime.now(),
    );

    Widget buildTestApp({Size size = const Size(360, 640)}) {
      return MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: const EdgeInsets.only(top: 24),
        ),
        child: MaterialApp(
          home: StudentHomeScreen(
            initialProfile: mockStudent,
            initialClassesStream: const Stream.empty(),
          ),
        ),
      );
    }

    testWidgets('Student dashboard renders without overflow on 360dp phone viewport', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(size: const Size(360, 640)));
      await tester.pump();

      // Ensure no Flutter overflow errors were logged
      expect(tester.takeException(), isNull);

      // Verify header titles
      expect(find.text('Student Portal'), findsOneWidget);
      expect(find.text('My Classes & Quizzes'), findsOneWidget);

      // Verify student profile details are clearly visible
      expect(find.byKey(const Key('student_display_name_text')), findsOneWidget);
      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.byKey(const Key('student_email_text')), findsOneWidget);
      expect(find.text('student.sample@university.edu'), findsOneWidget);
      expect(find.text('Student'), findsOneWidget);

      // Verify Avatar initial 'A'
      expect(find.text('A'), findsWidgets);

      // Verify Avatar menu is directly visible and rendered on the card
      final avatarMenu = find.byKey(const Key('student_header_avatar_menu'));
      expect(avatarMenu, findsOneWidget);

      // Verify Join Class button is visible
      final joinButton = find.byKey(const Key('student_join_class_button'));
      expect(joinButton, findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Join Class'), findsOneWidget);
    });

    testWidgets('Tapping Log Out in avatar menu displays confirmation dialog', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(size: const Size(360, 640)));
      await tester.pump();

      // Tap the avatar menu and select Log Out
      final avatarMenu = find.byKey(const Key('student_header_avatar_menu'));
      await tester.tap(avatarMenu);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final logoutItem = find.text('Log Out');
      expect(logoutItem, findsOneWidget);
      await tester.tap(logoutItem, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify confirmation dialog appears
      expect(find.text('Log Out'), findsWidgets);
      expect(find.text('Are you sure you want to log out of Studexa?'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Are you sure you want to log out of Studexa?'), findsNothing);
    });

    testWidgets('Dashboard renders cleanly on ultra-narrow 320dp viewport without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(size: const Size(320, 568)));
      await tester.pump();

      // No overflow exceptions on 320dp
      expect(tester.takeException(), isNull);

      // Elements remain visible
      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.byKey(const Key('student_header_avatar_menu')), findsOneWidget);
      expect(find.byKey(const Key('student_join_class_button')), findsOneWidget);
    });
  });
}
