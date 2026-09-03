import 'package:flutter/material.dart';

/// Active quiz screen displaying one question at a time with a progress bar,
/// question-type label, interactive inputs (MCQ buttons & text input),
/// a "Flag for review" toggle, and Next/Submit navigation.
class AnswerQuizScreen extends StatefulWidget {
  const AnswerQuizScreen({
    super.key,
    this.quizTitle = 'Cellular Respiration & ATP Synthesis',
  });

  final String quizTitle;

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

  // ── Hardcoded dummy questions ───────────────────────────────
  final List<Map<String, dynamic>> _questions = [
    {
      'type': 'mcq',
      'typeLabel': 'Multiple Choice',
      'questionText':
          'Which of the following cellular organelles is primarily responsible for generating ATP through oxidative phosphorylation?',
      'options': [
        'A. Nucleus',
        'B. Mitochondria',
        'C. Golgi Apparatus',
        'D. Endoplasmic Reticulum',
      ],
    },
    {
      'type': 'fill_blank',
      'typeLabel': 'Fill-in-the-Blank',
      'questionText':
          'The metabolic pathway that breaks down glucose into pyruvate and produces a net gain of 2 ATP molecules is called _______.',
      'hint': 'Enter metabolic process name...',
    },
    {
      'type': 'true_false',
      'typeLabel': 'True / False',
      'questionText':
          'Glycolysis requires molecular oxygen to proceed and takes place entirely within the mitochondrial matrix.',
      'options': [
        'True',
        'False',
      ],
    },
    {
      'type': 'identification',
      'typeLabel': 'Identification',
      'questionText':
          'Identify the enzyme that catalyzes the synthesis of ATP from ADP and inorganic phosphate during chemiosmosis.',
      'hint': 'Enter enzyme name...',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentAnswer();
  }

  @override
  void dispose() {
    _textAnswerController.dispose();
    super.dispose();
  }

  void _loadCurrentAnswer() {
    final currentAnswer = _userAnswers[_currentIndex];
    if (currentAnswer is String &&
        (_questions[_currentIndex]['type'] == 'fill_blank' ||
            _questions[_currentIndex]['type'] == 'identification')) {
      _textAnswerController.text = currentAnswer;
    } else {
      _textAnswerController.clear();
    }
  }

  void _saveCurrentAnswer() {
    final type = _questions[_currentIndex]['type'] as String;
    if (type == 'fill_blank' || type == 'identification') {
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

  void _showSubmitConfirmation() {
    _saveCurrentAnswer();
    final answeredCount = _userAnswers.values
        .where((ans) => ans != null && ans.toString().isNotEmpty)
        .length;
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
              'Once submitted, your responses will be scored instantly.',
              style: TextStyle(fontSize: 13, color: _textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Review Answers', style: TextStyle(color: _textSecondary)),
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
              // TODO: Wire to Firestore quizAttempts submission
              Navigator.pop(ctx);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Quiz submitted! Score: 4/4 (100%)'),
                  backgroundColor: _primaryNavy,
                ),
              );
            },
            child: const Text('Submit'),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.quizTitle,
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
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Question metadata header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'QUESTION ${_currentIndex + 1} OF ${_questions.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                              color: _textSecondary,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _primaryNavy.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              currentQ['typeLabel'] as String,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _primaryNavy,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Question prompt text
                      Text(
                        currentQ['questionText'] as String,
                        style: const TextStyle(
                          fontSize: 18,
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
                      if (currentQ['type'] == 'mcq' ||
                          currentQ['type'] == 'true_false')
                        _buildChoiceOptions(
                          currentQ['options'] as List<String>,
                        )
                      else if (currentQ['type'] == 'fill_blank' ||
                          currentQ['type'] == 'identification')
                        _buildTextInput(
                          currentQ['hint'] as String,
                        ),
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
                    // Previous button
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

                    // Next or Submit button
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

  /// Option selector for MCQ and True/False questions.
  Widget _buildChoiceOptions(List<String> options) {
    final selectedValue = _userAnswers[_currentIndex];

    return Column(
      children: options.map((option) {
        final isSelected = selectedValue == option;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? _primaryNavy.withValues(alpha: 0.06)
                : _surfaceWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? _primaryNavy : _outlineVariant,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            onTap: () {
              setState(() {
                _userAnswers[_currentIndex] = option;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? _primaryNavy : _outlineVariant,
                        width: 2,
                      ),
                      color: isSelected ? _primaryNavy : Colors.transparent,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      option,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: _textPrimary,
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

  /// Text field input for Fill-in-the-Blank and Identification questions.
  Widget _buildTextInput(String hint) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Answer:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _textAnswerController,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: _outlineVariant,
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _outlineVariant),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                borderSide: BorderSide(color: _primaryNavy, width: 1.5),
              ),
            ),
            onChanged: (val) {
              _userAnswers[_currentIndex] = val;
            },
          ),
        ],
      ),
    );
  }
}
