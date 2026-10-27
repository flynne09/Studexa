/// Supported question types in Phase 1.
enum QuizQuestionType {
  multipleChoice,
  trueFalse,
  fillInTheBlank,
  identification,
  enumeration;

  /// Returns the canonical snake_case string identifier stored in Postgres and Edge Functions.
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

  /// Returns the user-facing label for displaying the question type in the UI.
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

  /// Parses a string representation into a [QuizQuestionType], defaulting to [QuizQuestionType.multipleChoice].
  static QuizQuestionType fromString(String? typeStr) {
    if (typeStr == null || typeStr.isEmpty) {
      return QuizQuestionType.multipleChoice;
    }
    final lower = typeStr.toLowerCase().trim().replaceAll(
      RegExp(r'[\s\-\/]'),
      '_',
    );
    if (lower.contains('multiple') || lower.contains('mcq')) {
      return QuizQuestionType.multipleChoice;
    }
    if (lower.contains('true') ||
        lower.contains('false') ||
        lower.contains('tf')) {
      return QuizQuestionType.trueFalse;
    }
    if (lower.contains('fill') || lower.contains('blank')) {
      return QuizQuestionType.fillInTheBlank;
    }
    if (lower.contains('ident')) return QuizQuestionType.identification;
    if (lower.contains('enum')) return QuizQuestionType.enumeration;
    return QuizQuestionType.multipleChoice;
  }
}

/// Represents a single question within a quiz.
class QuizQuestion {
  /// Unique identifier of the question within the quiz (e.g., "q_1").
  final String id;

  /// Question format (Multiple Choice, True/False, Fill-in-the-Blank, Identification, or Enumeration).
  final QuizQuestionType type;

  /// Prompt or stem text presented to the student.
  final String question;

  /// Choice options for Multiple Choice or True/False questions.
  final List<String> options;

  /// Canonical correct answer for single-answer question types.
  final String correctAnswer;

  /// List of expected valid answers for Enumeration questions.
  final List<String> enumerationAnswers;

  /// Explanation or rationale shown during review after grading.
  final String explanation;

  /// Point value awarded for answering the question completely and accurately.
  final double points;

  /// Source of the question ('gemini', 'fallback', or 'manual').
  final String origin;

  /// Creates a [QuizQuestion] instance.
  const QuizQuestion({
    required this.id,
    required this.type,
    required this.question,
    this.options = const [],
    this.correctAnswer = '',
    this.enumerationAnswers = const [],
    this.explanation = '',
    this.points = 1.0,
    this.origin = 'gemini',
  });

  /// Constructs a [QuizQuestion] from a decoded JSON/database map.
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
      origin: (map['origin'] as String?) ?? 'gemini',
    );
  }

  /// Serializes this [QuizQuestion] to a JSON-compatible map for storage in `quizzes.questions`.
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
      if (origin == 'manual') 'origin': origin,
    };
  }

  /// Creates a copy of this [QuizQuestion] with specified fields replaced.
  QuizQuestion copyWith({
    String? id,
    QuizQuestionType? type,
    String? question,
    List<String>? options,
    String? correctAnswer,
    List<String>? enumerationAnswers,
    String? explanation,
    double? points,
    String? origin,
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
      origin: origin ?? this.origin,
    );
  }
}

/// Represents a generated or authored quiz document stored under `quizzes/{quizId}`.
class QuizModel {
  /// Unique UUID of the quiz record.
  final String id;

  /// ID of the class this quiz belongs to.
  final String classId;

  /// User ID of the teacher who owns this quiz.
  final String teacherId;

  /// ID of the study material from which this quiz was generated.
  final String materialId;

  /// Quiz category: `'actual'` (teacher-only exam master) or `'practice'` (student-facing review quiz).
  final String type; // "actual" | "practice"

  /// Display title of the quiz.
  final String title;

  /// Current workflow status (`'draft'`, `'finalized'`, `'published'`, or `'closed'`).
  final String status; // "draft" | "finalized" | "published" | "closed"

  /// Method used to produce the quiz (`'gemini'`, `'fallback'`, or `'manual'`).
  final String generationMethod; // "gemini" | "fallback" | "manual"

  /// If this is a practice quiz derived from an actual quiz, stores the source actual quiz's ID.
  final String? sourceQuizId;

  /// Ordered list of questions included in the quiz.
  final List<QuizQuestion> questions;

  /// Sum of points across all questions in the quiz.
  final double totalPoints;

  /// Number of questions originally requested by the teacher during AI generation.
  final int? requestedQuestionCount;

  /// Question type identifiers selected by the teacher for generation.
  final List<String> selectedQuestionTypes;

  /// Whether a top-up generation pass was already attempted for a shortfall.
  final bool extraGenerationAttempted;

  /// Indicates whether generation used the teacher's `'personal'` key or the `'backup'` server key.
  final String generationCredentialSource;

  /// Whether the server backup Gemini credential was used to generate this quiz.
  final bool backupUsed;

