import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
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

  group('Task 7: Teacher Profile & Phone Visibility Tests', () {
    final mockTeacher = UserProfile(
      uid: 'teacher_123',
      email: 'dr.stone@university.edu',
      displayName: 'Dr. Elizabeth Stone',
      role: 'teacher',
      createdAt: DateTime.now(),
    );

    Widget buildTestApp({Size size = const Size(360, 640)}) {
      return MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: const EdgeInsets.only(top: 24),
        ),
        child: MaterialApp(
          home: TeacherHomeScreen(
            initialProfile: mockTeacher,
            initialClassesStream: const Stream.empty(),
          ),
        ),
      );
    }

    testWidgets(
      'Teacher dashboard renders without overflow on 360dp phone viewport',
      (tester) async {
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
        expect(find.text('Teacher Account'), findsOneWidget);
        expect(find.text('My Classes & Materials'), findsOneWidget);
        expect(
          find.byKey(const Key('teacher_header_app_icon')),
          findsOneWidget,
        );

        // Verify teacher profile details are clearly visible
        expect(
          find.byKey(const Key('teacher_display_name_text')),
          findsOneWidget,
        );
        expect(find.text('Dr. Elizabeth Stone'), findsOneWidget);
        expect(find.byKey(const Key('teacher_email_text')), findsOneWidget);
        expect(find.text('dr.stone@university.edu'), findsOneWidget);
        expect(find.text('Teacher'), findsOneWidget);

        // Verify Avatar initial 'D'
        expect(find.text('D'), findsWidgets);

        // Logout is available from the header profile menu, not the profile card.
        expect(
          find.byKey(const Key('teacher_header_avatar_menu')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('teacher_logout_button')), findsNothing);

        // Verify Action Cards are visible
        expect(find.text('Upload Material'), findsOneWidget);
        expect(find.text('Create Class'), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping Log Out in profile menu displays confirmation dialog',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestApp(size: const Size(360, 640)));
        await tester.pump();

        await tester.tap(find.byKey(const Key('teacher_header_avatar_menu')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        final logoutItem = find.byKey(const Key('teacher_menu_logout'));
        expect(logoutItem, findsOneWidget);
        expect(
          find.byKey(const Key('teacher_menu_gemini_settings')),
          findsOneWidget,
        );
        await tester.tap(logoutItem);
        await tester.pump();

        // Confirmation dialog should appear
        expect(find.text('Log Out'), findsWidgets);
        expect(
          find.textContaining('Are you sure you want to log out of Studexa?'),
          findsOneWidget,
        );
        expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);

        // Dismiss dialog
        await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
        await tester.pump();
        expect(
          find.textContaining('Are you sure you want to log out of Studexa?'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Teacher dashboard renders without overflow on narrow 320dp phone viewport',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestApp(size: const Size(320, 568)));
        await tester.pump();

        // Zero render overflow on narrow 320dp screens
        expect(tester.takeException(), isNull);
        expect(find.text('Teacher Account'), findsOneWidget);
        expect(find.text('Dr. Elizabeth Stone'), findsOneWidget);
      },
    );
  });
}
