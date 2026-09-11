import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Structured result of document text extraction.
/// Accurately differentiates successful extraction from empty/scanned documents
/// ('no_extractable_text') and corrupted/unparseable files ('parse_error').
class DocumentExtractionResult {
  /// The extracted readable text content, or empty string if extraction failed.
  final String text;

  /// Whether extraction succeeded and produced meaningful readable text.
  final bool isSuccess;

  /// Standard error reason code matching MaterialModel:
  /// - 'no_extractable_text': document was parsed but contains no readable text (e.g. scanned image / blank)
  /// - 'parse_error': file is corrupt, malformed, encrypted, or parser crashed
  /// - 'unsupported_format': format is not supported
  /// - 'empty_file': file contains 0 bytes
  final String? errorReason;

  /// Diagnostic error or debug message for logging and inspection.
  final String? errorMessage;

  const DocumentExtractionResult({
    required this.text,
    required this.isSuccess,
    this.errorReason,
    this.errorMessage,
  });

  /// Factory for successful extraction with meaningful text.
  factory DocumentExtractionResult.success(String text) => DocumentExtractionResult(
        text: text,
        isSuccess: true,
      );

  /// Factory for failed extraction with a specific error reason.
  factory DocumentExtractionResult.failure({
    required String errorReason,
    String? errorMessage,
  }) =>
      DocumentExtractionResult(
        text: '',
        isSuccess: false,
        errorReason: errorReason,
        errorMessage: errorMessage,
      );
}

/// Client-side text extraction engine for PDF, DOCX, and PPTX documents.
/// Provides immediate, offline-resilient document text extraction directly on
/// the user's device without blocking on un-deployed Cloud Functions or storage buckets.
class DocumentTextExtractor {
  /// Extracts text and returns a structured result distinguishing successful extraction,
  /// empty/scanned documents ('no_extractable_text'), and parsing/corruption failures ('parse_error').
  static Future<DocumentExtractionResult> extract({
    required Uint8List bytes,
    required String extension,
  }) async {
    if (bytes.isEmpty) {
      return DocumentExtractionResult.failure(
        errorReason: 'empty_file',
        errorMessage: 'The file contains 0 bytes.',
      );
    }

    final cleanExt = extension.toLowerCase().replaceAll('.', '').trim();

    switch (cleanExt) {
      case 'pdf':
        return _extractPdfWithResult(bytes);
      case 'docx':
        return _extractDocxWithResult(bytes);
      case 'pptx':
        return _extractPptxWithResult(bytes);
      case 'txt':
        return _extractTxtWithResult(bytes);
      default:
        return DocumentExtractionResult.failure(
          errorReason: 'unsupported_format',
          errorMessage: 'Unsupported file extension: $cleanExt',
        );
    }
  }

  /// Extracts plain text from the given document bytes based on its extension.
  /// Throws [ArgumentError] on unsupported file extensions for backward compatibility.
  static Future<String> extractText({
    required Uint8List bytes,
    required String extension,
  }) async {
    final cleanExt = extension.toLowerCase().replaceAll('.', '').trim();
    if (!['pdf', 'docx', 'pptx', 'txt'].contains(cleanExt)) {
      throw ArgumentError('Unsupported file extension: $cleanExt');
    }
    final result = await extract(bytes: bytes, extension: extension);
    return result.text;
  }

  /// Checks if the extracted text contains meaningful readable educational content.
  /// Rejects empty, whitespace-only, or pure boilerplate strings.
  static bool isMeaningfulText(String text) {
    final trimmed = text.trim();
    if (trimmed.length < 25) return false;
    final words = RegExp(r'[a-zA-Z0-9]{2,}').allMatches(trimmed);
    return words.length >= 5;
  }

