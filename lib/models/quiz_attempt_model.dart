import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a student's graded attempt for a practice quiz stored under `attempts/{attemptId}`.
class QuizAttemptModel {
  final String id;
  final String quizId;
  final String? assignmentId;
  final String classId;
  final String studentId;
  final String studentName;
  final Map<String, dynamic> answers;
  final double score;
  final double totalPoints;
  final double percentage;
  final DateTime? submittedAt;
  final List<Map<String, dynamic>> breakdown;

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

  String get formattedPercentage => '${percentage.toStringAsFixed(0)}%';
  String get formattedScore =>
      '${score.toStringAsFixed(1)} / ${totalPoints.toStringAsFixed(0)}';
  bool get isPassed => percentage >= 70.0;

  factory QuizAttemptModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return QuizAttemptModel.fromMap(data, id: doc.id);
  }

  factory QuizAttemptModel.fromMap(
    Map<String, dynamic> map, {
    String id = '',
  }) {
    DateTime? parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    final rawScore = map['score'];
    double parsedScore = 0.0;
    if (rawScore is num) parsedScore = rawScore.toDouble();

    final rawTotal = map['totalPoints'];
    double parsedTotal = 0.0;
    if (rawTotal is num) parsedTotal = rawTotal.toDouble();

    final rawPercentage = map['percentage'];
    double parsedPercentage = parsedTotal > 0 ? (parsedScore / parsedTotal * 100) : 0.0;
    if (rawPercentage is num) parsedPercentage = rawPercentage.toDouble();

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

    final rawAnswers = map['answers'];
    Map<String, dynamic> parsedAnswers = {};
    if (rawAnswers is Map<String, dynamic>) {
      parsedAnswers = rawAnswers;
    } else if (rawAnswers is Map) {
      parsedAnswers = Map<String, dynamic>.from(rawAnswers);
    }

    return QuizAttemptModel(
      id: id.isNotEmpty ? id : ((map['id'] as String?) ?? ''),
      quizId: (map['quizId'] as String?) ?? '',
      assignmentId: map['assignmentId'] as String?,
      classId: (map['classId'] as String?) ?? '',
      studentId: (map['studentId'] as String?) ?? '',
      studentName: (map['studentName'] as String?) ?? 'Student',
      answers: parsedAnswers,
      score: parsedScore,
      totalPoints: parsedTotal,
      percentage: parsedPercentage,
      submittedAt: parseTimestamp(map['submittedAt']),
      breakdown: parsedBreakdown,
    );
  }

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
      if (submittedAt != null) 'submittedAt': Timestamp.fromDate(submittedAt!),
      'breakdown': breakdown,
    };
  }
}
