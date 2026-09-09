import 'package:flutter_test/flutter_test.dart';
import 'package:studexa/utils/scoring_utils.dart';

void main() {
  group('ScoringUtils - Prefix and Formatting Cleaning', () {
    test('cleans letter prefixes, number prefixes, bullets, and quotes', () {
      expect(ScoringUtils.cleanExpectedAnswer('A. Mitochondria'), 'Mitochondria');
      expect(ScoringUtils.cleanExpectedAnswer('B) Ribosome'), 'Ribosome');
      expect(ScoringUtils.cleanExpectedAnswer('1. Glycolysis'), 'Glycolysis');
      expect(ScoringUtils.cleanExpectedAnswer('- Chloroplast'), 'Chloroplast');
      expect(ScoringUtils.cleanExpectedAnswer('* Enzyme'), 'Enzyme');
      expect(ScoringUtils.cleanExpectedAnswer('"Adenosine Triphosphate"'), 'Adenosine Triphosphate');
      expect(ScoringUtils.cleanExpectedAnswer("'Nucleus'"), 'Nucleus');
    });
  });

  group('ScoringUtils - Free-Text Matching & Strict Typo Tolerance (Issue 6)', () {
    test('exact match with case and whitespace differences', () {
      expect(ScoringUtils.isFreeTextMatch('  Photosynthesis ', 'photosynthesis'), isTrue);
      expect(ScoringUtils.isFreeTextMatch('ATP SYNTHASE', 'atp synthase'), isTrue);
      expect(ScoringUtils.isFreeTextMatch('Apple', 'apple'), isTrue);
      expect(ScoringUtils.isFreeTextMatch('apple', 'Apple'), isTrue);
    });

    test('punctuation stripping', () {
      expect(ScoringUtils.isFreeTextMatch('Mitochondria.', 'mitochondria'), isTrue);
      expect(ScoringUtils.isFreeTextMatch('Ribosome,', 'ribosome'), isTrue);
    });

    test('expected answer with option prefix matches plain student answer', () {
      expect(ScoringUtils.isFreeTextMatch('Mitochondria', 'A. Mitochondria'), isTrue);
      expect(ScoringUtils.isFreeTextMatch('mitochondria', 'B) Mitochondria'), isTrue);
      expect(ScoringUtils.isFreeTextMatch('glycolysis', '1. Glycolysis'), isTrue);
    });

    test('short words (<=4 chars): exact match only, distance == 0 (rejects 1-letter errors)', () {
      // <= 4 chars: distance 0 required. Even 1 typo is rejected.
      expect(ScoringUtils.isFreeTextMatch('cell', 'cell'), isTrue);
      expect(ScoringUtils.isFreeTextMatch('CELL', 'cell'), isTrue);
      expect(ScoringUtils.isFreeTextMatch('cel', 'cell'), isFalse); // 1 deletion
      expect(ScoringUtils.isFreeTextMatch('celll', 'cell'), isFalse); // 1 insertion
      expect(ScoringUtils.isFreeTextMatch('call', 'cell'), isFalse); // 1 substitution
      expect(ScoringUtils.isFreeTextMatch('dna', 'dna'), isTrue);
      expect(ScoringUtils.isFreeTextMatch('rna', 'dna'), isFalse);
      expect(ScoringUtils.isFreeTextMatch('atp', 'atp'), isTrue);
      expect(ScoringUtils.isFreeTextMatch('adp', 'atp'), isFalse);
    });

    test('medium words (5-8 chars): tolerates at most 1 typo (distance <= 1)', () {
      // 5-8 chars: distance <= 1 allowed, 2 or more rejected
      expect(ScoringUtils.isFreeTextMatch('chloroplaast', 'chloroplast'), isTrue); // distance 1
      expect(ScoringUtils.isFreeTextMatch('nucleus', 'nucleos'), isTrue); // distance 1
      expect(ScoringUtils.isFreeTextMatch('enzyme', 'enzym'), isTrue); // distance 1
      expect(ScoringUtils.isFreeTextMatch('enzim', 'enzyme'), isFalse); // distance 2
      expect(ScoringUtils.isFreeTextMatch('nucl', 'nucleus'), isFalse); // distance 3
      expect(ScoringUtils.isFreeTextMatch('bacteria', 'bakteria'), isTrue); // distance 1
      expect(ScoringUtils.isFreeTextMatch('bacteria', 'bakterya'), isFalse); // distance 2
    });

    test('long words (>=9 chars): tolerates at most 2 typos (distance <= 2)', () {
      // >= 9 chars: distance <= 2 allowed, 3 or more rejected
      expect(ScoringUtils.isFreeTextMatch('photosynthesiss', 'photosynthesis'), isTrue); // distance 1
      expect(ScoringUtils.isFreeTextMatch('phottosynthesiss', 'photosynthesis'), isTrue); // distance 2
      expect(ScoringUtils.isFreeTextMatch('photosynthesi', 'photosynthesis'), isTrue); // distance 1
      expect(ScoringUtils.isFreeTextMatch('mitochondrionn', 'mitochondria'), isFalse); // distance 3
      expect(ScoringUtils.isFreeTextMatch('respiration', 'respiratn'), isTrue); // distance 2 (missing 'io')
      expect(ScoringUtils.isFreeTextMatch('respiration', 'resprat'), isFalse); // distance 4
    });

    test('clearly incorrect answers are rejected', () {
      expect(ScoringUtils.isFreeTextMatch('Elephant', 'Mitochondria'), isFalse);
      expect(ScoringUtils.isFreeTextMatch('Glucose', 'ATP Synthase'), isFalse);
      expect(ScoringUtils.isFreeTextMatch('', 'Mitochondria'), isFalse);
      expect(ScoringUtils.isFreeTextMatch('Mitochondria', ''), isFalse);
    });
  });

  group('ScoringUtils - Enumeration Partial Credit & Case Insensitivity (Issue 5)', () {
    final expectedFruits = ['Apple', 'Banana', 'Orange'];
    final expectedStages = [
      '1. Glycolysis',
      '2. Krebs Cycle',
      '3. Electron Transport Chain',
    ];

    test('case-insensitive matching (Apple vs apple)', () {
      final result = ScoringUtils.scoreEnumeration(
        studentItems: ['apple', 'BANANA', 'Orange'],
        expectedItems: expectedFruits,
        totalPoints: 3.0,
      );

      expect(result.found.length, 3);
      expect(result.missing.isEmpty, isTrue);
      expect(result.extra.isEmpty, isTrue);
      expect(result.earnedPoints, 3.0);
      expect(result.isFullyCorrect, isTrue);
    });

    test('cleans numbered prefixes from expected items', () {
      final result = ScoringUtils.scoreEnumeration(
        studentItems: ['glycolysis', 'krebs cycle', 'electron transport chain'],
        expectedItems: expectedStages,
        totalPoints: 3.0,
      );

      expect(result.found.length, 3);
      expect(result.missing.isEmpty, isTrue);
      expect(result.earnedPoints, 3.0);
      expect(result.isFullyCorrect, isTrue);
    });

    test('deduplicates student input case-insensitively', () {
      // Entering 'apple' and 'Apple' should not double-match or create extra false count
      final result = ScoringUtils.scoreEnumeration(
        studentItems: ['apple', 'Apple', 'APPLE', 'banana'],
        expectedItems: expectedFruits,
        totalPoints: 3.0,
      );

      // Should match apple and banana (2 found, 1 missing [Orange], 0 extra)
      expect(result.found.length, 2);
      expect(result.missing, ['Orange']);
      expect(result.extra.isEmpty, isTrue);
      expect(result.earnedPoints, 2.0);
      expect(result.isFullyCorrect, isFalse);
    });

    test('all correct items in different order yields 100%', () {
      final studentInput = [
        'Electron Transport Chain',
        'Glycolysis',
        'Krebs Cycle',
      ];

      final result = ScoringUtils.scoreEnumeration(
        studentItems: studentInput,
        expectedItems: expectedStages,
        totalPoints: 3.0,
      );

      expect(result.found.length, 3);
      expect(result.missing.isEmpty, isTrue);
      expect(result.extra.isEmpty, isTrue);
      expect(result.earnedPoints, 3.0);
      expect(result.isFullyCorrect, isTrue);
    });

    test('partial matches with typos award proportional credit', () {
      final studentInput = [
        'Glycolisis', // typo tolerated (distance 1, len 10)
        'Krebs Cycle',
      ];

      final result = ScoringUtils.scoreEnumeration(
        studentItems: studentInput,
        expectedItems: expectedStages,
        totalPoints: 3.0,
      );

      expect(result.found.length, 2);
      expect(result.missing, ['Electron Transport Chain']);
      expect(result.extra.isEmpty, isTrue);
      expect(result.earnedPoints, 2.0);
      expect(result.isFullyCorrect, isFalse);
    });

    test('extra incorrect items do not penalize or reduce score and appear in extra list', () {
      final studentInput = [
        'Glycolysis',
        'Krebs Cycle',
        'Fermentation', // extra
        'Calvin Cycle', // extra
      ];

      final result = ScoringUtils.scoreEnumeration(
        studentItems: studentInput,
        expectedItems: expectedStages,
        totalPoints: 3.0,
      );

      expect(result.found.length, 2);
      expect(result.missing, ['Electron Transport Chain']);
      expect(result.extra, ['Fermentation', 'Calvin Cycle']);
      expect(result.earnedPoints, 2.0); // Not deducted!
      expect(result.isFullyCorrect, isFalse);
    });

    test('empty response awards 0 points', () {
      final result = ScoringUtils.scoreEnumeration(
        studentItems: [],
        expectedItems: expectedStages,
        totalPoints: 3.0,
      );

      expect(result.found.isEmpty, isTrue);
      expect(result.missing.length, 3);
      expect(result.earnedPoints, 0.0);
    });
  });
}