  /// Sanitizes raw PDF bytes to prevent crashes in third-party parsers (e.g. Syncfusion)
  /// caused by null dictionary values such as `/Outlines null` (common in Canva and
  /// PowerPoint PDF exports). Replaces null dictionary entries with whitespace of exact
  /// equal length to preserve cross-reference table byte offsets.
  static Uint8List _sanitizePdfBytes(Uint8List bytes) {
    final latin1Str = latin1.decode(bytes, allowInvalid: true);
    if (!latin1Str.contains('/Outlines') &&
        !latin1Str.contains('/AcroForm') &&
        !latin1Str.contains('/StructTreeRoot') &&
        !latin1Str.contains('/MarkInfo')) {
      return bytes;
    }

    final patterns = [
      RegExp(r'/Outlines\s+null'),
      RegExp(r'/AcroForm\s+null'),
      RegExp(r'/StructTreeRoot\s+null'),
      RegExp(r'/MarkInfo\s+null'),
    ];

    bool modified = false;
    Uint8List? workingBytes;

    for (final pattern in patterns) {
      final matches = pattern.allMatches(latin1Str);
      for (final match in matches) {
        workingBytes ??= Uint8List.fromList(bytes);
        modified = true;
        for (int i = match.start; i < match.end; i++) {
          workingBytes[i] = 0x20; // ASCII space
        }
      }
    }

    return modified ? workingBytes! : bytes;
  }

  /// Extracts text from PDF bytes using Syncfusion PDF Text Extractor
  /// with pre-sanitization, line-aware grouping, multi-page baseline reconstruction,
  /// resilient page-by-page recovery, and stream decompression fallback for non-standard PDFs.
  static DocumentExtractionResult _extractPdfWithResult(Uint8List bytes) {
    final sanitizedBytes = _sanitizePdfBytes(bytes);
    PdfDocument? document;
    Object? initError;

    // 1. Initialize PdfDocument with pre-sanitized bytes (or original fallback)
    try {
      document = PdfDocument(inputBytes: sanitizedBytes);
    } catch (e) {
      initError = e;
      try {
        document = PdfDocument(inputBytes: bytes);
      } catch (origError) {
        initError = origError;
        debugPrint('PdfDocument initialization error with sanitized bytes: $e');
        debugPrint('PdfDocument initialization error with original bytes: $origError');
      }
    }

    // 2. Extract using Syncfusion parser if document was created
    if (document != null) {
      Object? extractorError;
      try {
        final textExtractor = PdfTextExtractor(document);

        // 2a. Primary: Syncfusion line-aware extractor across all pages
        try {
          final textLines = textExtractor.extractTextLines();
          if (textLines.isNotEmpty) {
            final buffer = StringBuffer();
            for (final line in textLines) {
              final t = line.text.trim();
              if (t.isNotEmpty) buffer.writeln(t);
            }
            final cleaned = _cleanText(buffer.toString());
            if (isMeaningfulText(cleaned)) {
              return DocumentExtractionResult.success(cleaned);
            }
          }
        } catch (lineError) {
          debugPrint('Syncfusion extractTextLines encountered: $lineError. Trying block extractor.');
        }

        // 2b. Secondary: full-document block extractor
        try {
          final extractedText = textExtractor.extractText();
          final cleanedBlock = _cleanText(extractedText);
          if (isMeaningfulText(cleanedBlock)) {
            return DocumentExtractionResult.success(cleanedBlock);
          }
        } catch (blockError) {
          debugPrint('Syncfusion extractText encountered: $blockError. Trying page-by-page extraction.');
        }

        // 2c. Tertiary: Resilient page-by-page extraction
        // Prevents one heavy, unsupported, or corrupt page from sinking the whole document
        final pageBuffer = StringBuffer();
        for (int p = 0; p < document.pages.count; p++) {
          try {
            final pageText = textExtractor.extractText(startPageIndex: p, endPageIndex: p);
            if (pageText.trim().isNotEmpty) {
              pageBuffer.writeln(pageText.trim());
            }
          } catch (pageError) {
            debugPrint('Page $p extraction skipped due to error: $pageError');
          }
        }

        final accumulated = _cleanText(pageBuffer.toString());
        if (isMeaningfulText(accumulated)) {
          return DocumentExtractionResult.success(accumulated);
        }
      } catch (e) {
        extractorError = e;
        debugPrint('Syncfusion text extractor general error: $e');
      } finally {
        try {
          document.dispose();
        } catch (_) {}
      }

      // 3. Resilient fallback: scan and decompress raw PDF streams (FlateDecode)
      try {
        final streamText = _scanPdfStreams(sanitizedBytes);
        if (isMeaningfulText(streamText)) {
          return DocumentExtractionResult.success(streamText);
        }
      } catch (streamError) {
        debugPrint('PDF raw stream scanner encountered error: $streamError');
      }

      // If text extractor crashed with a general exception and stream scanning couldn't extract anything,
      // the document's internal objects or font encodings are corrupt/unreadable.
      if (extractorError != null) {
        return DocumentExtractionResult.failure(
          errorReason: 'parse_error',
          errorMessage: 'PDF text extractor encountered an error: $extractorError',
        );
      }

      // Valid PDF document was parsed and inspected cleanly, but contains no extractable text
      // (e.g. scanned image, photographs, or empty pages)
      return DocumentExtractionResult.failure(
        errorReason: 'no_extractable_text',
        errorMessage: 'Valid PDF structure parsed successfully but contains no readable text or is a scanned image.',
      );
    }

    // Document could not be opened (corrupt xref, invalid header, password-protected, etc.)
    // Try raw stream scan as a last resort
    try {
      final streamText = _scanPdfStreams(sanitizedBytes);
      if (isMeaningfulText(streamText)) {
        return DocumentExtractionResult.success(streamText);
      }
    } catch (streamError) {
      debugPrint('PDF raw stream scanner fallback error: $streamError');
    }

    // Genuinely corrupt or unparseable PDF file
    return DocumentExtractionResult.failure(
      errorReason: 'parse_error',
      errorMessage: 'Could not parse PDF document structure: $initError',
    );
  }

