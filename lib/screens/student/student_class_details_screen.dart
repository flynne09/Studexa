import 'package:flutter/material.dart';
import '../../models/class_model.dart';
import '../../models/material_model.dart';
import '../../models/quiz_assignment_model.dart';
import '../../models/quiz_attempt_model.dart';
import '../../models/quiz_model.dart';
import '../../services/assignment_service.dart';
import '../../services/auth_service.dart';
import '../../services/class_service.dart';
import '../../services/material_service.dart';
import '../../services/quiz_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/studexa_background.dart';
import '../../widgets/app_feedback.dart';
import 'answer_quiz_screen.dart';
import '../materials/material_viewer_screen.dart';

/// Class Details Screen for Students (Google Classroom style).
///
/// Displays:
/// - Class header with class name, instructor, and join code.
/// - Materials tab with lecture notes, slides, and study documents for this class.
/// - Practice Quizzes tab with available practice quizzes for this class.
/// - People tab with instructor info and classmates.
class StudentClassDetailsScreen extends StatefulWidget {
  final ClassModel classModel;
  final Stream<ClassModel?>? initialClassStream;
  final Stream<List<MaterialModel>>? initialMaterialsStream;
  final Stream<List<QuizModel>>? initialQuizzesStream;
  final Stream<List<ClassMember>>? initialPeopleStream;

  const StudentClassDetailsScreen({
    super.key,
    required this.classModel,
    this.initialClassStream,
    this.initialMaterialsStream,
    this.initialQuizzesStream,
    this.initialPeopleStream,
  });

  @override
  State<StudentClassDetailsScreen> createState() =>
      _StudentClassDetailsScreenState();
}

