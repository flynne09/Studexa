import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/quiz_model.dart';
import 'firestore_provider.dart';

/// Service managing quiz creation, generation, Firestore persistence, and streaming.
class QuizService {
  QuizService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? getAppFirestore();

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _quizzesCollection =>
      _firestore.collection('quizzes');

  CollectionReference<Map<String, dynamic>> get _materialsCollection =>
      _firestore.collection('materials');

  /// Streams all quizzes for a specific class, optionally filtered by type ("actual" or "practice").
  Stream<List<QuizModel>> streamClassQuizzes(String classId, {String? type}) {
    Query<Map<String, dynamic>> query =
        _quizzesCollection.where('classId', isEqualTo: classId);

    if (type != null && type.isNotEmpty) {
      query = query.where('type', isEqualTo: type.toLowerCase());
    }

    return query.snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => QuizModel.fromFirestore(doc))
          .toList();
      // Sort in-memory by createdAt descending
      list.sort((a, b) {
        if (a.createdAt == null && b.createdAt == null) return 0;
        if (a.createdAt == null) return 1;
        if (b.createdAt == null) return -1;
        return b.createdAt!.compareTo(a.createdAt!);
      });
      return list;
    });
  }

  /// Streams all quizzes created by a specific teacher.
  Stream<List<QuizModel>> streamTeacherQuizzes(String teacherId) {
    return _quizzesCollection
        .where('teacherId', isEqualTo: teacherId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => QuizModel.fromFirestore(doc))
          .toList();
      list.sort((a, b) {
        if (a.createdAt == null && b.createdAt == null) return 0;
        if (a.createdAt == null) return 1;
        if (b.createdAt == null) return -1;
        return b.createdAt!.compareTo(a.createdAt!);
      });
      return list;
    });
  }

  /// Streams a single quiz by ID in real time.
  Stream<QuizModel?> streamQuiz(String quizId) {
    return _quizzesCollection.doc(quizId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return QuizModel.fromFirestore(doc);
    });
  }

  /// Fetches a single quiz by ID.
  Future<QuizModel?> getQuiz(String quizId) async {
    final doc = await _quizzesCollection.doc(quizId).get();
    if (!doc.exists) return null;
    return QuizModel.fromFirestore(doc);
  }

  /// Generates a quiz from a study material.
  /// Uses material text from Firestore and generates questions across requested types.
  Future<QuizModel> generateQuiz({
    required String teacherId,
    required String classId,
    required String materialId,
    required bool isActual,
    required List<String> questionTypes,
    required int questionCount,
    String? sourceQuizId,
  }) async {
    if (teacherId.isEmpty) {
      throw ArgumentError('Teacher ID is required to generate a quiz.');
    }
    if (classId.isEmpty) {
      throw ArgumentError('A class must be selected to generate a quiz.');
    }
    if (materialId.isEmpty) {
      throw ArgumentError('A study material must be selected to generate a quiz.');
    }

    // Retrieve material to access extractedText
    final matDoc = await _materialsCollection.doc(materialId).get();
    if (!matDoc.exists) {
      throw StateError('Study material not found.');
    }

    final matData = matDoc.data() ?? {};
    final extractedText = (matData['extractedText'] as String? ?? '').trim();
    final fileName = (matData['fileName'] as String? ?? 'Study Material');

    if (extractedText.length < 20) {
      throw StateError(
        'The selected study material has not completed text extraction or contains insufficient text.',
      );
    }

    // Generate questions using deterministic rule-based generator
    final questions = generateLocalFallbackQuestions(
      extractedText: extractedText,
      questionTypes: questionTypes,
      questionCount: questionCount,
      isActual: isActual,
    );

    final cleanName = fileName.replaceAll(RegExp(r'\.[^/.]+$'), '');
    final title = isActual ? '$cleanName - Exam' : '$cleanName - Practice Quiz';
    final totalPoints =
        questions.fold<double>(0.0, (acc, q) => acc + q.points);

    final quizDoc = _quizzesCollection.doc();
    final newQuiz = QuizModel(
      id: quizDoc.id,
      classId: classId,
      teacherId: teacherId,
      materialId: materialId,
      type: isActual ? 'actual' : 'practice',
      title: title,
      status: 'draft',
      generationMethod: 'fallback',
      sourceQuizId: sourceQuizId,
      questions: questions,
      totalPoints: totalPoints,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await quizDoc.set({
      ...newQuiz.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return newQuiz;
  }

  /// Updates an existing quiz with teacher edits.
  Future<void> updateQuiz(QuizModel quiz) async {
    await _quizzesCollection.doc(quiz.id).update({
      'title': quiz.title,
      'questions': quiz.questions.map((q) => q.toMap()).toList(),
      'totalPoints':
          quiz.questions.fold<double>(0.0, (acc, q) => acc + q.points),
      'status': quiz.status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Publishes a Practice Quiz, making it available to enrolled students.
  Future<void> publishQuiz(String quizId) async {
    await _quizzesCollection.doc(quizId).update({
      'status': 'published',
      'publishedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Finalizes an Actual Quiz as a reference exam.
  Future<void> finalizeQuiz(String quizId) async {
    await _quizzesCollection.doc(quizId).update({
      'status': 'finalized',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a quiz.
  Future<void> deleteQuiz(String quizId) async {
    await _quizzesCollection.doc(quizId).delete();
  }

  /// Deterministic local question generator that extracts questions across all 5 types
  /// from material text without requiring external network/AI calls.
  static List<QuizQuestion> generateLocalFallbackQuestions({
    required String extractedText,
    required List<String> questionTypes,
    required int questionCount,
    required bool isActual,
  }) {
    final parsedTypes = (questionTypes.isNotEmpty)
        ? questionTypes.map(QuizQuestionType.fromString).toList()
        : [
            QuizQuestionType.multipleChoice,
            QuizQuestionType.trueFalse,
            QuizQuestionType.fillInTheBlank,
            QuizQuestionType.identification,
            QuizQuestionType.enumeration,
          ];

    // Extract sentences of usable length
    final rawSentences = extractedText
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((s) => s.length >= 25 && s.length <= 250)
        .toList();

    final sentences = rawSentences.length >= 4
        ? rawSentences
        : [
            'Cellular respiration produces ATP by oxidizing glucose molecules in eukaryotic cells.',
            'Mitochondria are double-membraned organelles known as the powerhouse of the cell.',
            'Glycolysis occurs in the cytoplasm and breaks down glucose into two molecules of pyruvate.',
            'The citric acid cycle takes place inside the mitochondrial matrix.',
            'Adenosine triphosphate serves as the primary energy currency for cellular reactions.',
            'Photosynthesis converts light energy into chemical energy stored in carbohydrates.',
            'Enzymes are biological catalysts that lower activation energy without being consumed.',
            'DNA stores genetic information within the cell nucleus using four nucleotide bases.',
          ];

    // Extract candidate concepts and terms
    final candidateTerms = <String>[];
    final defRegex = RegExp(
      r'([A-Z][a-zA-Z\s]{2,25})\s+(?:is defined as|is a|is an|refers to|represents|serves as|means)\s+([^.!?]+)',
      caseSensitive: false,
    );

    for (final match in defRegex.allMatches(extractedText)) {
      final term = match.group(1)?.trim() ?? '';
      if (term.length > 2 && !candidateTerms.contains(term)) {
        candidateTerms.add(term);
      }
    }

    // Extract capitalized mid-sentence words
    for (final s in sentences) {
      final words = s.split(' ');
      for (int i = 1; i < words.length; i++) {
        final clean = words[i].replaceAll(RegExp(r'[^a-zA-Z]'), '');
        if (clean.length >= 4 &&
            words[i].startsWith(RegExp(r'[A-Z]')) &&
            !candidateTerms.contains(clean)) {
          candidateTerms.add(clean);
        }
      }
    }

    const defaultTerms = [
      'Mitochondria',
      'Ribosome',
      'Chloroplast',
      'Nucleus',
      'Enzyme',
      'Glucose',
      'ATP',
      'Cytoplasm'
    ];
    for (final t in defaultTerms) {
      if (!candidateTerms.contains(t)) candidateTerms.add(t);
    }

    final questions = <QuizQuestion>[];
    final targetCount = questionCount > 0 ? questionCount : 10;

    for (int i = 0; i < targetCount; i++) {
      final qIndex = i + 1;
      final qType = parsedTypes[i % parsedTypes.length];
      final sentence = sentences[i % sentences.length];
      final term = candidateTerms[i % candidateTerms.length];

      switch (qType) {
        case QuizQuestionType.multipleChoice:
          final words = sentence.split(' ');
          String targetWord = term;
          String displaySentence = sentence;

          if (sentence.contains(term)) {
            displaySentence = sentence.replaceFirst(term, '_______');
          } else {
            final noun = words.firstWhere(
              (w) => w.length >= 5 && RegExp(r'^[a-zA-Z]+$').hasMatch(w),
              orElse: () => words.first,
            );
            targetWord = noun.replaceAll(RegExp(r'[^a-zA-Z]'), '');
            displaySentence = sentence.replaceFirst(noun, '_______');
          }

          final distractors = candidateTerms
              .where((t) => t.toLowerCase() != targetWord.toLowerCase())
              .take(3)
              .toList();
          while (distractors.length < 3) {
            distractors.add('Concept ${distractors.length + 1}');
          }

          final allOptions = [targetWord, ...distractors]..shuffle();
          const letters = ['A', 'B', 'C', 'D'];
          final formattedOptions = List<String>.generate(
            allOptions.length,
            (idx) => '${letters[idx]}. ${allOptions[idx]}',
          );
          final correctIdx = allOptions.indexOf(targetWord);
          final correctAnswer = formattedOptions[correctIdx];

          questions.add(QuizQuestion(
            id: 'q_$qIndex',
            type: QuizQuestionType.multipleChoice,
            question: isActual
                ? 'Fill in the blank: $displaySentence'
                : 'Practice Question: Based on the reading, complete the statement: "$displaySentence"',
            options: formattedOptions,
            correctAnswer: correctAnswer,
            explanation: 'The correct answer is $targetWord from: "$sentence".',
            points: 1.0,
          ));
          break;

        case QuizQuestionType.trueFalse:
          final isTrue = i % 2 == 0;
          String statement = sentence;
          if (!isTrue) {
            if (statement.contains(' is ')) {
              statement = statement.replaceFirst(' is ', ' is not ');
            } else if (statement.contains(' are ')) {
              statement = statement.replaceFirst(' are ', ' are not ');
            } else if (statement.contains(' can ')) {
              statement = statement.replaceFirst(' can ', ' cannot ');
            } else {
              statement = 'It is false that ${statement[0].toLowerCase()}${statement.substring(1)}';
            }
          }

          questions.add(QuizQuestion(
            id: 'q_$qIndex',
            type: QuizQuestionType.trueFalse,
            question: isActual
                ? 'Determine whether the following statement is True or False:\n"$statement"'
                : 'Concept Check: Is the following statement accurate?\n"$statement"',
            options: const ['True', 'False'],
            correctAnswer: isTrue ? 'True' : 'False',
            explanation: isTrue
                ? 'Verified directly from the material: "$sentence".'
                : 'False. The actual material notes: "$sentence".',
            points: 1.0,
          ));
          break;

        case QuizQuestionType.fillInTheBlank:
          final words = sentence.split(' ');
          final keyword = words.firstWhere(
            (w) =>
                w.length >= 5 &&
                !RegExp(r'^(about|which|their|there|these|those)$',
                        caseSensitive: false)
                    .hasMatch(w),
            orElse: () => term,
          );
          final cleanKeyword = keyword.replaceAll(RegExp(r'[^a-zA-Z]'), '');
          final blankPrompt = sentence.replaceFirst(
            RegExp('\\b$cleanKeyword\\b', caseSensitive: false),
            '_______',
          );

          questions.add(QuizQuestion(
            id: 'q_$qIndex',
            type: QuizQuestionType.fillInTheBlank,
            question: isActual
                ? 'Complete the statement: $blankPrompt'
                : 'Fill in the missing term from the lesson: $blankPrompt',
            options: const [],
            correctAnswer: cleanKeyword,
            explanation: 'The missing term is "$cleanKeyword". Full context: "$sentence".',
            points: 1.0,
          ));
          break;

        case QuizQuestionType.identification:
          questions.add(QuizQuestion(
            id: 'q_$qIndex',
            type: QuizQuestionType.identification,
            question: isActual
                ? 'Identify the term or concept described:\n"$sentence"'
                : 'What key term or concept matches this description?\n"$sentence"',
            options: const [],
            correctAnswer: term,
            explanation: 'The term being identified is "$term".',
            points: 1.0,
          ));
          break;

        case QuizQuestionType.enumeration:
          final enumList = candidateTerms.skip(i % candidateTerms.length).take(3).toList();
          if (enumList.length < 3) {
            enumList.addAll(candidateTerms.take(3 - enumList.length));
          }

          questions.add(QuizQuestion(
            id: 'q_$qIndex',
            type: QuizQuestionType.enumeration,
            question: isActual
                ? 'Enumerate ${enumList.length} key components, elements, or concepts discussed regarding:\n"$sentence"'
                : 'Practice Enumeration: List any ${enumList.length} key terms or factors covered in this section:',
            options: const [],
            correctAnswer: enumList.join(', '),
            enumerationAnswers: enumList,
            explanation: 'Expected items: ${enumList.join(", ")}.',
            points: enumList.length * 1.0,
          ));
          break;
      }
    }

    return questions;
  }
}
