import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/quiz_model.dart';

/// Service for generating clean, academic printable exam PDFs from Actual Quizzes.
class PdfExportService {
  /// Generates the raw PDF bytes for an academic exam paper.
  ///
  /// Features:
  /// - Student identification header (Name, Date, Section, Score)
  /// - Formatted question sections tailored to each of the 5 question types
  /// - Optional Teacher Answer Key page
  /// - Professional exam typography and layout
  Future<Uint8List> generateExamPdf({
    required QuizModel quiz,
    bool includeAnswerKey = true,
    String? className,
    String? teacherName,
  }) async {
    final pdf = pw.Document();

    final baseFont = pw.Font.helvetica();
    final boldFont = pw.Font.helveticaBold();
    final italicFont = pw.Font.helveticaOblique();

    // ── 1. Main Student Examination Pages ──────────────────────
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(
          base: baseFont,
          bold: boldFont,
          italic: italicFont,
        ),
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
        header: (pw.Context ctx) => _buildPageHeader(quiz, className, boldFont, italicFont),
        footer: (pw.Context ctx) => _buildPageFooter(ctx, boldFont),
        build: (pw.Context ctx) => [
          _buildExamStudentHeader(quiz, className, teacherName, boldFont),
          pw.SizedBox(height: 14),
          _buildExamInstructions(boldFont, italicFont),
          pw.SizedBox(height: 16),
          _buildQuestionsList(quiz.questions, boldFont, italicFont),
        ],
      ),
    );

    // ── 2. Teacher Answer Key Page (Optional) ──────────────────
    if (includeAnswerKey && quiz.questions.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(
            base: baseFont,
            bold: boldFont,
            italic: italicFont,
          ),
          margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
          header: (pw.Context ctx) => pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.red800, width: 1.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'CONFIDENTIAL - TEACHER ANSWER KEY & RUBRIC',
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 10,
                    color: PdfColors.red800,
                  ),
                ),
                pw.Text(
                  'NOT FOR STUDENT DISTRIBUTION',
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 9,
                    color: PdfColors.red800,
                  ),
                ),
              ],
            ),
          ),
          footer: (pw.Context ctx) => _buildPageFooter(ctx, boldFont),
          build: (pw.Context ctx) => [
            pw.SizedBox(height: 10),
            pw.Text(
              'Answer Key: ${quiz.title}',
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 16,
                color: PdfColors.blue900,
              ),
            ),
            pw.Text(
              'Total Questions: ${quiz.questions.length}  |  Total Points: ${quiz.totalPoints} pts  |  Exam Type: Actual Quiz',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 16),
            _buildAnswerKeyTable(quiz.questions, boldFont),
          ],
        ),
      );
    }

    return pdf.save();
  }

  /// Builds the running header on top of every page.
  pw.Widget _buildPageHeader(
    QuizModel quiz,
    String? className,
    pw.Font boldFont,
    pw.Font italicFont,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'STUDEXA ACADEMIC EXAMINATION',
            style: pw.TextStyle(
              font: boldFont,
              fontSize: 8,
              color: PdfColors.grey700,
            ),
          ),
          if (className != null && className.isNotEmpty)
            pw.Text(
              className,
              style: pw.TextStyle(
                font: italicFont,
                fontSize: 8,
                color: PdfColors.grey700,
              ),
            ),
        ],
      ),
    );
  }

  /// Builds running footer with page numbers.
  pw.Widget _buildPageFooter(pw.Context ctx, pw.Font boldFont) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400, width: 0.8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Turn Class Materials into Quizzes - Studexa',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
          pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: pw.TextStyle(font: boldFont, fontSize: 8, color: PdfColors.grey800),
          ),
        ],
      ),
    );
  }

  /// Builds the top exam identification header for students to write their details.
  pw.Widget _buildExamStudentHeader(
    QuizModel quiz,
    String? className,
    String? teacherName,
    pw.Font boldFont,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey800, width: 1.2),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Text(
              quiz.title.toUpperCase(),
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 14,
                color: PdfColors.black,
              ),
            ),
          ),
          if (className != null && className.isNotEmpty)
            pw.Center(
              child: pw.Text(
                'Class: $className${teacherName != null && teacherName.isNotEmpty ? '  |  Instructor: $teacherName' : ''}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
              ),
            ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Text(
                  'Name: ____________________________________________________',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
              pw.Expanded(
                flex: 2,
                child: pw.Text(
                  'Date: ____________________',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Text(
                  'Grade / Section: __________________________________________',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
              pw.Expanded(
                flex: 2,
                child: pw.Text(
                  'Score: _______ / ${quiz.totalPoints} pts',
                  style: pw.TextStyle(font: boldFont, fontSize: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds the general exam instructions box.
  pw.Widget _buildExamInstructions(pw.Font boldFont, pw.Font italicFont) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'GENERAL INSTRUCTIONS:',
            style: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.grey900),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Read each question carefully. Write legibly in the spaces provided. For multiple choice, mark your chosen option clearly.',
            style: pw.TextStyle(font: italicFont, fontSize: 8.5, color: PdfColors.grey800),
          ),
        ],
      ),
    );
  }

  /// Formats all questions with proper spacing and type-specific answering areas.
  pw.Widget _buildQuestionsList(
    List<QuizQuestion> questions,
    pw.Font boldFont,
    pw.Font italicFont,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < questions.length; i++) ...[
          _buildQuestionItem(questions[i], i + 1, boldFont, italicFont),
          pw.SizedBox(height: 14),
        ],
      ],
    );
  }

  /// Builds a single question with point tag and answering UI.
  pw.Widget _buildQuestionItem(
    QuizQuestion q,
    int number,
    pw.Font boldFont,
    pw.Font italicFont,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Question Header
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '$number. ',
              style: pw.TextStyle(font: boldFont, fontSize: 10.5),
            ),
            pw.Expanded(
              child: pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: q.question,
                      style: pw.TextStyle(font: boldFont, fontSize: 10.5, color: PdfColors.black),
                    ),
                    pw.TextSpan(
                      text: '  (${q.points} ${q.points == 1 ? 'pt' : 'pts'})',
                      style: pw.TextStyle(font: italicFont, fontSize: 9, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),

        // Type-specific answering format
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 16),
          child: _buildAnswerAreaForType(q, boldFont, italicFont),
        ),
      ],
    );
  }

  /// Builds specific answering fields based on question type.
  pw.Widget _buildAnswerAreaForType(
    QuizQuestion q,
    pw.Font boldFont,
    pw.Font italicFont,
  ) {
    switch (q.type) {
      case QuizQuestionType.multipleChoice:
        final options = q.options.isNotEmpty
            ? q.options
            : ['Option A', 'Option B', 'Option C', 'Option D'];
        const letters = ['A', 'B', 'C', 'D', 'E', 'F'];

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (int j = 0; j < options.length; j++) ...[
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                      width: 13,
                      height: 13,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey800, width: 0.8),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Text(
                      '${j < letters.length ? letters[j] : (j + 1)}.  ${options[j]}',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey900),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );

      case QuizQuestionType.trueFalse:
        return pw.Row(
          children: [
            pw.Container(
              width: 13,
              height: 13,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey800, width: 0.8),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
            ),
            pw.SizedBox(width: 6),
            pw.Text('TRUE', style: pw.TextStyle(font: boldFont, fontSize: 9.5)),
            pw.SizedBox(width: 32),
            pw.Container(
              width: 13,
              height: 13,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey800, width: 0.8),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
            ),
            pw.SizedBox(width: 6),
            pw.Text('FALSE', style: pw.TextStyle(font: boldFont, fontSize: 9.5)),
          ],
        );

      case QuizQuestionType.identification:
      case QuizQuestionType.fillInTheBlank:
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Row(
            children: [
              pw.Text('Answer: ', style: pw.TextStyle(font: boldFont, fontSize: 9.5)),
              pw.Expanded(
                child: pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: PdfColors.grey800, width: 0.8),
                    ),
                  ),
                  height: 14,
                ),
              ),
            ],
          ),
        );

      case QuizQuestionType.enumeration:
        final expectedCount = q.enumerationAnswers.isNotEmpty
            ? q.enumerationAnswers.length
            : 3;
        final linesToShow = expectedCount.clamp(2, 6);

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (int k = 1; k <= linesToShow; k++) ...[
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
                child: pw.Row(
                  children: [
                    pw.Text('$k. ', style: pw.TextStyle(font: boldFont, fontSize: 9.5)),
                    pw.Expanded(
                      child: pw.Container(
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                            bottom: pw.BorderSide(color: PdfColors.grey800, width: 0.8),
                          ),
                        ),
                        height: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
    }
  }

  /// Builds a clean, organized Answer Key table for teachers.
  pw.Widget _buildAnswerKeyTable(List<QuizQuestion> questions, pw.Font boldFont) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.6),
      columnWidths: const {
        0: pw.FixedColumnWidth(28), // #
        1: pw.FixedColumnWidth(85), // Type
        2: pw.FlexColumnWidth(3),   // Question Prompt
        3: pw.FlexColumnWidth(2),   // Correct Answer
        4: pw.FixedColumnWidth(40), // Points
      },
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _buildTableHeaderCell('#', boldFont, align: pw.TextAlign.center),
            _buildTableHeaderCell('Type', boldFont),
            _buildTableHeaderCell('Question', boldFont),
            _buildTableHeaderCell('Correct Answer / Rubric', boldFont),
            _buildTableHeaderCell('Pts', boldFont, align: pw.TextAlign.center),
          ],
        ),
        // Question rows
        for (int i = 0; i < questions.length; i++) ...[
          _buildTableRow(questions[i], i + 1, boldFont),
        ],
      ],
    );
  }

  pw.Widget _buildTableHeaderCell(
    String text,
    pw.Font boldFont, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(font: boldFont, fontSize: 8.5, color: PdfColors.grey900),
      ),
    );
  }

  pw.TableRow _buildTableRow(QuizQuestion q, int index, pw.Font boldFont) {
    String answerDisplay;
    if (q.type == QuizQuestionType.enumeration) {
      if (q.enumerationAnswers.isNotEmpty) {
        answerDisplay = q.enumerationAnswers
            .asMap()
            .entries
            .map((e) => '${e.key + 1}. ${e.value}')
            .join('\n');
      } else {
        answerDisplay = q.correctAnswer;
      }
    } else {
      answerDisplay = q.correctAnswer;
    }

    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: index % 2 == 0 ? PdfColors.grey50 : PdfColors.white,
      ),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(
            '$index',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: boldFont, fontSize: 8.5),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(
            q.type.displayName,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(
            q.question,
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(
            answerDisplay,
            style: pw.TextStyle(font: boldFont, fontSize: 8, color: PdfColors.blue900),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(
            '${q.points}',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
      ],
    );
  }

  /// Triggers standard printing dialog or PDF export preview via [Printing.layoutPdf].
  Future<void> printOrShareExam({
    required BuildContext context,
    required QuizModel quiz,
    bool includeAnswerKey = true,
    String? className,
    String? teacherName,
  }) async {
    final cleanTitle = quiz.title.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final fileName = '${cleanTitle}_Exam.pdf';

    await Printing.layoutPdf(
      name: fileName,
      onLayout: (PdfPageFormat format) async {
        return generateExamPdf(
          quiz: quiz,
          includeAnswerKey: includeAnswerKey,
          className: className,
          teacherName: teacherName,
        );
      },
    );
  }
}
