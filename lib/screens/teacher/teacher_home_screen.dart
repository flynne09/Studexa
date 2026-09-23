import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../services/class_service.dart';
import '../../models/user_profile.dart';
import '../../models/class_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_feedback.dart';
import '../../widgets/home_account_menu.dart';
import '../../widgets/studexa_background.dart';
import '../auth/role_selection_screen.dart';
import 'upload_generate_quiz_screen.dart';
import 'teacher_class_details_screen.dart';
import 'gemini_api_settings_screen.dart';

/// Teacher Home Screen displaying the teacher's classes, quick actions
/// to create classes or upload materials, and recent quiz activity.
class TeacherHomeScreen extends StatefulWidget {
  final UserProfile? initialProfile;
  final Stream<List<ClassModel>>? initialClassesStream;

  const TeacherHomeScreen({
    super.key,
    this.initialProfile,
    this.initialClassesStream,
  });

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  // ── Design tokens ───────────────────────────────────────────
  static const _primaryNavy = AppTheme.primaryNavy;
  static const _surfaceWhite = AppTheme.surfaceWhite;
  static const _outlineVariant = AppTheme.outlineVariant;
  static const _textPrimary = AppTheme.textPrimary;
  static const _textSecondary = AppTheme.textSecondary;

  UserProfile? _teacherProfile;
  Stream<List<ClassModel>>? _classesStream;

  @override
  void initState() {
    super.initState();
    _teacherProfile = widget.initialProfile;
    _classesStream = widget.initialClassesStream;
    if (_classesStream == null) {
      final currentUid =
          widget.initialProfile?.uid ?? AuthService().currentUser?.uid;
      if (currentUid != null) {
        _classesStream = ClassService().getTeacherClassesStream(currentUid);
      }
    }
    if (_teacherProfile == null) {
      _loadTeacherProfile();
    }
  }

  Future<void> _loadTeacherProfile() async {
    final profile = await AuthService().getCurrentUserProfile();
    if (mounted && profile != null) {
      setState(() {
        _teacherProfile = profile;
        _classesStream = ClassService().getTeacherClassesStream(profile.uid);
      });
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showStudexaLogoutDialog(context);

    if (confirm) {
      await AuthService().signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        (route) => false,
      );
    }
  }