  /// Scans raw PDF bytes for FlateDecode / plain content streams and extracts text operators.
  static String _scanPdfStreams(Uint8List bytes) {
    final buffer = StringBuffer();
    final latin1String = latin1.decode(bytes, allowInvalid: true);

    int searchIdx = 0;
    while (searchIdx < bytes.length) {
      final streamStartMatch = latin1String.indexOf('stream', searchIdx);
      if (streamStartMatch == -1) break;

      int dataStart = streamStartMatch + 6;
      if (dataStart < bytes.length && bytes[dataStart] == 0x0D) dataStart++;
      if (dataStart < bytes.length && bytes[dataStart] == 0x0A) dataStart++;

      final streamEndMatch = latin1String.indexOf('endstream', dataStart);
      if (streamEndMatch == -1 || streamEndMatch <= dataStart) {
        searchIdx = dataStart;
        continue;
      }

      final streamBytes = bytes.sublist(dataStart, streamEndMatch);
      searchIdx = streamEndMatch + 9;

      List<int>? decompressed;
      try {
        decompressed = ZLibDecoder().decodeBytes(streamBytes);
      } catch (_) {
        decompressed = streamBytes;
      }

      final content = latin1.decode(decompressed, allowInvalid: true);
      _extractTextFromPdfStreamContent(content, buffer);
    }

    return _cleanText(buffer.toString());
  }

  /// Extracts text from decompressed PDF stream commands: (text) Tj, [(t) ... (ext)] TJ
  static void _extractTextFromPdfStreamContent(String content, StringBuffer buffer) {
    final arrayMatches = RegExp(r'\[(.*?)\]\s*TJ', dotAll: true).allMatches(content);
    for (final arrMatch in arrayMatches) {
      final inner = arrMatch.group(1) ?? '';
      final strMatches = RegExp(r'\((.*?)\)').allMatches(inner);
      for (final s in strMatches) {
        final t = _unescapePdfString(s.group(1) ?? '');
        if (t.isNotEmpty) buffer.write('$t ');
      }
      buffer.writeln();
    }

    final simpleMatches = RegExp(r'\(([^()]{2,})\)\s*Tj').allMatches(content);
    for (final m in simpleMatches) {
      final t = _unescapePdfString(m.group(1) ?? '');
      if (t.isNotEmpty && !t.startsWith('/')) {
        buffer.writeln(t);
      }
    }
  }

