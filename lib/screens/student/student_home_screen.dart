import 'package:flutter/material.dart';
import '../../models/class_model.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/class_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/home_account_menu.dart';
import '../../widgets/studexa_background.dart';
import '../auth/role_selection_screen.dart';
import 'join_class_screen.dart';
import 'student_class_details_screen.dart';

/// Student Home Screen displaying enrolled classes and assigned Practice Quizzes
/// with explicit availability statuses: open, closed, or past deadline.
class StudentHomeScreen extends StatefulWidget {
  final UserProfile? initialProfile;
  final Stream<List<ClassModel>>? initialClassesStream;

  const StudentHomeScreen({
    super.key,
    this.initialProfile,
    this.initialClassesStream,
  });

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  // ── Design tokens ───────────────────────────────────────────
  static const _primaryNavy = AppTheme.primaryNavy;
  static const _surfaceWhite = AppTheme.surfaceWhite;
  static const _outlineVariant = AppTheme.outlineVariant;
  static const _textPrimary = AppTheme.textPrimary;
  static const _textSecondary = AppTheme.textSecondary;

  UserProfile? _studentProfile;

  @override
  void initState() {
    super.initState();
    _studentProfile = widget.initialProfile;
    if (_studentProfile == null) {
      _loadStudentProfile();
    }
  }

  Future<void> _loadStudentProfile() async {
    final profile = await AuthService().getCurrentUserProfile();
    if (mounted && profile != null) {
      setState(() {
        _studentProfile = profile;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StudexaBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTheme.maxContentWidthTablet,
              ),
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
                                  key: const Key('student_header_app_icon'),
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
                                    'Student Account',
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
                              'My Classes & Quizzes',
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
                        key: const Key('student_header_avatar_menu'),
                        displayName:
                            _studentProfile?.displayName ?? 'Student',
                        email: _studentProfile?.email ?? '',
                        roleLabel: 'Student',
                        logoutItemKey: const Key('student_menu_logout'),
                        onLogout: _handleLogout,
                      ),
                    ],
                  ),
                ),
              ),

              // ── Student Profile & Quick Action Card ────────
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _surfaceWhite,
                    borderRadius: AppTheme.borderRadiusXl,
                    border: Border.all(color: AppTheme.outlineSubtle),
                    boxShadow: AppTheme.cardShadow,
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
                              gradient: AppTheme.heroGradient,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _surfaceWhite,
                                width: 2,
                              ),
                              boxShadow: AppTheme.cardShadow,
                            ),
                            child: Center(
                              child: Text(
                                _studentProfile != null &&
                                        _studentProfile!.displayName.isNotEmpty
                                    ? _studentProfile!.displayName[0]
                                        .toUpperCase()
                                    : 'S',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.onPrimary,
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
                                        _studentProfile?.displayName ??
                                            'Student Account',
                                        key: const Key(
                                            'student_display_name_text'),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: _textPrimary,
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
                                        color: AppTheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(
                                          AppTheme.radiusPill,
                                        ),
                                        border: Border.all(
                                          color: _primaryNavy.withValues(
                                            alpha: 0.12,
                                          ),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.person_outline_rounded,
                                            size: 12,
                                            color: _primaryNavy,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Student',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: _primaryNavy,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _studentProfile?.email.isNotEmpty == true
                                      ? _studentProfile!.email
                                      : 'Signed in as student',
                                  key: const Key('student_email_text'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          key: const Key('student_join_class_button'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryNavy,
                            foregroundColor: AppTheme.onPrimary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppTheme.borderRadiusMd,
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const JoinClassScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text(
                            'Join Class',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Class Sections ─────────────────────────────
              StreamBuilder<List<ClassModel>>(
                stream: widget.initialClassesStream ??
                    (_studentProfile != null
                        ? ClassService()
                            .getStudentJoinedClassesStream(_studentProfile!.uid)
                        : const Stream.empty()),
                builder: (context, snapshot) {
                  final joinedClasses = snapshot.data ?? [];

                  if (snapshot.connectionState == ConnectionState.waiting &&
                      joinedClasses.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child:
                                CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                      ),
                    );
                  }

                  if (joinedClasses.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: _surfaceWhite,
                          borderRadius: AppTheme.borderRadiusLg,
                          border: Border.all(color: _outlineVariant),
                          boxShadow: AppTheme.cardShadow,
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.menu_book_outlined,
                                size: 40,
                                color: _primaryNavy.withValues(alpha: 0.5)),
                            const SizedBox(height: 12),
                            const Text(
                              'No classes joined yet',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Tap the "Join Class" button at the top right to enter a unique code provided by your teacher.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 13, color: _textSecondary),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryNavy,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppTheme.borderRadiusMd,
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const JoinClassScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Enter Join Code'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, classIndex) {
                          final classItem = joinedClasses[classIndex];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: _surfaceWhite,
                              borderRadius: AppTheme.borderRadiusXl,
                              border: Border.all(color: AppTheme.outlineSubtle),
                              boxShadow: AppTheme.cardShadow,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: AppTheme.borderRadiusXl,
                              child: InkWell(
                                borderRadius: AppTheme.borderRadiusXl,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => StudentClassDetailsScreen(
                                        classModel: classItem,
                                      ),
                                    ),
                                  );
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Class Header Card
                                    Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: const BoxDecoration(
                                        gradient: AppTheme.heroGradient,
                                        borderRadius:
                                            BorderRadius.vertical(
                                          top: Radius.circular(
                                              AppTheme.radiusXl - 1),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withValues(alpha: 0.14),
                                              borderRadius:
                                                  AppTheme.borderRadiusMd,
                                              border: Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.22),
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.auto_stories_outlined,
                                              color: Colors.white,
                                              size: 22,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  classItem.name,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  classItem.teacherName
                                                          .isNotEmpty
                                                      ? 'Instructor: ${classItem.teacherName}'
                                                      : 'Instructor enrolled',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFFD7DAFF),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withValues(alpha: 0.14),
                                              borderRadius:
                                                  AppTheme.borderRadiusSm,
                                              border: Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.3),
                                              ),
                                            ),
                                            child: Text(
                                              classItem.joinCode,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Class Action Link
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 32,
                                                  height: 32,
                                                  decoration: BoxDecoration(
                                                    color: _primaryNavy
                                                        .withValues(alpha: 0.08),
                                                    borderRadius:
                                                        BorderRadius.circular(6),
                                                  ),
                                                  child: const Icon(
                                                    Icons.folder_open,
                                                    size: 16,
                                                    color: _primaryNavy,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                const Expanded(
                                                  child: Text(
                                                    'View Class Materials & Quizzes',
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
                                          ),
                                          const SizedBox(width: 8),
                                          const Icon(
                                            Icons.arrow_forward_ios,
                                            size: 14,
                                            color: _primaryNavy,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: joinedClasses.length,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
  }
}
