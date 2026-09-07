import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/class_model.dart';
import '../../models/material_model.dart';
import '../../services/class_service.dart';
import '../../services/material_service.dart';
import '../../services/quiz_service.dart';
import 'quiz_detail_screen.dart';

/// Screen allowing a teacher to upload a study material (PDF/PPTX/DOCX)
/// to Firebase Storage, monitor text extraction status in Firestore in real time,
/// and configure quiz parameters.
class UploadGenerateQuizScreen extends StatefulWidget {
  final String? initialClassId;
  final ClassModel? preselectedClass;
  final bool isClassLocked;

  const UploadGenerateQuizScreen({
    super.key,
    this.initialClassId,
    this.preselectedClass,
    this.isClassLocked = false,
  });

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

  final MaterialService _materialService = MaterialService();
  final ClassService _classService = ClassService();
  final QuizService _quizService = QuizService();

  // ── Upload & Firestore Material State ───────────────────────
  String? _materialId;
  String? _selectedFileName;
  String? _selectedFileType;
  int? _selectedFileBytesLength;
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  // Real-time Material Model
  MaterialModel? _material;
  StreamSubscription<MaterialModel?>? _materialSubscription;

  // ── Class Dropdown State ────────────────────────────────────
  String? _selectedClassId;
  List<ClassModel> _classes = [];
  StreamSubscription<List<ClassModel>>? _classesSubscription;
  bool _isLoadingClasses = true;

  // ── Quiz Configuration State ────────────────────────────────
  double _questionCount = 10;

