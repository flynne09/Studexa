import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a study material uploaded by a teacher to Firebase Storage,
/// tracked in Firestore `materials/{materialId}` and extracted by Cloud Functions.
class MaterialModel {
  final String id;
  final String teacherId;
  final String classId;
  final String fileName;
  final String fileType; // 'pdf' | 'pptx' | 'docx'
  final String fileRef; // Storage path e.g. uploads/{teacherId}/{materialId}/{fileName}
  final String? downloadUrl; // Direct download URL when stored in Firebase Storage
  final String? convertedPdfRef; // Storage path of converted preview PDF (uploads/{teacherId}/{materialId}/preview.pdf)
  final String? convertedPdfUrl; // Download URL of converted preview PDF
  final String? conversionStatus; // 'pending' | 'completed' | 'failed' | 'unsupported'
  final DateTime? convertedAt;
  final String status; // 'pending' | 'processing' | 'ready' | 'failed'
  final String? errorReason; // 'no_extractable_text' | 'unsupported_format' | 'parse_error' | etc.
  final String extractedText;
  final DateTime createdAt;
  final DateTime? extractedAt;
  final int? fileSizeBytes;

  const MaterialModel({
    required this.id,
    required this.teacherId,
    required this.classId,
    required this.fileName,
    required this.fileType,
    required this.fileRef,
    this.downloadUrl,
    this.convertedPdfRef,
    this.convertedPdfUrl,
    this.conversionStatus,
    this.convertedAt,
    required this.status,
    this.errorReason,
    this.extractedText = '',
    required this.createdAt,
    this.extractedAt,
    this.fileSizeBytes,
  });

  bool get isReady => status == 'ready';
  bool get isProcessing => status == 'processing' || status == 'pending';
  bool get hasFailed => status == 'failed';

  /// In-app preview availability
  bool get hasConvertedPdf =>
      conversionStatus == 'completed' &&
      ((convertedPdfUrl != null && convertedPdfUrl!.isNotEmpty) ||
          (convertedPdfRef != null && convertedPdfRef!.isNotEmpty));
  bool get isConverting => conversionStatus == 'pending';
  bool get conversionFailed => conversionStatus == 'failed';

  /// Human-readable explanation of error reasons matching Cloud Function codes
  String get formattedError {
    switch (errorReason) {
      case 'no_extractable_text':
        return 'No extractable text found in this file. Please ensure the document contains readable text and is not a scanned image (OCR is not supported in Phase 1).';
      case 'unsupported_format':
        return 'Unsupported format. Please select a valid PDF, PPTX, or DOCX document.';
      case 'parse_error':
        return 'This file couldn\'t be processed — try re-exporting it or use a different format.';
      case 'file_too_large':
        return 'The uploaded file exceeds the 50MB maximum size limit.';
      case 'empty_file':
        return 'The selected file is empty (0 bytes).';
      case 'file_bytes_unavailable':
        return 'Original document file is unavailable in storage. Please re-upload the document.';
      default:
        return errorReason ?? 'An unknown error occurred while extracting text from the document.';
    }
  }

  /// Alias for formattedError
  String get userFriendlyErrorReason => formattedError;

  /// Format file size for UI display
  String get formattedFileSize {
    if (fileSizeBytes == null || fileSizeBytes! <= 0) return '';
    if (fileSizeBytes! < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes! < 1024 * 1024) {
      return '${(fileSizeBytes! / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Standard MIME type for Firebase Storage upload metadata
  String get contentType => contentTypeForExtension(fileType);

  /// Map extension to MIME type for Storage upload metadata
  static String contentTypeForExtension(String extension) {
    switch (extension.toLowerCase().replaceAll('.', '').trim()) {
      case 'pdf':
        return 'application/pdf';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default:
        return 'application/octet-stream';
    }
  }

  /// Create a copy with selected fields overridden
  MaterialModel copyWith({
    String? id,
    String? teacherId,
    String? classId,
    String? fileName,
    String? fileType,
    String? fileRef,
    String? downloadUrl,
    String? convertedPdfRef,
    String? convertedPdfUrl,
    String? conversionStatus,
    DateTime? convertedAt,
    String? status,
    String? errorReason,
    String? extractedText,
    DateTime? createdAt,
    DateTime? extractedAt,
    int? fileSizeBytes,
  }) {
    return MaterialModel(
      id: id ?? this.id,
      teacherId: teacherId ?? this.teacherId,
      classId: classId ?? this.classId,
      fileName: fileName ?? this.fileName,
      fileType: fileType ?? this.fileType,
      fileRef: fileRef ?? this.fileRef,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      convertedPdfRef: convertedPdfRef ?? this.convertedPdfRef,
      convertedPdfUrl: convertedPdfUrl ?? this.convertedPdfUrl,
      conversionStatus: conversionStatus ?? this.conversionStatus,
      convertedAt: convertedAt ?? this.convertedAt,
      status: status ?? this.status,
      errorReason: errorReason ?? this.errorReason,
      extractedText: extractedText ?? this.extractedText,
      createdAt: createdAt ?? this.createdAt,
      extractedAt: extractedAt ?? this.extractedAt,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    );
  }

  /// Serialize to Firestore map format
  Map<String, dynamic> toMap() {
    return {
      'teacherId': teacherId,
      'classId': classId,
      'fileName': fileName,
      'fileType': fileType.toLowerCase(),
      'fileRef': fileRef,
      if (downloadUrl != null) 'downloadUrl': downloadUrl,
      if (convertedPdfRef != null) 'convertedPdfRef': convertedPdfRef,
      if (convertedPdfUrl != null) 'convertedPdfUrl': convertedPdfUrl,
      if (conversionStatus != null) 'conversionStatus': conversionStatus,
      if (convertedAt != null) 'convertedAt': Timestamp.fromDate(convertedAt!),
      'status': status,
      'errorReason': errorReason,
      'extractedText': extractedText,
      'createdAt': Timestamp.fromDate(createdAt),
      if (extractedAt != null) 'extractedAt': Timestamp.fromDate(extractedAt!),
      if (fileSizeBytes != null) 'fileSizeBytes': fileSizeBytes,
    };
  }

  /// Construct from Firestore map
  factory MaterialModel.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return MaterialModel(
      id: docId,
      teacherId: (map['teacherId'] as String?) ?? '',
      classId: (map['classId'] as String?) ?? '',
      fileName: (map['fileName'] as String?) ?? 'Unnamed Material',
      fileType: ((map['fileType'] as String?) ?? 'pdf').toLowerCase(),
      fileRef: (map['fileRef'] as String?) ?? '',
      downloadUrl: map['downloadUrl'] as String?,
      convertedPdfRef: map['convertedPdfRef'] as String?,
      convertedPdfUrl: map['convertedPdfUrl'] as String?,
      conversionStatus: map['conversionStatus'] as String?,
      convertedAt: map['convertedAt'] != null
          ? parseTimestamp(map['convertedAt'])
          : null,
      status: (map['status'] as String?) ?? 'pending',
      errorReason: map['errorReason'] as String?,
      extractedText: (map['extractedText'] as String?) ?? '',
      createdAt: parseTimestamp(map['createdAt']),
      extractedAt: map['extractedAt'] != null
          ? parseTimestamp(map['extractedAt'])
          : null,
      fileSizeBytes: map['fileSizeBytes'] as int?,
    );
  }
}