  static String _unescapePdfString(String input) {
    return input
        .replaceAll(r'\(', '(')
        .replaceAll(r'\)', ')')
        .replaceAll(r'\\', r'\')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '')
        .trim();
  }

  /// Extracts text from DOCX (Office Open XML ZIP format)
  static DocumentExtractionResult _extractDocxWithResult(Uint8List bytes) {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      return DocumentExtractionResult.failure(
        errorReason: 'parse_error',
        errorMessage: 'Failed to decompress DOCX ZIP archive: $e',
      );
    }

    // Find main document (handle both / and \ paths)
    ArchiveFile docFile;
    try {
      docFile = archive.files.firstWhere(
        (f) => f.name.replaceAll('\\', '/').toLowerCase() == 'word/document.xml',
        orElse: () => archive.files.firstWhere(
          (f) => f.name.replaceAll('\\', '/').toLowerCase().endsWith('document.xml'),
        ),
      );
    } catch (_) {
      return DocumentExtractionResult.failure(
        errorReason: 'parse_error',
        errorMessage: 'DOCX archive missing word/document.xml',
      );
    }

    try {
      final buffer = StringBuffer();
      final content = utf8.decode(_getFileBytes(docFile), allowMalformed: true);
      final bodyText = _extractOpenXmlParagraphs(content);
      if (bodyText.isNotEmpty) {
        buffer.writeln(bodyText);
      }

      // Check footnotes/endnotes
      final notesFiles = archive.files.where((f) {
        final normalized = f.name.replaceAll('\\', '/').toLowerCase();
        return normalized == 'word/footnotes.xml' || normalized == 'word/endnotes.xml';
      });
      for (final note in notesFiles) {
        final noteContent = utf8.decode(_getFileBytes(note), allowMalformed: true);
        final noteText = _extractOpenXmlParagraphs(noteContent);
        if (noteText.isNotEmpty) {
          buffer.writeln(noteText);
        }
      }

      final cleaned = _cleanText(buffer.toString());
      if (isMeaningfulText(cleaned)) {
        return DocumentExtractionResult.success(cleaned);
      } else {
        return DocumentExtractionResult.failure(
          errorReason: 'no_extractable_text',
          errorMessage: 'DOCX parsed successfully but contains no meaningful readable text.',
        );
      }
    } catch (e) {
      return DocumentExtractionResult.failure(
        errorReason: 'parse_error',
        errorMessage: 'Failed parsing DOCX XML contents: $e',
      );
    }
  }

  /// Extracts text from PPTX (Office Open XML ZIP format) across all slides in order
  static DocumentExtractionResult _extractPptxWithResult(Uint8List bytes) {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      return DocumentExtractionResult.failure(
        errorReason: 'parse_error',
        errorMessage: 'Failed to decompress PPTX ZIP archive: $e',
      );
    }

