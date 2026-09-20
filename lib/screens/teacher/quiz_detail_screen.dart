import 'package:flutter/material.dart';
import '../../models/class_model.dart';
import '../../models/quiz_model.dart';
import '../../services/class_service.dart';
import '../../services/pdf_export_service.dart';
import '../../services/quiz_service.dart';
import '../../services/quiz_generation_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/studexa_background.dart';
import '../../widgets/app_feedback.dart';
import 'quiz_monitoring_screen.dart';
import 'manual_question_dialog.dart';

/// Screen allowing a teacher to review, edit, finalize, and publish a generated quiz.
class QuizDetailScreen extends StatefulWidget {
  final QuizModel quiz;
  final ClassModel? initialClass;
  final bool showShortfallPrompt;

  const QuizDetailScreen({
    super.key,
    required this.quiz,
    this.initialClass,
    this.showShortfallPrompt = false,
  });

  @override
  State<QuizDetailScreen> createState() => _QuizDetailScreenState();
}

class _QuizDetailScreenState extends State<QuizDetailScreen> {
  static const _primaryNavy = AppTheme.primaryNavy;
  static const _darkNavy = AppTheme.darkNavy;
  static const _surfaceWhite = AppTheme.surfaceWhite;
  static const _outlineVariant = AppTheme.outlineVariant;
  static const _textPrimary = AppTheme.textPrimary;
  static const _textSecondary = AppTheme.textSecondary;

  final QuizService _quizService = QuizService();
  final PdfExportService _pdfExportService = PdfExportService();
  final ClassService _classService = ClassService();

  late QuizModel _currentQuiz;
  bool _isSaving = false;
  String? _className;
  String? _teacherName;

