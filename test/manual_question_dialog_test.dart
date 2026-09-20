import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studexa/models/quiz_model.dart';
import 'package:studexa/screens/teacher/manual_question_dialog.dart';

void main() {
  testWidgets('teacher creates a four-choice question with a selected answer', (tester) async {
    QuizQuestion? saved;
    await tester.binding.setSurfaceSize(const Size(375, 812));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => TextButton(
        onPressed: () async => saved = await showDialog<QuizQuestion>(
          context: context, builder: (_) => const ManualQuestionDialog()),
        child: const Text('Open editor'),
      ),
    ))));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Which structure stores data?');
    for (final entry in ['CPU', 'RAM', 'Monitor', 'Printer'].asMap().entries) {
      await tester.enterText(find.byType(TextField).at(entry.key + 1), entry.value);
    }
    await tester.tap(find.byTooltip('Choice B is correct'));
    await tester.tap(find.text('Add Question'));
    await tester.pumpAndSettle();
    expect(saved?.type, QuizQuestionType.multipleChoice);
    expect(saved?.correctAnswer, 'B. RAM');
    expect(saved?.options, ['A. CPU', 'B. RAM', 'C. Monitor', 'D. Printer']);
    expect(saved?.origin, 'manual');
  });

  testWidgets('teacher adds enumeration with item-based points', (tester) async {
    QuizQuestion? saved;
    await tester.binding.setSurfaceSize(const Size(375, 812));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => TextButton(
        onPressed: () async => saved = await showDialog<QuizQuestion>(
          context: context, builder: (_) => const ManualQuestionDialog()),
        child: const Text('Open editor'),
      ),
    ))));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<QuizQuestionType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enumeration').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'List the two memory types.');
    await tester.enterText(find.byType(TextField).at(1), 'RAM');
    await tester.enterText(find.byType(TextField).at(2), 'ROM');
    await tester.ensureVisible(find.text('Add Question'));
    await tester.tap(find.text('Add Question'));
    await tester.pumpAndSettle();
    expect(saved?.enumerationAnswers, ['RAM', 'ROM']);
    expect(saved?.points, 2);
  });

  for (final caseType in [
    QuizQuestionType.trueFalse,
    QuizQuestionType.fillInTheBlank,
    QuizQuestionType.identification,
  ]) {
    testWidgets('teacher creates a ${caseType.displayName} question', (tester) async {
      QuizQuestion? saved;
      await tester.binding.setSurfaceSize(const Size(375, 812));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
        builder: (context) => TextButton(
          onPressed: () async => saved = await showDialog<QuizQuestion>(
            context: context, builder: (_) => const ManualQuestionDialog()),
          child: const Text('Open editor'),
        ),
      ))));
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<QuizQuestionType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(caseType.displayName).last);
      await tester.pumpAndSettle();
      final prompt = caseType == QuizQuestionType.fillInTheBlank
          ? 'A program in execution is a _______.'
          : caseType == QuizQuestionType.trueFalse
              ? 'A process is a program in execution.'
              : 'What is a program in execution?';
      await tester.enterText(find.byType(TextField).first, prompt);
      if (caseType != QuizQuestionType.trueFalse) {
        await tester.enterText(find.byType(TextField).at(1), 'process');
      }
      await tester.ensureVisible(find.text('Add Question'));
      await tester.tap(find.text('Add Question'));
      await tester.pumpAndSettle();
      expect(saved?.type, caseType);
      expect(saved?.correctAnswer,
          caseType == QuizQuestionType.trueFalse ? 'True' : 'process');
      expect(saved?.origin, 'manual');
    });
  }
}
