import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/class_model.dart';
import '../../models/material_model.dart';
import '../../models/quiz_model.dart';
import '../../services/class_service.dart';
import '../../services/material_service.dart';
import '../../services/quiz_service.dart';
import 'quiz_detail_screen.dart';
import 'upload_generate_quiz_screen.dart';
import '../materials/material_viewer_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/studexa_background.dart';
import '../../widgets/app_feedback.dart';

/// Class Details Screen for Teachers (Google Classroom style).
///
/// Displays:
/// - Class header with unique join code, copy/share action, and metadata.
/// - Materials tab with real-time class materials stream and upload action.
/// - Quizzes tab for quizzes assigned to this class.
/// - Students tab with live enrolled member roster.
class TeacherClassDetailsScreen extends StatefulWidget {
  final ClassModel classModel;
  final Stream<ClassModel?>? initialClassStream;
  final Stream<List<MaterialModel>>? initialMaterialsStream;
  final Stream<List<QuizModel>>? initialQuizzesStream;
  final Stream<List<ClassMember>>? initialStudentsStream;

  const TeacherClassDetailsScreen({
    super.key,
    required this.classModel,
    this.initialClassStream,
    this.initialMaterialsStream,
    this.initialQuizzesStream,
    this.initialStudentsStream,
  });

  @override
  State<TeacherClassDetailsScreen> createState() =>
      _TeacherClassDetailsScreenState();
}