    try {
      final buffer = StringBuffer();

      // 1. Find all slide XML files (normalized path for Windows/Unix compatibility)
      final slideFiles = archive.files.where((f) {
        final normalized = f.name.replaceAll('\\', '/').toLowerCase();
        return RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(normalized);
      }).toList();

      if (slideFiles.isEmpty) {
        final isPresentation = archive.files.any(
          (f) => f.name.replaceAll('\\', '/').toLowerCase().startsWith('ppt/'),
        );
        if (!isPresentation) {
          return DocumentExtractionResult.failure(
            errorReason: 'parse_error',
            errorMessage: 'Archive does not contain PowerPoint structure.',
          );
        }
      }

      // Sort numerically by slide number (e.g. slide1, slide2, ..., slide10)
      slideFiles.sort((a, b) {
        final numA = _extractSlideNumber(a.name);
        final numB = _extractSlideNumber(b.name);
        return numA.compareTo(numB);
      });

      for (final slide in slideFiles) {
        final content = utf8.decode(_getFileBytes(slide), allowMalformed: true);
        final slideText = _extractOpenXmlParagraphs(content);
        if (slideText.isNotEmpty) {
          final slideNum = _extractSlideNumber(slide.name);
          buffer.writeln('--- Slide $slideNum ---');
          buffer.writeln(slideText);
          buffer.writeln();
        }
      }

      // 2. Extract speaker / lecture notes if present
      final notesFiles = archive.files.where((f) {
        final normalized = f.name.replaceAll('\\', '/').toLowerCase();
        return RegExp(r'^ppt/notesslides/notesslide\d+\.xml$').hasMatch(normalized);
      }).toList()
        ..sort((a, b) => _extractSlideNumber(a.name).compareTo(_extractSlideNumber(b.name)));

      for (final note in notesFiles) {
        final content = utf8.decode(_getFileBytes(note), allowMalformed: true);
        final noteText = _extractOpenXmlParagraphs(content);
        if (noteText.isNotEmpty) {
          final slideNum = _extractSlideNumber(note.name);
          buffer.writeln('--- Slide $slideNum Notes ---');
          buffer.writeln(noteText);
          buffer.writeln();
        }
      }

      // 3. Extract diagrams / SmartArt if present
      final diagramFiles = archive.files.where((f) {
        final normalized = f.name.replaceAll('\\', '/').toLowerCase();
        return RegExp(r'^ppt/diagrams/data\d+\.xml$').hasMatch(normalized);
      }).toList();

      for (final diag in diagramFiles) {
        final content = utf8.decode(_getFileBytes(diag), allowMalformed: true);
        final diagText = _extractOpenXmlParagraphs(content);
        if (diagText.isNotEmpty) {
          buffer.writeln(diagText);
          buffer.writeln();
        }
      }

      final cleaned = _cleanText(buffer.toString());
      if (isMeaningfulText(cleaned)) {
        return DocumentExtractionResult.success(cleaned);
      } else {
        return DocumentExtractionResult.failure(
          errorReason: 'no_extractable_text',
          errorMessage: 'PPTX parsed successfully but contains no meaningful readable text.',
        );
      }
    } catch (e) {
      return DocumentExtractionResult.failure(
        errorReason: 'parse_error',
        errorMessage: 'Failed parsing PPTX XML contents: $e',
      );
    }
  }

  /// Extracts integer slide number from paths like 'ppt/slides/slide3.xml' or 'ppt\slides\slide10.xml'
  static int _extractSlideNumber(String path) {
    final match = RegExp(r'slide(\d+)\.xml', caseSensitive: false).firstMatch(path);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

  /// Extracts plain text from OpenXML paragraphs (e.g. `<a:p>` or `<w:p>`),
  /// combining consecutive runs within a paragraph without extra spaces,
  /// and separating distinct paragraphs with newlines.
  static String _extractOpenXmlParagraphs(String xml) {
    final buffer = StringBuffer();

    // Match paragraph blocks: <a:p>...</a:p> or <w:p>...</w:p>
    final paragraphMatches = RegExp(
      r'<(?:[a-zA-Z0-9]+:)?p(?:[^>]*)>(.*?)</(?:[a-zA-Z0-9]+:)?p>',
      dotAll: true,
    ).allMatches(xml);

    if (paragraphMatches.isNotEmpty) {
      for (final pMatch in paragraphMatches) {
        final pContent = pMatch.group(1) ?? '';
        final line = _extractOpenXmlRuns(pContent);
        if (line.isNotEmpty) {
          buffer.writeln(line);
        }
      }
    } else {
      // Fallback: extract any text tags if no paragraph tags found
      final fallbackLine = _extractOpenXmlRuns(xml);
      if (fallbackLine.isNotEmpty) {
        buffer.writeln(fallbackLine);
      }
    }

    return buffer.toString().trim();
  }

  /// Extracts text runs within an OpenXML block: `<a:t>...</a:t>` or `<w:t>...</w:t>`
  static String _extractOpenXmlRuns(String xml) {
    final textMatches = RegExp(
      r'<(?:[a-zA-Z0-9]+:)?t(?:[^>]*)>(.*?)</(?:[a-zA-Z0-9]+:)?t>',
      dotAll: true,
    ).allMatches(xml);

    final lineBuffer = StringBuffer();
    for (final match in textMatches) {
      final raw = match.group(1);
      if (raw != null && raw.isNotEmpty) {
        final decoded = _decodeXmlEntities(raw);
        lineBuffer.write(decoded);
      }
    }

    return lineBuffer.toString().trim();
  }

  /// Decodes basic XML entity references
  static String _decodeXmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  /// Safely extracts raw byte content from an ArchiveFile
  static List<int> _getFileBytes(ArchiveFile file) {
    return file.content;
  }

  /// Extracts text from plain text files
  static DocumentExtractionResult _extractTxtWithResult(Uint8List bytes) {
    try {
      final text = _cleanText(utf8.decode(bytes, allowMalformed: true));
      final isMeaningful = isMeaningfulText(text);
      return DocumentExtractionResult(
        text: text,
        isSuccess: isMeaningful,
        errorReason: isMeaningful ? null : 'no_extractable_text',
        errorMessage: isMeaningful
            ? null
            : 'Text file contains no meaningful readable educational content.',
      );
    } catch (e) {
      return DocumentExtractionResult.failure(
        errorReason: 'parse_error',
        errorMessage: 'Failed to decode text file: $e',
      );
    }
  }

  /// Set of structural table / column header keywords commonly found in data grids.
  static final Set<String> _structuralHeaderKeywords = {
    'no', 'no.', 'num', 'num.', 'number', 'name', 'attribute', 'attributes',
    'value', 'values', 'field', 'fields', 'col', 'column', 'header', 'row',
    'description', 'remarks', 'category', 'categories', 'status', 'type',
    'types', 'item', 'items', 'parameter', 'parameters', 'date', 'key',
    'default', 'null', 'extra',
  };

  /// Strips table header artifacts and data grid structural labels from extracted text,
  /// preserving factual content inside table cells while preventing structural headers
  /// from leaking into generated questions.
  static String stripTableHeaderArtifacts(String text) {
    final lines = text.split('\n');
    final cleanedLines = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        cleanedLines.add(line);
        continue;
      }

      // Check 1: Standalone column or header indicators: "Column A", "Header 1", "Column 2:", "Table 1:"
      if (RegExp(r'^(?:Column|Header|Col|Row)\s+[A-Za-z0-9]+:?$', caseSensitive: false).hasMatch(trimmed)) {
        continue;
      }
      if (RegExp(r'^Table\s+\d+:?$', caseSensitive: false).hasMatch(trimmed)) {
        continue;
      }

      // Check 2: Pure sequence of column labels: "Column A | Column B | Column C" or "Header 1 \t Header 2"
      if (RegExp(r'^(?:(?:Column|Header|Col)\s+[A-Za-z0-9]+(?:\s*[\|\:\t\,]\s*|\s{2,}))+(?:(?:Column|Header|Col)\s+[A-Za-z0-9]+)?$', caseSensitive: false).hasMatch(trimmed)) {
        continue;
      }

      // Check 3: Multi-column structural header row separated by delimiters (|, \t, multiple spaces, commas)
      // e.g. "No. | Name | Attribute | Value" or "Field | Type | Null | Key | Default"
      if (trimmed.contains('|') || trimmed.contains('\t') || trimmed.contains(RegExp(r'\s{2,}')) || (trimmed.contains(',') && !trimmed.contains('.'))) {
        final segments = trimmed
            .split(RegExp(r'[\|\t]|\s{2,}|,'))
            .map((s) => s.trim().toLowerCase())
            .where((s) => s.isNotEmpty)
            .toList();

        if (segments.length >= 2) {
          int matchingHeaders = 0;
          for (final seg in segments) {
            final cleanedSeg = seg.replaceAll(RegExp(r'[^a-z0-9\.]'), '').trim();
            final isColHeader = RegExp(r'^(?:column|header|col|row)[a-z0-9]*$').hasMatch(cleanedSeg) ||
                RegExp(r'^(?:column|header|col|row)\s+[a-z0-9]+$').hasMatch(seg);
            if (_structuralHeaderKeywords.contains(cleanedSeg) || isColHeader) {
              matchingHeaders++;
            }
          }

          // If at least 60% of segments and at least 2 are structural header keywords, it's a table header line
          if (matchingHeaders >= 2 && matchingHeaders >= (segments.length * 0.6)) {
            continue;
          }
        }
      }

      cleanedLines.add(line);
    }

    return cleanedLines.join('\n');
  }

  /// Cleans and normalizes extracted text, stripping table header artifacts
  /// and structural data grid markers so questions are grounded in academic concepts.
  static String _cleanText(String text) {
    var cleaned = text
        .replaceAll(RegExp(r'\r\n|\r'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');

    cleaned = stripTableHeaderArtifacts(cleaned);

    return cleaned.trim();
  }
}
