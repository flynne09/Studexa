import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/quiz_attempt_model.dart';
import '../../models/quiz_model.dart';
import '../../services/assignment_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_feedback.dart';
import '../../widgets/studexa_background.dart';
import '../../utils/scoring_utils.dart';
import 'student_home_screen.dart';

/// Active quiz screen supporting all 5 Phase 1 question types:
/// 1. Multiple Choice
/// 2. True/False
/// 3. Fill-in-the-Blank
/// 4. Identification
/// 5. Enumeration
/// Evaluates answers deterministically using [ScoringUtils].
class AnswerQuizScreen extends StatefulWidget {
  final QuizModel? quiz;
  final String quizTitle;
  final int attemptNumber;
  final Random? random;
  final AssignmentService? assignmentService;
  final Map<String, dynamic>? initialAnswers;

  const AnswerQuizScreen({
    super.key,
    this.quiz,
    this.quizTitle = 'Cellular Respiration & ATP Synthesis',
    this.attemptNumber = 1,
    this.random,
    this.assignmentService,
    this.initialAnswers,
  });

  @override
  State<AnswerQuizScreen> createState() => _AnswerQuizScreenState();
}

class _AnswerQuizScreenState extends State<AnswerQuizScreen> {
  late final AssignmentService _assignmentService;
  // ── Design tokens ───────────────────────────────────────────
  static const _primaryNavy = AppTheme.primaryNavy;
  static const _surfaceWhite = AppTheme.surfaceWhite;
  static const _outlineVariant = AppTheme.outlineVariant;
  static const _textPrimary = AppTheme.textPrimary;
  static const _textSecondary = AppTheme.textSecondary;

  int _currentIndex = 0;
  bool _isSubmitting = false;
  bool _submitted = false;
  final Set<String> _flaggedQuestionIds = {};
  final Map<String, dynamic> _userAnswers = {};
  final Set<String> _pendingSkippedQuestionIds = {};

  final TextEditingController _textAnswerController = TextEditingController();
  final TextEditingController _enumInputController = TextEditingController();

  late List<QuizQuestion> _questions;
  late List<QuizQuestion> _questionQueue;

  QuizQuestion get _currentQuestion => _questionQueue.isNotEmpty
      ? _questionQueue[_currentIndex]
      : (_questions.isNotEmpty
            ? _questions.first
            : const QuizQuestion(
                id: '',
                type: QuizQuestionType.multipleChoice,
                question: '',
                points: 0,
              ));

  bool _isQuestionAnswered(QuizQuestion q) {
    final ans = _userAnswers[q.id];
    if (ans == null) return false;
    if (ans is String) return ans.trim().isNotEmpty;
    if (ans is List) return ans.isNotEmpty;
    return false;
  }

  bool get _allQuestionsAnswered => _questions.every(_isQuestionAnswered);
  int get _answeredCount => _questions.where(_isQuestionAnswered).length;
  bool get _hasSkippedPending => _pendingSkippedQuestionIds.any(
    (id) => !_isQuestionAnswered(
      _questions.firstWhere((q) => q.id == id, orElse: () => _currentQuestion),
    ),
  );

  String get _quizId =>
      (widget.quiz?.id.isNotEmpty == true) ? widget.quiz!.id : widget.quizTitle;

