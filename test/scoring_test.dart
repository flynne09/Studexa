import 'package:flutter_test/flutter_test.dart';
import 'package:studexa/utils/scoring_utils.dart';

void main() {
  group('ScoringUtils - Free-Text Matching & Typo Tolerance', () {
    test('exact match with case and whitespace differences', () {
      expect(ScoringUtils.isFreeTextMatch('  Photosynthesis ', 'photosynthesis'), isTrue);
      expect(ScoringUtils.isFreeTextMatch('ATP SYNTHASE', 'atp synthase'), isTrue);
    });

    test('punctuation stripping', () {
      expect(ScoringUtils.isFreeTextMatch('Mitochondria.', 'mitochondria'), isTrue);
      expect(ScoringUtils.isFreeTextMatch('Ribosome,', 'ribosome'), isTrue);
    });

    test('short words require exact match', () {
      // <= 4 chars: distance 0 required
      expect(ScoringUtils.isFreeTextMatch('cell', 'cell'), isTrue);
      expect(ScoringUtils.isFreeTextMatch('cel', 'cell'), isFalse);
    });

    test('medium words tolerate 1 typo', () {
      // 5-8 chars: distance <= 1
      expect(ScoringUtils.isFreeTextMatch('chloroplaast', 'chloroplast'), isTrue); // distance 1
      expect(ScoringUtils.isFreeTextMatch('nucleus', 'nucleos'), isTrue); // distance 1
      expect(ScoringUtils.isFreeTextMatch('nucl', 'nucleus'), isFalse); // distance 3
    });

    test('long words tolerate 2 typos', () {
      // >= 9 chars: distance <= 2
      expect(ScoringUtils.isFreeTextMatch('photosynthesiss', 'photosynthesis'), isTrue); // distance 1
      expect(ScoringUtils.isFreeTextMatch('phottosynthesiss', 'photosynthesis'), isTrue); // distance 2
      expect(ScoringUtils.isFreeTextMatch('mitochondrionn', 'mitochondria'), isFalse); // distance 3
    });
  });

  group('ScoringUtils - Enumeration Partial Credit', () {
    final expectedStages = [
      'Glycolysis',
      'Krebs Cycle',
      'Electron Transport Chain',
    ];

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

    test('extra incorrect items do not penalize or reduce score', () {
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

    test('empty response awards 0', () {
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
