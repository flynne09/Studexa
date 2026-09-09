import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:archive/archive.dart';
import 'package:studexa/services/quiz_service.dart';
import 'package:studexa/utils/document_text_extractor.dart';

void main() {
  group('DocumentTextExtractor — PDF, PPTX, and DOCX Accuracy & Resiliency Tests', () {
    test('1. PDF Extraction: Extracts readable multi-line sentences across pages with proper baseline grouping', () async {
      // Create a valid multi-page academic PDF
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Cellular Respiration & ATP Synthesis', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text('Cellular respiration is the biochemical pathway by which cells harvest energy stored in glucose molecules.'),
              pw.Text('The overall chemical equation yields carbon dioxide, water, and approximately 36 to 38 molecules of ATP.'),
            ],
          ),
        ),
      );
      pdf.addPage(
        pw.Page(
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Glycolysis in the Cytoplasm', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text('Glycolysis breaks down one six-carbon glucose into two three-carbon pyruvate molecules without requiring oxygen.'),
              pw.Text('A net production of 2 ATP and 2 NADH molecules is achieved during substrate-level phosphorylation.'),
            ],
          ),
        ),
      );

      final pdfBytes = Uint8List.fromList(await pdf.save());
      final extracted = await DocumentTextExtractor.extractText(
        bytes: pdfBytes,
        extension: 'pdf',
      );

      // Verify text is extracted cleanly as sentences/lines, not individual words on separate lines
      expect(extracted.contains('Cellular Respiration & ATP Synthesis'), true);
      expect(extracted.contains('harvest energy stored in'), true);
      expect(extracted.contains('glucose molecules.'), true);
      expect(extracted.contains('Glycolysis in the Cytoplasm'), true);
      expect(extracted.contains('substrate-level'), true);
      expect(extracted.contains('phosphorylation.'), true);
      expect(DocumentTextExtractor.isMeaningfulText(extracted), true);
    });

    test('2. PPTX Extraction: Extracts all slides in numerical order, supports Windows paths, merges split runs, and extracts notes', () async {
      final archive = Archive();

      // Slide 1 (Windows backslash path + split runs)
      const slide1Xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:txBody>
          <a:p>
            <a:r><a:t>Introduction to Cellular </a:t></a:r>
            <a:r><a:t>Biology</a:t></a:r>
          </a:p>
          <a:p>
            <a:r><a:t>Mito</a:t></a:r>
            <a:r><a:t>chondria</a:t></a:r>
            <a:r><a:t> are the primary ATP synthesis powerhouses.</a:t></a:r>
          </a:p>
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>''';

      // Slide 2 (Standard forward slash path)
      const slide2Xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:txBody>
          <a:p>
            <a:r><a:t>The Citric Acid Cycle</a:t></a:r>
          </a:p>
          <a:p>
            <a:r><a:t>Pyruvate is oxidized to acetyl-CoA inside the mitochondrial matrix.</a:t></a:r>
          </a:p>
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>''';

      // Slide 10 (Checks numerical sorting so slide 2 precedes slide 10)
      const slide10Xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:txBody>
          <a:p>
            <a:r><a:t>Final Exam Review &amp; Summary</a:t></a:r>
          </a:p>
          <a:p>
            <a:r><a:t>Chemiosmosis drives ATP synthase via the proton motive force.</a:t></a:r>
          </a:p>
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>''';

      // Slide 1 speaker notes
      const notesSlide1Xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:txBody>
          <a:p>
            <a:r><a:t>Professor note: Emphasize the double membrane structure of mitochondria during lecture.</a:t></a:r>
          </a:p>
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:notes>''';

      archive.addFile(ArchiveFile(r'ppt\slides\slide1.xml', utf8.encode(slide1Xml).length, utf8.encode(slide1Xml)));
      archive.addFile(ArchiveFile(r'ppt/slides/slide2.xml', utf8.encode(slide2Xml).length, utf8.encode(slide2Xml)));
      archive.addFile(ArchiveFile(r'ppt\slides\slide10.xml', utf8.encode(slide10Xml).length, utf8.encode(slide10Xml)));
      archive.addFile(ArchiveFile(r'ppt\notesSlides\notesSlide1.xml', utf8.encode(notesSlide1Xml).length, utf8.encode(notesSlide1Xml)));

      final encoder = ZipEncoder();
      final pptxBytes = Uint8List.fromList(encoder.encode(archive));

      final extracted = await DocumentTextExtractor.extractText(
        bytes: pptxBytes,
        extension: 'pptx',
      );

      // Verify word split runs were merged properly without extraneous spaces
      expect(extracted.contains('Introduction to Cellular Biology'), true);
      expect(extracted.contains('Mitochondria are the primary ATP synthesis powerhouses'), true);

      // Verify slide 2 is extracted before slide 10 (numerical sort, not alphabetical)
      final posSlide2 = extracted.indexOf('The Citric Acid Cycle');
      final posSlide10 = extracted.indexOf('Final Exam Review & Summary');
      expect(posSlide2 != -1, true);
      expect(posSlide10 != -1, true);
      expect(posSlide2 < posSlide10, true);

      // Verify speaker notes are extracted
      expect(extracted.contains('Professor note: Emphasize the double membrane structure'), true);
      expect(DocumentTextExtractor.isMeaningfulText(extracted), true);
    });

    test('3. DOCX Extraction: Correctly parses paragraph blocks and XML entities', () async {
      final archive = Archive();
      const docxXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r><w:t>Unit 3: Photosynthesis &amp; Cellular Respiration</w:t></w:r>
    </w:p>
    <w:p>
      <w:r><w:t>Plants convert sunlight into chemical energy via the light-dependent and light-independent Calvin cycle reactions.</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';

      archive.addFile(ArchiveFile(r'word\document.xml', utf8.encode(docxXml).length, utf8.encode(docxXml)));
      final encoder = ZipEncoder();
      final docxBytes = Uint8List.fromList(encoder.encode(archive));

      final extracted = await DocumentTextExtractor.extractText(
        bytes: docxBytes,
        extension: 'docx',
      );

      expect(extracted.contains('Unit 3: Photosynthesis & Cellular Respiration'), true);
      expect(extracted.contains('Calvin cycle reactions'), true);
      expect(DocumentTextExtractor.isMeaningfulText(extracted), true);
    });

    test('4. Empty / Near-Empty Failure State: isMeaningfulText rejects blank, corrupt, or boilerplate strings', () {
      expect(DocumentTextExtractor.isMeaningfulText(''), false);
      expect(DocumentTextExtractor.isMeaningfulText('    \n\t  '), false);
      expect(DocumentTextExtractor.isMeaningfulText('Page 1'), false);
      expect(DocumentTextExtractor.isMeaningfulText('Document Title'), false);
      expect(
        DocumentTextExtractor.isMeaningfulText(
          'Mitochondria produce ATP through aerobic respiration and the electron transport chain.',
        ),
        true,
      );
    });

    test('5. PowerPoint-Exported PDF (research_ppt_export.pdf): Extracts cleanly despite /Outlines null and generates questions', () async {
      final file = File('test/fixtures/sample_materials/research_ppt_export.pdf');
      expect(file.existsSync(), true, reason: 'Test fixture research_ppt_export.pdf must exist');

      final bytes = file.readAsBytesSync();
      final extracted = await DocumentTextExtractor.extractText(
        bytes: bytes,
        extension: 'pdf',
      );

      // Verify character count > 5,000 and passes meaningful text test
      expect(extracted.length, greaterThan(5000));
      expect(DocumentTextExtractor.isMeaningfulText(extracted), true);

      // Verify core phrases from slides are preserved
      expect(extracted.contains('Bohol Island State University'), true);
      expect(extracted.contains('METHODS'), true);
      expect(extracted.contains('DR. DARYL B. VALDEZ'), true);
      expect(extracted.contains('INTRODUCTION TO'), true);
      expect(extracted.contains('RESEARCH IN COMPUTER'), true);

      // Verify quiz generation generates valid questions from the extracted text
      final questions = QuizService.generateLocalFallbackQuestions(
        extractedText: extracted,
        questionTypes: ['multipleChoice', 'identification'],
        questionCount: 5,
        isActual: false,
      );

      expect(questions.isNotEmpty, true);
      expect(questions.length, greaterThanOrEqualTo(3));
      for (final q in questions) {
        expect(q.question.isNotEmpty, true);
        expect(q.correctAnswer.isNotEmpty, true);
      }
    });

    test('6. Genuinely Blank / Image-Only PDF: Returns no_extractable_text, NOT parse_error', () async {
      // Create a structurally valid PDF with a blank container (no text operators)
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          build: (ctx) => pw.Center(
            child: pw.Container(width: 200, height: 200),
          ),
        ),
      );

      final blankBytes = Uint8List.fromList(await pdf.save());
      final result = await DocumentTextExtractor.extract(
        bytes: blankBytes,
        extension: 'pdf',
      );

      expect(result.isSuccess, false);
      expect(result.errorReason, 'no_extractable_text');
      expect(result.text, isEmpty);
    });

    test('7. Corrupted Files: Returns parse_error for unparseable PDF, DOCX, and PPTX', () async {
      // Corrupted PDF (invalid header/structure)
      final corruptPdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x00, 0xFF, 0xFE, 0xFD]);
      final pdfResult = await DocumentTextExtractor.extract(
        bytes: corruptPdfBytes,
        extension: 'pdf',
      );
      expect(pdfResult.isSuccess, false);
      expect(pdfResult.errorReason, 'parse_error');

      // Corrupted DOCX (truncated/invalid zip header)
      final corruptDocxBytes = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0xDE, 0xAD, 0xBE, 0xEF]);
      final docxResult = await DocumentTextExtractor.extract(
        bytes: corruptDocxBytes,
        extension: 'docx',
      );
      expect(docxResult.isSuccess, false);
      expect(docxResult.errorReason, 'parse_error');

      // Corrupted PPTX (truncated/invalid zip header)
      final corruptPptxBytes = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0xCA, 0xFE, 0xBA, 0xBE]);
      final pptxResult = await DocumentTextExtractor.extract(
        bytes: corruptPptxBytes,
        extension: 'pptx',
      );
      expect(pptxResult.isSuccess, false);
      expect(pptxResult.errorReason, 'parse_error');
    });

    test('8. Structured Result on Valid Materials: Returns isSuccess true with accurate text', () async {
      final file = File('test/fixtures/sample_materials/research_ppt_export.pdf');
      final bytes = file.readAsBytesSync();

      final result = await DocumentTextExtractor.extract(
        bytes: bytes,
        extension: 'pdf',
      );

      expect(result.isSuccess, true);
      expect(result.errorReason, isNull);
      expect(result.text.length, greaterThan(5000));
      expect(result.text.contains('METHODS OF RESEARCH'), true);
    });

    test('9. Full Regression Suite: Verify research_ppt_export, blank/image-only, corrupt documents, and DOCX/PPTX fixtures', () async {
      // 1. Valid presentation export (research_ppt_export.pdf)
      final pptExportFile = File('test/fixtures/sample_materials/research_ppt_export.pdf');
      final pptExportBytes = pptExportFile.readAsBytesSync();
      final validResult = await DocumentTextExtractor.extract(
        bytes: pptExportBytes,
        extension: 'pdf',
      );
      expect(validResult.isSuccess, true);
      expect(validResult.errorReason, isNull);
      expect(validResult.text.length, greaterThan(5000));

      // Verify quiz generation works from extracted text
      final questions = QuizService.generateLocalFallbackQuestions(
        extractedText: validResult.text,
        questionTypes: ['multipleChoice', 'trueFalse', 'identification'],
        questionCount: 3,
        isActual: false,
      );
      expect(questions.length, 3);
      for (final q in questions) {
        expect(q.question.isNotEmpty, true);
        expect(q.correctAnswer.isNotEmpty, true);
      }

      // 2. Structurally valid blank/image-only PDF
      final pdf = pw.Document();
      pdf.addPage(pw.Page(build: (ctx) => pw.Container()));
      final blankBytes = Uint8List.fromList(await pdf.save());
      final blankResult = await DocumentTextExtractor.extract(
        bytes: blankBytes,
        extension: 'pdf',
      );
      expect(blankResult.isSuccess, false);
      expect(blankResult.errorReason, 'no_extractable_text');

      // 3. Corrupt PDF bytes
      final corruptPdfResult = await DocumentTextExtractor.extract(
        bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x00, 0xAA, 0xBB]),
        extension: 'pdf',
      );
      expect(corruptPdfResult.isSuccess, false);
      expect(corruptPdfResult.errorReason, 'parse_error');

      // 4. Corrupt DOCX bytes
      final corruptDocxResult = await DocumentTextExtractor.extract(
        bytes: Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0xFF, 0xEE]),
        extension: 'docx',
      );
      expect(corruptDocxResult.isSuccess, false);
      expect(corruptDocxResult.errorReason, 'parse_error');

      // 5. Corrupt PPTX bytes
      final corruptPptxResult = await DocumentTextExtractor.extract(
        bytes: Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0x11, 0x22]),
        extension: 'pptx',
      );
      expect(corruptPptxResult.isSuccess, false);
      expect(corruptPptxResult.errorReason, 'parse_error');
    });
  });
}
