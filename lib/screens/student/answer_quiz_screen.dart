import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/quiz_attempt_model.dart';
import '../../models/quiz_model.dart';
import '../../services/assignment_service.dart';
import '../../utils/scoring_utils.dart';

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

  const AnswerQuizScreen({
    super.key,
    this.quiz,
    this.quizTitle = 'Cellular Respiration & ATP Synthesis',
  });

  @override
  State<AnswerQuizScreen> createState() => _AnswerQuizScreenState();
}

class _AnswerQuizScreenState extends State<AnswerQuizScreen> {
  // ── Design tokens ───────────────────────────────────────────
  static const _primaryNavy = Color(0xFF1A237E);
  static const _gradientStart = Color(0xFFF3F0FF);
  static const _gradientEnd = Color(0xFFEFF6FF);
  static const _surfaceWhite = Color(0xFFFBF9F8);
  static const _outlineVariant = Color(0xFFC6C5D4);
  static const _textPrimary = Color(0xFF1B1C1C);
  static const _textSecondary = Color(0xFF454652);

  int _currentIndex = 0;
  final Set<int> _flaggedIndices = {};
  final Map<int, dynamic> _userAnswers = {};

  final TextEditingController _textAnswerController = TextEditingController();
  final TextEditingController _enumInputController = TextEditingController();

  late List<QuizQuestion> _questions;

