import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Screen allowing a teacher to upload a study material (PDF/PPTX/DOCX)
/// to Firebase Storage, monitor text extraction status in Firestore in real time,
/// and configure quiz parameters.
class UploadGenerateQuizScreen extends StatefulWidget {
  const UploadGenerateQuizScreen({super.key});

  @override
  State<UploadGenerateQuizScreen> createState() =>
      _UploadGenerateQuizScreenState();
}

class _UploadGenerateQuizScreenState extends State<UploadGenerateQuizScreen> {
  // ── Design tokens ───────────────────────────────────────────
  static const _primaryNavy = Color(0xFF1A237E);
  static const _darkNavy = Color(0xFF000666);
  static const _gradientStart = Color(0xFFF3F0FF);
  static const _gradientEnd = Color(0xFFEFF6FF);
  static const _surfaceWhite = Color(0xFFFBF9F8);
  static const _outlineVariant = Color(0xFFC6C5C4);
  static const _textPrimary = Color(0xFF1B1C1C);
  static const _textSecondary = Color(0xFF454652);

  // ── Upload & Firestore Material State ───────────────────────
  String? _materialId;
  String? _selectedFileName;
  String? _selectedFileType;
  int? _selectedFileBytesLength;
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  // Status: null (idle) | 'uploading' | 'processing' | 'ready' | 'failed'
  String? _materialStatus;
  String? _errorReason;
  String? _extractedText;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _materialSubscription;

  // ── Quiz Configuration State ────────────────────────────────
  double _questionCount = 10;
  String _selectedClass = 'Biology 101 - Cell Biology';

