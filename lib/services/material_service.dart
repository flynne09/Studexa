import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
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

/// Service handling study material uploads, Firebase Storage persistence,
/// and real-time Firestore tracking of Cloud Function text extraction.
class MaterialService {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  MaterialService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = getAppFirestore(firestore),
        _storage = storage ?? FirebaseStorage.instance;

  static const int maxFileSizeBytes = 50 * 1024 * 1024; // 50MB
  static const Set<String> supportedExtensions = {'pdf', 'pptx', 'docx'};

  /// Validate file parameters before initiating upload
  static void validateFile({
    required String fileName,
    required String extension,
    required int byteLength,
  }) {
    final cleanExt = extension.toLowerCase().replaceAll('.', '').trim();

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
  /// Firebase Storage upload is performed with a non-blocking timeout so users
  /// on free Firebase tiers are never stuck in an infinite upload loop.
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

    // 2. Prepare Firestore document ID and storage path up front
    final materialDocRef = _firestore.collection('materials').doc();
    final materialId = materialDocRef.id;
    final storagePath = 'uploads/$teacherId/$materialId/$fileName';

    // 3. Initiate Firebase Storage upload concurrently with text extraction
    UploadTask? uploadTask;
    StreamSubscription<TaskSnapshot>? progressSub;
    try {
      final storageRef = _storage.ref().child(storagePath);
      final metadata = SettableMetadata(
        contentType: MaterialModel.contentTypeForExtension(cleanExt),
        customMetadata: {
          'teacherId': teacherId,
          'materialId': materialId,
          'classId': cleanClassId,
        },
      );

      if (resolvedBytes != null) {
        uploadTask = storageRef.putData(resolvedBytes, metadata);
      } else if (localFilePath != null && !kIsWeb) {
        uploadTask = storageRef.putFile(File(localFilePath), metadata);
      }

      if (uploadTask != null && onProgress != null) {
        progressSub = uploadTask.snapshotEvents.listen(
          (TaskSnapshot snapshot) {
            if (snapshot.totalBytes > 0) {
              final progress = snapshot.bytesTransferred / snapshot.totalBytes;
              onProgress(progress);
            }
          },
          onError: (err) {
            debugPrint('Storage upload progress stream error: $err');
          },
          cancelOnError: true,
        );
      }
    } catch (e) {
      debugPrint('Storage upload task initiation note: $e');
    }

    // 4. Perform client-side text extraction concurrently while bytes are streaming to Storage
    String extractedText = '';
    String? errorReason;
    bool isExtracted = false;

    if (resolvedBytes != null && resolvedBytes.isNotEmpty) {
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
      status: initialStatus,
      errorReason: errorReason,
      extractedText: extractedText,
      conversionStatus: cleanExt == 'pdf' ? 'completed' : 'pending',
      createdAt: DateTime.now(),
      fileSizeBytes: byteLength,
    );

    await materialDocRef.set(readyModel.toMap());

    // 6. Non-blocking Storage upload resolution:
    // If the upload finished during text extraction, attach downloadUrl immediately.
    // Otherwise, let the background worker finalize downloadUrl in Firestore without
    // delaying the teacher from proceeding to quiz generation.
    String? downloadUrl;
    if (uploadTask != null) {
      final storageRef = _storage.ref().child(storagePath);

      // Fast check if already completed
      try {
        final fastSnapshot = await uploadTask.timeout(const Duration(milliseconds: 100));
        if (fastSnapshot.state == TaskState.success) {
          downloadUrl = await storageRef.getDownloadURL();
          await materialDocRef.update({'downloadUrl': downloadUrl});
          await progressSub?.cancel();
          onProgress?.call(1.0);
          return readyModel.copyWith(downloadUrl: downloadUrl);
        }
      } catch (_) {
        // Still transferring in the background; do not block the caller!
      }

      // Background worker to finalize downloadUrl in Firestore without delaying UI
      unawaited(() async {
        try {
          final snapshot = await uploadTask!.timeout(const Duration(seconds: 45));
          if (snapshot.state == TaskState.success) {
            try {
              final url = await storageRef.getDownloadURL();
              await materialDocRef.update({'downloadUrl': url});
            } catch (urlErr) {
              debugPrint('Failed to get download URL in background: $urlErr');
            }
          }
        } catch (storageErr) {
          debugPrint('Background storage upload note: $storageErr');
        } finally {
          await progressSub?.cancel();
          onProgress?.call(1.0);
        }
      }());
    } else {
      onProgress?.call(1.0);
    }

    return readyModel;
  }

  /// Fetch raw bytes for a material file (via download URL or directly from Storage)
  Future<Uint8List?> getMaterialFileBytes(MaterialModel material) async {
    // 1. Try downloadUrl via HTTP
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

    // 2. Try direct Storage path ref
    if (material.fileRef.isNotEmpty) {
      try {
        final bytes = await _storage
            .ref()
            .child(material.fileRef)
            .getData(maxFileSizeBytes);
        if (bytes != null && bytes.isNotEmpty) {
          return bytes;
        }
      } catch (e) {
        debugPrint('Failed to fetch material bytes via Storage ref: $e');
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

    // 2. Try direct Storage path ref
    if (material.convertedPdfRef != null &&
        material.convertedPdfRef!.isNotEmpty) {
      try {
        final bytes = await _storage
            .ref()
            .child(material.convertedPdfRef!)
            .getData(maxFileSizeBytes);
        if (bytes != null && bytes.isNotEmpty) {
          return bytes;
        }
      } catch (e) {
        debugPrint('Failed to fetch converted PDF bytes via Storage ref: $e');
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
    return _firestore
        .collection('materials')
        .doc(materialId)
        .snapshots()
        .map((snapshot) {
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
      final doc = await _firestore.collection('materials').doc(materialId).get();
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
            'errorReason': isExtracted ? FieldValue.delete() : (extractionResult.errorReason ?? 'no_extractable_text'),
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

  /// Delete a material from both Firestore and Firebase Storage, and clean up
  /// any orphaned draft quizzes and locally cached temporary files.
  Future<void> deleteMaterial({
    required String materialId,
    required String fileRef,
    String? fileName,
    String? convertedPdfRef,
  }) async {
    // 1. Delete Firestore material doc immediately so real-time UI streams reflect deletion
    final firestoreDelete = _firestore.collection('materials').doc(materialId).delete();

    // 2. Concurrently clean up orphaned draft quizzes referencing this material
    final quizCleanup = _cleanupMaterialQuizzes(materialId);

    // 3. Concurrently delete Firebase Storage file with a strict 5s timeout
    final storageDelete = (fileRef.isNotEmpty)
        ? _storage
            .ref()
            .child(fileRef)
            .delete()
            .timeout(const Duration(seconds: 5))
            .catchError((err) {
              debugPrint('Storage deletion non-critical notice: $err');
            })
        : Future.value();

    // Concurrently delete converted preview PDF if present
    final convertedStorageDelete = (convertedPdfRef != null && convertedPdfRef.isNotEmpty)
        ? _storage
            .ref()
            .child(convertedPdfRef)
            .delete()
            .timeout(const Duration(seconds: 5))
            .catchError((err) {
              debugPrint('Converted PDF deletion non-critical notice: $err');
            })
        : Future.value();

    // 4. Concurrently clean up any cached local temporary file
    final localCleanup = _cleanupLocalTempFile(fileName: fileName);

    await Future.wait([
      firestoreDelete,
      quizCleanup,
      storageDelete,
      convertedStorageDelete,
      localCleanup,
    ]);
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
      debugPrint('Notice: Quizzes cleanup for material $materialId finished with: $e');
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