  @override
  void initState() {
    super.initState();
    if (widget.quiz != null && widget.quiz!.questions.isNotEmpty) {
      _questions = widget.quiz!.questions;
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

    _loadCurrentAnswer();
  }

  @override
  void dispose() {
    _textAnswerController.dispose();
    _enumInputController.dispose();
    super.dispose();
  }

  void _loadCurrentAnswer() {
    final q = _questions[_currentIndex];
    final currentAnswer = _userAnswers[_currentIndex];

    if (q.type == QuizQuestionType.fillInTheBlank ||
        q.type == QuizQuestionType.identification) {
      _textAnswerController.text = (currentAnswer is String) ? currentAnswer : '';
    } else {
      _textAnswerController.clear();
    }
    _enumInputController.clear();
  }

  void _saveCurrentAnswer() {
    final q = _questions[_currentIndex];
    if (q.type == QuizQuestionType.fillInTheBlank ||
        q.type == QuizQuestionType.identification) {
      _userAnswers[_currentIndex] = _textAnswerController.text.trim();
    }
  }

  void _goToNext() {
    _saveCurrentAnswer();
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _loadCurrentAnswer();
      });
    } else {
      _showSubmitConfirmation();
    }
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

  void _toggleFlag() {
    setState(() {
      if (_flaggedIndices.contains(_currentIndex)) {
        _flaggedIndices.remove(_currentIndex);
      } else {
        _flaggedIndices.add(_currentIndex);
      }
    });
  }

  void _addEnumerationItem() {
    final text = _enumInputController.text.trim();
    if (text.isEmpty) return;

    final currentList = List<String>.from(
      (_userAnswers[_currentIndex] as List<String>?) ?? [],
    );

    if (!currentList.contains(text)) {
      currentList.add(text);
      setState(() {
        _userAnswers[_currentIndex] = currentList;
        _enumInputController.clear();
      });
    }
  }

  void _removeEnumerationItem(String item) {
    final currentList = List<String>.from(
      (_userAnswers[_currentIndex] as List<String>?) ?? [],
    );
    currentList.remove(item);
    setState(() {
      _userAnswers[_currentIndex] = currentList;
    });
  }

  void _showSubmitConfirmation() {
    _saveCurrentAnswer();

    int answeredCount = 0;
    for (int i = 0; i < _questions.length; i++) {
      final ans = _userAnswers[i];
      if (ans is String && ans.isNotEmpty) answeredCount++;
      if (ans is List && ans.isNotEmpty) answeredCount++;
    }

    final totalCount = _questions.length;
    final flaggedCount = _flaggedIndices.length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              'Answered $answeredCount of $totalCount questions.',
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
            child: const Text('Review Answers',
                style: TextStyle(color: _textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
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

  void _evaluateAndShowResults() {
    double totalEarned = 0.0;
    double totalPossible = 0.0;
    final List<Map<String, dynamic>> questionBreakdown = [];

    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final userAns = _userAnswers[i];
      totalPossible += q.points;

      double earned = 0.0;
      bool isCorrect = false;
      dynamic details;

      switch (q.type) {
        case QuizQuestionType.multipleChoice:
        case QuizQuestionType.trueFalse:
          final cleanUser = (userAns?.toString() ?? '').trim().toLowerCase();
          final cleanExpected = q.correctAnswer.trim().toLowerCase();
          // Match full option or prefix letter
          isCorrect = cleanUser == cleanExpected ||
              (cleanUser.length > 2 && cleanExpected.contains(cleanUser));
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
          final enumResult = ScoringUtils.scoreEnumeration(
            studentItems: studentItems,
            expectedItems: q.enumerationAnswers,
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

    final percentage =
        totalPossible > 0 ? (totalEarned / totalPossible * 100) : 0.0;

    // Persist attempt to Firestore in the background
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && widget.quiz != null) {
      final attempt = QuizAttemptModel(
        id: '',
        quizId: widget.quiz!.id,
        classId: widget.quiz!.classId,
        studentId: user.uid,
        studentName: user.displayName ??
            (user.email?.split('@').first ?? 'Student'),
        answers: _userAnswers.map((k, v) => MapEntry('q_$k', v)),
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

      AssignmentService().submitAttempt(attempt).catchError((err) {
        debugPrint('Attempt persistence info: $err');
        return attempt;
      });
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your Score',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
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
                            horizontal: 14, vertical: 8),
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
                      borderRadius: BorderRadius.circular(10),
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
                                  fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            Text(
                              '${earned.toStringAsFixed(1)} / ${q.points.toStringAsFixed(0)} pt',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isCor ? Colors.green[800] : Colors.red[800],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(q.question,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),

                        if (details is EnumerationResult) ...[
                          Text(
                            'Found: ${details.found.isEmpty ? "None" : details.found.join(", ")}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.green),
                          ),
                          if (details.missing.isNotEmpty)
                            Text(
                              'Missing: ${details.missing.join(", ")}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.red),
                            ),
                          if (details.extra.isNotEmpty)
                            Text(
                              'Extra (not penalized): ${details.extra.join(", ")}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.blue),
                            ),
                        ] else ...[
                          Text(
                            'Expected: ${q.correctAnswer}',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.green[800],
                                fontWeight: FontWeight.w600),
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
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryNavy,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentQ = _questions[_currentIndex];
    final isFlagged = _flaggedIndices.contains(_currentIndex);
    final isLastQuestion = _currentIndex == _questions.length - 1;
    final progress = (_currentIndex + 1) / _questions.length;
    final title = widget.quiz?.title ?? widget.quizTitle;

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
          icon: const Icon(Icons.close, color: _primaryNavy),
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
          child: Column(
            children: [
              // ── Top Progress Indicator ─────────────────────
              LinearProgressIndicator(
                value: progress,
                backgroundColor: _outlineVariant.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(_primaryNavy),
                minHeight: 4,
              ),

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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _primaryNavy.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              currentQ.type.displayName,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _primaryNavy,
                              ),
                            ),
                          ),
                          Text(
                            'Question ${_currentIndex + 1} of ${_questions.length}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: _textSecondary,
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
                      if (currentQ.type == QuizQuestionType.multipleChoice ||
                          currentQ.type == QuizQuestionType.trueFalse)
                        _buildChoiceOptions(currentQ.options)
                      else if (currentQ.type ==
                              QuizQuestionType.fillInTheBlank ||
                          currentQ.type == QuizQuestionType.identification)
                        _buildTextInput(
                          currentQ.type == QuizQuestionType.fillInTheBlank
                              ? 'Enter missing word or term...'
                              : 'Enter identified concept...',
                        )
                      else if (currentQ.type == QuizQuestionType.enumeration)
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
                child: Row(
                  children: [
                    if (_currentIndex > 0)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _textPrimary,
                          side: const BorderSide(color: _outlineVariant),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onPressed: _goToPrevious,
                        child: const Row(
                          children: [
                            Icon(Icons.arrow_back, size: 16),
                            SizedBox(width: 4),
                            Text('Previous'),
                          ],
                        ),
                      ),
                    if (_currentIndex > 0) const SizedBox(width: 12),

                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryNavy,
                          foregroundColor: Colors.white,
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _goToNext,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              isLastQuestion ? 'Submit Quiz' : 'Next Question',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              isLastQuestion
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChoiceOptions(List<String> options) {
    final selectedOption = _userAnswers[_currentIndex];

    return Column(
      children: options.map((option) {
        final isSelected = selectedOption == option;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () {
              setState(() {
                _userAnswers[_currentIndex] = option;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? _primaryNavy.withValues(alpha: 0.08)
                    : _surfaceWhite,
                borderRadius: BorderRadius.circular(12),
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
                        ? const Icon(
                            Icons.check,
                            size: 14,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      option,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
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
        borderRadius: BorderRadius.circular(12),
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
          _userAnswers[_currentIndex] = val.trim();
        },
      ),
    );
  }

  Widget _buildEnumerationInput() {
    final currentList = List<String>.from(
      (_userAnswers[_currentIndex] as List<String>?) ?? [],
    );

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
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _outlineVariant),
                ),
                child: TextField(
                  controller: _enumInputController,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _surfaceWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _primaryNavy.withValues(alpha: 0.4)),
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
                      child: const Icon(Icons.close, size: 16, color: Colors.red),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
