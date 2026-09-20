import 'package:flutter/material.dart';

import '../../models/quiz_model.dart';
import '../../theme/app_theme.dart';

/// Collects a teacher-authored question in the format used by scoring and PDF export.
class ManualQuestionDialog extends StatefulWidget {
  const ManualQuestionDialog({super.key});

  @override
  State<ManualQuestionDialog> createState() => _ManualQuestionDialogState();
}

class _ManualQuestionDialogState extends State<ManualQuestionDialog> {
  QuizQuestionType _type = QuizQuestionType.multipleChoice;
  final _prompt = TextEditingController();
  final _answer = TextEditingController();
  final _explanation = TextEditingController();
  final _options = List.generate(4, (_) => TextEditingController());
  final _items = List.generate(5, (_) => TextEditingController());
  int _correctOption = 0;
  bool _trueAnswer = true;
  String? _error;

  @override
  void dispose() {
    _prompt.dispose();
    _answer.dispose();
    _explanation.dispose();
    for (final controller in [..._options, ..._items]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = 'Enter the question prompt.');
      return;
    }
    final answer = _answer.text.trim();
    List<String> options = const [];
    List<String> enumerationAnswers = const [];
    String correctAnswer = answer;
    double points = 1;
    String? error;

    switch (_type) {
      case QuizQuestionType.multipleChoice:
        final values = _options.map((controller) => controller.text.trim()).toList();
        if (values.any((value) => value.isEmpty)) {
          error = 'Enter all four answer choices.';
        } else if (values.map((value) => value.toLowerCase()).toSet().length != 4) {
          error = 'Each answer choice must be different.';
        } else {
          options = List.generate(4, (index) => '${'ABCD'[index]}. ${values[index]}');
          correctAnswer = options[_correctOption];
        }
      case QuizQuestionType.trueFalse:
        options = const ['True', 'False'];
        correctAnswer = _trueAnswer ? 'True' : 'False';
      case QuizQuestionType.fillInTheBlank:
        if (RegExp('_______').allMatches(prompt).length != 1) {
          error = 'Use exactly one _______ blank in the prompt.';
        } else if (answer.isEmpty || answer.split(RegExp(r'\s+')).length > 2) {
          error = 'Enter a one- or two-word answer for the blank.';
        }
      case QuizQuestionType.identification:
        if (answer.isEmpty) error = 'Enter the term students should identify.';
      case QuizQuestionType.enumeration:
        enumerationAnswers = _items.map((controller) => controller.text.trim())
            .where((item) => item.isNotEmpty).toList();
        if (enumerationAnswers.length < 2) {
          error = 'Enter at least two expected answers.';
        } else if (enumerationAnswers.map((item) => item.toLowerCase()).toSet().length != enumerationAnswers.length) {
          error = 'Expected answers must be different.';
        } else {
          correctAnswer = enumerationAnswers.join(', ');
          points = enumerationAnswers.length.toDouble();
        }
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, QuizQuestion(
      id: '',
      type: _type,
      question: prompt,
      options: options,
      correctAnswer: correctAnswer,
      enumerationAnswers: enumerationAnswers,
      explanation: _explanation.text.trim(),
      points: points,
      origin: 'manual',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceWhite,
      shape: RoundedRectangleBorder(borderRadius: AppTheme.borderRadiusXl),
      title: const Text('Add Your Question'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<QuizQuestionType>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Question type'),
                items: QuizQuestionType.values.map((type) => DropdownMenuItem(
                  value: type,
                  child: Text(type.displayName),
                )).toList(),
                onChanged: (type) {
                  if (type != null) setState(() { _type = type; _error = null; });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _prompt,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Question prompt',
                  hintText: _type == QuizQuestionType.fillInTheBlank
                      ? 'The answer is _______.' : null,
                ),
              ),
              const SizedBox(height: 12),
              if (_type == QuizQuestionType.multipleChoice) ...[
                for (var index = 0; index < 4; index++)
                  Row(children: [
                    IconButton(
                      tooltip: 'Choice ${'ABCD'[index]} is correct',
                      icon: Icon(_correctOption == index
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked),
                      onPressed: () => setState(() => _correctOption = index),
                    ),
                    Expanded(child: TextField(
                      controller: _options[index],
                      decoration: InputDecoration(labelText: 'Choice ${'ABCD'[index]}'),
                    )),
                  ]),
                const Text('Select the correct choice.'),
              ] else if (_type == QuizQuestionType.trueFalse)
                DropdownButtonFormField<bool>(
                  initialValue: _trueAnswer,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Correct answer'),
                  items: const [
                    DropdownMenuItem(value: true, child: Text('True')),
                    DropdownMenuItem(value: false, child: Text('False')),
                  ],
                  onChanged: (value) => setState(() => _trueAnswer = value ?? true),
                )
              else if (_type == QuizQuestionType.enumeration) ...[
                for (var index = 0; index < 5; index++)
                  TextField(
                    controller: _items[index],
                    decoration: InputDecoration(labelText: 'Expected answer ${index + 1}${index >= 2 ? ' (optional)' : ''}'),
                  ),
              ] else
                TextField(
                  controller: _answer,
                  decoration: InputDecoration(labelText: _type == QuizQuestionType.identification
                      ? 'Term to identify' : 'Answer for the blank'),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _explanation,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Explanation (optional)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: AppTheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Add Question')),
      ],
    );
  }
}
