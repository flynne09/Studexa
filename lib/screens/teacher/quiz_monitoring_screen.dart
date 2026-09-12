import 'package:flutter/material.dart';
import '../../models/class_model.dart';
import '../../models/quiz_assignment_model.dart';
import '../../models/quiz_attempt_model.dart';
import '../../models/quiz_model.dart';
import '../../services/assignment_service.dart';
import '../../services/class_service.dart';
import '../../theme/app_theme.dart';

/// Teacher screen for monitoring class quiz submissions, reviewing individual student scores,
/// managing assignment status (open/close/deadline), and viewing class summary analytics.
class QuizMonitoringScreen extends StatefulWidget {
  final QuizModel quiz;
  final String className;
  final Stream<List<ClassMember>>? initialMembersStream;
  final Stream<List<QuizAttemptModel>>? initialAttemptsStream;
  final QuizAssignmentModel? initialAssignment;

  const QuizMonitoringScreen({
    super.key,
    required this.quiz,
    this.className = 'Class',
    this.initialMembersStream,
    this.initialAttemptsStream,
    this.initialAssignment,
  });

  @override
  State<QuizMonitoringScreen> createState() => _QuizMonitoringScreenState();
}

class _QuizMonitoringScreenState extends State<QuizMonitoringScreen> {
  static const _primaryNavy = AppTheme.primaryNavy;
  static const _darkNavy = AppTheme.darkNavy;
  static const _gradientStart = AppTheme.gradientStart;
  static const _gradientEnd = AppTheme.gradientEnd;
  static const _surfaceWhite = AppTheme.surfaceWhite;
  static const _outlineVariant = AppTheme.outlineVariant;
  static const _textPrimary = AppTheme.textPrimary;
  static const _textSecondary = AppTheme.textSecondary;

  final AssignmentService _assignmentService = AssignmentService();
  final ClassService _classService = ClassService();

  QuizAssignmentModel? _assignment;
  late Stream<List<ClassMember>> _membersStream;
  late Stream<List<QuizAttemptModel>> _attemptsStream;

  @override
  void initState() {
    super.initState();
    _initStreams();
    if (widget.initialAssignment != null) {
      _assignment = widget.initialAssignment;
    } else {
      _loadAssignment();
    }
  }

  void _initStreams() {
    _membersStream = widget.initialMembersStream ??
        _classService.getClassMembersStream(widget.quiz.classId);
    _attemptsStream = widget.initialAttemptsStream ??
        _assignmentService.streamClassQuizAttempts(
          widget.quiz.classId,
          widget.quiz.id,
        );
  }