class _TeacherClassDetailsScreenState extends State<TeacherClassDetailsScreen>
    with SingleTickerProviderStateMixin {
  static const _primaryNavy = AppTheme.primaryNavy;
  static const _darkNavy = AppTheme.darkNavy;
  static const _surfaceWhite = AppTheme.surfaceWhite;
  static const _outlineVariant = AppTheme.outlineVariant;
  static const _textPrimary = AppTheme.textPrimary;
  static const _textSecondary = AppTheme.textSecondary;

  late TabController _tabController;
  final MaterialService _materialService = MaterialService();
  final ClassService _classService = ClassService();
  final QuizService _quizService = QuizService();

  late Stream<ClassModel?> _classStream;
  late Stream<List<MaterialModel>> _materialsStream;
  late Stream<List<QuizModel>> _quizzesStream;
  late Stream<List<ClassMember>> _studentsStream;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initStreams(widget.classModel.id);
  }

  void _initStreams(String classId) {
    _classStream =
        widget.initialClassStream ?? _classService.streamClass(classId);
    _materialsStream =
        widget.initialMaterialsStream ??
        _materialService.streamClassMaterials(classId);
    _quizzesStream =
        widget.initialQuizzesStream ?? _quizService.streamClassQuizzes(classId);
    _studentsStream =
        widget.initialStudentsStream ??
        _classService.getClassMembersStream(classId);
  }

  @override
  void didUpdateWidget(covariant TeacherClassDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.classModel.id != widget.classModel.id) {
      _initStreams(widget.classModel.id);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _copyJoinCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    AppFeedback.success(
      context,
      'Join code $code is ready to share.',
      title: 'Copied to clipboard',
      duration: const Duration(seconds: 2),
    );
  }

  void _openUploadScreen(ClassModel liveClass) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UploadGenerateQuizScreen(
          initialClassId: liveClass.id,
          preselectedClass: liveClass,
          isClassLocked: true,
        ),
      ),
    );
  }

  void _showMaterialDetails(MaterialModel material) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildFileTypeBadge(material.fileType),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        material.fileName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        ' • Uploaded ',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              'Extraction Status',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                _buildStatusChip(material),
                if (material.hasFailed)
                  TextButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry Extraction'),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _materialService.retryMaterialExtraction(
                        material.id,
                      );
                    },
                  ),
              ],
            ),
            if (material.extractedText.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Extracted Text Preview',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _surfaceWhite,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _outlineVariant),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    material.extractedText,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (material.isReady) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryNavy,
                    side: const BorderSide(color: _primaryNavy, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    MaterialViewerScreen.open(
                      context: context,
                      material: material,
                      materialService: _materialService,
                    );
                  },
                  icon: Icon(
                    material.fileType.toLowerCase() == 'pdf'
                        ? Icons.picture_as_pdf
                        : Icons.open_in_new,
                    size: 18,
                  ),
                  label: Text(
                    'View Material (${material.fileType.toUpperCase()})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UploadGenerateQuizScreen(
                          initialClassId: widget.classModel.id,
                          preselectedClass: widget.classModel,
                          preselectedMaterial: material,
                          isClassLocked: true,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text(
                    'Generate Quiz from this Material',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          title: const Text('Delete Material?'),
                          content: Text(
                            'Are you sure you want to delete "${material.fileName}"? This cannot be undone.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                              ),
                              onPressed: () => Navigator.pop(dCtx, true),
                              child: const Text(
                                'Delete',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        if (!mounted) return;
                        AppFeedback.info(
                          context,
                          'Removing "${material.fileName}" from this class.',
                          title: 'Deleting material',
                          duration: const Duration(seconds: 2),
                        );

                        try {
                          await _materialService.deleteMaterial(
                            materialId: material.id,
                            fileRef: material.fileRef,
                            fileName: material.fileName,
                            convertedPdfRef: material.convertedPdfRef,
                          );
                          if (!mounted) return;
                          AppFeedback.success(
                            context,
                            '"${material.fileName}" was removed from the class.',
                            title: 'Material deleted',
                          );
                        } catch (e) {
                          if (!mounted) return;
                          debugPrint('Failed to delete material: $e');
                          AppFeedback.error(
                            context,
                            'The material could not be deleted. Check your connection and try again.',
                            title: 'Unable to delete material',
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete Material'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildFileTypeBadge(String ext) {
    Color bg = Colors.blue;
    String label = ext.toUpperCase();

    if (ext.toLowerCase() == 'pdf') {
      bg = Colors.redAccent;
    } else if (ext.toLowerCase() == 'pptx') {
      bg = Colors.orange;
    } else if (ext.toLowerCase() == 'docx') {
      bg = Colors.blueAccent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bg.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: bg),
      ),
    );
  }

  Widget _buildStatusChip(MaterialModel material) {
    if (material.isReady) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 14, color: Colors.green),
            SizedBox(width: 4),
            Flexible(
              child: Text(
                'Extracted & Ready',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    if (material.isProcessing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.blue,
              ),
            ),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Processing Text...',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              material.userFriendlyErrorReason,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.redAccent,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ClassModel?>(
      stream: _classStream,
      initialData: widget.classModel,
      builder: (context, classSnapshot) {
        final liveClass = classSnapshot.data ?? widget.classModel;

        return Scaffold(
          body: StudexaBackground(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: Column(
                    children: [
                      // ── Top Navigation Bar ────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: _textPrimary,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                liveClass.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Google Classroom Header Banner ────────────
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_primaryNavy, _darkNavy],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: _primaryNavy.withValues(alpha: 0.25),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    liveClass.name,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${liveClass.rosterCount} students',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (liveClass.teacherName.isNotEmpty)
                              Text(
                                'Instructor: ${liveClass.teacherName}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            const SizedBox(height: 14),
                            // Join Code Action Bar
                            GestureDetector(
                              onTap: () => _copyJoinCode(liveClass.joinCode),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.vpn_key_outlined,
                                        size: 14,
                                        color: Colors.white70,
                                      ),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'CLASS CODE: ',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white70,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      Text(
                                        liveClass.joinCode,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.copy,
                                        size: 14,
                                        color: Colors.white70,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ── Segmented Tabs ───────────────────────────
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: _surfaceWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _outlineVariant),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          labelColor: _primaryNavy,
                          unselectedLabelColor: _textSecondary,
                          indicatorColor: _primaryNavy,
                          indicatorWeight: 3,
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          tabs: const [
                            Tab(
                              icon: Icon(Icons.folder_outlined),
                              text: 'Materials',
                            ),
                            Tab(
                              icon: Icon(Icons.quiz_outlined),
                              text: 'Quizzes',
                            ),
                            Tab(
                              icon: Icon(Icons.people_outline),
                              text: 'Students',
                            ),
                          ],
                        ),
                      ),

                      // ── Tab Views ────────────────────────────────
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // 1. Materials Tab
                            _KeepAliveTab(child: _buildMaterialsTab(liveClass)),

                            // 2. Quizzes Tab
                            _KeepAliveTab(child: _buildQuizzesTab(liveClass)),

                            // 3. Students / Roster Tab
                            _KeepAliveTab(child: _buildStudentsTab(liveClass)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: _primaryNavy,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.upload_file),
            label: const Text('Upload Material'),
            onPressed: () => _openUploadScreen(liveClass),
          ),
        );
      },
    );
  }

  // ── Materials Tab View ─────────────────────────────────────────
  Widget _buildMaterialsTab(ClassModel liveClass) {
    return StreamBuilder<List<MaterialModel>>(
      stream: _materialsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2.5),
          );
        }

        final materials = snapshot.data ?? [];

        if (materials.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.upload_file_outlined,
                    size: 64,
                    color: _primaryNavy.withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Study Materials Yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Upload a lecture PDF, slides (PPTX), or notes (DOCX) for this class to extract text and generate quizzes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: _textSecondary),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _openUploadScreen(liveClass),
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Upload Study Material'),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          itemCount: materials.length,
          itemBuilder: (context, index) {
            final mat = materials[index];
            return RepaintBoundary(
              key: ValueKey(mat.id),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _surfaceWhite,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    leading: _buildFileTypeBadge(mat.fileType),
                    title: Text(
                      mat.fileName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              mat.formattedFileSize,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '• ',
                              style: const TextStyle(
                                fontSize: 12,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _buildStatusChip(mat),
                      ],
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: _textSecondary,
                    ),
                    onTap: () => _showMaterialDetails(mat),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Quizzes Tab View ───────────────────────────────────────────
  Widget _buildQuizzesTab(ClassModel liveClass) {
    return StreamBuilder<List<QuizModel>>(
      stream: _quizzesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, color: _textSecondary),
                  const SizedBox(height: 12),
                  const Text(
                    'Unable to load quizzes. Check your connection and try again.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _quizzesStream =
                          widget.initialQuizzesStream ??
                          _quizService.streamClassQuizzes(liveClass.id);
                    }),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2.5),
          );
        }

        final quizzes = snapshot.data ?? [];

        if (quizzes.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.quiz_outlined,
                    size: 64,
                    color: _primaryNavy.withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Quizzes Created Yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Quizzes generated from this class\'s study materials will appear here with student attempt analytics.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: _textSecondary),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _openUploadScreen(liveClass),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Generate from Material'),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          itemCount: quizzes.length,
          itemBuilder: (context, index) {
            final q = quizzes[index];
            return RepaintBoundary(
              key: ValueKey(q.id),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _surfaceWhite,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: (q.isActual ? Colors.purple : _primaryNavy)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        q.isActual ? Icons.print_outlined : Icons.quiz_outlined,
                        color: q.isActual ? Colors.purple : _primaryNavy,
                      ),
                    ),
                    title: Text(
                      q.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          '${q.questionCount} Questions • ${q.totalPoints.toStringAsFixed(0)} Points',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _buildQuizBadge(
                              label: q.isActual
                                  ? 'Actual Exam'
                                  : 'Practice Quiz',
                              color: q.isActual ? Colors.purple : Colors.blue,
                            ),
                            _buildQuizBadge(
                              label: q.formattedStatus,
                              color: q.isPublished
                                  ? Colors.green
                                  : (q.isFinalized
                                        ? Colors.teal
                                        : Colors.orange),
                            ),
                            _buildQuizBadge(
                              label: q.isGeminiGenerated
                                  ? 'AI Generated'
                                  : 'Auto Generated',
                              color: Colors.indigo,
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: _textSecondary,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => QuizDetailScreen(quiz: q),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuizBadge({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  // ── Students / Roster Tab View ─────────────────────────────────
  Widget _buildStudentsTab(ClassModel liveClass) {
    return StreamBuilder<List<ClassMember>>(
      stream: _studentsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2.5),
          );
        }

        final members = snapshot.data ?? [];
        final students = members.where((m) => m.role == 'student').toList();

        if (students.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 64,
                    color: _primaryNavy.withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Students Enrolled Yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Share the join code "${liveClass.joinCode}" with your students to have them join this class.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: _textSecondary),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _copyJoinCode(liveClass.joinCode),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy Join Code'),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: students.length,
          itemBuilder: (context, index) {
            final student = students[index];
            final initial = student.displayName.isNotEmpty
                ? student.displayName[0].toUpperCase()
                : 'S';

            return RepaintBoundary(
              key: ValueKey(student.userId),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: _surfaceWhite,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _primaryNavy.withValues(alpha: 0.1),
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _primaryNavy,
                        ),
                      ),
                    ),
                    title: Text(
                      student.displayName.isNotEmpty
                          ? student.displayName
                          : 'Student',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                      ),
                    ),
                    subtitle: student.email.isNotEmpty
                        ? Text(
                            student.email,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _textSecondary,
                            ),
                          )
                        : null,
                    trailing: student.joinedAt != null
                        ? Text(
                            'Joined ',
                            style: const TextStyle(
                              fontSize: 11,
                              color: _textSecondary,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Helper widget to retain tab state and scroll position across TabBarView switches.
class _KeepAliveTab extends StatefulWidget {
  final Widget child;
  const _KeepAliveTab({required this.child});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
