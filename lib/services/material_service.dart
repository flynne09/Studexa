import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/material_model.dart';
import '../utils/document_text_extractor.dart';

/// Exception thrown when study material validation or processing fails.
class MaterialValidationException implements Exception {
  final String message;
  const MaterialValidationException(this.message);

  @override
  String toString() => message;
}

/// Represents the possible outcomes when preparing or downloading a study material file.
enum MaterialDownloadStatus {
  ready,
  uploadInProgress,
  uploadFailed,
  unavailable,
  unsupportedPlatform,
  failed,
}

/// Encapsulates the status, local [File] reference, and user-facing message
/// resulting from a study material download/preparation request.
class MaterialDownloadResult {
  final MaterialDownloadStatus status;
  final File? file;
  final String message;

  const MaterialDownloadResult({
    required this.status,
    required this.message,
    this.file,
  });

  /// Returns `true` if the material was downloaded to a valid local [file] and is ready to open.
  bool get isReady => status == MaterialDownloadStatus.ready && file != null;
}

/// Service handling on-device material extraction, Supabase Storage
/// persistence, and real-time Supabase tracking.
class MaterialService {
  final SupabaseClient? _injectedSupabase;

  /// Creates a [MaterialService] with an optional injected [SupabaseClient] for testing.
  MaterialService({SupabaseClient? supabase}) : _injectedSupabase = supabase;

  /// Returns the configured [SupabaseClient] or throws [MaterialValidationException]
  /// if Supabase credentials have not been provided in the build configuration.
  SupabaseClient get _supabase {
    if (_injectedSupabase != null) return _injectedSupabase;
    if (!SupabaseConfig.isConfigured) {
      throw const MaterialValidationException(
        'File storage is not configured yet. Add the Supabase URL and publishable key to the app run configuration, then restart Studexa.',
      );
    }
    return Supabase.instance.client;
  }

  static const int maxFileSizeBytes = 50 * 1024 * 1024; // 50MB
  static const Set<String> supportedExtensions = {'pdf', 'pptx', 'docx'};

  /// Validate file parameters before initiating upload
  static void validateFile({
    required String fileName,
    required String extension,
    required int byteLength,
  }) {
    final cleanExt = extension.toLowerCase().replaceAll('.', '').trim();
    if (fileName.trim().isEmpty ||
        fileName.contains('/') ||
        fileName.contains('\\')) {
      throw const MaterialValidationException(
        'Choose a document with a valid file name.',
      );
    }

    if (!supportedExtensions.contains(cleanExt)) {
      throw MaterialValidationException(
        'Unsupported file format ".$cleanExt". Studexa supports PDF, PPTX, and DOCX documents only.',
      );
    }

    if (byteLength <= 0) {
      throw const MaterialValidationException(
        'The selected file is empty (0 bytes). Please choose a valid document.',
      );
    }

    if (byteLength > maxFileSizeBytes) {
      final sizeMb = (byteLength / (1024 * 1024)).toStringAsFixed(1);
      throw MaterialValidationException(
        'The file size ($sizeMb MB) exceeds the 50 MB upload limit. Please select a smaller file.',
      );
    }
  }

  /// Validate upload parameters including target class before initiating upload
  static void validateUploadRequest({
    required String classId,
    required String fileName,
    required String extension,
    required int byteLength,
  }) {
    final cleanClassId = classId.trim();
    if (cleanClassId.isEmpty) {
      throw const MaterialValidationException(
        'A target class must be selected before uploading study materials.',
      );
    }
    validateFile(
      fileName: fileName,
      extension: extension,
      byteLength: byteLength,
    );
  }

