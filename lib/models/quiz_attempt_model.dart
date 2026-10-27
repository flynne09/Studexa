/// Represents a student's graded attempt for a practice quiz stored under `attempts/{attemptId}`.
class QuizAttemptModel {
  /// Unique UUID of the quiz attempt.
  final String id;

  /// ID of the quiz that was taken.
  final String quizId;

  /// Optional ID of the class assignment associated with this attempt.
  final String? assignmentId;

  /// ID of the class in which the attempt was submitted.
  final String classId;

  /// User ID of the student who submitted the attempt.
  final String studentId;

  /// Display name of the student at submission time.
  final String studentName;

  /// Map of question IDs to the student's submitted answers.
  final Map<String, dynamic> answers;

  /// Total points earned by the student on this attempt.
  final double score;

  /// Maximum possible points for the quiz at the time of submission.
  final double totalPoints;

  /// Percentage score (`0.0` to `100.0`) achieved on the attempt.
  final double percentage;

  /// Timestamp when the attempt was graded and submitted.
  final DateTime? submittedAt;

  /// Detailed per-question grading breakdown (correctness, earned points, feedback).
  final List<Map<String, dynamic>> breakdown;

  /// Creates a [QuizAttemptModel] instance.
  const QuizAttemptModel({
    required this.id,
    required this.quizId,
    this.assignmentId,
    required this.classId,
    required this.studentId,
    required this.studentName,
    this.answers = const {},
    required this.score,
    required this.totalPoints,
    required this.percentage,
    this.submittedAt,
    this.breakdown = const [],
  });

  /// Formats the percentage as a whole number with a `%` suffix (e.g., "85%").
  String get formattedPercentage => '${percentage.toStringAsFixed(0)}%';

  /// Formats the earned score relative to total points (e.g., "8.5 / 10").
  String get formattedScore =>
      '${score.toStringAsFixed(1)} / ${totalPoints.toStringAsFixed(0)}';

  /// Returns `true` if the student achieved the passing threshold of 70% or higher.
  bool get isPassed => percentage >= 70.0;

  /// Constructs a [QuizAttemptModel] from a database (snake_case) or domain (camelCase) map.
  factory QuizAttemptModel.fromMap(
    Map<String, dynamic> map, {
    String id = '',
  }) {
    // Helper to parse optional ISO-8601 timestamp strings.
    DateTime? parseTimestamp(dynamic val) {
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    // Extract numeric score safely.
    final rawScore = map['score'];
    double parsedScore = 0.0;
    if (rawScore is num) parsedScore = rawScore.toDouble();

    // Extract total possible points safely.
    final rawTotal = map['total_points'] ?? map['totalPoints'];
    double parsedTotal = 0.0;
    if (rawTotal is num) parsedTotal = rawTotal.toDouble();

    // Compute or extract percentage score.
    final rawPercentage = map['percentage'];
    double parsedPercentage = parsedTotal > 0 ? (parsedScore / parsedTotal * 100) : 0.0;
    if (rawPercentage is num) parsedPercentage = rawPercentage.toDouble();

    // Parse per-question grading breakdown items.
    final rawBreakdown = map['breakdown'];
    List<Map<String, dynamic>> parsedBreakdown = [];
    if (rawBreakdown is List) {
      for (final item in rawBreakdown) {
        if (item is Map<String, dynamic>) {
          parsedBreakdown.add(item);
        } else if (item is Map) {
          parsedBreakdown.add(Map<String, dynamic>.from(item));
        }
      }
    }

    // Parse submitted student answers map.
    final rawAnswers = map['answers'];
    Map<String, dynamic> parsedAnswers = {};
    if (rawAnswers is Map<String, dynamic>) {
      parsedAnswers = rawAnswers;
    } else if (rawAnswers is Map) {
      parsedAnswers = Map<String, dynamic>.from(rawAnswers);
    }

    return QuizAttemptModel(
      id: id.isNotEmpty ? id : ((map['id'] as String?) ?? ''),
      quizId: (map['quiz_id'] ?? map['quizId'])?.toString() ?? '',
      assignmentId: (map['assignment_id'] ?? map['assignmentId'])?.toString(),
      classId: (map['class_id'] ?? map['classId'])?.toString() ?? '',
      studentId: (map['student_id'] ?? map['studentId'])?.toString() ?? '',
      studentName: (map['student_name'] ?? map['studentName'])?.toString() ?? 'Student',
      answers: parsedAnswers,
      score: parsedScore,
      totalPoints: parsedTotal,
      percentage: parsedPercentage,
      submittedAt: parseTimestamp(map['submitted_at'] ?? map['submittedAt']),
      breakdown: parsedBreakdown,
    );
  }

  /// Serializes this [QuizAttemptModel] to a camelCase map for domain use.
  Map<String, dynamic> toMap() {
    return {
      'quizId': quizId,
      'assignmentId': assignmentId,
      'classId': classId,
      'studentId': studentId,
      'studentName': studentName,
      'answers': answers,
      'score': score,
      'totalPoints': totalPoints,
      'percentage': percentage,
      if (submittedAt != null)
        'submittedAt': submittedAt!.toUtc().toIso8601String(),
      'breakdown': breakdown,
    };
  }

  /// Serializes this [QuizAttemptModel] to a snake_case map for the `public.quiz_attempts` table.
  Map<String, dynamic> toDatabaseMap() {
    return {
      'quiz_id': quizId,
      'assignment_id': assignmentId,
      'class_id': classId,
      'student_id': studentId,
      'student_name': studentName,
      'answers': answers,
      'score': score,
      'total_points': totalPoints,
      'percentage': percentage,
      if (submittedAt != null)
        'submitted_at': submittedAt!.toUtc().toIso8601String(),
      'breakdown': breakdown,
    };
  }
}
