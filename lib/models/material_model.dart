/// Represents a study material tracked in Supabase Postgres and Storage.
class MaterialModel {
  final String id;
  final String teacherId;
  final String classId;
  final String fileName;
  final String fileType; // 'pdf' | 'pptx' | 'docx'
  final String
  fileRef; // Storage path e.g. uploads/{teacherId}/{materialId}/{fileName}
  final String storageProvider;
  final String? storageBucket;
  final String? storageUploadStatus; // 'uploading' | 'completed' | 'failed'
  final String? downloadUrl; // Legacy direct download URL
  final String?
  convertedPdfRef; // Storage path of converted preview PDF (uploads/{teacherId}/{materialId}/preview.pdf)
  final String? convertedPdfUrl; // Download URL of converted preview PDF
  final String?
  conversionStatus; // 'pending' | 'completed' | 'failed' | 'unsupported'
  final DateTime? convertedAt;
  final String status; // 'pending' | 'processing' | 'ready' | 'failed'
  final String?
  errorReason; // 'no_extractable_text' | 'unsupported_format' | 'parse_error' | etc.
  final String extractedText;
  final DateTime createdAt;
  final DateTime? extractedAt;
  final int? fileSizeBytes;
  final bool isPosted;
  final DateTime? postedAt;

  const MaterialModel({
    required this.id,
    required this.teacherId,
    required this.classId,
    required this.fileName,
    required this.fileType,
    required this.fileRef,
    this.storageProvider = 'supabase',
    this.storageBucket,
    this.storageUploadStatus,
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
    this.isPosted = false,
    this.postedAt,
  });

  bool get isReady => status == 'ready';
  bool get isProcessing => status == 'processing' || status == 'pending';
  bool get hasFailed => status == 'failed';
  bool get isUploadInProgress => storageUploadStatus == 'uploading';
  bool get isUploadCompleted =>
      storageUploadStatus == 'completed' || storageUploadStatus == null;
  bool get canBePosted => isReady && isUploadCompleted;

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
        return errorReason ??
            'An unknown error occurred while extracting text from the document.';
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