  @override
  void didUpdateWidget(covariant QuizMonitoringScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quiz.id != widget.quiz.id ||
        oldWidget.quiz.classId != widget.quiz.classId) {
      _initStreams();
    }
  }

  Future<void> _loadAssignment() async {
    if (widget.initialAssignment != null) return;
    final assign = await _assignmentService.getAssignmentForQuiz(
      widget.quiz.classId,
      widget.quiz.id,
    );
    if (!mounted) return;
    setState(() {
      _assignment = assign;
    });
  }

  Future<void> _toggleAssignmentStatus() async {
    if (_assignment == null) {
      // Create assignment first
      final newAssign = await _assignmentService.createAssignment(
        quizId: widget.quiz.id,
        classId: widget.quiz.classId,
        teacherId: widget.quiz.teacherId,
        quizTitle: widget.quiz.title,
      );
      setState(() => _assignment = newAssign);
      return;
    }

    if (_assignment!.isClosed) {
      await _assignmentService.reopenAssignment(_assignment!.id);
      setState(() {
        _assignment = _assignment!.copyWith(isClosed: false);
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quiz assignment reopened for submissions.'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      await _assignmentService.closeAssignment(_assignment!.id);
      setState(() {
        _assignment = _assignment!.copyWith(isClosed: true);
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quiz assignment closed. No new submissions allowed.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _setDeadline() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _assignment?.deadline ?? now.add(const Duration(days: 2)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (pickedDate == null) return;

    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _assignment?.deadline ?? now.add(const Duration(hours: 2)),
      ),
    );

    if (pickedTime == null) return;

    final combinedDeadline = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (_assignment == null) {
      final newAssign = await _assignmentService.createAssignment(
        quizId: widget.quiz.id,
        classId: widget.quiz.classId,
        teacherId: widget.quiz.teacherId,
        quizTitle: widget.quiz.title,
        deadline: combinedDeadline,
      );
      setState(() => _assignment = newAssign);
    } else {
      await _assignmentService.updateDeadline(
        _assignment!.id,
        combinedDeadline,
      );
      setState(() {
        _assignment = _assignment!.copyWith(deadline: combinedDeadline);
      });
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Deadline set to ${combinedDeadline.month}/${combinedDeadline.day}/${combinedDeadline.year} at ${pickedTime.format(context)}',
        ),
        backgroundColor: _primaryNavy,
      ),
    );
  }

  void _showStudentAttemptDetails(QuizAttemptModel attempt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surfaceWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusXl),
        ),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            controller: scrollController,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attempt.studentName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _textPrimary,
                          ),
                        ),
                        Text(
                          'Score: ${attempt.formattedScore} (${attempt.formattedPercentage})',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: attempt.isPassed ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 24),
              const Text(
                'Submission Breakdown',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...List.generate(attempt.breakdown.length, (idx) {
                final b = attempt.breakdown[idx];
                final isCor = (b['isCorrect'] as bool?) ?? false;
                final earned = (b['earned'] as num?)?.toDouble() ?? 0.0;
                final points = (b['points'] as num?)?.toDouble() ?? 1.0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isCor
                        ? Colors.green.withValues(alpha: 0.05)
                        : Colors.red.withValues(alpha: 0.05),
                    borderRadius: AppTheme.borderRadiusMd,
                    border: Border.all(
                      color: isCor
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Q${idx + 1}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Text(
                            '${earned.toStringAsFixed(1)} / ${points.toStringAsFixed(0)} pt',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color:
                                  isCor ? Colors.green[800] : Colors.red[800],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Student Answer: ${b['userAnswer'] ?? 'None'}',
                          style: const TextStyle(fontSize: 13)),
                      Text('Expected: ${b['correctAnswer'] ?? 'N/A'}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.green[900])),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Quiz Monitoring',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _textPrimary,
          ),
        ),
        backgroundColor: _surfaceWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _primaryNavy),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_gradientStart, _gradientEnd],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTheme.maxContentWidthTablet,
              ),
              child: StreamBuilder<List<ClassMember>>(
                stream: _membersStream,
                builder: (context, membersSnapshot) {
                  final allMembers = membersSnapshot.data ?? [];
                  final students =
                      allMembers.where((m) => m.role == 'student').toList();

                  return StreamBuilder<List<QuizAttemptModel>>(
                    stream: _attemptsStream,
                    builder: (context, attemptsSnapshot) {
                      final attempts = attemptsSnapshot.data ?? [];

                      // Map studentId -> latest attempt
                      final Map<String, QuizAttemptModel> studentAttempts = {};
                      for (final att in attempts) {
                        if (!studentAttempts.containsKey(att.studentId)) {
                          studentAttempts[att.studentId] = att;
                        }
                      }

                      // Class analytics calculations
                      final totalStudents = students.length;
                      final completedStudents = studentAttempts.length;
                      final completionRate = totalStudents > 0
                          ? (completedStudents / totalStudents * 100)
                          : 0.0;

                      double avgPercentage = 0.0;
                      double highestScore = 0.0;
                      if (completedStudents > 0) {
                        final totalP = studentAttempts.values
                            .fold<double>(0.0, (acc, a) => acc + a.percentage);
                        avgPercentage = totalP / completedStudents;
                        highestScore = studentAttempts.values
                            .map((a) => a.percentage)
                            .reduce((a, b) => a > b ? a : b);
                      }

                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // ── Header Card ──────────────────────────────
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [_primaryNavy, _darkNavy],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: AppTheme.borderRadiusLg,
                              boxShadow: AppTheme.cardShadow,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.quiz.title,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Class: ${widget.className} • ${widget.quiz.questionCount} Questions (${widget.quiz.totalPoints.toStringAsFixed(0)} pts)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // ── Assignment Status & Controls ─────────────
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _surfaceWhite,
                              borderRadius: AppTheme.borderRadiusLg,
                              border: Border.all(color: _outlineVariant),
                              boxShadow: AppTheme.cardShadow,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Assignment Status',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: _textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: (_assignment?.isAvailable ?? true)
                                            ? Colors.green.withValues(alpha: 0.1)
                                            : Colors.red.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: (_assignment?.isAvailable ?? true)
                                              ? Colors.green
                                              : Colors.red,
                                        ),
                                      ),
                                      child: Text(
                                        _assignment?.formattedStatus ?? 'Open',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: (_assignment?.isAvailable ?? true)
                                              ? Colors.green[800]
                                              : Colors.red[800],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_assignment?.deadline != null) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.schedule,
                                          size: 14, color: _textSecondary),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Deadline: ${_assignment!.deadline!.month}/${_assignment!.deadline!.day}/${_assignment!.deadline!.year} at ${_assignment!.deadline!.hour}:${_assignment!.deadline!.minute.toString().padLeft(2, '0')}',
                                          style: const TextStyle(
                                              fontSize: 12, color: _textSecondary),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              (_assignment?.isClosed ?? false)
                                                  ? Colors.green
                                                  : Colors.red[700],
                                          side: BorderSide(
                                            color: (_assignment?.isClosed ?? false)
                                                ? Colors.green
                                                : Colors.red.shade300,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                AppTheme.borderRadiusMd,
                                          ),
                                        ),
                                        onPressed: _toggleAssignmentStatus,
                                        icon: Icon(
                                          (_assignment?.isClosed ?? false)
                                              ? Icons.lock_open
                                              : Icons.lock_outline,
                                          size: 16,
                                        ),
                                        label: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            (_assignment?.isClosed ?? false)
                                                ? 'Reopen Quiz'
                                                : 'Close Submissions',
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: _primaryNavy,
                                          side: const BorderSide(color: _primaryNavy),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: AppTheme.borderRadiusMd,
                                          ),
                                        ),
                                        onPressed: _setDeadline,
                                        icon: const Icon(Icons.calendar_month,
                                            size: 16),
                                        label: const FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text('Set Deadline'),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                      // ── Analytics Summary Cards ──────────────────
                      Row(
                        children: [
                          _buildMetricCard(
                            label: 'Completion',
                            value:
                                '$completedStudents/$totalStudents (${completionRate.toStringAsFixed(0)}%)',
                            color: Colors.blue,
                            icon: Icons.people_outline,
                          ),
                          const SizedBox(width: 10),
                          _buildMetricCard(
                            label: 'Average Score',
                            value: '${avgPercentage.toStringAsFixed(0)}%',
                            color: Colors.teal,
                            icon: Icons.analytics_outlined,
                          ),
                          const SizedBox(width: 10),
                          _buildMetricCard(
                            label: 'Top Score',
                            value: '${highestScore.toStringAsFixed(0)}%',
                            color: Colors.amber[800]!,
                            icon: Icons.star_border,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Enrolled Student Roster & Results ─────────
                      const Text(
                        'Student Submissions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),

                      if (students.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: _surfaceWhite,
                            borderRadius: AppTheme.borderRadiusMd,
                            border: Border.all(color: _outlineVariant),
                          ),
                          child: const Center(
                            child: Text(
                              'No students currently enrolled in this class.',
                              style: TextStyle(
                                  fontSize: 13, color: _textSecondary),
                            ),
                          ),
                        )
                      else
                        ...students.map((student) {
                          final attempt = studentAttempts[student.userId];
                          final hasCompleted = attempt != null;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: _surfaceWhite,
                              borderRadius: AppTheme.borderRadiusLg,
                              border: Border.all(
                                color: hasCompleted
                                    ? Colors.green.withValues(alpha: 0.3)
                                    : _outlineVariant,
                              ),
                              boxShadow: AppTheme.cardShadow,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: AppTheme.borderRadiusLg,
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 4),
                                leading: CircleAvatar(
                                  backgroundColor: hasCompleted
                                      ? Colors.green.withValues(alpha: 0.15)
                                      : Colors.grey.withValues(alpha: 0.15),
                                  child: Text(
                                    student.displayName.isNotEmpty
                                        ? student.displayName[0].toUpperCase()
                                        : 'S',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: hasCompleted
                                          ? Colors.green[800]
                                          : Colors.grey[700],
                                    ),
                                  ),
                                ),
                                title: Text(
                                  student.displayName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: _textPrimary,
                                  ),
                                ),
                                subtitle: Text(
                                  hasCompleted
                                      ? 'Score: ${attempt.formattedScore} (${attempt.formattedPercentage})'
                                      : 'Not yet attempted',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: hasCompleted
                                        ? Colors.green[800]
                                        : _textSecondary,
                                    fontWeight: hasCompleted
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                                trailing: hasCompleted
                                    ? OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: _primaryNavy,
                                          side: const BorderSide(
                                              color: _primaryNavy),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                AppTheme.borderRadiusMd,
                                          ),
                                        ),
                                        onPressed: () =>
                                            _showStudentAttemptDetails(attempt),
                                        child: const Text('Review',
                                            style: TextStyle(fontSize: 11)),
                                      )
                                    : Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color:
                                              Colors.grey.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'Pending',
                                          style: TextStyle(
                                              fontSize: 11, color: Colors.grey),
                                        ),
                                      ),
                              ),
                            ),
                          );
                        }),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    ),
  ),
);
}

  Widget _buildMetricCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _surfaceWhite,
          borderRadius: AppTheme.borderRadiusLg,
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: _textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