  String get _studentId {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? 'guest_student';
    } catch (_) {
      return 'guest_student';
    }
  }

  List<String> _getEnumerationAnswers(String questionId) {
    final raw = _userAnswers[questionId];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return [];
  }

  void _persistDraftAnswers() {
    if (_submitted || _isSubmitting) return;
    _assignmentService
        .saveDraftAnswers(
          studentId: _studentId,
          quizId: _quizId,
          attemptNumber: widget.attemptNumber,
          answers: Map<String, dynamic>.from(_userAnswers),
        )
        .catchError((_) {});
  }

  Future<void> _loadDraftAnswersFromService() async {
    try {
      final drafts = await _assignmentService.getDraftAnswers(
        studentId: _studentId,
        quizId: _quizId,
        attemptNumber: widget.attemptNumber,
      );
      if (drafts != null && mounted && !_submitted && !_isSubmitting) {
        setState(() {
          for (final entry in drafts.entries) {
            _userAnswers.putIfAbsent(entry.key, () => entry.value);
          }
          _loadCurrentAnswer();
        });
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _assignmentService = widget.assignmentService ?? AssignmentService();

    if (widget.initialAnswers != null) {
      _userAnswers.addAll(widget.initialAnswers!);
    }

    if (widget.attemptNumber >= 3) {
      _questions = const [];
      _questionQueue = [];
      return;
    }

    if (widget.quiz != null) {
      _questions = List<QuizQuestion>.from(widget.quiz!.questions);
    } else {
      // Default fallback demo questions across all 5 types
      _questions = const [
        QuizQuestion(
          id: 'q_demo_1',
          type: QuizQuestionType.multipleChoice,
          question:
              'Which cellular organelle is primarily responsible for generating ATP through oxidative phosphorylation?',
          options: [
            'A. Nucleus',
            'B. Mitochondria',
            'C. Golgi Apparatus',
            'D. Endoplasmic Reticulum',
          ],
          correctAnswer: 'B. Mitochondria',
          points: 1.0,
        ),
        QuizQuestion(
          id: 'q_demo_2',
          type: QuizQuestionType.trueFalse,
          question:
              'Glycolysis requires molecular oxygen to proceed and takes place entirely within the mitochondrial matrix.',
          options: ['True', 'False'],
          correctAnswer: 'False',
          points: 1.0,
        ),
        QuizQuestion(
          id: 'q_demo_3',
          type: QuizQuestionType.fillInTheBlank,
          question:
              'The metabolic pathway that breaks down glucose into pyruvate and produces a net gain of 2 ATP molecules is called _______.',
          correctAnswer: 'Glycolysis',
          points: 1.0,
        ),
        QuizQuestion(
          id: 'q_demo_4',
          type: QuizQuestionType.identification,
          question:
              'Identify the enzyme that catalyzes the synthesis of ATP from ADP and inorganic phosphate during chemiosmosis.',
          correctAnswer: 'ATP Synthase',
          points: 1.0,
        ),
        QuizQuestion(
          id: 'q_demo_5',
          type: QuizQuestionType.enumeration,
          question:
              'Enumerate the three primary stages of eukaryotic cellular respiration:',
          enumerationAnswers: [
            'Glycolysis',
            'Krebs Cycle',
            'Electron Transport Chain',
          ],
          points: 3.0,
        ),
      ];
    }

    // On Attempt 2: shuffle question presentation order
    if (widget.attemptNumber == 2 && _questions.length > 1) {
      final originalIds = _questions.map((q) => q.id).toList();
      final rnd = widget.random ?? Random();
      _questions = List<QuizQuestion>.from(_questions)..shuffle(rnd);

      // Ensure that shuffled order differs from original
      final newIds = _questions.map((q) => q.id).toList();
      bool isIdentical = true;
      for (int i = 0; i < originalIds.length; i++) {
        if (originalIds[i] != newIds[i]) {
          isIdentical = false;
          break;
        }
      }
      if (isIdentical) {
        _questions = [..._questions.sublist(1), _questions.first];
      }
    }

    _questionQueue = List<QuizQuestion>.from(_questions);
    _loadCurrentAnswer();
    _loadDraftAnswersFromService();
  }

  @override
  void dispose() {
    _saveCurrentAnswer();
    _persistDraftAnswers();
    _textAnswerController.dispose();
    _enumInputController.dispose();
    super.dispose();
  }

  void _loadCurrentAnswer() {
    final q = _currentQuestion;
    final currentAnswer = _userAnswers[q.id];

    if (q.type == QuizQuestionType.fillInTheBlank ||
        q.type == QuizQuestionType.identification) {
      _textAnswerController.text = (currentAnswer is String)
          ? currentAnswer
          : '';
    } else {
      _textAnswerController.clear();
    }
    _enumInputController.clear();
  }

  void _saveCurrentAnswer() {
    final q = _currentQuestion;
    if (q.type == QuizQuestionType.fillInTheBlank ||
        q.type == QuizQuestionType.identification) {
      final text = _textAnswerController.text.trim();
      if (text.isNotEmpty) {
        _userAnswers[q.id] = text;
        _pendingSkippedQuestionIds.remove(q.id);
      } else {
        _userAnswers.remove(q.id);
      }
    } else if (q.type == QuizQuestionType.enumeration) {
      final pendingEnum = _enumInputController.text.trim();
      if (pendingEnum.isNotEmpty) {
        final currentList = _getEnumerationAnswers(q.id);
        final parts = pendingEnum
            .split(RegExp(r'[\n,]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        bool addedAny = false;
        for (final part in parts) {
          final normText = part.toLowerCase();
          final alreadyExists = currentList.any(
            (item) => item.trim().toLowerCase() == normText,
          );
          if (!alreadyExists) {
            currentList.add(part);
            addedAny = true;
          }
        }
        if (addedAny) {
          _userAnswers[q.id] = currentList;
          _pendingSkippedQuestionIds.remove(q.id);
          _enumInputController.clear();
        }
      }
    }
    _persistDraftAnswers();
  }

  void _skipCurrentQuestion() {
    _saveCurrentAnswer();
    final currentQ = _currentQuestion;

    // Skip does NOT count as answered
    _userAnswers.remove(currentQ.id);
    _pendingSkippedQuestionIds.add(currentQ.id);
    _persistDraftAnswers();

    // Requeue: remove from current position and append to end
    final skipped = _questionQueue.removeAt(_currentIndex);
    _questionQueue.add(skipped);

    if (_currentIndex >= _questionQueue.length) {
      _currentIndex = 0;
    }

    setState(() {
      _loadCurrentAnswer();
    });

    AppFeedback.info(
      context,
      'You can answer it after the remaining questions.',
      title: 'Question moved to the end',
      compact: true,
      duration: const Duration(milliseconds: 1500),
    );
  }

  void _goToNext() {
    _saveCurrentAnswer();

    // Check if on the last question of the queue
    if (_currentIndex >= _questionQueue.length - 1) {
      if (_allQuestionsAnswered) {
        _showSubmitConfirmation();
        return;
      } else {
        // Route straight into the first pending unanswered question!
        final firstUnanswered = _questionQueue.indexWhere(
          (q) => !_isQuestionAnswered(q),
        );
        if (firstUnanswered != -1) {
          setState(() {
            _currentIndex = firstUnanswered;
            _loadCurrentAnswer();
          });
          AppFeedback.info(
            context,
            'Returning to unanswered question ($_answeredCount of ${_questions.length} answered).',
            title: 'Answer needed',
            compact: true,
            duration: const Duration(milliseconds: 1800),
          );
          return;
        }
      }
    }

    // Normal advance in queue
    setState(() {
      _currentIndex++;
      _loadCurrentAnswer();
    });
  }

  void _goToPrevious() {
    _saveCurrentAnswer();
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _loadCurrentAnswer();
      });
    }
  }

  void _jumpToQuestion(QuizQuestion targetQ) {
    _saveCurrentAnswer();
    final targetIndex = _questionQueue.indexWhere((q) => q.id == targetQ.id);
    if (targetIndex != -1) {
      setState(() {
        _currentIndex = targetIndex;
        _loadCurrentAnswer();
      });
    }
  }

  void _toggleFlag() {
    setState(() {
      final id = _currentQuestion.id;
      if (_flaggedQuestionIds.contains(id)) {
        _flaggedQuestionIds.remove(id);
      } else {
        _flaggedQuestionIds.add(id);
      }
    });
  }

  void _addEnumerationItem() {
    final text = _enumInputController.text.trim();
    if (text.isEmpty) return;

    final currentList = _getEnumerationAnswers(_currentQuestion.id);
    final parts = text
        .split(RegExp(r'[\n,]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    bool addedAny = false;
    for (final part in parts) {
      final normText = part.toLowerCase();
      final alreadyExists = currentList.any(
        (item) => item.trim().toLowerCase() == normText,
      );
      if (!alreadyExists) {
        currentList.add(part);
        addedAny = true;
      }
    }

    if (addedAny) {
      setState(() {
        _userAnswers[_currentQuestion.id] = currentList;
        _pendingSkippedQuestionIds.remove(_currentQuestion.id);
        _enumInputController.clear();
      });
      _persistDraftAnswers();
    } else {
      _enumInputController.clear();
    }
  }

  void _removeEnumerationItem(String item) {
    final currentList = _getEnumerationAnswers(_currentQuestion.id);
    currentList.remove(item);
    setState(() {
      if (currentList.isEmpty) {
        _userAnswers.remove(_currentQuestion.id);
      } else {
        _userAnswers[_currentQuestion.id] = currentList;
      }
    });
    _persistDraftAnswers();
  }

  void _showSubmitConfirmation() {
    if (_isSubmitting || _submitted) return;
    _saveCurrentAnswer();

    if (!_allQuestionsAnswered) {
      AppFeedback.warning(
        context,
        'You answered $_answeredCount of ${_questions.length} questions. Complete every answer before submitting.',
        title: 'Quiz is not complete',
      );
      return;
    }

    final totalCount = _questions.length;
    final flaggedCount = _flaggedQuestionIds.length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        ),
        title: const Text(
          'Submit Practice Quiz?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Answered all $totalCount questions.',
              style: const TextStyle(fontSize: 14, color: _textPrimary),
            ),
            if (flaggedCount > 0) ...[
              const SizedBox(height: 6),
              Text(
                '$flaggedCount question(s) currently flagged for review.',
                style: const TextStyle(fontSize: 13, color: Colors.orange),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Once submitted, your responses will be evaluated deterministically according to Phase 1 scoring standards.',
              style: TextStyle(fontSize: 13, color: _textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Review Answers',
              style: TextStyle(color: _textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx); // close confirm dialog
              _evaluateAndShowResults();
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _evaluateAndShowResults() async {
    if (_isSubmitting || _submitted) return;
    setState(() => _isSubmitting = true);
    double totalEarned = 0.0;
    double totalPossible = 0.0;
    final List<Map<String, dynamic>> questionBreakdown = [];

    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final userAns = _userAnswers[q.id];
      totalPossible += q.points;

      double earned = 0.0;
      bool isCorrect = false;
      dynamic details;

      switch (q.type) {
        case QuizQuestionType.multipleChoice:
        case QuizQuestionType.trueFalse:
          final cleanUser = (userAns?.toString() ?? '').trim().toLowerCase();
          final cleanExpected = q.correctAnswer.trim().toLowerCase();
          isCorrect = cleanUser == cleanExpected;
          earned = isCorrect ? q.points : 0.0;
          break;

        case QuizQuestionType.fillInTheBlank:
        case QuizQuestionType.identification:
          final userText = (userAns?.toString() ?? '').trim();
          isCorrect = ScoringUtils.isFreeTextMatch(userText, q.correctAnswer);
          earned = isCorrect ? q.points : 0.0;
          break;

        case QuizQuestionType.enumeration:
          final studentItems = (userAns is List)
              ? userAns.map((e) => e.toString()).toList()
              : <String>[];
          final expectedList = q.enumerationAnswers.isNotEmpty
              ? q.enumerationAnswers
              : q.correctAnswer
                    .split(RegExp(r'[\n,]'))
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
          final enumResult = ScoringUtils.scoreEnumeration(
            studentItems: studentItems,
            expectedItems: expectedList,
            totalPoints: q.points,
          );
          earned = enumResult.earnedPoints;
          isCorrect = enumResult.isFullyCorrect;
          details = enumResult;
          break;
      }

      totalEarned += earned;
      questionBreakdown.add({
        'question': q,
        'userAnswer': userAns,
        'earned': earned,
        'isCorrect': isCorrect,
        'details': details,
      });
    }

    final percentage = totalPossible > 0
        ? (totalEarned / totalPossible * 100)
        : 0.0;

    // A displayed result must correspond to an acknowledged saved attempt.
    final user = FirebaseAuth.instance.currentUser;
    if (widget.quiz != null &&
        user == null &&
        _assignmentService.useFirestore) {
      setState(() => _isSubmitting = false);
      AppFeedback.error(
        context,
        'Sign in again before submitting. Your answers have been kept on this device.',
        title: 'Session expired',
      );
      return;
    }
    if (widget.quiz != null) {
      final attempt = QuizAttemptModel(
        id: '${_studentId}_${widget.quiz!.id}_attempt_${widget.attemptNumber}',
        quizId: widget.quiz!.id,
        classId: widget.quiz!.classId,
        studentId: _studentId,
        studentName:
            user?.displayName ?? (user?.email?.split('@').first ?? 'Student'),
        answers: {
          for (int i = 0; i < _questions.length; i++)
            'q_$i': _userAnswers[_questions[i].id],
          for (final q in _questions) q.id: _userAnswers[q.id],
        },
        score: totalEarned,
        totalPoints: totalPossible,
        percentage: percentage,
        submittedAt: DateTime.now(),
        breakdown: questionBreakdown.map((item) {
          final q = item['question'] as QuizQuestion;
          return {
            'questionId': q.id,
            'question': q.question,
            'userAnswer': item['userAnswer']?.toString() ?? '',
            'correctAnswer': q.correctAnswer.isNotEmpty
                ? q.correctAnswer
                : q.enumerationAnswers.join(', '),
            'earned': item['earned'],
            'points': q.points,
            'isCorrect': item['isCorrect'],
          };
        }).toList(),
      );

      try {
        await _assignmentService.submitAttempt(attempt);
      } catch (error) {
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        _persistDraftAnswers();
        final message = error is QuizUnavailableException
            ? error.message
            : error is TimeoutException
            ? 'Saving took too long. Check your connection and history before trying again.'
            : 'Could not save your result. Check your Internet connection and try again.';
        AppFeedback.error(
          context,
          '$message Your answers have been kept. They remain on this device.',
          title: 'Result not saved',
        );
        return;
      }
    }

    _submitted = true;
    await _assignmentService
        .clearDraftAnswers(
          studentId: _studentId,
          quizId: _quizId,
          attemptNumber: widget.attemptNumber,
        )
        .catchError((_) {});
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        ),
        title: Row(
          children: [
            Icon(
              percentage >= 75 ? Icons.emoji_events : Icons.check_circle,
              color: percentage >= 75 ? Colors.amber[800] : _primaryNavy,
              size: 28,
            ),
            const SizedBox(width: 10),
            const Text(
              'Quiz Results',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Score Summary Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_primaryNavy, Color(0xFF000666)],
                    ),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your Score',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${totalEarned.toStringAsFixed(1)} / ${totalPossible.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${percentage.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Question Review',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                // Question breakdown
                ...List.generate(questionBreakdown.length, (idx) {
                  final item = questionBreakdown[idx];
                  final q = item['question'] as QuizQuestion;
                  final earned = item['earned'] as double;
                  final isCor = item['isCorrect'] as bool;
                  final details = item['details'];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isCor
                          ? Colors.green.withValues(alpha: 0.05)
                          : (earned > 0
                                ? Colors.orange.withValues(alpha: 0.05)
                                : Colors.red.withValues(alpha: 0.05)),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(
                        color: isCor
                            ? Colors.green.withValues(alpha: 0.4)
                            : (earned > 0
                                  ? Colors.orange.withValues(alpha: 0.4)
                                  : Colors.red.withValues(alpha: 0.4)),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Q${idx + 1} (${q.type.displayName})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${earned.toStringAsFixed(1)} / ${q.points.toStringAsFixed(0)} pt',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isCor
                                    ? Colors.green[800]
                                    : Colors.red[800],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          q.question,
                          style: const TextStyle(fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),

                        if (details is EnumerationResult) ...[
                          Text(
                            'Found: ${details.found.isEmpty ? "None" : details.found.join(", ")}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.green,
                            ),
                          ),
                          if (details.missing.isNotEmpty)
                            Text(
                              'Missing: ${details.missing.join(", ")}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.red,
                              ),
                            ),
                          if (details.extra.isNotEmpty)
                            Text(
                              'Extra / Not Counted: ${details.extra.join(", ")}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.blue,
                              ),
                            ),
                        ] else ...[
                          Text(
                            'Expected: ${q.correctAnswer}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green[800],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: _textSecondary,
              side: const BorderSide(color: _outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.home, size: 18),
            label: const Text('Home'),
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const StudentHomeScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.quiz?.title ?? widget.quizTitle;

    if (widget.attemptNumber >= 3) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
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
        body: StudexaBackground(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppTheme.maxContentWidthMobile,
                ),
                child: Card(
                  elevation: 0,
                  color: _surfaceWhite,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    side: const BorderSide(color: _outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.block_rounded,
                            size: 56,
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Maximum Attempts Reached',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'You have reached the maximum 2 attempts for this practice quiz. Further attempts are not permitted.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: _textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryNavy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusMd,
                              ),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('Return to Class'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final currentQ = _currentQuestion;
    final isFlagged = _flaggedQuestionIds.contains(currentQ.id);
    final isLastQueueItem = _currentIndex == _questionQueue.length - 1;
    final hasSkippedPending = _hasSkippedPending;
    final isSubmitState = isLastQueueItem && !hasSkippedPending;
    final canSubmit =
        !_isSubmitting &&
        !_submitted &&
        (_allQuestionsAnswered ||
            (_currentQuestion.type == QuizQuestionType.enumeration &&
                _enumInputController.text.trim().isNotEmpty &&
                _questions
                    .where((q) => q.id != _currentQuestion.id)
                    .every(_isQuestionAnswered)));
    final progress = _questions.isEmpty
        ? 0.0
        : (_answeredCount / _questions.length);

    return PopScope(
      canPop: !_isSubmitting,
      onPopInvokedWithResult: (didPop, result) {
        _saveCurrentAnswer();
        _persistDraftAnswers();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _textPrimary,
            ),
          ),
          backgroundColor: _surfaceWhite,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: _primaryNavy),
            onPressed: _isSubmitting
                ? null
                : () {
                    _saveCurrentAnswer();
                    _persistDraftAnswers();
                    Navigator.pop(context);
                  },
          ),
        ),
        body: _isSubmitting
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Saving your result...'),
                  ],
                ),
              )
            : StudexaBackground(
                child: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppTheme.maxContentWidthTablet,
                      ),
                      child: Column(
                        children: [
                          // ── Top Progress Indicator ─────────────────────
                          LinearProgressIndicator(
                            value: progress,
                            backgroundColor: _outlineVariant.withValues(
                              alpha: 0.3,
                            ),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              _primaryNavy,
                            ),
                            minHeight: 4,
                          ),

                          // ── Question Navigation & Status Strip ────────
                          _buildQuestionNavigationStrip(),

                          // ── Question Content Area ──────────────────────
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Question-type badge & progress counter
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _primaryNavy.withValues(
                                              alpha: 0.08,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            currentQ.type.displayName,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: _primaryNavy,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            'Question ${_currentIndex + 1} of ${_questions.length}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: _textSecondary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),

                                  // Question Prompt
                                  Text(
                                    currentQ.question,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: _textPrimary,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // "Flag for review" toggle button
                                  InkWell(
                                    onTap: _toggleFlag,
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6,
                                        horizontal: 4,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isFlagged
                                                ? Icons.flag
                                                : Icons.flag_outlined,
                                            size: 18,
                                            color: isFlagged
                                                ? Colors.amber[800]
                                                : _textSecondary,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            isFlagged
                                                ? 'Flagged for review'
                                                : 'Flag for review',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: isFlagged
                                                  ? Colors.amber[900]
                                                  : _textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),

                                  // ── Interactive Answer Inputs ──────────────────
                                  if (currentQ.type ==
                                          QuizQuestionType.multipleChoice ||
                                      currentQ.type ==
                                          QuizQuestionType.trueFalse)
                                    _buildChoiceOptions(currentQ.options)
                                  else if (currentQ.type ==
                                          QuizQuestionType.fillInTheBlank ||
                                      currentQ.type ==
                                          QuizQuestionType.identification)
                                    _buildTextInput(
                                      currentQ.type ==
                                              QuizQuestionType.fillInTheBlank
                                          ? 'Enter missing word or term...'
                                          : 'Enter identified concept...',
                                    )
                                  else if (currentQ.type ==
                                      QuizQuestionType.enumeration)
                                    _buildEnumerationInput(),
                                ],
                              ),
                            ),
                          ),

                          // ── Bottom Navigation Controls ─────────────────
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: _surfaceWhite,
                              border: const Border(
                                top: BorderSide(color: _outlineVariant),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, -2),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    if (_currentIndex > 0) ...[
                                      OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: _textPrimary,
                                          side: const BorderSide(
                                            color: _outlineVariant,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              AppTheme.radiusMd,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                        ),
                                        onPressed: _goToPrevious,
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.arrow_back, size: 16),
                                            SizedBox(width: 4),
                                            Text('Previous'),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.orange.shade800,
                                        side: BorderSide(
                                          color: Colors.orange.shade400,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            AppTheme.radiusMd,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 12,
                                        ),
                                      ),
                                      onPressed: _skipCurrentQuestion,
                                      icon: const Icon(
                                        Icons.skip_next,
                                        size: 18,
                                      ),
                                      label: const Text('Skip'),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _primaryNavy,
                                          foregroundColor: Colors.white,
                                          disabledBackgroundColor: _primaryNavy
                                              .withValues(alpha: 0.35),
                                          disabledForegroundColor:
                                              Colors.white70,
                                          elevation: 1,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              AppTheme.radiusMd,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                        ),
                                        onPressed: isSubmitState
                                            ? (canSubmit
                                                  ? _showSubmitConfirmation
                                                  : null)
                                            : _goToNext,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Flexible(
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  isSubmitState
                                                      ? 'Submit Quiz'
                                                      : 'Next Question',
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Icon(
                                              isSubmitState
                                                  ? Icons.check
                                                  : Icons.arrow_forward,
                                              size: 18,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (isSubmitState && !canSubmit) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Answer all questions to enable submission ($_answeredCount of ${_questions.length} completed)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange.shade800,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildChoiceOptions(List<String> options) {
    final selectedOption = _userAnswers[_currentQuestion.id];

    return Column(
      children: options.map((option) {
        final isSelected = selectedOption == option;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () {
              setState(() {
                _userAnswers[_currentQuestion.id] = option;
                _pendingSkippedQuestionIds.remove(_currentQuestion.id);
              });
              _persistDraftAnswers();
            },
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? _primaryNavy.withValues(alpha: 0.08)
                    : _surfaceWhite,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                  color: isSelected ? _primaryNavy : _outlineVariant,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? _primaryNavy : _outlineVariant,
                        width: 2,
                      ),
                      color: isSelected ? _primaryNavy : Colors.transparent,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      option,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected ? _primaryNavy : _textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextInput(String hint) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: _outlineVariant),
      ),
      child: TextField(
        controller: _textAnswerController,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _textSecondary, fontSize: 14),
          border: InputBorder.none,
        ),
        onChanged: (val) {
          setState(() {
            _userAnswers[_currentQuestion.id] = val.trim();
            if (val.trim().isNotEmpty) {
              _pendingSkippedQuestionIds.remove(_currentQuestion.id);
            }
          });
          _persistDraftAnswers();
        },
      ),
    );
  }

  Widget _buildEnumerationInput() {
    final currentList = _getEnumerationAnswers(_currentQuestion.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: _surfaceWhite,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(color: _outlineVariant),
                ),
                child: TextField(
                  controller: _enumInputController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Type item and tap Add...',
                    hintStyle: TextStyle(fontSize: 13, color: _textSecondary),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _addEnumerationItem(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
              ),
              onPressed: _addEnumerationItem,
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (currentList.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No items added yet. Enter items in any order.',
              style: TextStyle(fontSize: 13, color: _textSecondary),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: currentList.map((item) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _surfaceWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _primaryNavy.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _primaryNavy,
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => _removeEnumerationItem(item),
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        if (currentList.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 15,
                color: Colors.green[700],
              ),
              const SizedBox(width: 5),
              Text(
                '${currentList.length} item${currentList.length == 1 ? "" : "s"} added — partial credit enabled',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green[800],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildQuestionNavigationStrip() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: _surfaceWhite,
        border: Border(bottom: BorderSide(color: _outlineVariant, width: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2E7D32),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$_answeredCount answered',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF767683),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_questions.length - _answeredCount} unanswered',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF767683),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: _showQuestionGridModal,
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.grid_view, size: 14, color: _primaryNavy),
                      SizedBox(width: 4),
                      Text(
                        'Grid View',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _primaryNavy,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _questions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final q = _questions[idx];
                final isCurrent = q.id == _currentQuestion.id;
                final isAnswered = _isQuestionAnswered(q);
                final isFlagged = _flaggedQuestionIds.contains(q.id);

                return _buildQuestionBadge(
                  number: idx + 1,
                  isCurrent: isCurrent,
                  isAnswered: isAnswered,
                  isFlagged: isFlagged,
                  onTap: () => _jumpToQuestion(q),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionBadge({
    required int number,
    required bool isCurrent,
    required bool isAnswered,
    required bool isFlagged,
    required VoidCallback onTap,
  }) {
    final Color bgColor;
    final Color borderColor;
    final Color textColor;

    if (isAnswered) {
      bgColor = const Color(0xFFE8F5E9);
      borderColor = isCurrent ? _primaryNavy : const Color(0xFF81C784);
      textColor = const Color(0xFF1B5E20);
    } else {
      bgColor = const Color(0xFFF1F1F4);
      borderColor = isCurrent ? _primaryNavy : _outlineVariant;
      textColor = const Color(0xFF767683);
    }

    return Semantics(
      label:
          'Question $number, ${isAnswered ? "Answered" : "Unanswered"}${isCurrent ? ", Current" : ""}',
      button: true,
      child: Tooltip(
        message:
            'Question $number: ${isAnswered ? "Answered" : "Unanswered"}${isCurrent ? " (Current)" : ""}',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            key: ValueKey('question_badge_$number'),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: borderColor,
                width: isCurrent ? 2.5 : 1.0,
              ),
              boxShadow: isCurrent
                  ? [
                      BoxShadow(
                        color: _primaryNavy.withValues(alpha: 0.18),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isAnswered) ...[
                      const Icon(
                        Icons.check,
                        size: 11,
                        color: Color(0xFF1B5E20),
                      ),
                      const SizedBox(width: 1),
                    ],
                    Text(
                      '$number',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isCurrent || isAnswered
                            ? FontWeight.bold
                            : FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                if (isFlagged)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showQuestionGridModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surfaceWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Question Overview',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildLegendItem(
                          color: const Color(0xFFE8F5E9),
                          borderColor: const Color(0xFF81C784),
                          label: 'Answered ($_answeredCount)',
                        ),
                        const SizedBox(width: 12),
                        _buildLegendItem(
                          color: const Color(0xFFF1F1F4),
                          borderColor: _outlineVariant,
                          label:
                              'Unanswered (${_questions.length - _answeredCount})',
                        ),
                        if (_flaggedQuestionIds.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          _buildLegendItem(
                            color: Colors.amber.shade100,
                            borderColor: Colors.amber,
                            label: 'Flagged (${_flaggedQuestionIds.length})',
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.45,
                      ),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: List.generate(_questions.length, (idx) {
                            final q = _questions[idx];
                            final isCurrent = q.id == _currentQuestion.id;
                            final isAnswered = _isQuestionAnswered(q);
                            final isFlagged = _flaggedQuestionIds.contains(
                              q.id,
                            );

                            return _buildQuestionBadge(
                              number: idx + 1,
                              isCurrent: isCurrent,
                              isAnswered: isAnswered,
                              isFlagged: isFlagged,
                              onTap: () {
                                Navigator.pop(ctx);
                                _jumpToQuestion(q);
                              },
                            );
                          }),
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
  }

  Widget _buildLegendItem({
    required Color color,
    required Color borderColor,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: _textSecondary),
        ),
      ],
    );
  }
}
