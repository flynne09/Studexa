import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../services/class_service.dart';
import '../../models/user_profile.dart';
import '../../models/class_model.dart';
import '../auth/role_selection_screen.dart';
import 'upload_generate_quiz_screen.dart';
import 'teacher_class_details_screen.dart';

/// Teacher Home Screen displaying the teacher's classes, quick actions
/// to create classes or upload materials, and recent quiz activity.
class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  // ── Design tokens ───────────────────────────────────────────
  static const _primaryNavy = Color(0xFF1A237E);
  static const _gradientStart = Color(0xFFF3F0FF);
  static const _gradientEnd = Color(0xFFEFF6FF);
  static const _surfaceWhite = Color(0xFFFBF9F8);
  static const _outlineVariant = Color(0xFFC6C5D4);
  static const _textPrimary = Color(0xFF1B1C1C);
  static const _textSecondary = Color(0xFF454652);

  UserProfile? _teacherProfile;

  @override
  void initState() {
    super.initState();
    _loadTeacherProfile();
  }

  Future<void> _loadTeacherProfile() async {
    final profile = await AuthService().getCurrentUserProfile();
    if (mounted && profile != null) {
      setState(() {
        _teacherProfile = profile;
      });
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceWhite,
        title: const Text(
          'Log Out',
          style: TextStyle(fontWeight: FontWeight.bold, color: _textPrimary),
        ),
        content: const Text(
          'Are you sure you want to log out of Studexa?',
          style: TextStyle(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: _textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AuthService().signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _showClassSelectionSheet() async {
    final uid = _teacherProfile?.uid;
    if (uid == null) return;

    final classes = await ClassService().getTeacherClassesStream(uid).first;
    if (!mounted) return;

    if (classes.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _surfaceWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: _primaryNavy),
              SizedBox(width: 8),
              Text(
                'Create a Class First',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          content: const Text(
            'You must select or create a class before uploading study materials. All uploaded materials strictly belong to their assigned class.',
            style: TextStyle(color: _textSecondary, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: _textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryNavy,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _showCreateClassDialog();
              },
              child: const Text('Create Class'),
            ),
          ],
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: _surfaceWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Target Class',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose which class this study material will belong to:',
                style: TextStyle(fontSize: 13, color: _textSecondary),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: classes.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final cls = classes[i];
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: _outlineVariant),
                      ),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _primaryNavy.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.school, color: _primaryNavy, size: 20),
                      ),
                      title: Text(
                        cls.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        'Code: ${cls.joinCode} • ${cls.rosterCount} students',
                        style: const TextStyle(fontSize: 12, color: _textSecondary),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: _primaryNavy),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UploadGenerateQuizScreen(
                              initialClassId: cls.id,
                              preselectedClass: cls,
                              isClassLocked: true,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateClassDialog() {
    final nameController = TextEditingController();
    bool isCreating = false;
    String? errorMessage;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _surfaceWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Create New Class',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _textPrimary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter a class name. A unique join code will be generated automatically.',
                style: TextStyle(fontSize: 13, color: _textSecondary),
              ),
              const SizedBox(height: 16),
              if (errorMessage != null) ...[
                Text(
                  errorMessage!,
                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: nameController,
                autofocus: true,
                enabled: !isCreating,
                decoration: InputDecoration(
                  hintText: 'e.g. Physics 102 - Mechanics',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _primaryNavy, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isCreating ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: _textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryNavy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: isCreating
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        setDialogState(() {
                          errorMessage = 'Please enter a class name.';
                        });
                        return;
                      }

                      setDialogState(() {
                        isCreating = true;
                        errorMessage = null;
                      });

                      try {
                        final teacherId = _teacherProfile?.uid ??
                            AuthService().currentUser?.uid ??
                            'teacher_demo';
                        final teacherName = _teacherProfile?.displayName ??
                            AuthService().currentUser?.displayName ??
                            'Teacher';

                        final createdClass = await ClassService().createClass(
                          name: name,
                          teacherId: teacherId,
                          teacherName: teacherName,
                        );

                        if (!mounted) return;
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                        }
                        _showClassCreatedSuccessDialog(createdClass);
                      } catch (e) {
                        setDialogState(() {
                          isCreating = false;
                          errorMessage = 'Failed to create class: $e';
                        });
                      }
                    },
              child: isCreating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showClassCreatedSuccessDialog(ClassModel createdClass) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 24),
            SizedBox(width: 8),
            Text(
              'Class Created!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _textPrimary,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              createdClass.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Share this join code with your students:',
              style: TextStyle(fontSize: 13, color: _textSecondary),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: _primaryNavy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _primaryNavy.withValues(alpha: 0.2)),
              ),
              child: Center(
                child: Text(
                  createdClass.joinCode,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                    color: _primaryNavy,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          child: CustomScrollView(
            slivers: [
              // ── Header Bar ─────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: _primaryNavy.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.school,
                                  size: 16,
                                  color: _primaryNavy,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Teacher Portal',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _primaryNavy,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'My Classes & Materials',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: _textPrimary,
                            ),
                          ),
                        ],
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Account options',
                        color: _surfaceWhite,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: _outlineVariant),
                        ),
                        onSelected: (val) {
                          if (val == 'logout') {
                            _handleLogout();
                          }
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem<String>(
                            enabled: false,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _teacherProfile?.displayName ?? 'Teacher Account',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: _textPrimary,
                                  ),
                                ),
                                if (_teacherProfile?.email.isNotEmpty ?? false)
                                  Text(
                                    _teacherProfile!.email,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem<String>(
                            value: 'logout',
                            child: Row(
                              children: [
                                Icon(Icons.logout,
                                    color: Colors.redAccent, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Log Out',
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _surfaceWhite,
                            shape: BoxShape.circle,
                            border: Border.all(color: _outlineVariant),
                          ),
                          child: Center(
                            child: _teacherProfile != null &&
                                    _teacherProfile!.displayName.isNotEmpty
                                ? Text(
                                    _teacherProfile!.displayName[0]
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _primaryNavy,
                                    ),
                                  )
                                : const Icon(
                                    Icons.person_outline,
                                    color: _primaryNavy,
                                    size: 22,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Prominent Action Buttons ───────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    children: [
                      // Upload Material & Generate Quiz Action
                      Expanded(
                        child: _ActionCard(
                          title: 'Upload Material',
                          subtitle: 'Select class & file',
                          icon: Icons.upload_file_outlined,
                          isPrimary: true,
                          onTap: _showClassSelectionSheet,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Create Class Action
                      Expanded(
                        child: _ActionCard(
                          title: 'Create Class',
                          subtitle: 'Generate join code',
                          icon: Icons.add_circle_outline,
                          isPrimary: false,
                          onTap: _showCreateClassDialog,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Section: Classes ───────────────────────────
              StreamBuilder<List<ClassModel>>(
                stream: _teacherProfile != null
                    ? ClassService()
                        .getTeacherClassesStream(_teacherProfile!.uid)
                    : const Stream.empty(),
                builder: (context, snapshot) {
                  final classes = snapshot.data ?? [];
                  final countText =
                      snapshot.connectionState == ConnectionState.waiting
                          ? 'Loading...'
                          : '${classes.length} total';

                  return SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Enrolled Classes',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _textPrimary,
                                ),
                              ),
                              Text(
                                countText,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          classes.isEmpty)
                        const SliverToBoxAdapter(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.5),
                              ),
                            ),
                          ),
                        )
                      else if (classes.isEmpty)
                        SliverToBoxAdapter(
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: _surfaceWhite,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _outlineVariant),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.school_outlined,
                                    size: 36,
                                    color:
                                        _primaryNavy.withValues(alpha: 0.5)),
                                const SizedBox(height: 10),
                                const Text(
                                  'No classes yet',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: _textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Tap "Create Class" above to create your first class and get a join code.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 13, color: _textSecondary),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20.0),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final item = classes[index];
                                return _ClassItemCard(
                                  classModel: item,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            TeacherClassDetailsScreen(
                                          classModel: item,
                                        ),
                                      ),
                                    );
                                  },
                                  onUploadTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            UploadGenerateQuizScreen(
                                          initialClassId: item.id,
                                          preselectedClass: item,
                                          isClassLocked: true,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                              childCount: classes.length,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),

              // ── Section: Class Workflow Info ───────────────
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _surfaceWhite,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lightbulb_outline,
                              size: 20, color: _primaryNavy),
                          SizedBox(width: 8),
                          Text(
                            'Classroom Workflow',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Studexa organizes learning materials and quizzes by class:\n'
                        '• Tap any class above to view its materials, quizzes, and student roster.\n'
                        '• Upload study materials directly inside each class (PDF, PPTX, DOCX).\n'
                        '• Share the unique join code with students to invite them to your class.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Action card for prominent "Upload Material" or "Create Class" buttons.
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const primaryNavy = Color(0xFF1A237E);
    const surfaceWhite = Color(0xFFFBF9F8);
    const outlineVariant = Color(0xFFC6C5D4);

    return Material(
      color: isPrimary ? primaryNavy : surfaceWhite,
      borderRadius: BorderRadius.circular(14),
      elevation: isPrimary ? 2 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPrimary ? Colors.transparent : outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isPrimary
                      ? Colors.white.withValues(alpha: 0.15)
                      : primaryNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: isPrimary ? Colors.white : primaryNavy,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isPrimary ? Colors.white : const Color(0xFF1B1C1C),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: isPrimary
                      ? Colors.white.withValues(alpha: 0.8)
                      : const Color(0xFF454652),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card representing a teacher's class with name, join code, roster count, and quick actions.
class _ClassItemCard extends StatelessWidget {
  const _ClassItemCard({
    required this.classModel,
    required this.onTap,
    required this.onUploadTap,
  });

  final ClassModel classModel;
  final VoidCallback onTap;
  final VoidCallback onUploadTap;

  @override
  Widget build(BuildContext context) {
    const primaryNavy = Color(0xFF1A237E);
    const surfaceWhite = Color(0xFFFBF9F8);
    const outlineVariant = Color(0xFFC6C5D4);
    const textPrimary = Color(0xFF1B1C1C);
    const textSecondary = Color(0xFF454652);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: outlineVariant),
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
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            classModel.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          if (classModel.section.isNotEmpty)
                            Text(
                              'Section: ${classModel.section}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: classModel.joinCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Join code ${classModel.joinCode} copied to clipboard!'),
                            backgroundColor: primaryNavy,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: primaryNavy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: primaryNavy.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.vpn_key_outlined,
                              size: 13,
                              color: primaryNavy,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              classModel.joinCode,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: primaryNavy,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.people_alt_outlined,
                      size: 15,
                      color: textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${classModel.rosterCount} students enrolled',
                      style: const TextStyle(
                        fontSize: 13,
                        color: textSecondary,
                      ),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryNavy,
                        side: BorderSide(
                            color: primaryNavy.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onUploadTap,
                      icon: const Icon(Icons.upload_file, size: 14),
                      label: const Text('Upload',
                          style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_ios,
                      size: 13,
                      color: textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