  /// Uploads a study material file, extracts text on-device immediately,
  /// and writes the ready material directly to Postgres.
  /// Supabase Storage upload is non-blocking so original-file network latency
  /// never delays the ready extracted text used for quiz generation.
  Future<MaterialModel> uploadStudyMaterial({
    required String teacherId,
    required String classId,
    required String fileName,
    required String fileExtension,
    required int byteLength,
    Uint8List? fileBytes,
    String? localFilePath,
    void Function(double progress)? onProgress,
  }) async {
    final cleanExt = fileExtension.toLowerCase().replaceAll('.', '').trim();
    final cleanClassId = classId.trim();

    // 1. Client-side pre-validation
    validateUploadRequest(
      classId: cleanClassId,
      fileName: fileName,
      extension: cleanExt,
      byteLength: byteLength,
    );

    // Ensure bytes are available
    Uint8List? resolvedBytes = fileBytes;
    if (resolvedBytes == null && localFilePath != null && !kIsWeb) {
      try {
        final localFile = File(localFilePath);
        if (await localFile.exists()) {
          resolvedBytes = await localFile.readAsBytes();
        }
      } catch (e) {
        debugPrint('Could not read local file bytes: $e');
      }
    }

    if (teacherId.trim().isEmpty) {
      throw const MaterialValidationException(
        'Please sign in before uploading a document.',
      );
    }
    if (resolvedBytes == null) {
      throw const MaterialValidationException(
        'The file could not be opened. Select it again and check that it is still accessible.',
      );
    }
    validateFile(
      fileName: fileName,
      extension: cleanExt,
      byteLength: resolvedBytes.length,
    );

    // Missing build-time configuration is not a recoverable background upload
    // failure. Stop here so the UI does not report a material as uploaded when
    // no Supabase request could have been made.
    final SupabaseClient supabase = _supabase;

    // 2. Prepare the database ID and storage path up front.
    final materialId = _uuidV4();
    final storageFileName = _safeStorageFileName(fileName);
    final storagePath = 'uploads/$teacherId/$materialId/$storageFileName';

    // 3. Initiate Supabase Storage upload concurrently with text extraction.
    Future<void>? uploadFuture;
    try {
      onProgress?.call(0.0);
      uploadFuture = supabase.storage
          .from(SupabaseConfig.storageBucket)
          .uploadBinary(
            storagePath,
            resolvedBytes,
            fileOptions: FileOptions(
              contentType: MaterialModel.contentTypeForExtension(cleanExt),
              upsert: false,
            ),
          )
          .timeout(const Duration(seconds: 90))
          .then<void>((_) {});
    } catch (e) {
      debugPrint('Supabase upload task initiation note: $e');
    }

    // 4. Perform client-side text extraction concurrently while bytes are streaming to Storage
    String extractedText = '';
    String? errorReason;
    bool isExtracted = false;

    if (resolvedBytes.isNotEmpty) {
      try {
        final extractionResult = await DocumentTextExtractor.extract(
          bytes: resolvedBytes,
          extension: cleanExt,
        );
        if (extractionResult.isSuccess) {
          extractedText = extractionResult.text;
          isExtracted = true;
        } else {
          errorReason = extractionResult.errorReason ?? 'no_extractable_text';
        }
      } catch (e) {
        debugPrint('Client text extraction warning: $e');
        errorReason = 'parse_error';
      }
    } else {
      errorReason = 'empty_file';
    }

    final String initialStatus = isExtracted ? 'ready' : 'failed';

    // 5. Write the ready database row immediately.
    final readyModel = MaterialModel(
      id: materialId,
      teacherId: teacherId,
      classId: cleanClassId,
      fileName: fileName,
      fileType: cleanExt,
      fileRef: storagePath,
      storageProvider: 'supabase',
      storageBucket: SupabaseConfig.storageBucket,
      storageUploadStatus: uploadFuture == null ? 'failed' : 'uploading',
      status: initialStatus,
      errorReason: errorReason,
      extractedText: extractedText,
      conversionStatus: cleanExt == 'pdf' ? 'completed' : 'unsupported',
      createdAt: DateTime.now(),
      fileSizeBytes: resolvedBytes.length,
    );

    final insertPayload = <String, dynamic>{
      'id': materialId,
      ...readyModel.toDatabaseMap(),
      if (isExtracted) 'extracted_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      try {
        await _supabase
            .from('materials')
            .insert(insertPayload)
            .timeout(const Duration(seconds: 15));
      } on PostgrestException catch (pe) {
        if (pe.code == '42703' &&
            (pe.message.contains('is_posted') ||
                pe.message.contains('posted_at'))) {
          debugPrint(
            'Supabase materials table missing is_posted column, falling back to legacy schema: ${pe.message}',
          );
          final legacyPayload = Map<String, dynamic>.from(insertPayload)
            ..remove('is_posted')
            ..remove('posted_at');
          await _supabase
              .from('materials')
              .insert(legacyPayload)
              .timeout(const Duration(seconds: 15));
        } else {
          rethrow;
        }
      }
    } catch (e, st) {
      debugPrint('Material Postgres insert error: $e\n$st');
      if (uploadFuture != null) {
        unawaited(
          uploadFuture.then(
            (_) => _deleteSupabaseFiles([storagePath]),
            onError: (_) {},
          ),
        );
      }
      if (e is PostgrestException) {
        if (e.code == '42501' ||
            e.message.toLowerCase().contains('row-level security') ||
            e.message.toLowerCase().contains('permission denied')) {
          throw const MaterialValidationException(
            'You do not have permission to upload materials to this class.',
          );
        }
        throw MaterialValidationException(
          'Could not save material: ${e.message}',
        );
      }
      if (e is MaterialValidationException) {
        rethrow;
      }
      throw const MaterialValidationException(
        'Could not save this material. Check your Internet connection and try again.',
      );
    }

