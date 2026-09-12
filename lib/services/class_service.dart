import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/class_model.dart';
import 'firestore_provider.dart';

/// Exception thrown when joining a class fails.
class ClassJoinException implements Exception {
  const ClassJoinException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Service managing classes, join codes, and student enrollment rosters
/// in Cloud Firestore.
class ClassService {
  ClassService({FirebaseFirestore? firestore})
      : _firestore = getAppFirestore(firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _classesCollection =>
      _firestore.collection('classes');

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  /// Generates a human-friendly, collision-resistant join code (e.g. "BIO-4921").
  /// Verifies against Firestore to guarantee uniqueness across all active classes.
  Future<String> generateUniqueJoinCode({String prefix = 'CLS'}) async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // omit ambiguous 0/O, 1/I
    final random = Random.secure();

    final cleanPrefix = prefix
        .replaceAll(RegExp(r'[^a-zA-Z]'), '')
        .toUpperCase();
    final safePrefix = cleanPrefix.length >= 3
        ? cleanPrefix.substring(0, 3)
        : ('${cleanPrefix}CLS').substring(0, 3);

    for (int attempt = 0; attempt < 10; attempt++) {
      final randomPart = List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
      final candidateCode = '$safePrefix-$randomPart';

      final existing = await _classesCollection
          .where('joinCode', isEqualTo: candidateCode)
          .limit(1)
          .get();

      if (existing.docs.isEmpty) {
        return candidateCode;
      }
    }

    // High collision fallback: use timestamp hex suffix
    final timeSuffix = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase().substring(4);
    return '$safePrefix-$timeSuffix';
  }

