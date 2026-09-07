import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/material_model.dart';
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

  /// Uploads a study material file to Firebase Storage and initializes
  /// the Firestore `materials/{materialId}` document.
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

    // 2. Generate new Firestore materialId
    final materialDocRef = _firestore.collection('materials').doc();
    final materialId = materialDocRef.id;
    final storagePath = 'uploads/$teacherId/$materialId/$fileName';

    // 3. Create initial Firestore document with status: 'processing'
    final initialModel = MaterialModel(
      id: materialId,
      teacherId: teacherId,
      classId: cleanClassId,
      fileName: fileName,
      fileType: cleanExt,
      fileRef: storagePath,
      status: 'processing',
      createdAt: DateTime.now(),
      fileSizeBytes: byteLength,
    );

    await materialDocRef.set(initialModel.toMap());

    // 4. Upload to Firebase Storage
    final storageRef = _storage.ref().child(storagePath);
    final metadata = SettableMetadata(
      contentType: initialModel.contentType,
      customMetadata: {
        'teacherId': teacherId,
        'materialId': materialId,
        'classId': cleanClassId,
      },
    );

    UploadTask uploadTask;
    if (fileBytes != null) {
      uploadTask = storageRef.putData(fileBytes, metadata);
    } else if (localFilePath != null && !kIsWeb) {
      uploadTask = storageRef.putFile(File(localFilePath), metadata);
    } else {
      throw const MaterialValidationException(
        'No file data available to upload. Please pick the file again.',
      );
    }

    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        if (snapshot.totalBytes > 0) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          onProgress(progress);
        }
      });
    }

    await uploadTask;

    return initialModel;
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

  /// Reset a failed extraction attempt so the Cloud Function or user can retry
  Future<void> retryMaterialExtraction(String materialId) async {
    await _firestore.collection('materials').doc(materialId).update({
      'status': 'processing',
      'errorReason': FieldValue.delete(),
    });
  }

  /// Delete a material from both Firestore and Firebase Storage
  Future<void> deleteMaterial({
    required String materialId,
    required String fileRef,
  }) async {
    try {
      await _storage.ref().child(fileRef).delete();
    } catch (_) {
      // Storage deletion could fail if file doesn't exist; continue to delete Firestore doc
    }
    await _firestore.collection('materials').doc(materialId).delete();
  }
}