  /// Reason code explaining why the backup credential was used (if applicable).
  final String? backupUsageReason;

  /// Remaining grace-period backup generations available to the teacher.
  final int? backupGraceRemaining;

  /// Remaining daily fallback backup generations available to the teacher today.
  final int? backupFallbackRemainingToday;

  /// Timestamp when the quiz was first created.
  final DateTime? createdAt;

  /// Timestamp when the quiz was last modified.
  final DateTime? updatedAt;

  /// Timestamp when the quiz was published or finalized.
  final DateTime? publishedAt;

  /// Creates a [QuizModel] instance.
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
    this.requestedQuestionCount,
    this.selectedQuestionTypes = const [],
    this.extraGenerationAttempted = false,
    this.generationCredentialSource = 'personal',
    this.backupUsed = false,
    this.backupUsageReason,
    this.backupGraceRemaining,
    this.backupFallbackRemainingToday,
    this.createdAt,
    this.updatedAt,
    this.publishedAt,
  });

  /// Returns `true` if this is a teacher-only Actual Quiz.
  bool get isActual => type.toLowerCase() == 'actual';

  /// Returns `true` if this is a student-facing Practice Quiz.
  bool get isPractice => type.toLowerCase() == 'practice';

  /// Returns `true` if the quiz is still in editable draft state.
  bool get isDraft => status.toLowerCase() == 'draft';

  /// Returns `true` if an Actual Quiz has been finalized for PDF export.
  bool get isFinalized => status.toLowerCase() == 'finalized';

  /// Returns `true` if a Practice Quiz has been published for students to take.
  bool get isPublished => status.toLowerCase() == 'published';

  /// Returns `true` if the quiz has been closed to further student attempts.
  bool get isClosed => status.toLowerCase() == 'closed';

  /// Total number of questions currently in the quiz.
  int get questionCount => questions.length;

  /// Returns `true` if AI generation returned fewer questions than requested while still in draft.
  bool get hasGenerationShortfall =>
      isDraft &&
      requestedQuestionCount != null &&
      questionCount < requestedQuestionCount!;

  /// Returns `true` if generated via the Gemini AI model.
  bool get isGeminiGenerated => generationMethod.toLowerCase() == 'gemini';

  /// Returns `true` if generated via the deterministic fallback generator.
  bool get isFallbackGenerated => generationMethod.toLowerCase() == 'fallback';

  /// Returns `true` if authored manually.
  bool get isManual => generationMethod.toLowerCase() == 'manual';

  /// Human-readable status string for UI badges.
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

  /// Constructs a [QuizModel] from a database (snake_case) or domain (camelCase) map.
  factory QuizModel.fromMap(Map<String, dynamic> map, {String id = ''}) {
    // Parse embedded JSON array of questions.
    final rawQuestions = map['questions'];
    List<QuizQuestion> parsedQuestions = [];
    if (rawQuestions is List) {
      for (int i = 0; i < rawQuestions.length; i++) {
        final q = rawQuestions[i];
        if (q is Map<String, dynamic>) {
          parsedQuestions.add(QuizQuestion.fromMap(q, index: i));
        } else if (q is Map) {
          parsedQuestions.add(
            QuizQuestion.fromMap(Map<String, dynamic>.from(q), index: i),
          );
        }
      }
    }

    // Calculate total points from the stored field or by summing question points.
    final rawPoints = map['total_points'] ?? map['totalPoints'];
    double parsedTotalPoints = 0.0;
    if (rawPoints is num) {
      parsedTotalPoints = rawPoints.toDouble();
    } else {
      parsedTotalPoints = parsedQuestions.fold<double>(
        0.0,
        (acc, q) => acc + q.points,
      );
    }

    // Helper to parse optional ISO-8601 timestamp strings.
    DateTime? parseTimestamp(dynamic val) {
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return QuizModel(
      id: id.isNotEmpty ? id : ((map['id'] as String?) ?? ''),
      classId: (map['class_id'] ?? map['classId'])?.toString() ?? '',
      teacherId: (map['teacher_id'] ?? map['teacherId'])?.toString() ?? '',
      materialId: (map['material_id'] ?? map['materialId'])?.toString() ?? '',
      type: (map['quiz_type'] ?? map['type'])?.toString() ?? 'actual',
      title: (map['title'] as String?) ?? 'Untitled Quiz',
      status: (map['status'] as String?) ?? 'draft',
      generationMethod:
          (map['generation_method'] ?? map['generationMethod'])?.toString() ??
              'fallback',
      sourceQuizId:
          (map['source_quiz_id'] ?? map['sourceQuizId'])?.toString(),
      questions: parsedQuestions,
      totalPoints: parsedTotalPoints,
      requestedQuestionCount:
          (map['requested_question_count'] ?? map['requestedQuestionCount'])
                  is num
              ? ((map['requested_question_count'] ??
                      map['requestedQuestionCount']) as num)
                  .toInt()
              : null,
      selectedQuestionTypes:
          ((map['selected_question_types'] ?? map['selectedQuestionTypes'])
                  as List?)
              ?.map((value) => value.toString())
              .toList() ??
          const [],
      extraGenerationAttempted:
          (map['extra_generation_attempted'] ??
              map['extraGenerationAttempted']) == true,
      generationCredentialSource:
          (map['generation_credential_source'] ??
                      map['generationCredentialSource'])
                  ?.toString() ??
              'personal',
      backupUsed: (map['backup_used'] ?? map['backupUsed']) == true,
      backupUsageReason:
          (map['backup_usage_reason'] ?? map['backupUsageReason'])?.toString(),
      backupGraceRemaining:
          (map['backup_grace_remaining'] ?? map['backupGraceRemaining']) is num
              ? ((map['backup_grace_remaining'] ??
                      map['backupGraceRemaining']) as num)
                  .toInt()
              : null,
      backupFallbackRemainingToday:
          (map['backup_fallback_remaining_today'] ??
                      map['backupFallbackRemainingToday'])
                  is num
              ? ((map['backup_fallback_remaining_today'] ??
                      map['backupFallbackRemainingToday']) as num)
                  .toInt()
              : null,
      createdAt: parseTimestamp(map['created_at'] ?? map['createdAt']),
      updatedAt: parseTimestamp(map['updated_at'] ?? map['updatedAt']),
      publishedAt: parseTimestamp(map['published_at'] ?? map['publishedAt']),
    );
  }

  /// Serializes this [QuizModel] to a camelCase map for in-app usage.
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
      if (requestedQuestionCount != null)
        'requestedQuestionCount': requestedQuestionCount,
      if (selectedQuestionTypes.isNotEmpty)
        'selectedQuestionTypes': selectedQuestionTypes,
      'extraGenerationAttempted': extraGenerationAttempted,
      'generationCredentialSource': generationCredentialSource,
      'backupUsed': backupUsed,
      'backupUsageReason': backupUsageReason,
      if (backupGraceRemaining != null)
        'backupGraceRemaining': backupGraceRemaining,
      if (backupFallbackRemainingToday != null)
        'backupFallbackRemainingToday': backupFallbackRemainingToday,
      if (createdAt != null)
        'createdAt': createdAt!.toUtc().toIso8601String(),
      if (updatedAt != null)
        'updatedAt': updatedAt!.toUtc().toIso8601String(),
      if (publishedAt != null)
        'publishedAt': publishedAt!.toUtc().toIso8601String(),
    };
  }

  /// Serializes this [QuizModel] to a snake_case map for the `public.quizzes` table.
  Map<String, dynamic> toDatabaseMap() {
    return {
      'class_id': classId,
      'teacher_id': teacherId,
      'material_id': materialId,
      'quiz_type': type,
      'title': title,
      'status': status,
      'generation_method': generationMethod,
      'source_quiz_id': sourceQuizId,
      'questions': questions.map((q) => q.toMap()).toList(),
      'total_points': totalPoints,
      if (requestedQuestionCount != null)
        'requested_question_count': requestedQuestionCount,
      if (selectedQuestionTypes.isNotEmpty)
        'selected_question_types': selectedQuestionTypes,
      'extra_generation_attempted': extraGenerationAttempted,
      'generation_credential_source': generationCredentialSource,
      'backup_used': backupUsed,
      'backup_usage_reason': backupUsageReason,
      if (backupGraceRemaining != null)
        'backup_grace_remaining': backupGraceRemaining,
      if (backupFallbackRemainingToday != null)
        'backup_fallback_remaining_today': backupFallbackRemainingToday,
      if (createdAt != null)
        'created_at': createdAt!.toUtc().toIso8601String(),
      if (updatedAt != null)
        'updated_at': updatedAt!.toUtc().toIso8601String(),
      if (publishedAt != null)
        'published_at': publishedAt!.toUtc().toIso8601String(),
    };
  }

  /// Creates a copy of this [QuizModel] with selected fields updated.
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
    int? requestedQuestionCount,
    List<String>? selectedQuestionTypes,
    bool? extraGenerationAttempted,
    String? generationCredentialSource,
    bool? backupUsed,
    String? backupUsageReason,
    int? backupGraceRemaining,
    int? backupFallbackRemainingToday,
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
      requestedQuestionCount:
          requestedQuestionCount ?? this.requestedQuestionCount,
      selectedQuestionTypes:
          selectedQuestionTypes ?? this.selectedQuestionTypes,
      extraGenerationAttempted:
          extraGenerationAttempted ?? this.extraGenerationAttempted,
      generationCredentialSource:
          generationCredentialSource ?? this.generationCredentialSource,
      backupUsed: backupUsed ?? this.backupUsed,
      backupUsageReason: backupUsageReason ?? this.backupUsageReason,
      backupGraceRemaining: backupGraceRemaining ?? this.backupGraceRemaining,
      backupFallbackRemainingToday:
          backupFallbackRemainingToday ?? this.backupFallbackRemainingToday,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      publishedAt: publishedAt ?? this.publishedAt,
    );
  }
}
