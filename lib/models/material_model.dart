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

  /// Human-readable explanation of error reasons matching Cloud Function codes
  String get formattedError {
    switch (errorReason) {
      case 'no_extractable_text':
        return 'No extractable text found in this file. Please ensure the document contains readable text and is not a scanned image (OCR is not supported in Phase 1).';
      case 'unsupported_format':
        return 'Unsupported format. Please select a valid PDF, PPTX, or DOCX document.';
      case 'parse_error':
        return 'Parse error encountered while reading the document. The file may be corrupt or encrypted.';
      case 'file_too_large':
        return 'The uploaded file exceeds the 50MB maximum size limit.';
      case 'empty_file':
        return 'The selected file is empty (0 bytes).';
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
  String get contentType {
    switch (fileType.toLowerCase()) {
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