    // 6. Record background upload completion without persisting an expiring URL.
    if (uploadFuture != null) {
      unawaited(() async {
        try {
          await uploadFuture;
          await _supabase
              .from('materials')
              .update({'storage_upload_status': 'completed'})
              .eq('id', materialId)
              .timeout(const Duration(seconds: 10));
        } catch (storageErr) {
          debugPrint('Background Supabase upload note: $storageErr');
          try {
            await _supabase
                .from('materials')
                .update({'storage_upload_status': 'failed'})
                .eq('id', materialId)
                .timeout(const Duration(seconds: 10));
          } catch (updateErr) {
            debugPrint('Could not record Supabase upload failure: $updateErr');
          }
        } finally {
          onProgress?.call(1.0);
        }
      }());
    } else {
      onProgress?.call(1.0);
    }

    return readyModel;
  }

  /// Fetch raw bytes from Supabase, with legacy URL support for old records.
  Future<Uint8List?> getMaterialFileBytes(MaterialModel material) async {
    // 1. Preserve access to archived records that have a direct download URL.
    if (material.downloadUrl != null && material.downloadUrl!.isNotEmpty) {
      try {
        final response = await http
            .get(Uri.parse(material.downloadUrl!))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          return response.bodyBytes;
        }
      } catch (e) {
        debugPrint('Failed to download material via downloadUrl: $e');
      }
    }

    // 2. New records use their private Supabase bucket and object path.
    if (material.storageProvider == 'supabase' && material.fileRef.isNotEmpty) {
      try {
        final bytes = await _supabase.storage
            .from(material.storageBucket ?? SupabaseConfig.storageBucket)
            .download(material.fileRef)
            .timeout(const Duration(seconds: 30));
        if (bytes.isNotEmpty) {
          return bytes;
        }
      } catch (e) {
        debugPrint('Failed to fetch material bytes from Supabase: $e');
      }
    }

    return null;
  }

  /// Fetch raw bytes for a converted preview PDF (via download URL or directly from Storage)
  Future<Uint8List?> getConvertedPdfBytes(MaterialModel material) async {
    // 1. Try convertedPdfUrl via HTTP
    if (material.convertedPdfUrl != null &&
        material.convertedPdfUrl!.isNotEmpty) {
      try {
        final response = await http
            .get(Uri.parse(material.convertedPdfUrl!))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          return response.bodyBytes;
        }
      } catch (e) {
        debugPrint('Failed to download converted PDF via convertedPdfUrl: $e');
      }
    }

    // 2. New converted previews, if added later, can also live in Supabase.
    if (material.convertedPdfRef != null &&
        material.convertedPdfRef!.isNotEmpty &&
        material.storageProvider == 'supabase') {
      try {
        final bytes = await _supabase.storage
            .from(material.storageBucket ?? SupabaseConfig.storageBucket)
            .download(material.convertedPdfRef!)
            .timeout(const Duration(seconds: 30));
        if (bytes.isNotEmpty) {
          return bytes;
        }
      } catch (e) {
        debugPrint('Failed to fetch converted PDF from Supabase: $e');
      }
    }

    return null;
  }

  /// Download a material to a uniquely named temporary file for native apps.
  /// Returns a structured result so the UI can distinguish an unfinished
  /// upload, a failed upload, a missing object, and a local write failure.
  Future<MaterialDownloadResult> prepareMaterialForExternalOpen(
    MaterialModel material,
  ) async {
    if (kIsWeb) {
      return const MaterialDownloadResult(
        status: MaterialDownloadStatus.unsupportedPlatform,
        message: 'Opening Office files in another app is unavailable on web.',
      );
    }

    if (material.storageUploadStatus == 'uploading') {
      return const MaterialDownloadResult(
        status: MaterialDownloadStatus.uploadInProgress,
        message:
            'The original file is still uploading. Wait a moment, then try again.',
      );
    }

    if (material.storageUploadStatus == 'failed') {
      return const MaterialDownloadResult(
        status: MaterialDownloadStatus.uploadFailed,
        message:
            'The original file was not uploaded successfully. Ask the teacher to upload it again.',
      );
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final safeId = material.id.replaceAll(RegExp(r'[^\w\.-]'), '_');
      final safeName = material.fileName.replaceAll(RegExp(r'[^\w\.-]'), '_');
      final tempFile = File(
        '${tempDir.path}${Platform.pathSeparator}${safeId}_$safeName',
      );

      if (await tempFile.exists()) {
        final cachedLength = await tempFile.length();
        final expectedLength = material.fileSizeBytes;
        if (cachedLength > 0 &&
            (expectedLength == null ||
                expectedLength <= 0 ||
                cachedLength == expectedLength)) {
          return MaterialDownloadResult(
            status: MaterialDownloadStatus.ready,
            file: tempFile,
            message: 'The original file is ready to open.',
          );
        }
      }

      final bytes = await getMaterialFileBytes(material);
      if (bytes == null || bytes.isEmpty) {
        return const MaterialDownloadResult(
          status: MaterialDownloadStatus.unavailable,
          message:
              'The original file could not be downloaded. Check your connection and try again.',
        );
      }

      await tempFile.writeAsBytes(bytes, flush: true);
      if (!await tempFile.exists() || await tempFile.length() == 0) {
        return const MaterialDownloadResult(
          status: MaterialDownloadStatus.failed,
          message: 'The downloaded file could not be saved on this device.',
        );
      }

      return MaterialDownloadResult(
        status: MaterialDownloadStatus.ready,
        file: tempFile,
        message: 'The original file is ready to open.',
      );
    } catch (e) {
      debugPrint('Error writing material to temp file: $e');
      return const MaterialDownloadResult(
        status: MaterialDownloadStatus.failed,
        message:
            'The original file could not be prepared. Check your connection and available storage, then try again.',
      );
    }
  }

  /// Backward-compatible helper for callers that only need the downloaded file.
  Future<File?> downloadMaterialToTemp(MaterialModel material) async {
    final result = await prepareMaterialForExternalOpen(material);
    return result.file;
  }

  /// Stream a single material document in real time to monitor extraction status
  Stream<MaterialModel?> streamMaterial(String materialId) {
    return _supabase
        .from('materials')
        .stream(primaryKey: ['id'])
        .eq('id', materialId)
        .map(
          (rows) => rows.isEmpty
              ? null
              : MaterialModel.fromMap(rows.first, rows.first['id'].toString()),
        );
  }

  /// Stream all materials belonging to a specific class in real time.
  Stream<List<MaterialModel>> streamClassMaterials(
    String classId, {
    bool postedOnly = false,
  }) {
    return _supabase
        .from('materials')
        .stream(primaryKey: ['id'])
        .eq('class_id', classId)
        .order('created_at', ascending: false)
        .map((rows) {
          final list = rows
              .map((row) => MaterialModel.fromMap(row, row['id'].toString()))
              .toList();
          if (postedOnly) {
            return list
                .where((m) => m.isPosted && m.isReady && m.isUploadCompleted)
                .toList();
          }
          return list;
        });
  }

  /// Explicitly publish / post an uploaded study material to the class,
  /// making it visible and accessible to enrolled students.
  Future<void> postMaterial(String materialId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final updatedRows = await _supabase
        .from('materials')
        .update({'is_posted': true, 'posted_at': now})
        .eq('id', materialId)
        .select('id, is_posted, posted_at')
        .timeout(const Duration(seconds: 15));
    if (updatedRows.isEmpty || updatedRows.first['is_posted'] != true) {
      throw StateError(
        'The material was not posted. It may no longer exist or you may not have permission to update it.',
      );
    }
  }

  /// Unpost / hide a study material from students while keeping it in the teacher's class.
  Future<void> unpostMaterial(String materialId) async {
    final updatedRows = await _supabase
        .from('materials')
        .update({'is_posted': false, 'posted_at': null})
        .eq('id', materialId)
        .select('id, is_posted, posted_at')
        .timeout(const Duration(seconds: 15));
    if (updatedRows.isEmpty || updatedRows.first['is_posted'] != false) {
      throw StateError(
        'The material was not unposted. It may no longer exist or you may not have permission to update it.',
      );
    }
  }

  /// Stream all materials uploaded by a teacher, optionally filtered by classId
  Stream<List<MaterialModel>> streamTeacherMaterials(
    String teacherId, {
    String? classId,
  }) {
    final stream = _supabase
        .from('materials')
        .stream(primaryKey: ['id'])
        .eq('teacher_id', teacherId);
    final filtered = classId != null && classId.isNotEmpty
        ? stream.eq('class_id', classId)
        : stream;
    return filtered
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
              .map((row) => MaterialModel.fromMap(row, row['id'].toString()))
              .toList(),
        );
  }

  /// Reset a failed extraction attempt and re-attempt extraction if bytes are retrievable
  Future<void> retryMaterialExtraction(String materialId) async {
    try {
      final row = await _supabase
          .from('materials')
          .select()
          .eq('id', materialId)
          .maybeSingle();
      if (row != null) {
        final mat = MaterialModel.fromMap(row, materialId);
        final bytes = await getMaterialFileBytes(mat);
        if (bytes != null && bytes.isNotEmpty) {
          final extractionResult = await DocumentTextExtractor.extract(
            bytes: bytes,
            extension: mat.fileType,
          );
          final isExtracted = extractionResult.isSuccess;
          await _supabase
              .from('materials')
              .update({
                'status': isExtracted ? 'ready' : 'failed',
                'extracted_text': extractionResult.text,
                'extracted_at': isExtracted
                    ? DateTime.now().toUtc().toIso8601String()
                    : null,
                'error_reason': isExtracted
                    ? null
                    : (extractionResult.errorReason ?? 'no_extractable_text'),
              })
              .eq('id', materialId);
          return;
        }
      }
    } catch (e) {
      debugPrint('Retry extraction error: $e');
    }

    // If file bytes cannot be retrieved, do NOT set status to 'processing'
    // (which would hang indefinitely on free Spark tier). Mark as failed with clear reason.
    try {
      await _supabase
          .from('materials')
          .update({
            'status': 'failed',
            'error_reason': 'file_bytes_unavailable',
          })
          .eq('id', materialId);
    } catch (updateErr) {
      debugPrint('Status update error during retry failure: $updateErr');
    }
    throw const MaterialValidationException(
      'Original document file is unavailable in storage. Please re-upload the document.',
    );
  }

  /// Delete a material from Postgres and Supabase Storage, and clean up
  /// any orphaned draft quizzes and locally cached temporary files.
  Future<void> deleteMaterial({
    required String materialId,
    required String fileRef,
    String? fileName,
    String? convertedPdfRef,
    String storageProvider = 'supabase',
    String? storageBucket,
  }) async {
    // 1. Delete the row immediately so real-time UI streams reflect deletion.
    final databaseDelete = _supabase
        .from('materials')
        .delete()
        .eq('id', materialId);

    // 2. Concurrently clean up orphaned draft quizzes referencing this material
    final quizCleanup = _cleanupMaterialQuizzes(materialId);

    // 3. Concurrently remove Supabase objects.
    final storageRefs = <String>[
      if (fileRef.isNotEmpty) fileRef,
      if (convertedPdfRef != null && convertedPdfRef.isNotEmpty)
        convertedPdfRef,
    ];
    final storageDelete = storageProvider == 'supabase'
        ? _deleteSupabaseFiles(storageRefs, bucket: storageBucket)
        : Future<void>.value();

    // 4. Concurrently clean up any cached local temporary file
    final localCleanup = _cleanupLocalTempFile(
      materialId: materialId,
      fileName: fileName,
    );

    await Future.wait([
      databaseDelete,
      quizCleanup,
      storageDelete,
      localCleanup,
    ]);
  }

  /// Helper that removes a list of object paths from the specified Supabase Storage bucket.
  Future<void> _deleteSupabaseFiles(
    List<String> paths, {
    String? bucket,
  }) async {
    if (paths.isEmpty) return;
    try {
      await _supabase.storage
          .from(bucket ?? SupabaseConfig.storageBucket)
          .remove(paths)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Supabase deletion non-critical notice: $e');
    }
  }

  /// Sanitizes a file name so it only contains safe alphanumeric, dot, underscore, and hyphen characters for storage paths.
  static String _safeStorageFileName(String fileName) {
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? 'material' : safe;
  }

  /// Generates a cryptographically random RFC 4122 version 4 UUID string for new material IDs.
  static String _uuidV4() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Cleans up quizzes linked to a deleted material: deletes unpublished draft quizzes
  /// and unlinks (`material_id = null`) published/finalized quizzes so student records remain intact.
  Future<void> _cleanupMaterialQuizzes(String materialId) async {
    if (materialId.isEmpty) return;
    try {
      final rows = await _supabase
          .from('quizzes')
          .select('id,status')
          .eq('material_id', materialId)
          .timeout(const Duration(seconds: 5));
      final maps = List<Map<String, dynamic>>.from(rows);
      final draftIds = maps
          .where((row) => row['status'] == 'draft')
          .map((row) => row['id'].toString())
          .toList();
      final retainedIds = maps
          .where((row) => row['status'] != 'draft')
          .map((row) => row['id'].toString())
          .toList();
      if (draftIds.isNotEmpty) {
        await _supabase.from('quizzes').delete().inFilter('id', draftIds);
      }
      if (retainedIds.isNotEmpty) {
        await _supabase
            .from('quizzes')
            .update({'material_id': null})
            .inFilter('id', retainedIds);
      }
    } catch (e) {
      debugPrint(
        'Notice: Quizzes cleanup for material $materialId finished with: $e',
      );
    }
  }

  /// Deletes any locally cached temporary files created when opening this material in an external app.
  Future<void> _cleanupLocalTempFile({
    required String materialId,
    String? fileName,
  }) async {
    if (kIsWeb || fileName == null || fileName.isEmpty) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final safeId = materialId.replaceAll(RegExp(r'[^\w\.-]'), '_');
      final safeName = fileName.replaceAll(RegExp(r'[^\w\.-]'), '_');
      final files = <File>[
        File('${tempDir.path}${Platform.pathSeparator}${safeId}_$safeName'),
        // Remove files cached by the earlier filename-only implementation.
        File('${tempDir.path}${Platform.pathSeparator}$safeName'),
      ];
      for (final file in files) {
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('Notice: Local temp file cleanup error: $e');
    }
  }
}
