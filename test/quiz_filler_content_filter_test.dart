import 'package:flutter_test/flutter_test.dart';
import 'package:studexa/models/quiz_model.dart';
import 'package:studexa/services/quiz_service.dart';

void main() {
  group('Task 6 — Filter Irrelevant & Filler Content in Quiz Generation', () {
    test('1. QuizService.isFillerOrBoilerplateQuestion accurately flags non-academic questions and answers', () {
      // Copyright / licensing
      final qCopyright = QuizQuestion(
        id: 'q1',
        type: QuizQuestionType.multipleChoice,
        question: 'What is the copyright notice of this presentation?',
        options: ['A. All rights reserved', 'B. Creative Commons', 'C. Public Domain', 'D. MIT'],
        correctAnswer: 'A. All rights reserved',
        explanation: 'Copyright notice',
      );
      expect(QuizService.isFillerOrBoilerplateQuestion(qCopyright), isTrue);

      // Author / instructor info
      final qInstructor = QuizQuestion(
        id: 'q2',
        type: QuizQuestionType.identification,
        question: 'Who is the instructor for this computer science class?',
        options: [],
        correctAnswer: 'Dr. Turing',
        explanation: 'Instructor name',
      );
      expect(QuizService.isFillerOrBoilerplateQuestion(qInstructor), isTrue);

      // Email address in answer
      final qEmail = QuizQuestion(
        id: 'q3',
        type: QuizQuestionType.fillInTheBlank,
        question: 'For office hours, contact the professor at _______.',
        options: [],
        correctAnswer: 'professor@university.edu',
        explanation: 'Email address',
      );
      expect(QuizService.isFillerOrBoilerplateQuestion(qEmail), isTrue);

      // Document metadata (slide/page)
      final qSlide = QuizQuestion(
        id: 'q4',
        type: QuizQuestionType.multipleChoice,
        question: 'On Slide 4, what diagram was presented?',
        options: ['A. Architecture', 'B. Pipeline', 'C. Cache', 'D. Register'],
        correctAnswer: 'A. Architecture',
        explanation: 'Slide metadata question',
      );
      expect(QuizService.isFillerOrBoilerplateQuestion(qSlide), isTrue);

      // Lecture boilerplate phrases
      final qWelcome = QuizQuestion(
        id: 'q5',
        type: QuizQuestionType.fillInTheBlank,
        question: 'Welcome to _______, where we will study modern operating systems.',
        options: [],
        correctAnswer: 'CS 301',
        explanation: 'Lecture intro boilerplate',
      );
      expect(QuizService.isFillerOrBoilerplateQuestion(qWelcome), isTrue);

      // Administrative syllabus / grading
      final qGrading = QuizQuestion(
        id: 'q6',
        type: QuizQuestionType.multipleChoice,
        question: 'According to the syllabus, what percentage of the grade is the final exam?',
        options: ['A. 20%', 'B. 30%', 'C. 40%', 'D. 50%'],
        correctAnswer: 'C. 40%',
        explanation: 'Grading policy question',
      );
      expect(QuizService.isFillerOrBoilerplateQuestion(qGrading), isTrue);

      // Legitimate academic questions must NOT be flagged
      final qAcademic1 = QuizQuestion(
        id: 'q7',
        type: QuizQuestionType.multipleChoice,
        question: 'Which page replacement algorithm evicts the page that has not been used for the longest period of time?',
        options: ['A. Least Recently Used', 'B. First In First Out', 'C. Optimal', 'D. Clock'],
        correctAnswer: 'A. Least Recently Used',
        explanation: 'Core concept in OS memory management',
      );
      expect(QuizService.isFillerOrBoilerplateQuestion(qAcademic1), isFalse);

      final qAcademic2 = QuizQuestion(
        id: 'q8',
        type: QuizQuestionType.fillInTheBlank,
        question: 'Photosynthesis converts solar energy into chemical energy stored in _______ molecules.',
        options: [],
        correctAnswer: 'glucose',
        explanation: 'Core biological concept',
      );
      expect(QuizService.isFillerOrBoilerplateQuestion(qAcademic2), isFalse);
    });

    test('2. Sample Material 1: Course presentation with header/footer boilerplate produces 0 filler questions', () {
      const sample1 = '''
Welcome to CS 301: Advanced Operating Systems!
Instructor: Dr. Alan Turing (email: aturing@cambridge.edu)
Office Hours: Mondays 2:00 PM - 4:00 PM in Room 302
All rights reserved. Copyright 2024 Cambridge University Press.
Slide 1: Introduction to Virtual Memory
Virtual memory is a memory management technique that provides an idealized abstraction of storage resources.
Page replacement algorithms determine which memory pages to evict when allocating new physical frames.
Thrashing occurs when a computer system spends more time servicing page faults than executing instructions.
Demand paging loads pages into main memory only when they are referenced during process execution.
The translation lookaside buffer caches recent virtual-to-physical address mappings.
Thank you for attending today's lecture. Any questions?
''';

      final questions = QuizService.generateLocalFallbackQuestions(
        extractedText: sample1,
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

      final forbiddenKeywords = [
        'turing', 'aturing@', 'cambridge', 'copyright', 'all rights reserved',
        'office hours', 'welcome', 'thank you', 'any questions', 'slide 1',
        'room 302', 'cs 301', 'email', 'instructor',
      ];

      for (final q in questions) {
        expect(
          QuizService.isFillerOrBoilerplateQuestion(q),
          isFalse,
          reason: 'Question should not be flagged as filler: "${q.question}"',
        );

        final lowerQ = q.question.toLowerCase();
        final lowerA = q.correctAnswer.toLowerCase();

        for (final kw in forbiddenKeywords) {
          expect(
            lowerQ.contains(kw),
            isFalse,
            reason: 'Question stem contains boilerplate "$kw": "${q.question}"',
          );
          expect(
            lowerA.contains(kw),
            isFalse,
            reason: 'Answer contains boilerplate "$kw": "${q.correctAnswer}"',
          );
        }
      }
    });

    test('3. Sample Material 2: Textbook chapter with publication metadata and licensing produces 0 filler questions', () {
      const sample2 = '''
Biochemistry: Principles and Mechanisms, 5th Edition
ISBN 978-0-123456-78-9. Published in 2023. Licensed under Creative Commons BY-NC 4.0.
Authors: Dr. Rosalind Franklin and Dr. Francis Crick (rfranklin@kings.ac.uk)
Chapter 4: Photosynthesis and Energy Transformation
Photosynthesis converts light energy into chemical energy stored in covalent glucose bonds.
Chloroplasts contain thylakoid membranes where light-dependent reactions take place.
Chlorophyll pigments absorb blue and red light wavelengths while reflecting green light.
The Calvin cycle takes place inside the stroma and synthesizes carbohydrates from carbon dioxide.
Adenosine triphosphate provides the free energy required for endergonic biosynthetic reactions.
Summary of today's chapter and further reading on page 412. References and acknowledgments.
''';

      final questions = QuizService.generateLocalFallbackQuestions(
        extractedText: sample2,
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

      final forbiddenKeywords = [
        'franklin', 'crick', 'isbn', 'creative commons', 'published in 2023',
        'chapter 4', 'page 412', 'further reading', 'references',
        'acknowledgments', 'edition', 'summary of today',
      ];

      for (final q in questions) {
        expect(
          QuizService.isFillerOrBoilerplateQuestion(q),
          isFalse,
          reason: 'Question should not be flagged as filler: "${q.question}"',
        );

        final lowerQ = q.question.toLowerCase();
        final lowerA = q.correctAnswer.toLowerCase();

        for (final kw in forbiddenKeywords) {
          expect(
            lowerQ.contains(kw),
            isFalse,
            reason: 'Question stem contains boilerplate "$kw": "${q.question}"',
          );
          expect(
            lowerA.contains(kw),
            isFalse,
            reason: 'Answer contains boilerplate "$kw": "${q.correctAnswer}"',
          );
        }
      }
    });

    test('4. Sample Material 3: Lecture notes with syllabus policies produces 0 filler questions', () {
      const sample3 = '''
Biology 101 Lecture Notes — Fall 2024
Grading Policy: Midterm 30%, Final Exam 40%, Homework Assignments 30%.
Homework due date is Friday at 11:59 PM via the course portal.
Cellular respiration oxidizes glucose molecules to generate ATP in eukaryotic organisms.
Glycolysis is the initial metabolic pathway that splits glucose into two molecules of pyruvate.
The citric acid cycle operates inside the mitochondrial matrix to produce electron carriers.
Oxidative phosphorylation utilizes the electron transport chain to synthesize large quantities of ATP.
Enzymes lower the activation energy barrier required for biochemical transitions.
Acknowledgments: Special thanks to teaching assistants for preparing these notes.
''';

      final questions = QuizService.generateLocalFallbackQuestions(
        extractedText: sample3,
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

      final forbiddenKeywords = [
        'grading policy', 'midterm 30%', 'final exam 40%', 'homework',
        'due date', 'course portal', 'fall 2024', 'acknowledgments',
        'biology 101', 'lecture notes',
      ];

      for (final q in questions) {
        expect(
          QuizService.isFillerOrBoilerplateQuestion(q),
          isFalse,
          reason: 'Question should not be flagged as filler: "${q.question}"',
        );

        final lowerQ = q.question.toLowerCase();
        final lowerA = q.correctAnswer.toLowerCase();

        for (final kw in forbiddenKeywords) {
          expect(
            lowerQ.contains(kw),
            isFalse,
            reason: 'Question stem contains boilerplate "$kw": "${q.question}"',
          );
          expect(
            lowerA.contains(kw),
            isFalse,
            reason: 'Answer contains boilerplate "$kw": "${q.correctAnswer}"',
          );
        }
      }
    });

    test('5. QuizService.validateAndDeduplicateQuestions purges filler questions and backfills with academic concepts', () {
      final candidateQuestions = [
        QuizQuestion(
          id: 'q1',
          type: QuizQuestionType.multipleChoice,
          question: 'What is the professor email address according to the syllabus?',
          options: ['A. prof@cambridge.edu', 'B. info@university.edu', 'C. help@college.edu', 'D. admin@school.edu'],
          correctAnswer: 'A. prof@cambridge.edu',
          explanation: 'Filler question',
        ),
        QuizQuestion(
          id: 'q2',
          type: QuizQuestionType.multipleChoice,
          question: 'Which organelle is known as the powerhouse of the cell?',
          options: ['A. Mitochondria', 'B. Ribosome', 'C. Nucleus', 'D. Chloroplast'],
          correctAnswer: 'A. Mitochondria',
          explanation: 'Core concept',
        ),
      ];

      final validated = QuizService.validateAndDeduplicateQuestions(
        candidateQuestions,
        targetCount: 2,
        extractedText: 'Mitochondria generate ATP. Ribosomes synthesize proteins.',
        questionTypes: ['multipleChoice'],
        isActual: false,
      );

      expect(validated.length, 2);
      expect(validated.any((q) => q.question.contains('email') || q.correctAnswer.contains('@')), isFalse);
      for (final q in validated) {
        expect(QuizService.isFillerOrBoilerplateQuestion(q), isFalse);
      }
    });
  });
}
