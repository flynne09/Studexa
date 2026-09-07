import 'package:cloud_firestore/cloud_firestore.dart';

/// Supported question types in Phase 1.
enum QuizQuestionType {
  multipleChoice,
  trueFalse,
  fillInTheBlank,
  identification,
  enumeration;

  String get value {
    switch (this) {
      case QuizQuestionType.multipleChoice:
        return 'multiple_choice';
      case QuizQuestionType.trueFalse:
        return 'true_false';
      case QuizQuestionType.fillInTheBlank:
        return 'fill_blank';
      case QuizQuestionType.identification:
        return 'identification';
      case QuizQuestionType.enumeration:
        return 'enumeration';
    }
  }

  String get displayName {
    switch (this) {
      case QuizQuestionType.multipleChoice:
        return 'Multiple Choice';
      case QuizQuestionType.trueFalse:
        return 'True / False';
      case QuizQuestionType.fillInTheBlank:
        return 'Fill-in-the-Blank';
      case QuizQuestionType.identification:
        return 'Identification';
      case QuizQuestionType.enumeration:
        return 'Enumeration';
    }
  }

  static QuizQuestionType fromString(String? typeStr) {
    if (typeStr == null || typeStr.isEmpty) return QuizQuestionType.multipleChoice;
    final lower = typeStr.toLowerCase().trim().replaceAll(RegExp(r'[\s\-\/]'), '_');
    if (lower.contains('multiple') || lower.contains('mcq')) return QuizQuestionType.multipleChoice;
    if (lower.contains('true') || lower.contains('false') || lower.contains('tf')) return QuizQuestionType.trueFalse;
    if (lower.contains('fill') || lower.contains('blank')) return QuizQuestionType.fillInTheBlank;
    if (lower.contains('ident')) return QuizQuestionType.identification;
    if (lower.contains('enum')) return QuizQuestionType.enumeration;
    return QuizQuestionType.multipleChoice;
  }
}

/// Represents a single question within a quiz.
class QuizQuestion {
  final String id;
  final QuizQuestionType type;
  final String question;
  final List<String> options;
  final String correctAnswer;
  final List<String> enumerationAnswers;
  final String explanation;
  final double points;

  const QuizQuestion({
    required this.id,
    required this.type,
    required this.question,
    this.options = const [],
    this.correctAnswer = '',
    this.enumerationAnswers = const [],
    this.explanation = '',
    this.points = 1.0,
  });

  factory QuizQuestion.fromMap(Map<String, dynamic> map, {int index = 0}) {
    final rawOptions = map['options'];
    List<String> parsedOptions = [];
    if (rawOptions is List) {
      parsedOptions = rawOptions.map((e) => e?.toString() ?? '').toList();
    }

    final rawEnum = map['enumerationAnswers'];
    List<String> parsedEnum = [];
    if (rawEnum is List) {
      parsedEnum = rawEnum.map((e) => e?.toString() ?? '').toList();
    }

    final rawPoints = map['points'];
    double parsedPoints = 1.0;
    if (rawPoints is num) {
      parsedPoints = rawPoints.toDouble();
    }

    return QuizQuestion(
      id: (map['id'] as String?) ?? 'q_${index + 1}',
      type: QuizQuestionType.fromString(map['type']?.toString()),
      question: (map['question'] as String?) ?? '',
      options: parsedOptions,
      correctAnswer: (map['correctAnswer'] as String?) ?? '',
      enumerationAnswers: parsedEnum,
      explanation: (map['explanation'] as String?) ?? '',
      points: parsedPoints > 0 ? parsedPoints : 1.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.value,
      'question': question,
      'options': options,
      'correctAnswer': correctAnswer,
      'enumerationAnswers': enumerationAnswers,
      'explanation': explanation,
      'points': points,
    };
  }

  QuizQuestion copyWith({
    String? id,
    QuizQuestionType? type,
    String? question,
    List<String>? options,
    String? correctAnswer,
    List<String>? enumerationAnswers,
    String? explanation,
    double? points,
  }) {
    return QuizQuestion(
      id: id ?? this.id,
      type: type ?? this.type,
      question: question ?? this.question,
      options: options ?? this.options,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      enumerationAnswers: enumerationAnswers ?? this.enumerationAnswers,
      explanation: explanation ?? this.explanation,
      points: points ?? this.points,
    );
  }
}

/// Represents a generated or authored quiz document stored under `quizzes/{quizId}`.
class QuizModel {
  final String id;
  final String classId;
  final String teacherId;
  final String materialId;
  final String type; // "actual" | "practice"
  final String title;
  final String status; // "draft" | "finalized" | "published" | "closed"
  final String generationMethod; // "gemini" | "fallback" | "manual"
  final String? sourceQuizId;
  final List<QuizQuestion> questions;
  final double totalPoints;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? publishedAt;