  final Map<String, bool> _questionTypes = {
    'Multiple Choice': true,
    'True/False': true,
    'Fill-in-the-Blank': false,
    'Identification': false,
    'Enumeration': false,
  };

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _selectedClassId = widget.initialClassId ?? widget.preselectedClass?.id;
    if (widget.isClassLocked && widget.preselectedClass != null) {
      _classes = [widget.preselectedClass!];
      _isLoadingClasses = false;
    }
    _initClasses();
  }

  void _initClasses() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId != null) {
      _classesSubscription = _classService
          .getTeacherClassesStream(currentUserId)
          .listen((classList) {
        if (!mounted) return;
        setState(() {
          _classes = classList;
          _isLoadingClasses = false;

          if (widget.isClassLocked && widget.preselectedClass != null) {
            _selectedClassId = widget.preselectedClass!.id;
          } else if (_selectedClassId == null && classList.isNotEmpty) {
            final match = classList.firstWhere(
              (c) => c.id == widget.initialClassId,
              orElse: () => classList.first,
            );
            _selectedClassId = match.id;
          }
        });
      });
    } else {
      _isLoadingClasses = false;
    }
  }

  @override
  void dispose() {
    _classesSubscription?.cancel();
    _materialSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Real file picker and upload workflow
  Future<void> _pickAndUploadFile() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Please sign in as a teacher to upload study materials.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please select or create a class first before uploading materials.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final pickedFile = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'pptx', 'docx'],
      );

      if (pickedFile == null) {
        return; // User canceled picker
      }

      final fileName = pickedFile.name;
      final fileExtension = pickedFile.extension ?? '';
      final byteLength = pickedFile.lengthSync() ?? await pickedFile.length();

      // Validate file before initiating upload
      MaterialService.validateFile(
        fileName: fileName,
        extension: fileExtension,
        byteLength: byteLength,
      );

      setState(() {
        _selectedFileName = fileName;
        _selectedFileType = fileExtension.toLowerCase();
        _selectedFileBytesLength = byteLength;
        _isUploading = true;
        _uploadProgress = 0.0;
        _material = null;
      });

      final fileBytes = await pickedFile.readAsBytes();

      final createdMaterial = await _materialService.uploadStudyMaterial(
        teacherId: currentUserId,
        classId: _selectedClassId!,
        fileName: fileName,
        fileExtension: fileExtension,
        byteLength: byteLength,
        fileBytes: fileBytes,
        localFilePath: pickedFile.path,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _uploadProgress = progress;
            });
          }
        },
      );

      setState(() {
        _materialId = createdMaterial.id;
        _material = createdMaterial;
        _isUploading = false;
      });

      // Listen to real-time status updates from Cloud Function
      _listenToMaterial(createdMaterial.id);
    } on MaterialValidationException catch (e) {
      setState(() => _isUploading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      setState(() => _isUploading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  /// Listen in real time to the materials/{materialId} Firestore document
  void _listenToMaterial(String materialId) {
    _materialSubscription?.cancel();
    _materialSubscription =
        _materialService.streamMaterial(materialId).listen(
      (material) {
        if (!mounted || material == null) return;
        setState(() {
          _material = material;
        });
      },
      onError: (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error monitoring extraction: $error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      },
    );
  }

  Future<void> _retryExtraction() async {
    if (_materialId == null) return;
    try {
      await _materialService.retryMaterialExtraction(_materialId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Retrying text extraction...'),
          backgroundColor: _primaryNavy,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Retry failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _generateQuiz({required bool isActual}) async {
    // Disabled until material status is "ready"
    if (_material == null || !_material!.isReady) {
      return;
    }

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in as a teacher to generate quizzes.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a target class first.'),
          backgroundColor: Colors.orange,
        ),
      );
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

    final quizKind = isActual ? 'Actual Quiz (Exam)' : 'Practice Quiz';

    // Show persistent generation dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                color: _primaryNavy,
                strokeWidth: 3,
              ),
              const SizedBox(height: 20),
              Text(
                'Synthesizing $quizKind...',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Generating ${_questionCount.toInt()} questions from "$_selectedFileName"...',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: _textSecondary),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final createdQuiz = await _quizService.generateQuiz(
        teacherId: currentUserId,
        classId: _selectedClassId!,
        materialId: _materialId!,
        isActual: isActual,
        questionTypes: activeTypes,
        questionCount: _questionCount.toInt(),
      );

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Navigate to QuizDetailScreen for teacher review and editing
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => QuizDetailScreen(quiz: createdQuiz),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Quiz generation failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMaterialReady = _material?.isReady ?? false;

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
                // ── Section 1: Target Class ──────────────────
                const Text(
                  'Assign to Class',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select which of your classes this material belongs to.',
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
                const SizedBox(height: 8),

                _buildClassSelector(),

                const SizedBox(height: 24),

                // ── Section 2: Study Material Upload ─────────
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
                  'Upload lecture slides, book chapters, or notes (PDF, PPTX, DOCX, up to 50MB).',
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
                          'Uploads to Firebase Storage & extracts text server-side',
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
                if (_isUploading || _material != null) ...[
                  const SizedBox(height: 16),
                  _buildRealtimeStatusCard(),
                ],

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
                    Text('5 questions',
                        style: TextStyle(fontSize: 12, color: _textSecondary)),
                    Text('50 questions',
                        style: TextStyle(fontSize: 12, color: _textSecondary)),
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
                if (!isMaterialReady) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: Colors.amber[900]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _material?.isProcessing == true
                                ? 'Generation buttons will unlock once text extraction completes.'
                                : 'Please upload and extract a study material first to generate quizzes.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.amber[900]),
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
                      disabledForegroundColor:
                          Colors.white.withValues(alpha: 0.6),
                      elevation: isMaterialReady ? 1 : 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: isMaterialReady
                        ? () => _generateQuiz(isActual: true)
                        : null,
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
                    onPressed: isMaterialReady
                        ? () => _generateQuiz(isActual: false)
                        : null,
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

  /// Class selection dropdown or empty state
  Widget _buildClassSelector() {
    if (widget.isClassLocked) {
      final className = widget.preselectedClass?.name ??
          _classes
              .where((c) => c.id == _selectedClassId)
              .map((c) => c.name)
              .firstOrNull ??
          'Selected Class';

      final sectionText = widget.preselectedClass?.section.isNotEmpty == true
          ? ' • Section ${widget.preselectedClass!.section}'
          : '';

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _primaryNavy.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _primaryNavy.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _primaryNavy.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.class_, size: 18, color: _primaryNavy),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    className,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _primaryNavy,
                    ),
                  ),
                  Text(
                    'Locked to class$sectionText',
                    style: const TextStyle(fontSize: 11, color: _textSecondary),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 12, color: Colors.green),
                  SizedBox(width: 4),
                  Text(
                    'Assigned',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoadingClasses) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _surfaceWhite,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _outlineVariant),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Loading your classes...',
                style: TextStyle(fontSize: 13, color: _textSecondary)),
          ],
        ),
      );
    }

    if (_classes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 20, color: Colors.amber[900]),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No classes found. Please return to the dashboard and create a class first.',
                style: TextStyle(fontSize: 13, color: Colors.amber[900]),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _surfaceWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedClassId,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down),
          items: _classes.map((cls) {
            return DropdownMenuItem(
              value: cls.id,
              child: Text(
                cls.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _textPrimary,
                ),
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedClassId = val;
              });
            }
          },
        ),
      ),
    );
  }

  /// Real-time Material Status Card reflecting Firestore document updates
  Widget _buildRealtimeStatusCard() {
    final material = _material;
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

    if (material == null) return const SizedBox.shrink();

    if (material.isProcessing) {
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

    if (material.isReady) {
      // Success State with Continue Action
      final previewLen = material.extractedText.length;

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

    if (material.hasFailed) {
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
                if (material.errorReason != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      material.errorReason!,
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
              material.formattedError,
              style: const TextStyle(fontSize: 13, color: _textPrimary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red[800],
                      side:
                          BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _pickAndUploadFile,
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('Choose Another'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryNavy,
                    side: const BorderSide(color: _primaryNavy),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _retryExtraction,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
