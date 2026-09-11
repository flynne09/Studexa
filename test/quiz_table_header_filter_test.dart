import 'package:flutter_test/flutter_test.dart';
import 'package:studexa/models/quiz_model.dart';
import 'package:studexa/services/quiz_service.dart';
import 'package:studexa/utils/document_text_extractor.dart';

void main() {
  group('Task 5 — Table/Column Header Filtering Tests', () {
    test('1. DocumentTextExtractor.stripTableHeaderArtifacts strips structural header rows and preserves data rows & academic sentences', () {
      const mockRawText = '''
Table 1: Organelle Inventory and Function
Column A | Column B | Column C | Column D
No. | Name | Attribute | Value | Description
1 | Mitochondria | Powerhouse of the cell | Produces ATP via oxidative phosphorylation
2 | Ribosome | Protein synthesis | Translates mRNA into polypeptide chains
Field | Type | Null | Key | Default
Item | Category | Description | Remarks
The value of activation energy determines the rate of biochemical reactions.
The name deoxyribonucleic acid reflects the chemical composition of genetic material.
Column 1
Header A
''';

      final cleaned = DocumentTextExtractor.stripTableHeaderArtifacts(mockRawText);

      // Structural header lines MUST be stripped
      expect(cleaned.contains('Column A | Column B | Column C | Column D'), isFalse);
      expect(cleaned.contains('No. | Name | Attribute | Value | Description'), isFalse);
      expect(cleaned.contains('Field | Type | Null | Key | Default'), isFalse);
      expect(cleaned.contains('Item | Category | Description | Remarks'), isFalse);
      expect(cleaned.contains('\nColumn 1\n'), isFalse);
      expect(cleaned.contains('\nHeader A\n'), isFalse);

      // Data rows MUST be preserved
      expect(cleaned.contains('1 | Mitochondria | Powerhouse of the cell | Produces ATP via oxidative phosphorylation'), isTrue);
      expect(cleaned.contains('2 | Ribosome | Protein synthesis | Translates mRNA into polypeptide chains'), isTrue);

      // Legitimate academic sentences mentioning "value" or "name" MUST be preserved
      expect(cleaned.contains('The value of activation energy determines the rate of biochemical reactions.'), isTrue);
      expect(cleaned.contains('The name deoxyribonucleic acid reflects the chemical composition of genetic material.'), isTrue);
    });

    test('2. QuizService.isTableHeaderQuestion accurately flags structural table questions and answers', () {
      // Structural questions that MUST be flagged as true
      final qTableRef = QuizQuestion(
        id: 'q1',
        type: QuizQuestionType.multipleChoice,
        question: 'In Table 1, what is listed in Column A?',
        options: ['A. Mitochondria', 'B. Ribosome', 'C. Nucleus', 'D. Enzyme'],
        correctAnswer: 'A. Mitochondria',
        explanation: 'Table column question',
      );
      expect(QuizService.isTableHeaderQuestion(qTableRef), isTrue);

      final qWhichCol = QuizQuestion(
        id: 'q2',
        type: QuizQuestionType.identification,
        question: 'Which column describes the attributes of the cell?',
        options: [],
        correctAnswer: 'Column B',
        explanation: 'Structural column answer',
      );
      expect(QuizService.isTableHeaderQuestion(qWhichCol), isTrue);

      final qColAnswer = QuizQuestion(
        id: 'q3',
        type: QuizQuestionType.fillInTheBlank,
        question: 'The organelle name is found under _______ in the table.',
        options: [],
        correctAnswer: 'Column A',
        explanation: 'Target answer is a column label',
      );
      expect(QuizService.isTableHeaderQuestion(qColAnswer), isTrue);

      final qAttrAnswer = QuizQuestion(
        id: 'q4',
        type: QuizQuestionType.identification,
        question: 'Identify the property listed on the left.',
        options: [],
        correctAnswer: 'Attribute',
        explanation: 'Target answer is a structural label',
      );
      expect(QuizService.isTableHeaderQuestion(qAttrAnswer), isTrue);

      final qStructuralMCQ = QuizQuestion(
        id: 'q5',
        type: QuizQuestionType.multipleChoice,
        question: 'Identify the structural section of the data sheet.',
        options: ['A. Column A', 'B. Column B', 'C. Header 1', 'D. Header 2'],
        correctAnswer: 'A. Column A',
        explanation: 'Options are pure structural column labels',
      );
      expect(QuizService.isTableHeaderQuestion(qStructuralMCQ), isTrue);

      // Legitimate academic questions that MUST NOT be flagged (false)
      final qValidMCQ = QuizQuestion(
        id: 'q6',
        type: QuizQuestionType.multipleChoice,
        question: 'Which organelle serves as the primary site of cellular respiration and ATP synthesis?',
        options: ['A. Mitochondria', 'B. Ribosome', 'C. Chloroplast', 'D. Nucleus'],
        correctAnswer: 'A. Mitochondria',
        explanation: 'Core academic concept',
      );
      expect(QuizService.isTableHeaderQuestion(qValidMCQ), isFalse);

      final qValidFib = QuizQuestion(
        id: 'q7',
        type: QuizQuestionType.fillInTheBlank,
        question: 'Cellular respiration produces energy by breaking down _______ molecules in the cytoplasm.',
        options: [],
        correctAnswer: 'glucose',
        explanation: 'Valid single-term blank',
      );
      expect(QuizService.isTableHeaderQuestion(qValidFib), isFalse);
    });

    test('3. QuizService.generateLocalFallbackQuestions ignores tabular headers and generates 100% academic questions', () {
      const mockTabularExtractedText = '''
Table 1: Overview of Cellular Organelles
Column A | Column B | Column C | Column D
No. | Name | Attribute | Value | Description
1 | Mitochondria | Energy | High | Mitochondria are double-membraned organelles known as the powerhouse of the cell.
2 | Ribosome | Protein | High | Ribosomes are macromolecular complexes responsible for protein synthesis in the cytoplasm.
3 | Chloroplast | Photosynthesis | High | Chloroplasts contain chlorophyll pigments that absorb sunlight during photosynthesis.
4 | Enzyme | Catalyst | Variable | Enzymes are biological catalysts that lower activation energy without being consumed.
Column 1
Header 1
Field | Type | Description
The cell membrane maintains homeostasis through selective membrane permeability.
Glycolysis occurs in the cytoplasm and breaks down glucose into two molecules of pyruvate.
''';

      final questions = QuizService.generateLocalFallbackQuestions(
        extractedText: mockTabularExtractedText,
        questionTypes: [
          'multipleChoice',
          'trueFalse',
          'fillInTheBlank',
          'identification',
          'enumeration',
        ],
        questionCount: 10,
        isActual: false,
      );

      expect(questions.length, 10);

      final structuralKeywords = {
        'column', 'header', 'attribute', 'value', 'field', 'no.', 'no',
        'column a', 'column b', 'column c', 'column d', 'header 1', 'table 1',
      };

      for (final q in questions) {
        // Assert question is not flagged as table header question
        expect(
          QuizService.isTableHeaderQuestion(q),
          isFalse,
          reason: 'Generated question should not be a table header question: "\${q.question}" (answer: "\${q.correctAnswer}")',
        );

        // Assert correct answer is not a structural keyword
        final cleanAnswer = q.correctAnswer.toLowerCase().trim();
        expect(
          structuralKeywords.contains(cleanAnswer),
          isFalse,
          reason: 'Correct answer should not be a structural keyword: "\${q.correctAnswer}"',
        );

        // Assert question prompt does not ask about columns or headers
        final cleanPrompt = q.question.toLowerCase().trim();
        expect(
          cleanPrompt.contains('column a') ||
              cleanPrompt.contains('column b') ||
              cleanPrompt.contains('header 1') ||
              cleanPrompt.contains('which column') ||
              cleanPrompt.contains('in table 1'),
          isFalse,
          reason: 'Question prompt should not test table structure: "\${q.question}"',
        );

        // Assert distractors for MCQ are not structural column labels
        if (q.type == QuizQuestionType.multipleChoice) {
          for (final opt in q.options) {
            final lowerOpt = opt.toLowerCase();
            expect(
              lowerOpt.contains('column a') || lowerOpt.contains('header 1'),
              isFalse,
              reason: 'MCQ options should not contain column labels: "\$opt"',
            );
          }
        }
      }
    });

    test('4. QuizService.validateAndDeduplicateQuestions prunes table header questions and backfills', () {
      final questionsWithArtifact = [
        QuizQuestion(
          id: 'q1',
          type: QuizQuestionType.multipleChoice,
          question: 'In Table 1, which column contains the organelle name?',
          options: ['A. Column A', 'B. Column B', 'C. Column C', 'D. Column D'],
          correctAnswer: 'A. Column A',
          explanation: 'Table column header question',
        ),
        QuizQuestion(
          id: 'q2',
          type: QuizQuestionType.multipleChoice,
          question: 'Which organelle is considered the powerhouse of the cell?',
          options: ['A. Mitochondria', 'B. Ribosome', 'C. Chloroplast', 'D. Nucleus'],
          correctAnswer: 'A. Mitochondria',
          explanation: 'Mitochondria produce ATP.',
        ),
      ];

      final validated = QuizService.validateAndDeduplicateQuestions(
        questionsWithArtifact,
        targetCount: 2,
        extractedText: 'Mitochondria produce ATP. Ribosomes synthesize proteins from amino acids.',
        questionTypes: ['multipleChoice'],
        isActual: false,
      );

      expect(validated.length, 2);
      // The first question testing "Column A" must have been purged!
      expect(
        validated.any((q) => q.question.contains('Column A') || q.correctAnswer.contains('Column A')),
        isFalse,
      );
      // All validated questions must be valid academic questions
      for (final q in validated) {
        expect(QuizService.isTableHeaderQuestion(q), isFalse);
      }
    });
  });
}