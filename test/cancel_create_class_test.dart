import 'test_backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studexa/models/user_profile.dart';
import 'package:studexa/screens/teacher/teacher_home_screen.dart';

void main() {
  setUpAll(setupMockSupabase);

  final mockTeacher = UserProfile(
    uid: 'teacher_123',
    email: 'dr.stone@university.edu',
    displayName: 'Dr. Elizabeth Stone',
    role: 'teacher',
    createdAt: DateTime(2026, 1, 1),
  );

  testWidgets('Tap Cancel in Create Class dialog', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TeacherHomeScreen(
        initialProfile: mockTeacher,
        initialClassesStream: Stream.value([]),
      ),
    ));
    await tester.pump();

    // Open create class dialog
    await tester.tap(find.text('Create Class'));
    await tester.pumpAndSettle();

    expect(find.text('Create New Class'), findsOneWidget);

    // Focus the text field
    await tester.tap(find.byType(TextField).first);
    await tester.pump();

    // Tap Cancel
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Create New Class'), findsNothing);
  });
}
