import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/material_model.dart';
import '../utils/document_text_extractor.dart';
import 'firestore_provider.dart';

/// Exception thrown when study material validation or processing fails.
class MaterialValidationException implements Exception {
  final String message;
  const MaterialValidationException(this.message);

  @override
  String toString() => message;
}

/// Service handling on-device material extraction, Supabase Storage
/// persistence, and real-time Firestore tracking.
class MaterialService {
  final FirebaseFirestore _firestore;
  final SupabaseClient? _injectedSupabase;

  MaterialService({FirebaseFirestore? firestore, SupabaseClient? supabase})
    : _firestore = getAppFirestore(firestore),
      _injectedSupabase = supabase;

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
  /// and writes the ready document directly to Firestore.
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

    // 2. Prepare Firestore document ID and storage path up front
    final materialDocRef = _firestore.collection('materials').doc();
    final materialId = materialDocRef.id;
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

    // 5. Write Firestore document with status: 'ready' immediately
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

    try {
      await materialDocRef
          .set({
            ...readyModel.toMap(),
            'createdAt': FieldValue.serverTimestamp(),
            if (isExtracted) 'extractedAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      if (uploadFuture != null) {
        unawaited(
          uploadFuture.then(
            (_) => _deleteSupabaseFiles([storagePath]),
            onError: (_) {},
          ),
        );
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
          await materialDocRef
              .update({'storageUploadStatus': 'completed'})
              .timeout(const Duration(seconds: 10));
        } catch (storageErr) {
          debugPrint('Background Supabase upload note: $storageErr');
          try {
            await materialDocRef
                .update({'storageUploadStatus': 'failed'})
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
    // 1. Preserve access to legacy records that have a direct Firebase URL.
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

  /// Download material to temporary file directory for opening with native apps
  Future<File?> downloadMaterialToTemp(MaterialModel material) async {
    if (kIsWeb) return null;
    try {
      final bytes = await getMaterialFileBytes(material);
      if (bytes == null || bytes.isEmpty) return null;

      final tempDir = await getTemporaryDirectory();
      final safeName = material.fileName.replaceAll(RegExp(r'[^\w\.-]'), '_');
      final tempFile = File('${tempDir.path}/$safeName');
      await tempFile.writeAsBytes(bytes, flush: true);
      return tempFile;
    } catch (e) {
      debugPrint('Error writing material to temp file: $e');
      return null;
    }
  }

  /// Stream a single material document in real time to monitor extraction status
  Stream<MaterialModel?> streamMaterial(String materialId) {
    return _firestore.collection('materials').doc(materialId).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists || snapshot.data() == null) return null;
      return MaterialModel.fromMap(snapshot.data()!, snapshot.id);
    });
  }

  /// Stream all materials belonging to a specific class in real time.
  Stream<List<MaterialModel>> streamClassMaterials(String classId) {
    return _firestore
        .collection('materials')
        .where('classId', isEqualTo: classId)
        .snapshots()
        .map((snapshot) {
          final materials = snapshot.docs
              .map((doc) => MaterialModel.fromMap(doc.data(), doc.id))
              .toList();
          materials.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return materials;
        });
  }

  /// Stream all materials uploaded by a teacher, optionally filtered by classId
  Stream<List<MaterialModel>> streamTeacherMaterials(
    String teacherId, {
    String? classId,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('materials')
        .where('teacherId', isEqualTo: teacherId);

    if (classId != null && classId.isNotEmpty) {
      query = query.where('classId', isEqualTo: classId);
    }

    return query.snapshots().map((snapshot) {
      final materials = snapshot.docs
          .map((doc) => MaterialModel.fromMap(doc.data(), doc.id))
          .toList();
      materials.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return materials;
    });
  }

  /// Reset a failed extraction attempt and re-attempt extraction if bytes are retrievable
  Future<void> retryMaterialExtraction(String materialId) async {
    try {
      final doc = await _firestore
          .collection('materials')
          .doc(materialId)
          .get();
      if (doc.exists && doc.data() != null) {
        final mat = MaterialModel.fromMap(doc.data()!, doc.id);
        final bytes = await getMaterialFileBytes(mat);
        if (bytes != null && bytes.isNotEmpty) {
          final extractionResult = await DocumentTextExtractor.extract(
            bytes: bytes,
            extension: mat.fileType,
          );
          final isExtracted = extractionResult.isSuccess;
          await _firestore.collection('materials').doc(materialId).update({
            'status': isExtracted ? 'ready' : 'failed',
            'extractedText': extractionResult.text,
            'extractedAt': isExtracted ? FieldValue.serverTimestamp() : null,
            'errorReason': isExtracted
                ? FieldValue.delete()
                : (extractionResult.errorReason ?? 'no_extractable_text'),
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Retry extraction error: $e');
    }

    // If file bytes cannot be retrieved, do NOT set status to 'processing'
    // (which would hang indefinitely on free Spark tier). Mark as failed with clear reason.
    try {
      await _firestore.collection('materials').doc(materialId).update({
        'status': 'failed',
        'errorReason': 'file_bytes_unavailable',
      });
    } catch (updateErr) {
      debugPrint('Status update error during retry failure: $updateErr');
    }
    throw const MaterialValidationException(
      'Original document file is unavailable in storage. Please re-upload the document.',
    );
  }

  /// Delete a material from Firestore and Supabase Storage, and clean up
  /// any orphaned draft quizzes and locally cached temporary files.
  Future<void> deleteMaterial({
    required String materialId,
    required String fileRef,
    String? fileName,
    String? convertedPdfRef,
    String storageProvider = 'supabase',
    String? storageBucket,
  }) async {
    // 1. Delete Firestore material doc immediately so real-time UI streams reflect deletion
    final firestoreDelete = _firestore
        .collection('materials')
        .doc(materialId)
        .delete();

    // 2. Concurrently clean up orphaned draft quizzes referencing this material
    final quizCleanup = _cleanupMaterialQuizzes(materialId);

    // 3. Concurrently remove Supabase objects. Legacy Firebase objects are
    // intentionally left untouched; their Firestore record is still removed.
    final storageRefs = <String>[
      if (fileRef.isNotEmpty) fileRef,
      if (convertedPdfRef != null && convertedPdfRef.isNotEmpty)
        convertedPdfRef,
    ];
    final storageDelete = storageProvider == 'supabase'
        ? _deleteSupabaseFiles(storageRefs, bucket: storageBucket)
        : Future<void>.value();

    // 4. Concurrently clean up any cached local temporary file
    final localCleanup = _cleanupLocalTempFile(fileName: fileName);

    await Future.wait([
      firestoreDelete,
      quizCleanup,
      storageDelete,
      localCleanup,
    ]);
  }

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

  static String _safeStorageFileName(String fileName) {
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? 'material' : safe;
  }

  Future<void> _cleanupMaterialQuizzes(String materialId) async {
    if (materialId.isEmpty) return;
    try {
      final snapshot = await _firestore
          .collection('quizzes')
          .where('materialId', isEqualTo: materialId)
          .get()
          .timeout(const Duration(seconds: 5));

      if (snapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final status = data['status'] as String? ?? 'draft';
        if (status == 'draft') {
          // Clean up unfinalized draft quizzes tied to the deleted material
          batch.delete(doc.reference);
        } else {
          // Unlink materialId from finalized or published quizzes to preserve student records
          batch.update(doc.reference, {'materialId': ''});
        }
      }
      await batch.commit().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint(
        'Notice: Quizzes cleanup for material $materialId finished with: $e',
      );
    }
  }

  Future<void> _cleanupLocalTempFile({String? fileName}) async {
    if (kIsWeb || fileName == null || fileName.isEmpty) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final safeName = fileName.replaceAll(RegExp(r'[^\w\.-]'), '_');
      final file = File('${tempDir.path}/$safeName');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Notice: Local temp file cleanup error: $e');
    }
  }
}
