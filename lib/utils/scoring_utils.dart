import 'dart:math';

/// Scoring utility providing deterministic evaluation of quiz answers
/// matching Phase 1 specifications (free-text typo tolerance and enumeration partial credit).
class ScoringUtils {
  /// Normalizes free-text answers by trimming whitespace, lowercasing,
  /// and stripping extraneous punctuation.
  static String normalizeText(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // remove punctuation
        .replaceAll(RegExp(r'\s+'), ' '); // collapse multi-spaces
  }

  /// Calculates the Levenshtein distance between two strings.
  static int levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;

      for (int j = 0; j < s2.length; j++) {
        int cost = (s1[i] == s2[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }

      for (int j = 0; j < v0.length; j++) {
        v0[j] = v1[j];
      }
    }

    return v0[s2.length];
  }

  /// Determines if a student's free-text response matches the expected answer,
  /// allowing deterministic typo tolerance based on length:
  /// - Length <= 4: exact normalized match (distance == 0)
  /// - Length 5 to 8: distance <= 1
  /// - Length >= 9: distance <= 2
  static bool isFreeTextMatch(String studentAnswer, String expectedAnswer) {
    final normStudent = normalizeText(studentAnswer);
    final normExpected = normalizeText(expectedAnswer);

    if (normStudent == normExpected) return true;
    if (normExpected.isEmpty || normStudent.isEmpty) return false;

    final distance = levenshteinDistance(normStudent, normExpected);
    final expectedLen = normExpected.length;

    if (expectedLen <= 4) {
      return distance == 0;
    } else if (expectedLen <= 8) {
      return distance <= 1;
    } else {
      return distance <= 2;
    }
  }

  /// Evaluates an Enumeration question where order does not matter,
  /// partial credit is awarded proportionally, and extra incorrect items do not penalize.
  static EnumerationResult scoreEnumeration({
    required List<String> studentItems,
    required List<String> expectedItems,
    double totalPoints = 1.0,
  }) {
    final List<String> found = [];
    final List<String> missing = [];
    final List<String> extra = [];

    final remainingExpected = expectedItems.map((e) => e.trim()).toList();
    final remainingStudent = studentItems.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    for (final studentItem in remainingStudent) {
      int matchIndex = -1;
      for (int i = 0; i < remainingExpected.length; i++) {
        if (isFreeTextMatch(studentItem, remainingExpected[i])) {
          matchIndex = i;
          break;
        }
      }

      if (matchIndex != -1) {
        found.add(studentItem);
        remainingExpected.removeAt(matchIndex);
      } else {
        extra.add(studentItem);
      }
    }

    missing.addAll(remainingExpected);

    final expectedCount = expectedItems.length;
    final earnedPoints = expectedCount == 0
        ? 0.0
        : (found.length / expectedCount) * totalPoints;

    return EnumerationResult(
      found: found,
      missing: missing,
      extra: extra,
      earnedPoints: earnedPoints,
      totalPoints: totalPoints,
      isFullyCorrect: found.length == expectedCount && missing.isEmpty,
    );
  }
}

/// Result breakdown for an Enumeration question.
class EnumerationResult {
  const EnumerationResult({
    required this.found,
    required this.missing,
    required this.extra,
    required this.earnedPoints,
    required this.totalPoints,
    required this.isFullyCorrect,
  });

  final List<String> found;
  final List<String> missing;
  final List<String> extra;
  final double earnedPoints;
  final double totalPoints;
  final bool isFullyCorrect;
}