  @override
  void initState() {
    super.initState();
    _currentQuiz = widget.quiz;
    if (widget.initialClass != null) {
      _className = widget.initialClass?.name;
      _teacherName = widget.initialClass?.teacherName;
    } else {
      _loadClassDetails();
    }
    if (widget.showShortfallPrompt && _currentQuiz.hasGenerationShortfall) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showShortfallDialog();
      });
    }
  }

  Future<void> _showShortfallDialog() async {
    if (!_currentQuiz.hasGenerationShortfall || !mounted) return;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quiz draft is ready'),
        content: Text(_currentQuiz.extraGenerationAttempted
            ? 'This draft has ${_currentQuiz.questionCount} of ${_currentQuiz.requestedQuestionCount} distinct questions. You can use these or add your own.'
            : 'Generated ${_currentQuiz.questionCount} of ${_currentQuiz.requestedQuestionCount} distinct questions. You can use this draft, add your own question, or try once more for different questions.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, 'use'), child: const Text('Use these questions')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, 'add'), child: const Text('Add my own')),
          if (!_currentQuiz.extraGenerationAttempted)
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, 'more'), child: const Text('Generate more')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'add') {
      await _addManualQuestion();
    }
    if (choice == 'more') {
      await _generateMore();
    }
  }

  Future<void> _generateMore() async {
    if (_isSaving || !_currentQuiz.hasGenerationShortfall ||
        _currentQuiz.extraGenerationAttempted) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      final updated = await _quizService.generateMore(_currentQuiz);
      if (!mounted) return;
      setState(() { _currentQuiz = updated; _isSaving = false; });
      if (_currentQuiz.hasGenerationShortfall) {
        await _showShortfallDialog();
      } else {
        AppFeedback.success(context, 'The draft now has ${updated.questionCount} distinct questions.', title: 'Quiz completed');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppFeedback.error(context, error is QuizGenerationException ? error.message :
          'Could not generate more questions. Your existing draft is safe; try again later.', title: 'More questions unavailable');
    }
  }

  Future<void> _addManualQuestion() async {
    if (_isSaving || !_currentQuiz.isDraft) return;
    final question = await showDialog<QuizQuestion>(
      context: context,
      builder: (_) => const ManualQuestionDialog(),
    );
    if (question == null || !mounted) return;
    final similar = _currentQuiz.questions.any((existing) {
      final overlap = QuizService.tokenJaccardSimilarity(question.question, existing.question);
      return overlap > 0.70 ||
          (overlap > 0.45 && question.correctAnswer.trim().toLowerCase() ==
              existing.correctAnswer.trim().toLowerCase());
    });
    if (similar) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Similar question found'),
          content: const Text('This looks like another question in the draft. Add it only if it tests a different fact or reasoning skill.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Review again')),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Add anyway')),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    setState(() => _isSaving = true);
    try {
      final updated = await _quizService.appendManualQuestion(_currentQuiz.id, question);
      if (!mounted) return;
      setState(() { _currentQuiz = updated; _isSaving = false; });
      AppFeedback.success(context, 'Your question was added to this private draft.', title: 'Question added');
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppFeedback.error(context, error is StateError ? error.message :
          'The question could not be saved. Check your connection and try again.', title: 'Question not added');
    }
  }

  Future<void> _loadClassDetails() async {
    if (widget.initialClass != null) return;
    if (_currentQuiz.classId.isNotEmpty) {
      final cls = await _classService.getClassById(_currentQuiz.classId);
      if (cls != null && mounted) {
        setState(() {
          _className = cls.name;
          _teacherName = cls.teacherName;
        });
      }
    }
  }

  Future<void> _publishQuiz() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: AppTheme.borderRadiusXl),
        title: const Text('Publish Practice Quiz?'),
        content: Text(
          'Enrolled students in this class will immediately see and be able to take "${_currentQuiz.title}".',
          style: const TextStyle(fontSize: 14, color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: AppTheme.borderRadiusMd,
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Publish Now'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    final publishValidationError = QuizService.validateQuizQuestions(
      _currentQuiz.questions,
    );
    if (publishValidationError != null) {
      AppFeedback.warning(
        context,
        publishValidationError,
        title: 'Quiz is not ready to publish',
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _quizService.publishQuiz(_currentQuiz.id, quiz: _currentQuiz);
      setState(() {
        _currentQuiz = _currentQuiz.copyWith(status: 'published');
        _isSaving = false;
      });
      if (!mounted) return;
      AppFeedback.success(
        context,
        'Students in this class can now find and take the practice quiz.',
        title: 'Quiz published',
      );
    } catch (e) {
      setState(() => _isSaving = false);
      if (!mounted) return;
      debugPrint('Failed to publish quiz: $e');
      AppFeedback.error(
        context,
        'The quiz could not be published. Check your connection and try again.',
        title: 'Unable to publish quiz',
      );
    }
  }

  Future<void> _finalizeQuiz() async {
    final finalizeValidationError = QuizService.validateQuizQuestions(
      _currentQuiz.questions,
    );
    if (finalizeValidationError != null) {
      AppFeedback.warning(
        context,
        finalizeValidationError,
        title: 'Quiz is not ready to finalize',
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _quizService.finalizeQuiz(_currentQuiz.id, quiz: _currentQuiz);
      setState(() {
        _currentQuiz = _currentQuiz.copyWith(status: 'finalized');
        _isSaving = false;
      });
      if (!mounted) return;
      AppFeedback.success(
        context,
        'The Actual Quiz is saved as the reference exam.',
        title: 'Quiz finalized',
      );
    } catch (e) {
      setState(() => _isSaving = false);
      if (!mounted) return;
      debugPrint('Failed to finalize quiz: $e');
      AppFeedback.error(
        context,
        'The quiz could not be finalized. Check your connection and try again.',
        title: 'Unable to finalize quiz',
      );
    }
  }

  Future<void> _editTitle() async {
    final titleController = TextEditingController(text: _currentQuiz.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: AppTheme.borderRadiusXl),
        title: const Text('Edit Quiz Title'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter quiz title...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: AppTheme.borderRadiusMd,
              ),
            ),
            onPressed: () => Navigator.pop(ctx, titleController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newTitle == null ||
        newTitle.isEmpty ||
        newTitle == _currentQuiz.title) {
      return;
    }

    final updated = _currentQuiz.copyWith(title: newTitle);
    setState(() => _currentQuiz = updated);
    await _quizService.updateQuiz(updated);
  }

  Future<void> _editQuestion(int index) async {
    final q = _currentQuiz.questions[index];
    final questionTextController = TextEditingController(text: q.question);
    final answerController = TextEditingController(text: q.correctAnswer);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: AppTheme.borderRadiusXl),
        title: Text('Edit Question ${index + 1} (${q.type.displayName})'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Question Prompt',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: questionTextController,
                maxLines: 3,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              const Text(
                'Correct Answer',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: answerController,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: AppTheme.borderRadiusMd,
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    final updatedQuestions = List<QuizQuestion>.from(_currentQuiz.questions);
    updatedQuestions[index] = q.copyWith(
      question: questionTextController.text.trim(),
      correctAnswer: answerController.text.trim(),
    );

    final updatedQuiz = _currentQuiz.copyWith(questions: updatedQuestions);
    setState(() => _currentQuiz = updatedQuiz);
    await _quizService.updateQuiz(updatedQuiz);
  }

  Future<void> _deleteQuiz() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: AppTheme.borderRadiusXl),
        title: const Text('Delete Quiz?'),
        content: const Text(
          'Are you sure you want to permanently delete this quiz? This action cannot be undone.',
          style: TextStyle(fontSize: 14, color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: AppTheme.borderRadiusMd,
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
    AppFeedback.info(
      context,
      'Removing "${_currentQuiz.title}" from this class.',
      title: 'Deleting quiz',
      duration: const Duration(seconds: 2),
    );

    try {
      await _quizService.deleteQuiz(_currentQuiz.id);
      if (!mounted) return;
      Navigator.pop(context);
      AppFeedback.success(
        context,
        '"${_currentQuiz.title}" was removed from the class.',
        title: 'Quiz deleted',
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('Failed to delete quiz: $e');
      AppFeedback.error(
        context,
        'The quiz could not be deleted. Check your connection and try again.',
        title: 'Unable to delete quiz',
      );
    }
  }

  Future<void> _exportOrPrintExam() async {
    bool includeKey = true;

    final shouldPrint = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: _surfaceWhite,
              shape: RoundedRectangleBorder(
                borderRadius: AppTheme.borderRadiusXl,
              ),
              title: const Row(
                children: [
                  Icon(Icons.print_outlined, color: _primaryNavy),
                  SizedBox(width: 8),
                  Text(
                    'Print Exam (PDF)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Generate a printable academic paper for "${_currentQuiz.title}" with student fill-in header, question formatting, and optional answer key.',
                    style: const TextStyle(fontSize: 13, color: _textSecondary),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: AppTheme.borderRadiusMd,
                      border: Border.all(color: _outlineVariant),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: AppTheme.borderRadiusMd,
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Include Teacher Answer Key',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'Appends a confidential rubric page at the end of the PDF for teacher scoring.',
                          style: TextStyle(fontSize: 11, color: _textSecondary),
                        ),
                        value: includeKey,
                        activeThumbColor: _primaryNavy,
                        onChanged: (val) {
                          setModalState(() => includeKey = val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryNavy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppTheme.borderRadiusMd,
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.picture_as_pdf, size: 16),
                  label: const Text('Generate & Print'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldPrint != true || !mounted) return;

    try {
      await _pdfExportService.printOrShareExam(
        context: context,
        quiz: _currentQuiz,
        includeAnswerKey: includeKey,
        className: _className,
        teacherName: _teacherName,
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('Failed to generate PDF: $e');
      AppFeedback.error(
        context,
        'The PDF could not be prepared. Please try again.',
        title: 'Unable to create PDF',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentQuiz.isActual ? 'Actual Quiz (Exam)' : 'Practice Quiz',
          style: const TextStyle(
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
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined, color: _primaryNavy),
            onPressed: _exportOrPrintExam,
            tooltip: 'Print / Export Exam PDF',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: _deleteQuiz,
            tooltip: 'Delete Quiz',
          ),
        ],
      ),
      body: StudexaBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTheme.maxContentWidthTablet,
              ),
              child: Column(
                children: [
                  // ── Header Banner ──────────────────────────────────
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _currentQuiz.title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.edit,
                                color: Colors.white70,
                                size: 20,
                              ),
                              onPressed: _editTitle,
                              tooltip: 'Edit Title',
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _buildBadge(
                              label: _currentQuiz.isActual
                                  ? 'Actual Quiz (Exam)'
                                  : 'Practice Quiz',
                              color: _currentQuiz.isActual
                                  ? Colors.purpleAccent
                                  : Colors.blueAccent,
                            ),
                            _buildBadge(
                              label: _currentQuiz.formattedStatus,
                              color: _currentQuiz.isPublished
                                  ? Colors.greenAccent
                                  : (_currentQuiz.isFinalized
                                        ? Colors.tealAccent
                                        : Colors.amberAccent),
                            ),
                            _buildBadge(
                              label: _currentQuiz.isGeminiGenerated
                                  ? 'AI Generated'
                                  : (_currentQuiz.isFallbackGenerated
                                        ? 'Auto Generated'
                                        : 'Manual'),
                              color: Colors.orangeAccent,
                            ),
                            _buildBadge(
                              label: '${_currentQuiz.questionCount} Questions',
                              color: Colors.white70,
                            ),
                            _buildBadge(
                              label:
                                  '${_currentQuiz.totalPoints.toStringAsFixed(0)} Pts',
                              color: Colors.white70,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ── Action Bar (Publish / Finalize / Monitor) ────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        if (_currentQuiz.isDraft && _currentQuiz.isPractice)
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[700],
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppTheme.borderRadiusMd,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              onPressed: _isSaving ? null : _publishQuiz,
                              icon: const Icon(Icons.send_rounded, size: 18),
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Publish to Class'),
                              ),
                            ),
                          ),
                        if (_currentQuiz.isPublished && _currentQuiz.isPractice)
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryNavy,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppTheme.borderRadiusMd,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => QuizMonitoringScreen(
                                      quiz: _currentQuiz,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.analytics_outlined,
                                size: 18,
                              ),
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Monitor Submissions'),
                              ),
                            ),
                          ),
                        if (_currentQuiz.isDraft && _currentQuiz.isActual)
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryNavy,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppTheme.borderRadiusMd,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              onPressed: _isSaving ? null : _finalizeQuiz,
                              icon: const Icon(
                                Icons.check_circle_outline,
                                size: 18,
                              ),
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Finalize Reference Exam'),
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _primaryNavy,
                            side: const BorderSide(color: _primaryNavy),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppTheme.borderRadiusMd,
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 14,
                            ),
                          ),
                          onPressed: _exportOrPrintExam,
                          icon: const Icon(Icons.print_outlined, size: 18),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Print Exam'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  if (_currentQuiz.isDraft)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isSaving ? null : _addManualQuestion,
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Add Your Question'),
                        ),
                      ),
                    ),

                  if (_currentQuiz.hasGenerationShortfall && !_currentQuiz.extraGenerationAttempted)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextButton.icon(
                        onPressed: _isSaving ? null : _generateMore,
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: Text('Generate more (${_currentQuiz.questionCount}/${_currentQuiz.requestedQuestionCount})'),
                      ),
                    ),

                  // ── Questions List ─────────────────────────────────
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: _currentQuiz.questions.length,
                      itemBuilder: (context, index) {
                        final q = _currentQuiz.questions[index];
                        return _buildQuestionCard(q, index);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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

  Widget _buildQuestionCard(QuizQuestion q, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceWhite,
        borderRadius: AppTheme.borderRadiusLg,
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.6)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Index, Type Chip, Edit Action
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _primaryNavy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Q${index + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _primaryNavy,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    q.type.displayName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.indigo[800],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${q.points.toStringAsFixed(0)} pt',
                style: const TextStyle(fontSize: 12, color: _textSecondary),
              ),
              const SizedBox(width: 6),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: _primaryNavy,
                ),
                onPressed: () => _editQuestion(index),
                tooltip: 'Edit Question',
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Question Prompt
          Text(
            q.question,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),

          // Options or Answer Key
          if (q.type == QuizQuestionType.multipleChoice)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: q.options.map((opt) {
                final isCorrect = opt == q.correctAnswer;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isCorrect
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: AppTheme.borderRadiusSm,
                    border: Border.all(
                      color: isCorrect
                          ? Colors.green
                          : _outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isCorrect
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: isCorrect ? Colors.green : _textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          opt,
                          style: TextStyle(
                            fontSize: 13,
                            color: isCorrect ? Colors.green[900] : _textPrimary,
                            fontWeight: isCorrect
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            )
          else if (q.type == QuizQuestionType.trueFalse)
            Row(
              children: ['True', 'False'].map((opt) {
                final isCorrect =
                    opt.toLowerCase() == q.correctAnswer.toLowerCase();
                return Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isCorrect
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: AppTheme.borderRadiusSm,
                    border: Border.all(
                      color: isCorrect ? Colors.green : _outlineVariant,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isCorrect
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: isCorrect ? Colors.green : _textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        opt,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isCorrect
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isCorrect ? Colors.green[900] : _textPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            )
          else if (q.type == QuizQuestionType.enumeration)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.05),
                borderRadius: AppTheme.borderRadiusSm,
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Expected Items (Order-independent):',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: q.enumerationAnswers.map((item) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Text(
                          item,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _textPrimary,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: AppTheme.borderRadiusSm,
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.key, size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Answer: ${q.correctAnswer}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.green[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Explanation note
          if (q.explanation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Context: ${q.explanation}',
              style: const TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: _textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
