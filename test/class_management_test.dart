import 'package:flutter_test/flutter_test.dart';
import 'package:studexa/models/class_model.dart';
import 'package:studexa/services/class_service.dart';

void main() {
  group('ClassModel Tests', () {
    test('serializes and deserializes properly', () {
      final now = DateTime(2026, 9, 7, 12, 0);
      final model = ClassModel(
        id: 'cls_123',
        name: 'Biology 101 - Cell Biology',
        joinCode: 'BIO-4921',
        teacherId: 'teacher_999',
        teacherName: 'Prof. Davis',
        section: 'Section A',
        subject: 'Biology',
        status: 'active',
        rosterCount: 25,
        recentQuiz: 'Cellular Respiration',
        createdAt: now,
        updatedAt: now,
      );

      final map = model.toMap();
      expect(map['name'], 'Biology 101 - Cell Biology');
      expect(map['joinCode'], 'BIO-4921');
      expect(map['teacherId'], 'teacher_999');
      expect(map['teacherName'], 'Prof. Davis');
      expect(map['section'], 'Section A');
      expect(map['subject'], 'Biology');
      expect(map['status'], 'active');
      expect(map['rosterCount'], 25);
      expect(map['recentQuiz'], 'Cellular Respiration');

      final fromMap = ClassModel.fromMap({
        'name': 'Biology 101 - Cell Biology',
        'joinCode': 'bio-4921', // test uppercase normalization
        'teacherId': 'teacher_999',
        'teacherName': 'Prof. Davis',
        'section': 'Section A',
        'subject': 'Biology',
        'status': 'active',
        'rosterCount': 25,
        'recentQuiz': 'Cellular Respiration',
        'createdAt': '2026-09-07T12:00:00.000',
      }, 'cls_123');

      expect(fromMap.id, 'cls_123');
      expect(fromMap.name, 'Biology 101 - Cell Biology');
      expect(fromMap.joinCode, 'BIO-4921');
      expect(fromMap.section, 'Section A');
      expect(fromMap.subject, 'Biology');
      expect(fromMap.rosterCount, 25);
      expect(fromMap.createdAt?.year, 2026);
    });

    test('copyWith updates fields while preserving immutability', () {
      const model = ClassModel(
        id: 'c1',
        name: 'Physics',
        joinCode: 'PHY-1234',
        teacherId: 't1',
        rosterCount: 5,
      );

      final updated = model.copyWith(rosterCount: 6);
      expect(updated.rosterCount, 6);
      expect(updated.name, 'Physics');
      expect(model.rosterCount, 5);
    });
  });

  group('ClassMember Tests', () {
    test('serializes and deserializes class member', () {
      final member = ClassMember(
        userId: 'stu_456',
        role: 'student',
        displayName: 'Jordan Lee',
        email: 'jordan@school.edu',
        joinedAt: DateTime(2026, 9, 1),
      );

      final map = member.toMap();
      expect(map['userId'], 'stu_456');
      expect(map['role'], 'student');
      expect(map['displayNameSnapshot'], 'Jordan Lee');
      expect(map['emailSnapshot'], 'jordan@school.edu');

      final fromMap = ClassMember.fromMap({
        'userId': 'stu_456',
        'role': 'Student',
        'displayNameSnapshot': 'Jordan Lee',
        'emailSnapshot': 'jordan@school.edu',
        'joinedAt': '2026-09-01T00:00:00.000',
      }, 'stu_456');

      expect(fromMap.userId, 'stu_456');
      expect(fromMap.role, 'student');
      expect(fromMap.displayName, 'Jordan Lee');
      expect(fromMap.email, 'jordan@school.edu');
    });
  });

  group('ClassJoinException Tests', () {
    test('exception toString returns clean message', () {
      const ex = ClassJoinException('Invalid join code provided.');
      expect(ex.toString(), 'Invalid join code provided.');
    });
  });

  group('Join Code Format Tests', () {
    test('join code regex matches standard format (PREFIX-XXXX)', () {
      final codeRegex = RegExp(r'^[A-Z]{3}-[A-Z0-9]{4,6}$');
      expect(codeRegex.hasMatch('BIO-4921'), isTrue);
      expect(codeRegex.hasMatch('CLS-A89K'), isTrue);
      expect(codeRegex.hasMatch('CS-8812'), isFalse); // only 2 prefix letters
      expect(codeRegex.hasMatch('MAT-1234'), isTrue);
    });
  });
}