class _StudentClassDetailsScreenState extends State<StudentClassDetailsScreen>
    with SingleTickerProviderStateMixin {
  static const _primaryNavy = AppTheme.primaryNavy;
  static const _darkNavy = AppTheme.darkNavy;
  static const _surfaceWhite = AppTheme.surfaceWhite;
  static const _outlineVariant = AppTheme.outlineVariant;
  static const _textPrimary = AppTheme.textPrimary;
  static const _textSecondary = AppTheme.textSecondary;

  late TabController _tabController;
  final MaterialService _materialService = MaterialService();
  final ClassService _classService = ClassService();
  final QuizService _quizService = QuizService();
  final AssignmentService _assignmentService = AssignmentService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showStudentMaterialDetails(MaterialModel material) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildFileTypeBadge(material.fileType),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        material.fileName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _textPrimary,
                        ),
                      ),
                      Text(
                        ' • Posted ',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _textSecondary,
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
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            if (material.isReady && material.extractedText.isNotEmpty) ...[
              const Text(
                'Study Content & Notes',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _primaryNavy,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 250),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _surfaceWhite,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _outlineVariant),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    material.extractedText,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _textPrimary,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surfaceWhite,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _outlineVariant),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: _primaryNavy, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This study material is being processed by your instructor.',
                        style: TextStyle(fontSize: 13, color: _textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (material.isReady) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    MaterialViewerScreen.open(
                      context: context,
                      material: material,
                      materialService: _materialService,
                    );
                  },
                  icon: Icon(
                    material.fileType.toLowerCase() == 'pdf'
                        ? Icons.picture_as_pdf
                        : Icons.open_in_new,
                    size: 18,
                  ),
                  label: Text(
                    'View Material (${material.fileType.toUpperCase()})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildFileTypeBadge(String ext) {
    Color bg = Colors.blue;
    String label = ext.toUpperCase();

    if (ext.toLowerCase() == 'pdf') {
      bg = Colors.redAccent;
    } else if (ext.toLowerCase() == 'pptx') {
      bg = Colors.orange;
    } else if (ext.toLowerCase() == 'docx') {
      bg = Colors.blueAccent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bg.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: bg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ClassModel?>(
      stream:
          widget.initialClassStream ??
          _classService.streamClass(widget.classModel.id),
      initialData: widget.classModel,
      builder: (context, classSnapshot) {
        final liveClass = classSnapshot.data ?? widget.classModel;

        return Scaffold(
          body: StudexaBackground(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppTheme.maxContentWidthTablet,
                  ),
                  child: Column(
                    children: [
                      // ── Top Navigation Bar ────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: _textPrimary,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                liveClass.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Google Classroom Header Banner ────────────
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(20),
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
                              liveClass.name,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (liveClass.teacherName.isNotEmpty)
                              Text(
                                'Instructor: ${liveClass.teacherName}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Class Code: ${liveClass.joinCode}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ── Segmented Tabs ───────────────────────────
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: _surfaceWhite,
                          borderRadius: AppTheme.borderRadiusMd,
                          border: Border.all(color: _outlineVariant),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          labelColor: _primaryNavy,
                          unselectedLabelColor: _textSecondary,
                          indicator: BoxDecoration(
                            color: _primaryNavy.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          tabs: const [
                            Tab(
                              icon: Icon(Icons.folder_outlined),
                              text: 'Materials',
                            ),
                            Tab(
                              icon: Icon(Icons.quiz_outlined),
                              text: 'Quizzes',
                            ),
                            Tab(
                              icon: Icon(Icons.people_outline),
                              text: 'Class Info',
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // ── Tab Views ────────────────────────────────
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // 1. Materials Tab
                            _buildMaterialsTab(liveClass),

                            // 2. Practice Quizzes Tab
                            _buildQuizzesTab(liveClass),

                            // 3. Class Info & People Tab
                            _buildPeopleTab(liveClass),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Materials Tab View ─────────────────────────────────────────
  Widget _buildMaterialsTab(ClassModel liveClass) {
    return StreamBuilder<List<MaterialModel>>(
      stream:
          widget.initialMaterialsStream ??
          _materialService.streamClassMaterials(liveClass.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2.5),
          );
        }

        final materials = snapshot.data ?? [];

        if (materials.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: 60,
                    color: _primaryNavy.withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Materials Shared Yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'When your instructor uploads lecture slides, PDFs, or study notes for this class, they will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: _textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: materials.length,
          itemBuilder: (context, index) {
            final mat = materials[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _surfaceWhite,
                borderRadius: AppTheme.borderRadiusLg,
                border: Border.all(color: _outlineVariant),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: AppTheme.borderRadiusLg,
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: _buildFileTypeBadge(mat.fileType),
                  title: Text(
                    mat.fileName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    ' • Posted ',
                    style: const TextStyle(fontSize: 12, color: _textSecondary),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: _textSecondary,
                  ),
                  onTap: () => _showStudentMaterialDetails(mat),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Practice Quizzes Tab View ──────────────────────────────────
  Widget _buildQuizzesTab(ClassModel liveClass) {
    final currentUserId = AuthService().currentUser?.uid ?? '';

    return StreamBuilder<List<QuizModel>>(
      stream:
          widget.initialQuizzesStream ??
          _quizService.streamClassQuizzes(
            liveClass.id,
            type: 'practice',
            publishedOnly: true,
          ),
      builder: (context, quizSnapshot) {
        if (quizSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2.5),
          );
        }

        final allQuizzes = quizSnapshot.data ?? [];
        final publishedQuizzes = allQuizzes
            .where((q) => q.isPublished)
            .toList();

        if (publishedQuizzes.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.quiz_outlined,
                    size: 60,
                    color: _primaryNavy.withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Practice Quizzes Assigned',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Practice quizzes published by your teacher for this class will appear here so you can practice smarter.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: _textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        return StreamBuilder<List<QuizAssignmentModel>>(
          stream: _assignmentService.streamClassAssignments(liveClass.id),
          builder: (context, assignmentSnapshot) {
            final assignments = assignmentSnapshot.data ?? [];

            return StreamBuilder<List<QuizAttemptModel>>(
              stream: currentUserId.isNotEmpty
                  ? _assignmentService.streamStudentClassAttempts(
                      liveClass.id,
                      currentUserId,
                    )
                  : Stream.value(<QuizAttemptModel>[]),
              builder: (context, attemptSnapshot) {
                final attempts = attemptSnapshot.data ?? [];

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: publishedQuizzes.length,
                  itemBuilder: (context, index) {
                    final quiz = publishedQuizzes[index];

                    final assignment = assignments
                        .where((a) => a.quizId == quiz.id)
                        .firstOrNull;

                    final studentAttempts = attempts
                        .where((a) => a.quizId == quiz.id)
                        .toList();
                    final attemptCount = studentAttempts.length;
                    final attempt = studentAttempts.isNotEmpty
                        ? studentAttempts.first
                        : null;

                    final isClosed = assignment?.isClosed == true;
                    final isExpired = assignment?.isExpired == true;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: _surfaceWhite,
                        borderRadius: AppTheme.borderRadiusLg,
                        border: Border.all(color: _outlineVariant),
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: attemptCount > 0
                                        ? (attempt!.isPassed
                                              ? Colors.green.withValues(
                                                  alpha: 0.1,
                                                )
                                              : Colors.orange.withValues(
                                                  alpha: 0.1,
                                                ))
                                        : _primaryNavy.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    attemptCount > 0
                                        ? (attempt!.isPassed
                                              ? Icons.check_circle
                                              : Icons.refresh)
                                        : Icons.quiz_outlined,
                                    color: attemptCount > 0
                                        ? (attempt!.isPassed
                                              ? Colors.green
                                              : Colors.orange)
                                        : _primaryNavy,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        quiz.title,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: _textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${quiz.questionCount} Questions • ${quiz.totalPoints.toStringAsFixed(0)} Points',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: _textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (attemptCount >= 2) ...[
                                  _buildQuizStatusChip(
                                    label:
                                        'Score: ${attempt!.formattedScore} (${attempt.formattedPercentage})',
                                    color: attempt.isPassed
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                  _buildQuizStatusChip(
                                    label: 'Attempts: 2/2 (Max Reached)',
                                    color: Colors.redAccent,
                                  ),
                                ] else if (attemptCount == 1) ...[
                                  _buildQuizStatusChip(
                                    label:
                                        'Attempt 1: ${attempt!.formattedScore} (${attempt.formattedPercentage})',
                                    color: attempt.isPassed
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                  _buildQuizStatusChip(
                                    label: '1 Attempt Remaining',
                                    color: Colors.indigo,
                                  ),
                                ] else if (isClosed) ...[
                                  _buildQuizStatusChip(
                                    label: 'Submissions Closed',
                                    color: Colors.redAccent,
                                  ),
                                ] else if (isExpired) ...[
                                  _buildQuizStatusChip(
                                    label: 'Deadline Passed',
                                    color: Colors.redAccent,
                                  ),
                                ] else ...[
                                  _buildQuizStatusChip(
                                    label: 'Available (2 attempts max)',
                                    color: Colors.teal,
                                  ),
                                ],
                                if (assignment?.deadline != null)
                                  _buildQuizStatusChip(
                                    label:
                                        'Due: ${_formatDeadline(assignment!.deadline!)}',
                                    color: isExpired
                                        ? Colors.redAccent
                                        : Colors.indigo,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: (isClosed || isExpired) && attemptCount > 0
                                  ? OutlinedButton.icon(
                                      onPressed: () =>
                                          _showAttemptReview(attempt!, quiz),
                                      icon: const Icon(
                                        Icons.assessment_outlined,
                                      ),
                                      label: const Text(
                                        'Review Results & Feedback',
                                      ),
                                    )
                                  : (isClosed || isExpired)
                                  ? ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.grey[300],
                                        foregroundColor: Colors.grey[700],
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: AppTheme.borderRadiusMd,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                      ),
                                      onPressed: () {
                                        AppFeedback.warning(
                                          context,
                                          isClosed
                                              ? 'Your teacher has closed this quiz, so it no longer accepts submissions.'
                                              : 'The deadline has passed, so this quiz no longer accepts submissions.',
                                          title: 'Quiz unavailable',
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.lock_outline,
                                        size: 18,
                                      ),
                                      label: Text(
                                        isClosed
                                            ? 'Closed by Instructor'
                                            : 'Deadline Passed',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    )
                                  : attemptCount >= 2
                                  ? OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _primaryNavy,
                                        side: const BorderSide(
                                          color: _primaryNavy,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: AppTheme.borderRadiusMd,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                      ),
                                      onPressed: () =>
                                          _showAttemptReview(attempt!, quiz),
                                      icon: const Icon(
                                        Icons.assessment_outlined,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        'Review Results & Feedback (2/2 Used)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    )
                                  : attemptCount == 1
                                  ? Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: _primaryNavy,
                                              side: const BorderSide(
                                                color: _primaryNavy,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    AppTheme.borderRadiusMd,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 10,
                                                  ),
                                            ),
                                            onPressed: () => _showAttemptReview(
                                              attempt!,
                                              quiz,
                                            ),
                                            icon: const Icon(
                                              Icons.assessment_outlined,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              'Review #1',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: _primaryNavy,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    AppTheme.borderRadiusMd,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 10,
                                                  ),
                                            ),
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      AnswerQuizScreen(
                                                        quiz: quiz,
                                                        attemptNumber: 2,
                                                      ),
                                                ),
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.shuffle_rounded,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              'Retake #2',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _primaryNavy,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: AppTheme.borderRadiusMd,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                      ),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                AnswerQuizScreen(
                                                  quiz: quiz,
                                                  attemptNumber: 1,
                                                ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.play_arrow_rounded,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        'Start Practice Quiz',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  void _showAttemptReview(QuizAttemptModel attempt, QuizModel quiz) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: _surfaceWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quiz.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Score: ${attempt.formattedScore} • ${attempt.formattedPercentage}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: attempt.isPassed
                                ? Colors.green[800]
                                : Colors.orange[800],
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
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: attempt.breakdown.length,
                itemBuilder: (context, index) {
                  final item = attempt.breakdown[index];
                  final isCorrect = item['isCorrect'] == true;
                  final questionText =
                      item['question']?.toString() ?? 'Question ${index + 1}';
                  final userAns = item['userAnswer']?.toString() ?? '';
                  final correctAns = item['correctAnswer']?.toString() ?? '';
                  final earned = (item['earned'] as num?)?.toDouble() ?? 0.0;
                  final points = (item['points'] as num?)?.toDouble() ?? 1.0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isCorrect
                            ? Colors.green.withValues(alpha: 0.3)
                            : Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${index + 1}. ',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                questionText,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isCorrect
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${earned.toStringAsFixed(earned.truncateToDouble() == earned ? 0 : 1)}/${points.toStringAsFixed(0)} pt',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isCorrect
                                      ? Colors.green[800]
                                      : Colors.red[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your Answer: ${userAns.isNotEmpty ? userAns : "(no answer)"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isCorrect
                                ? Colors.green[800]
                                : Colors.red[800],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (!isCorrect) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Correct Answer: $correctAns',
                            style: const TextStyle(
                              fontSize: 12,
                              color: _primaryNavy,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuizStatusChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _formatDeadline(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, $hour:$minute $ampm';
  }

  // ── People & Class Info Tab View ───────────────────────────────
  Widget _buildPeopleTab(ClassModel liveClass) {
    return StreamBuilder<List<ClassMember>>(
      stream:
          widget.initialPeopleStream ??
          _classService.getClassMembersStream(liveClass.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2.5),
          );
        }

        final members = snapshot.data ?? [];
        final teachers = members.where((m) => m.role == 'teacher').toList();
        final classmates = members.where((m) => m.role == 'student').toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Teacher section
            const Text(
              'Instructor',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: _primaryNavy,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: _surfaceWhite,
                borderRadius: AppTheme.borderRadiusLg,
                border: Border.all(color: _outlineVariant),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: AppTheme.borderRadiusLg,
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _primaryNavy.withValues(alpha: 0.1),
                    child: const Icon(Icons.school, color: _primaryNavy),
                  ),
                  title: Text(
                    liveClass.teacherName.isNotEmpty
                        ? liveClass.teacherName
                        : (teachers.isNotEmpty
                              ? teachers.first.displayName
                              : 'Instructor'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  subtitle: const Text(
                    'Class Owner',
                    style: TextStyle(fontSize: 12, color: _textSecondary),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Classmates section
            Text(
              'Classmates (${classmates.length})',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: _primaryNavy,
              ),
            ),
            const SizedBox(height: 8),

            if (classmates.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surfaceWhite,
                  borderRadius: AppTheme.borderRadiusLg,
                  border: Border.all(color: _outlineVariant),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: const Text(
                  'You are the first student in this class!',
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
              )
            else
              ...classmates.map((student) {
                final initial = student.displayName.isNotEmpty
                    ? student.displayName[0].toUpperCase()
                    : 'S';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: _surfaceWhite,
                    borderRadius: AppTheme.borderRadiusLg,
                    border: Border.all(color: _outlineVariant),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: AppTheme.borderRadiusLg,
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _primaryNavy.withValues(alpha: 0.08),
                        child: Text(
                          initial,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _primaryNavy,
                          ),
                        ),
                      ),
                      title: Text(
                        student.displayName.isNotEmpty
                            ? student.displayName
                            : 'Student',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _textPrimary,
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
  }
}