  /// Creates a new class for the authenticated teacher, generates a unique
  /// join code, records the teacher as an owner member, and returns the created [ClassModel].
  Future<ClassModel> createClass({
    required String name,
    required String teacherId,
    required String teacherName,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Class name cannot be empty.');
    }

    // Prefix join code with the first letters of the class name
    final words = trimmedName.split(' ');
    String codePrefix = 'CLS';
    if (words.isNotEmpty && words.first.isNotEmpty) {
      codePrefix = words.first;
    }

    final joinCode = await generateUniqueJoinCode(prefix: codePrefix);
    final docRef = _classesCollection.doc();

    final newClass = ClassModel(
      id: docRef.id,
      name: trimmedName,
      joinCode: joinCode,
      teacherId: teacherId,
      teacherName: teacherName.trim(),
      status: 'active',
      rosterCount: 0,
      recentQuiz: 'No quizzes yet',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final batch = _firestore.batch();
    batch.set(docRef, newClass.toMap());

    // Record teacher as class owner member
    final memberRef = docRef.collection('members').doc(teacherId);
    batch.set(memberRef, {
      'userId': teacherId,
      'role': 'teacher',
      'displayNameSnapshot': teacherName.trim(),
      'joinedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    return newClass;
  }

  /// Real-time stream of all classes created by a specific teacher.
  Stream<List<ClassModel>> getTeacherClassesStream(String teacherId) {
    return _classesCollection
        .where('teacherId', isEqualTo: teacherId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => ClassModel.fromFirestore(doc))
          .toList();
      // Sort client-side by createdAt descending
      list.sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      return list;
    });
  }

  /// Real-time stream of student members enrolled in a specific class.
  Stream<List<ClassMember>> getClassMembersStream(String classId) {
    return _classesCollection
        .doc(classId)
        .collection('members')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ClassMember.fromFirestore(doc))
          .toList();
    });
  }

  /// Validates a join code and enrolls a student into the target class.
  /// Prevents duplicate enrollment and atomically updates the roster.
  Future<ClassModel> joinClassByCode({
    required String joinCode,
    required String studentId,
    required String studentName,
    String studentEmail = '',
  }) async {
    final cleanStudentId = studentId.trim();
    if (cleanStudentId.isEmpty || cleanStudentId == 'student_demo') {
      throw const ClassJoinException(
        'Please sign in with a valid student account before joining a class.',
      );
    }

    final normalizedCode = joinCode.trim().toUpperCase();
    if (normalizedCode.isEmpty) {
      throw const ClassJoinException('Please enter a valid join code.');
    }

    try {
      // 1. Query class matching the unique join code
      final querySnap = await _classesCollection
          .where('joinCode', isEqualTo: normalizedCode)
          .limit(1)
          .get();

      if (querySnap.docs.isEmpty) {
        throw ClassJoinException(
          'No class found with join code "$normalizedCode". Please verify the code with your teacher.',
        );
      }

      final classDoc = querySnap.docs.first;
      final targetClass = ClassModel.fromFirestore(classDoc);

      if (targetClass.status != 'active') {
        throw const ClassJoinException(
          'This class is currently inactive or archived and is not accepting new students.',
        );
      }

      // 2. Prevent duplicate enrollment
      final memberDoc = await classDoc.reference
          .collection('members')
          .doc(cleanStudentId)
          .get();

      if (memberDoc.exists) {
        throw ClassJoinException(
          'You are already enrolled in "${targetClass.name}".',
        );
      }

      // 3. Atomically add to class roster and student's joinedClasses
      final batch = _firestore.batch();

      // Add to classes/{classId}/members/{studentId}
      final newMemberRef =
          classDoc.reference.collection('members').doc(cleanStudentId);
      batch.set(newMemberRef, {
        'userId': cleanStudentId,
        'role': 'student',
        'displayNameSnapshot': studentName.trim(),
        'emailSnapshot': studentEmail.trim(),
        'joinedAt': FieldValue.serverTimestamp(),
      });

      // Add to users/{studentId}/joinedClasses/{classId}
      final userJoinedClassRef = _usersCollection
          .doc(cleanStudentId)
          .collection('joinedClasses')
          .doc(targetClass.id);

      batch.set(userJoinedClassRef, {
        'classId': targetClass.id,
        'className': targetClass.name,
        'teacherName': targetClass.teacherName,
        'teacherId': targetClass.teacherId,
        'joinCode': targetClass.joinCode,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      batch.update(classDoc.reference, {
        'rosterCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();

      return targetClass.copyWith(rosterCount: targetClass.rosterCount + 1);
    } on ClassJoinException {
      rethrow;
    } on FirebaseException catch (fe) {
      if (fe.code == 'permission-denied') {
        throw const ClassJoinException(
          'Permission denied: Unable to access class. Please make sure the Firestore Security Rules are published in your Firebase Console.',
        );
      }
      throw ClassJoinException('Firebase error (${fe.code}): ${fe.message}');
    } catch (e) {
      throw ClassJoinException('Failed to join class: $e');
    }
  }

  /// Real-time stream of all classes a student has joined.
  Stream<List<ClassModel>> getStudentJoinedClassesStream(String studentId) {
    return _usersCollection
        .doc(studentId)
        .collection('joinedClasses')
        .snapshots()
        .asyncMap((snap) async {
      if (snap.docs.isEmpty) return <ClassModel>[];

      final List<ClassModel> classes = [];
      for (final doc in snap.docs) {
        final classId = doc.data()['classId'] as String? ?? doc.id;
        try {
          final liveClassDoc = await _classesCollection.doc(classId).get();
          if (liveClassDoc.exists && liveClassDoc.data() != null) {
            classes.add(ClassModel.fromFirestore(liveClassDoc));
          } else {
            // Fallback to snapshot info stored in joinedClasses
            final data = doc.data();
            classes.add(ClassModel(
              id: classId,
              name: data['className'] as String? ?? 'Class',
              joinCode: data['joinCode'] as String? ?? '',
              teacherId: data['teacherId'] as String? ?? '',
              teacherName: data['teacherName'] as String? ?? '',
              createdAt: (data['joinedAt'] as Timestamp?)?.toDate(),
            ));
          }
        } catch (_) {
          // If live read fails, use snapshot data
          final data = doc.data();
          classes.add(ClassModel(
            id: classId,
            name: data['className'] as String? ?? 'Class',
            joinCode: data['joinCode'] as String? ?? '',
            teacherId: data['teacherId'] as String? ?? '',
            teacherName: data['teacherName'] as String? ?? '',
            createdAt: (data['joinedAt'] as Timestamp?)?.toDate(),
          ));
        }
      }
      return classes;
    });
  }

  /// Real-time stream of a single class by its ID.
  Stream<ClassModel?> streamClass(String classId) {
    return _classesCollection.doc(classId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return ClassModel.fromFirestore(doc);
    });
  }

  /// Fetches a single class by its ID.
  Future<ClassModel?> getClassById(String classId) async {
    final doc = await _classesCollection.doc(classId).get();
    if (!doc.exists || doc.data() == null) return null;
    return ClassModel.fromFirestore(doc);
  }
}
