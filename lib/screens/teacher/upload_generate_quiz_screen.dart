import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/class_model.dart';
import '../../models/material_model.dart';
import '../../services/class_service.dart';
import '../../services/material_service.dart';
import '../../services/quiz_service.dart';
import '../../services/quiz_generation_client.dart';
import 'quiz_detail_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/studexa_background.dart';
import '../../widgets/app_feedback.dart';
import '../../widgets/gemini_api_generation_guard.dart';

/// Screen allowing a teacher to upload a study material (PDF/PPTX/DOCX),
/// perform client-side text extraction, configure question parameters,
/// and synthesize quizzes with automatic generation.
class UploadGenerateQuizScreen extends StatefulWidget {
  final String? initialClassId;
  final ClassModel? preselectedClass;
  final MaterialModel? preselectedMaterial;
  final bool isClassLocked;

  const UploadGenerateQuizScreen({
    super.key,
    this.initialClassId,
    this.preselectedClass,
    this.preselectedMaterial,
    this.isClassLocked = false,
  });

  @override
  State<UploadGenerateQuizScreen> createState() =>
      _UploadGenerateQuizScreenState();
}

class _UploadGenerateQuizScreenState extends State<UploadGenerateQuizScreen> {
  // ── Design tokens ───────────────────────────────────────────
  static const _primaryNavy = AppTheme.primaryNavy;
  static const _darkNavy = AppTheme.darkNavy;
  static const _surfaceWhite = AppTheme.surfaceWhite;
  static const _outlineVariant = AppTheme.outlineVariant;
  static const _textPrimary = AppTheme.textPrimary;
  static const _textSecondary = AppTheme.textSecondary;

  final MaterialService _materialService = MaterialService();
  final ClassService _classService = ClassService();
  final QuizService _quizService = QuizService();

  // ── Upload & Firestore Material State ───────────────────────
  String? _materialId;
  String? _actualQuizId;
  String? _actualQuizMaterialId;
  String? _selectedFileName;
  String? _selectedFileType;
  int? _selectedFileBytesLength;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String? _uploadError;
  Uint8List? _cachedPickedBytes;
  String? _cachedPickedPath;

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

    // Pre-populate if a material was passed in directly
    if (widget.preselectedMaterial != null) {
      final mat = widget.preselectedMaterial!;
      _material = mat;
      _materialId = mat.id;
      _selectedFileName = mat.fileName;
      _selectedFileType = mat.fileType;
      _selectedFileBytesLength = mat.fileSizeBytes;
      if (_selectedClassId == null && mat.classId.isNotEmpty) {
        _selectedClassId = mat.classId;
      }
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

  /// Real file picker and upload workflow with client-side text extraction
  Future<void> _pickAndUploadFile() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      AppFeedback.error(
        context,
        'Sign in with a teacher account before uploading study materials.',
        title: 'Teacher sign-in required',
      );
      return;
    }