  /// Standard MIME type for private object upload metadata.
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
    String? storageProvider,
    String? storageBucket,
    String? storageUploadStatus,
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
    bool? isPosted,
    DateTime? postedAt,
  }) {
    return MaterialModel(
      id: id ?? this.id,
      teacherId: teacherId ?? this.teacherId,
      classId: classId ?? this.classId,
      fileName: fileName ?? this.fileName,
      fileType: fileType ?? this.fileType,
      fileRef: fileRef ?? this.fileRef,
      storageProvider: storageProvider ?? this.storageProvider,
      storageBucket: storageBucket ?? this.storageBucket,
      storageUploadStatus: storageUploadStatus ?? this.storageUploadStatus,
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
      isPosted: isPosted ?? this.isPosted,
      postedAt: (isPosted ?? this.isPosted)
          ? (postedAt ?? this.postedAt)
          : null,
    );
  }

  /// Serialize to the app's domain map format.
  Map<String, dynamic> toMap() {
    return {
      'teacherId': teacherId,
      'classId': classId,
      'fileName': fileName,
      'fileType': fileType.toLowerCase(),
      'fileRef': fileRef,
      'storageProvider': storageProvider,
      if (storageBucket != null) 'storageBucket': storageBucket,
      if (storageUploadStatus != null)
        'storageUploadStatus': storageUploadStatus,
      if (downloadUrl != null) 'downloadUrl': downloadUrl,
      if (convertedPdfRef != null) 'convertedPdfRef': convertedPdfRef,
      if (convertedPdfUrl != null) 'convertedPdfUrl': convertedPdfUrl,
      if (conversionStatus != null) 'conversionStatus': conversionStatus,
      if (convertedAt != null)
        'convertedAt': convertedAt!.toUtc().toIso8601String(),
      'status': status,
      'errorReason': errorReason,
      'extractedText': extractedText,
      'createdAt': createdAt.toUtc().toIso8601String(),
      if (extractedAt != null)
        'extractedAt': extractedAt!.toUtc().toIso8601String(),
      if (fileSizeBytes != null) 'fileSizeBytes': fileSizeBytes,
      'isPosted': isPosted,
      if (postedAt != null) 'postedAt': postedAt!.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> toDatabaseMap() {
    return {
      'teacher_id': teacherId,
      'class_id': classId,
      'file_name': fileName,
      'file_type': fileType.toLowerCase(),
      'file_ref': fileRef,
      'storage_provider': storageProvider,
      if (storageBucket != null) 'storage_bucket': storageBucket,
      if (storageUploadStatus != null)
        'storage_upload_status': storageUploadStatus,
      if (downloadUrl != null) 'download_url': downloadUrl,
      if (convertedPdfRef != null) 'converted_pdf_ref': convertedPdfRef,
      if (convertedPdfUrl != null) 'converted_pdf_url': convertedPdfUrl,
      if (conversionStatus != null) 'conversion_status': conversionStatus,
      if (convertedAt != null)
        'converted_at': convertedAt!.toUtc().toIso8601String(),
      'status': status,
      'error_reason': errorReason,
      'extracted_text': extractedText,
      'created_at': createdAt.toUtc().toIso8601String(),
      if (extractedAt != null)
        'extracted_at': extractedAt!.toUtc().toIso8601String(),
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      'is_posted': isPosted,
      if (postedAt != null) 'posted_at': postedAt!.toUtc().toIso8601String(),
    };
  }

  /// Construct from either database or domain map keys.
  factory MaterialModel.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parseTimestamp(dynamic val) {
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    DateTime? parseOptionalTimestamp(dynamic val) {
      if (val == null) return null;
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    final rawIsPosted = map['is_posted'] ?? map['isPosted'];
    final isPostedBool =
        rawIsPosted == true || rawIsPosted == 'true' || rawIsPosted == 1;

    return MaterialModel(
      id: docId,
      teacherId: (map['teacher_id'] ?? map['teacherId'])?.toString() ?? '',
      classId: (map['class_id'] ?? map['classId'])?.toString() ?? '',
      fileName:
          (map['file_name'] ?? map['fileName'])?.toString() ??
          'Unnamed Material',
      fileType: ((map['file_type'] ?? map['fileType'])?.toString() ?? 'pdf')
          .toLowerCase(),
      fileRef: (map['file_ref'] ?? map['fileRef'])?.toString() ?? '',
      storageProvider:
          (map['storage_provider'] ?? map['storageProvider'])?.toString() ??
          'supabase',
      storageBucket: (map['storage_bucket'] ?? map['storageBucket'])
          ?.toString(),
      storageUploadStatus:
          (map['storage_upload_status'] ?? map['storageUploadStatus'])
              ?.toString(),
      downloadUrl: (map['download_url'] ?? map['downloadUrl'])?.toString(),
      convertedPdfRef: (map['converted_pdf_ref'] ?? map['convertedPdfRef'])
          ?.toString(),
      convertedPdfUrl: (map['converted_pdf_url'] ?? map['convertedPdfUrl'])
          ?.toString(),
      conversionStatus: (map['conversion_status'] ?? map['conversionStatus'])
          ?.toString(),
      convertedAt: (map['converted_at'] ?? map['convertedAt']) != null
          ? parseTimestamp(map['converted_at'] ?? map['convertedAt'])
          : null,
      status: (map['status'] as String?) ?? 'pending',
      errorReason: (map['error_reason'] ?? map['errorReason'])?.toString(),
      extractedText:
          (map['extracted_text'] ?? map['extractedText'])?.toString() ?? '',
      createdAt: parseTimestamp(map['created_at'] ?? map['createdAt']),
      extractedAt: (map['extracted_at'] ?? map['extractedAt']) != null
          ? parseTimestamp(map['extracted_at'] ?? map['extractedAt'])
          : null,
      fileSizeBytes: (map['file_size_bytes'] ?? map['fileSizeBytes']) is num
          ? ((map['file_size_bytes'] ?? map['fileSizeBytes']) as num).toInt()
          : null,
      isPosted: isPostedBool,
      postedAt: parseOptionalTimestamp(map['posted_at'] ?? map['postedAt']),
    );
  }
}