  final Map<String, bool> _questionTypes = {
    'Multiple Choice': true,
    'True/False': true,
    'Fill-in-the-Blank': false,
    'Identification': false,
    'Enumeration': false,
  };

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _materialSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Format human-readable error reasons matching the Firestore schema
  String _formatErrorReason(String? reason) {
    switch (reason) {
      case 'no_extractable_text':
        return 'No extractable text found in this file. Please ensure the document contains readable text and is not a scanned image.';
      case 'unsupported_format':
        return 'Unsupported format. Please select a valid PDF, PPTX, or DOCX document.';
      case 'parse_error':
        return 'Parse error encountered while reading the document. The file may be corrupt or encrypted.';
      default:
        return reason ?? 'Unknown error occurred while processing the document.';
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Real file picker and upload workflow
  Future<void> _pickAndUploadFile() async {
    try {
      final pickedFile = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'pptx', 'docx'],
      );

      if (pickedFile == null) {
        return; // User canceled picker
      }

      final fileName = pickedFile.name;
      final fileExtension = pickedFile.extension?.toLowerCase();

      if (fileExtension != 'pdf' &&
          fileExtension != 'pptx' &&
          fileExtension != 'docx') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a PDF, PPTX, or DOCX file.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      // Generate a new Firestore materialId
      final materialDocRef =
          FirebaseFirestore.instance.collection('materials').doc();
      final newMaterialId = materialDocRef.id;
      const teacherId = 'teacher_demo'; // In later auth phase: currentUser.uid
      final storagePath = 'uploads/$teacherId/$newMaterialId/$fileName';

      final fileLength =
          pickedFile.lengthSync() ?? await pickedFile.length();

      setState(() {
        _materialId = newMaterialId;
        _selectedFileName = fileName;
        _selectedFileType = fileExtension;
        _selectedFileBytesLength = fileLength;
        _isUploading = true;
        _uploadProgress = 0.0;
        _materialStatus = 'processing';
        _errorReason = null;
        _extractedText = null;
      });

      // 1. Create corresponding materials/{materialId} document in Firestore with status: "processing"
      await materialDocRef.set({
        'teacherId': teacherId,
        'classId': _selectedClass,
        'fileRef': storagePath,
        'fileType': fileExtension,
        'status': 'processing',
        'extractedText': '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2. Start real-time Firestore stream listener on materials/{materialId}
      _listenToMaterial(newMaterialId);

      // 3. Upload file to Firebase Storage
      final storageRef = FirebaseStorage.instance.ref().child(storagePath);
      UploadTask uploadTask;

      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        uploadTask = storageRef.putData(
          bytes,
          SettableMetadata(contentType: _getContentType(fileExtension)),
        );
      } else if (pickedFile.path != null) {
        uploadTask = storageRef.putFile(
          File(pickedFile.path!),
          SettableMetadata(contentType: _getContentType(fileExtension)),
        );
      } else {
        final bytes = await pickedFile.readAsBytes();
        uploadTask = storageRef.putData(
          bytes,
          SettableMetadata(contentType: _getContentType(fileExtension)),
        );
      }

      // Monitor upload progress
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        if (snapshot.totalBytes > 0) {
          setState(() {
            _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
          });
        }
      });

      await uploadTask;

      setState(() {
        _isUploading = false;
      });
    } catch (e) {
      setState(() {
        _isUploading = false;
        _materialStatus = 'failed';
        _errorReason = e.toString();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  String _getContentType(String? ext) {
    switch (ext?.toLowerCase()) {
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

  /// Listen in real time to the materials/{materialId} Firestore document
  void _listenToMaterial(String materialId) {
    _materialSubscription?.cancel();
    _materialSubscription = FirebaseFirestore.instance
        .collection('materials')
        .doc(materialId)
        .snapshots()
        .listen(
      (snapshot) {
        if (!snapshot.exists || snapshot.data() == null) return;

        final data = snapshot.data()!;
        final status = data['status'] as String? ?? 'processing';
        final errorReason = data['errorReason'] as String?;
        final extractedText = data['extractedText'] as String?;

        setState(() {
          _materialStatus = status;
          _errorReason = errorReason;
          _extractedText = extractedText;
        });
      },
      onError: (error) {
        setState(() {
          _materialStatus = 'failed';
          _errorReason = error.toString();
        });
      },
    );
  }

  void _generateQuiz({required bool isActual}) {
    // Disabled until material status is "ready"
    if (_materialStatus != 'ready') {
      return;
    }

    final activeTypes = _questionTypes.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    if (activeTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one question type.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // TODO: Wire Gemini API quiz synthesis in upcoming phase
    final quizKind = isActual ? 'Actual Quiz' : 'Practice Quiz';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Stub: Generating $quizKind (${_questionCount.toInt()} questions) from $_selectedFileName...',
        ),
        backgroundColor: _primaryNavy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMaterialReady = _materialStatus == 'ready';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Generate Quiz',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _textPrimary,
          ),
        ),
        backgroundColor: _surfaceWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _primaryNavy),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_gradientStart, _gradientEnd],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Section 1: Study Material Upload ─────────
                const Text(
                  'Upload Study Material',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Upload lecture slides, book chapters, or notes (PDF, PPTX, DOCX).',
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
                const SizedBox(height: 12),

                // File picker tap area / upload trigger
                InkWell(
                  onTap: _isUploading ? null : _pickAndUploadFile,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: _surfaceWhite,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _primaryNavy.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _primaryNavy.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.cloud_upload_outlined,
                            size: 28,
                            color: _primaryNavy,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _selectedFileName == null
                              ? 'Select PDF, PPTX, or DOCX File'
                              : 'Choose a Different File',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _primaryNavy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Uploads to Firebase Storage & extracts text',
                          style: TextStyle(
                            fontSize: 12,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Real-time Status Area ────────────────────
                if (_materialStatus != null) ...[
                  const SizedBox(height: 16),
                  _buildRealtimeStatusCard(),
                ],

                const SizedBox(height: 24),

                // ── Section 2: Target Class ──────────────────
                const Text(
                  'Assign to Class',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: _surfaceWhite,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _outlineVariant),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedClass,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down),
                      items: const [
                        DropdownMenuItem(
                          value: 'Biology 101 - Cell Biology',
                          child: Text('Biology 101 - Cell Biology'),
                        ),
                        DropdownMenuItem(
                          value: 'CS 201 - Data Structures',
                          child: Text('CS 201 - Data Structures'),
                        ),
                        DropdownMenuItem(
                          value: 'AP Chemistry - Period 3',
                          child: Text('AP Chemistry - Period 3'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedClass = val);
                        }
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Section 3: Question Count ────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Number of Questions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _primaryNavy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_questionCount.toInt()} questions',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _primaryNavy,
                        ),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _questionCount,
                  min: 5,
                  max: 50,
                  divisions: 9,
                  activeColor: _primaryNavy,
                  inactiveColor: _outlineVariant,
                  label: '${_questionCount.toInt()}',
                  onChanged: (val) {
                    setState(() => _questionCount = val);
                  },
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('5 questions', style: TextStyle(fontSize: 12, color: _textSecondary)),
                    Text('50 questions', style: TextStyle(fontSize: 12, color: _textSecondary)),
                  ],
                ),

                const SizedBox(height: 24),

                // ── Section 4: Question Types ────────────────
                const Text(
                  'Question Types',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select the question formats Gemini will synthesize from the extracted text.',
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
                const SizedBox(height: 12),

                Container(
                  decoration: BoxDecoration(
                    color: _surfaceWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _outlineVariant),
                  ),
                  child: Column(
                    children: _questionTypes.keys.map((type) {
                      final isChecked = _questionTypes[type] ?? false;
                      return CheckboxListTile(
                        value: isChecked,
                        activeColor: _primaryNavy,
                        title: Text(
                          type,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _textPrimary,
                          ),
                        ),
                        onChanged: (val) {
                          setState(() {
                            _questionTypes[type] = val ?? false;
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Section 5: Quiz Generation Buttons ───────
                // Disabled until material status is "ready"
                if (!isMaterialReady) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.amber[900]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _materialStatus == 'processing'
                                ? 'Generation buttons will unlock once text extraction completes.'
                                : 'Please upload a study material first to generate quizzes.',
                            style: TextStyle(fontSize: 12, color: Colors.amber[900]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Actual Quiz Button (Disabled until material is ready)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _darkNavy,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _darkNavy.withValues(alpha: 0.3),
                      disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
                      elevation: isMaterialReady ? 1 : 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: isMaterialReady ? () => _generateQuiz(isActual: true) : null,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.print_outlined, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Generate Actual Quiz (PDF Exam)',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Practice Quiz Button (Disabled until material is ready)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _surfaceWhite,
                      foregroundColor: _primaryNavy,
                      disabledForegroundColor: _outlineVariant,
                      side: BorderSide(
                        color: isMaterialReady
                            ? _primaryNavy
                            : _outlineVariant.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: isMaterialReady ? () => _generateQuiz(isActual: false) : null,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.phone_android_outlined, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Generate Practice Quiz (App Practice)',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Real-time Material Status Card reflecting Firestore document updates
  Widget _buildRealtimeStatusCard() {
    final status = _materialStatus;
    final fileTypeBadge = (_selectedFileType ?? '').toUpperCase();
    final fileSizeText = _formatFileSize(_selectedFileBytesLength);

    if (_isUploading) {
      // Storage Uploading State
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _primaryNavy.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Uploading $_selectedFileName ($fileSizeText)...',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${(_uploadProgress * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _primaryNavy,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _uploadProgress,
              backgroundColor: _outlineVariant.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(_primaryNavy),
            ),
          ],
        ),
      );
    }

    if (status == 'processing') {
      // Cloud Function Text Extraction in progress
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _primaryNavy.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(_primaryNavy),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Processing Document...',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _textPrimary,
                        ),
                      ),
                      if (fileTypeBadge.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: _primaryNavy.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            fileTypeBadge,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _primaryNavy,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'extractText Cloud Function is extracting content from $_selectedFileName',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (status == 'ready') {
      // Success State with Continue Action
      final previewLen = _extractedText?.length ?? 0;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Document Ready for Quiz Generation',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
                if (_materialId != null)
                  Text(
                    'ID: ${_materialId!.substring(0, 6)}...',
                    style: const TextStyle(fontSize: 10, color: _textSecondary),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Successfully extracted $previewLen characters from $_selectedFileName ($fileSizeText).',
              style: const TextStyle(fontSize: 12, color: _textSecondary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryNavy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () {
                  // "Continue" action scrolls down to quiz options
                  _scrollController.animateTo(
                    300,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                  );
                },
                icon: const Icon(Icons.arrow_downward, size: 16),
                label: const Text('Continue to Quiz Options'),
              ),
            ),
          ],
        ),
      );
    }

    if (status == 'failed') {
      // Error State showing exact errorReason
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Extraction Failed',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const Spacer(),
                if (_errorReason != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _errorReason!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.red,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _formatErrorReason(_errorReason),
              style: const TextStyle(fontSize: 13, color: _textPrimary),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red[800],
                side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _pickAndUploadFile,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Try Another File'),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