    if (_selectedClassId == null) {
      AppFeedback.warning(
        context,
        'Select an existing class or create one before uploading a material.',
        title: 'Choose a class',
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
      String fileExtension = (pickedFile.extension ?? '').toLowerCase().trim();
      if (fileExtension.isEmpty && fileName.contains('.')) {
        fileExtension = fileName.split('.').last.toLowerCase().trim();
      }

      // Resilient byte length reading (safely handling Android SAF content URI quirks)
      int byteLength = 0;
      try {
        byteLength = pickedFile.lengthSync() ?? 0;
      } catch (_) {}
      if (byteLength <= 0) {
        try {
          byteLength = await pickedFile.length();
        } catch (_) {}
      }

      // Read bytes safely
      Uint8List? fileBytes;
      try {
        fileBytes = await pickedFile.readAsBytes();
      } catch (readErr) {
        debugPrint('Error reading picked file bytes: $readErr');
      }

      if (byteLength <= 0 && fileBytes != null && fileBytes.isNotEmpty) {
        byteLength = fileBytes.length;
      }

      // Validate file and target class before initiating upload
      MaterialService.validateUploadRequest(
        classId: _selectedClassId!,
        fileName: fileName,
        extension: fileExtension,
        byteLength: byteLength,
      );

      setState(() {
        _selectedFileName = fileName;
        _selectedFileType = fileExtension.toLowerCase();
        _selectedFileBytesLength = byteLength;
        _cachedPickedBytes = fileBytes;
        _cachedPickedPath = pickedFile.path;
        _isUploading = true;
        _uploadProgress = 0.1;
        _uploadError = null;
        _material = null;
      });

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
            // Throttle progress updates to at least 5% steps or completion to prevent UI stutter
            if ((progress - _uploadProgress).abs() >= 0.05 ||
                progress >= 1.0 ||
                _uploadProgress == 0.0) {
              setState(() {
                _uploadProgress = progress;
              });
            }
          }
        },
      );

      if (mounted) {
        setState(() {
          _materialId = createdMaterial.id;
          _material = createdMaterial;
          _isUploading = false;
          _uploadProgress = 1.0;
          _uploadError = null;
        });

        if (createdMaterial.isReady) {
          AppFeedback.success(
            context,
            '"$fileName" is ready. You can now configure and generate a quiz.',
            title: 'Material ready',
          );
        } else if (createdMaterial.hasFailed) {
          AppFeedback.error(
            context,
            createdMaterial.formattedError,
            title: 'Text extraction failed',
          );
        }

        // Listen to real-time status updates
        _listenToMaterial(createdMaterial.id);
      }
    } on MaterialValidationException catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadError = e.message;
        });
        AppFeedback.error(context, e.message, title: 'Unable to upload file');
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Material upload failed: $e');
        setState(() {
          _isUploading = false;
          _uploadError =
              'The material could not be uploaded. Check your connection and try again.';
        });
        AppFeedback.error(context, _uploadError!, title: 'Upload failed');
      }
    } finally {
      if (mounted && _isUploading) {
        setState(() => _isUploading = false);
      }
    }
  }

  /// Re-attempt upload of the currently selected file without reopening the OS file picker
  Future<void> _retryUploadWithCachedFile() async {
    if (_cachedPickedBytes == null && _cachedPickedPath == null) {
      _pickAndUploadFile();
      return;
    }

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      AppFeedback.error(
        context,
        'Sign in with a teacher account before uploading study materials.',
        title: 'Teacher sign-in required',
      );
      return;
    }

    if (_selectedClassId == null) {
      AppFeedback.warning(
        context,
        'Select the class that should receive this material.',
        title: 'Choose a class',
      );
      return;
    }

    final fileName = _selectedFileName ?? 'document';
    final fileExtension = _selectedFileType ?? '';
    final byteLength =
        _selectedFileBytesLength ?? _cachedPickedBytes?.length ?? 0;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.1;
      _uploadError = null;
      _material = null;
    });

    try {
      final createdMaterial = await _materialService.uploadStudyMaterial(
        teacherId: currentUserId,
        classId: _selectedClassId!,
        fileName: fileName,
        fileExtension: fileExtension,
        byteLength: byteLength,
        fileBytes: _cachedPickedBytes,
        localFilePath: _cachedPickedPath,
        onProgress: (progress) {
          if (mounted) {
            // Throttle progress updates to at least 5% steps or completion to prevent UI stutter
            if ((progress - _uploadProgress).abs() >= 0.05 ||
                progress >= 1.0 ||
                _uploadProgress == 0.0) {
              setState(() {
                _uploadProgress = progress;
              });
            }
          }
        },
      );

      if (mounted) {
        setState(() {
          _materialId = createdMaterial.id;
          _material = createdMaterial;
          _isUploading = false;
          _uploadProgress = 1.0;
          _uploadError = null;
        });

        if (createdMaterial.isReady) {
          AppFeedback.success(
            context,
            '"$fileName" is ready. You can now configure and generate a quiz.',
            title: 'Material ready',
          );
        } else if (createdMaterial.hasFailed) {
          AppFeedback.error(
            context,
            createdMaterial.formattedError,
            title: 'Text extraction failed',
          );
        }

        _listenToMaterial(createdMaterial.id);
      }
    } on MaterialValidationException catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadError = e.message;
        });
        AppFeedback.error(context, e.message, title: 'Unable to upload file');
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Material upload retry failed: $e');
        setState(() {
          _isUploading = false;
          _uploadError =
              'The material could not be uploaded. Check your connection and try again.';
        });
        AppFeedback.error(context, _uploadError!, title: 'Upload failed');
      }
    } finally {
      if (mounted && _isUploading) {
        setState(() => _isUploading = false);
      }
    }
  }

  /// Listen in real time to the materials/{materialId} Firestore document
  void _listenToMaterial(String materialId) {
    _materialSubscription?.cancel();
    _materialSubscription = _materialService
        .streamMaterial(materialId)
        .listen(
          (material) {
            if (!mounted || material == null) return;
            setState(() {
              _material = material;
            });
          },
          onError: (error) {
            if (!mounted) return;
            debugPrint('Material extraction stream failed: $error');
            AppFeedback.error(
              context,
              'Live extraction updates stopped. Reopen this screen to refresh the material status.',
              title: 'Status update unavailable',
            );
          },
        );
  }

  Future<void> _retryExtraction() async {
    if (_materialId == null) return;
    try {
      await _materialService.retryMaterialExtraction(_materialId!);
      if (!mounted) return;
      AppFeedback.info(
        context,
        'Studexa is processing the material again.',
        title: 'Extraction restarted',
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('Material extraction retry failed: $e');
      AppFeedback.error(
        context,
        'Text extraction could not be restarted. Check your connection and try again.',
        title: 'Unable to retry extraction',
      );
    }
  }

  Future<void> _generateQuiz({required bool isActual}) async {
    // Check if material is loaded and ready
    if (_material == null) {
      AppFeedback.warning(
        context,
        'Select an existing material or upload one before generating a quiz.',
        title: 'Choose a study material',
      );
      return;
    }
    if (_material!.hasFailed) {
      AppFeedback.error(
        context,
        _material!.formattedError,
        title: 'Material processing failed',
      );
      return;
    }
    if (!_material!.isReady) {
      AppFeedback.info(
        context,
        'Wait for text extraction to finish before generating the quiz.',
        title: 'Material is still processing',
      );
      return;
    }

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      AppFeedback.error(
        context,
        'Sign in with a teacher account before generating quizzes.',
        title: 'Teacher sign-in required',
      );
      return;
    }

    if (_selectedClassId == null) {
      AppFeedback.warning(
        context,
        'Select the class that should receive this quiz.',
        title: 'Choose a class',
      );
      return;
    }

    final activeTypes = _questionTypes.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    if (activeTypes.isEmpty) {
      AppFeedback.warning(
        context,
        'Choose at least one question type to include in the quiz.',
        title: 'Question type required',
      );
      return;
    }

    if (!await confirmGeminiGeneration(context) || !mounted) return;

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
        sourceQuizId: !isActual && _actualQuizMaterialId == _materialId
            ? _actualQuizId
            : null,
        preloadedExtractedText: _material?.extractedText,
        preloadedFileName: _material?.fileName,
      );

      if (isActual) {
        _actualQuizId = createdQuiz.id;
        _actualQuizMaterialId = createdQuiz.materialId;
      }
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Navigate to QuizDetailScreen for teacher review and editing
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              QuizDetailScreen(quiz: createdQuiz, showShortfallPrompt: true),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      debugPrint('Quiz generation failed: $e');
      final errorMessage = e is QuizGenerationException
          ? e.message
          : 'The quiz could not be generated. Check the material and your connection, then try again.';
      AppFeedback.error(context, errorMessage, title: 'Quiz generation failed');
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
      body: StudexaBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
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
                    if (_isUploading ||
                        _material != null ||
                        _uploadError != null) ...[
                      const SizedBox(height: 16),
                      _buildRealtimeStatusCard(),
                    ],

                    const SizedBox(height: 24),

                    // ── Section 3: Question Count ────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Number of Questions',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _textPrimary,
                            ),
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
                        Text(
                          '5 questions',
                          style: TextStyle(fontSize: 12, color: _textSecondary),
                        ),
                        Text(
                          '50 questions',
                          style: TextStyle(fontSize: 12, color: _textSecondary),
                        ),
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
                      'Select the question formats to generate from the extracted text.',
                      style: TextStyle(fontSize: 13, color: _textSecondary),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      decoration: BoxDecoration(
                        color: _surfaceWhite,
                        borderRadius: AppTheme.borderRadiusLg,
                        border: Border.all(color: _outlineVariant),
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: AppTheme.borderRadiusLg,
                        clipBehavior: Clip.antiAlias,
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
                    ),

                    const SizedBox(height: 28),

                    // ── Section 5: Quiz Generation Buttons ───────
                    if (!isMaterialReady) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Colors.amber[900],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _material?.isProcessing == true
                                    ? 'Generation buttons will unlock once text extraction completes.'
                                    : 'Please upload and extract a study material first to generate quizzes.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.amber[900],
                                ),
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
                          disabledBackgroundColor: _darkNavy.withValues(
                            alpha: 0.3,
                          ),
                          disabledForegroundColor: Colors.white.withValues(
                            alpha: 0.6,
                          ),
                          elevation: isMaterialReady ? 1 : 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: AppTheme.borderRadiusMd,
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
                            Flexible(
                              child: Text(
                                'Generate Actual Quiz (PDF Exam)',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                            borderRadius: AppTheme.borderRadiusMd,
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
                            Flexible(
                              child: Text(
                                'Generate Practice Quiz (App Practice)',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
        ),
      ),
    );
  }

  /// Class selection dropdown or empty state
  Widget _buildClassSelector() {
    if (widget.isClassLocked) {
      final className =
          widget.preselectedClass?.name ??
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
            Text(
              'Loading your classes...',
              style: TextStyle(fontSize: 13, color: _textSecondary),
            ),
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
            Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: Colors.amber[900],
            ),
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
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _primaryNavy.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
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

    if (_uploadError != null) {
      // Upload Failure State
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 22),
                SizedBox(width: 8),
                Text(
                  'Upload Failed',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _uploadError!,
              style: const TextStyle(fontSize: 13, color: _textPrimary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red[800],
                      side: BorderSide(
                        color: Colors.red.withValues(alpha: 0.5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _pickAndUploadFile,
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('Choose Another'),
                  ),
                ),
                if (_cachedPickedBytes != null ||
                    _cachedPickedPath != null) ...[
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryNavy,
                      side: const BorderSide(color: _primaryNavy),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _retryUploadWithCachedFile,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry Upload'),
                  ),
                ],
              ],
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
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _primaryNavy.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
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
                    'Extracting text content from $_selectedFileName...',
                    style: const TextStyle(fontSize: 12, color: _textSecondary),
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
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
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
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
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
                      side: BorderSide(
                        color: Colors.red.withValues(alpha: 0.5),
                      ),
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