  void _openGeminiSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const GeminiApiSettingsScreen()));
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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
              child: const Text(
                'Cancel',
                style: TextStyle(color: _textSecondary),
              ),
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
                      key: ValueKey(cls.id),
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
                        child: const Icon(
                          Icons.school,
                          color: _primaryNavy,
                          size: 20,
                        ),
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
                        style: const TextStyle(
                          fontSize: 12,
                          color: _textSecondary,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        size: 14,
                        color: _primaryNavy,
                      ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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
                    borderSide: const BorderSide(
                      color: _primaryNavy,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isCreating ? null : () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: _textSecondary),
              ),
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
                        final teacherId =
                            _teacherProfile?.uid ??
                            AuthService().currentUser?.uid ??
                            'teacher_demo';
                        final teacherName =
                            _teacherProfile?.displayName ??
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
                        debugPrint('Failed to create class: $e');
                        setDialogState(() {
                          isCreating = false;
                          errorMessage =
                              'We could not create the class. Check your connection and try again.';
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
      body: StudexaBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: CustomScrollView(
                slivers: [
                  // ── Header Bar ─────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ClipRRect(
                                      key: const Key('teacher_header_app_icon'),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.asset(
                                        'assets/images/Studexa_icon.png',
                                        width: 28,
                                        height: 28,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Flexible(
                                      child: Text(
                                        'Teacher Account',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _primaryNavy,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'My Classes & Materials',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: _textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          HomeAccountMenu(
                            key: const Key('teacher_header_avatar_menu'),
                            displayName:
                                _teacherProfile?.displayName ?? 'Teacher',
                            email: _teacherProfile?.email ?? '',
                            roleLabel: 'Teacher',
                            logoutItemKey: const Key('teacher_menu_logout'),
                            geminiSettingsItemKey: const Key(
                              'teacher_menu_gemini_settings',
                            ),
                            onGeminiSettings: _openGeminiSettings,
                            onLogout: _handleLogout,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Teacher Profile & Quick Action Card ────────
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: AppTheme.heroGradient,
                        borderRadius: AppTheme.borderRadiusXl,
                        boxShadow: AppTheme.featureShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.28),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    _teacherProfile != null &&
                                            _teacherProfile!
                                                .displayName
                                                .isNotEmpty
                                        ? _teacherProfile!.displayName[0]
                                              .toUpperCase()
                                        : 'T',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _teacherProfile?.displayName ??
                                                'Teacher Account',
                                            key: const Key(
                                              'teacher_display_name_text',
                                            ),
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.16,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              AppTheme.radiusPill,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.22,
                                              ),
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.badge_outlined,
                                                size: 12,
                                                color: Colors.white,
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                'Teacher',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _teacherProfile?.email.isNotEmpty == true
                                          ? _teacherProfile!.email
                                          : 'Signed in as teacher',
                                      key: const Key('teacher_email_text'),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFFD7DAFF),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
                    stream: _classesStream ?? const Stream.empty(),
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
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                24,
                                20,
                                12,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Enrolled Classes',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: _textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
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
                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              classes.isEmpty)
                            const SliverToBoxAdapter(
                              child: Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else if (classes.isEmpty)
                            SliverToBoxAdapter(
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 8,
                                ),
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: _surfaceWhite,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: _outlineVariant),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.school_outlined,
                                      size: 36,
                                      color: _primaryNavy.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
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
                                        fontSize: 13,
                                        color: _textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20.0,
                              ),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  final item = classes[index];
                                  return RepaintBoundary(
                                    key: ValueKey(item.id),
                                    child: _ClassItemCard(
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
                                    ),
                                  );
                                }, childCount: classes.length),
                              ),
                            ),
                        ],
                      );
                    },
                  ),

                  // Bottom spacing for visual balance and scroll clearance
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
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
    return Material(
      color: Colors.transparent,
      borderRadius: AppTheme.borderRadiusXl,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.borderRadiusXl,
        child: Container(
          padding: const EdgeInsets.all(AppTheme.spacingXl),
          decoration: BoxDecoration(
            color: isPrimary ? null : AppTheme.surfaceWhite,
            gradient: isPrimary ? AppTheme.heroGradient : null,
            borderRadius: AppTheme.borderRadiusXl,
            border: Border.all(
              color: isPrimary ? Colors.transparent : AppTheme.outlineSubtle,
            ),
            boxShadow: isPrimary ? AppTheme.featureShadow : AppTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isPrimary
                          ? Colors.white.withValues(alpha: 0.15)
                          : AppTheme.primaryContainer,
                      borderRadius: AppTheme.borderRadiusMd,
                    ),
                    child: Icon(
                      icon,
                      size: 23,
                      color: isPrimary ? Colors.white : AppTheme.primaryNavy,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 19,
                    color: isPrimary
                        ? Colors.white.withValues(alpha: 0.72)
                        : AppTheme.primaryNavy,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isPrimary ? Colors.white : AppTheme.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: isPrimary
                      ? Colors.white.withValues(alpha: 0.8)
                      : AppTheme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: AppTheme.borderRadiusXl,
        border: Border.all(color: AppTheme.outlineSubtle),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppTheme.borderRadiusXl,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppTheme.borderRadiusXl,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: AppTheme.heroGradient,
                        borderRadius: AppTheme.borderRadiusMd,
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: const Icon(
                        Icons.school_outlined,
                        color: Colors.white,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            classModel.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (classModel.section.isNotEmpty)
                            Text(
                              'Section: ${classModel.section}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: classModel.joinCode),
                        );
                        AppFeedback.success(
                          context,
                          'Join code ${classModel.joinCode} is ready to share.',
                          title: 'Copied to clipboard',
                          duration: const Duration(seconds: 2),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.vpn_key_outlined,
                              size: 13,
                              color: AppTheme.primaryNavy,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              classModel.joinCode,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryNavy,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.people_alt_outlined,
                            size: 15,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${classModel.rosterCount} students enrolled',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryNavy,
                        side: BorderSide(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.4),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onUploadTap,
                      icon: const Icon(Icons.upload_file, size: 14),
                      label: const Text(
                        'Upload',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_ios,
                      size: 13,
                      color: AppTheme.textSecondary,
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