  const QuizModel({
    required this.id,
    required this.classId,
    required this.teacherId,
    required this.materialId,
    required this.type,
    required this.title,
    this.status = 'draft',
    this.generationMethod = 'gemini',
    this.sourceQuizId,
    this.questions = const [],
    this.totalPoints = 0.0,
    this.createdAt,
    this.updatedAt,
    this.publishedAt,
  });

  bool get isActual => type.toLowerCase() == 'actual';
  bool get isPractice => type.toLowerCase() == 'practice';
  bool get isDraft => status.toLowerCase() == 'draft';
  bool get isFinalized => status.toLowerCase() == 'finalized';
  bool get isPublished => status.toLowerCase() == 'published';
  bool get isClosed => status.toLowerCase() == 'closed';
  int get questionCount => questions.length;
  bool get isGeminiGenerated => generationMethod.toLowerCase() == 'gemini';
  bool get isFallbackGenerated => generationMethod.toLowerCase() == 'fallback';
  bool get isManual => generationMethod.toLowerCase() == 'manual';

  String get formattedStatus {
    switch (status.toLowerCase()) {
      case 'published':
        return 'Published';
      case 'finalized':
        return 'Finalized';
      case 'closed':
        return 'Closed';
      default:
        return 'Draft';
    }
  }

  factory QuizModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return QuizModel.fromMap(data, id: doc.id);
  }

  factory QuizModel.fromMap(Map<String, dynamic> map, {String id = ''}) {
    final rawQuestions = map['questions'];
    List<QuizQuestion> parsedQuestions = [];
    if (rawQuestions is List) {
      for (int i = 0; i < rawQuestions.length; i++) {
        final q = rawQuestions[i];
        if (q is Map<String, dynamic>) {
          parsedQuestions.add(QuizQuestion.fromMap(q, index: i));
        } else if (q is Map) {
          parsedQuestions.add(QuizQuestion.fromMap(Map<String, dynamic>.from(q), index: i));
        }
      }
    }

    final rawPoints = map['totalPoints'];
    double parsedTotalPoints = 0.0;
    if (rawPoints is num) {
      parsedTotalPoints = rawPoints.toDouble();
    } else {
      parsedTotalPoints =
          parsedQuestions.fold<double>(0.0, (acc, q) => acc + q.points);
    }

    DateTime? parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return QuizModel(
      id: id.isNotEmpty ? id : ((map['id'] as String?) ?? ''),
      classId: (map['classId'] as String?) ?? '',
      teacherId: (map['teacherId'] as String?) ?? '',
      materialId: (map['materialId'] as String?) ?? '',
      type: (map['type'] as String?) ?? 'actual',
      title: (map['title'] as String?) ?? 'Untitled Quiz',
      status: (map['status'] as String?) ?? 'draft',
      generationMethod: (map['generationMethod'] as String?) ?? 'fallback',
      sourceQuizId: map['sourceQuizId'] as String?,
      questions: parsedQuestions,
      totalPoints: parsedTotalPoints,
      createdAt: parseTimestamp(map['createdAt']),
      updatedAt: parseTimestamp(map['updatedAt']),
      publishedAt: parseTimestamp(map['publishedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'classId': classId,
      'teacherId': teacherId,
      'materialId': materialId,
      'type': type,
      'title': title,
      'status': status,
      'generationMethod': generationMethod,
      'sourceQuizId': sourceQuizId,
      'questions': questions.map((q) => q.toMap()).toList(),
      'totalPoints': totalPoints,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      if (publishedAt != null) 'publishedAt': Timestamp.fromDate(publishedAt!),
    };
  }

  QuizModel copyWith({
    String? id,
    String? classId,
    String? teacherId,
    String? materialId,
    String? type,
    String? title,
    String? status,
    String? generationMethod,
    String? sourceQuizId,
    List<QuizQuestion>? questions,
    double? totalPoints,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? publishedAt,
  }) {
    return QuizModel(
      id: id ?? this.id,
      classId: classId ?? this.classId,
      teacherId: teacherId ?? this.teacherId,
      materialId: materialId ?? this.materialId,
      type: type ?? this.type,
      title: title ?? this.title,
      status: status ?? this.status,
      generationMethod: generationMethod ?? this.generationMethod,
      sourceQuizId: sourceQuizId ?? this.sourceQuizId,
      questions: questions ?? this.questions,
      totalPoints: totalPoints ?? this.totalPoints,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      publishedAt: publishedAt ?? this.publishedAt,
    );
  }
}
