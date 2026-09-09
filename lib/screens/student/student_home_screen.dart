import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/class_service.dart';
import '../../models/user_profile.dart';
import '../../models/class_model.dart';
import '../auth/role_selection_screen.dart';
import 'join_class_screen.dart';
import 'student_class_details_screen.dart';

/// Student Home Screen displaying enrolled classes and assigned Practice Quizzes
/// with explicit availability statuses: open, closed, or past deadline.
class StudentHomeScreen extends StatefulWidget {
  final UserProfile? initialProfile;

  const StudentHomeScreen({
    super.key,
    this.initialProfile,
  });

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  // ── Design tokens ───────────────────────────────────────────
  static const _primaryNavy = Color(0xFF1A237E);
  static const _gradientStart = Color(0xFFF3F0FF);
  static const _gradientEnd = Color(0xFFEFF6FF);
  static const _surfaceWhite = Color(0xFFFBF9F8);
  static const _outlineVariant = Color(0xFFC6C5D4);
  static const _textPrimary = Color(0xFF1B1C1C);
  static const _textSecondary = Color(0xFF454652);

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
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: _primaryNavy.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.menu_book,
                                    size: 16,
                                    color: _primaryNavy,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Flexible(
                                  child: Text(
                                    'Student Portal',
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
                      PopupMenuButton<String>(
                        key: const Key('student_header_avatar_menu'),
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
                                  _studentProfile?.displayName ??
                                      'Student Account',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: _textPrimary,
                                  ),
                                ),
                                if (_studentProfile?.email.isNotEmpty ?? false)
                                  Text(
                                    _studentProfile!.email,
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
                            child: _studentProfile != null &&
                                    _studentProfile!.displayName.isNotEmpty
                                ? Text(
                                    _studentProfile!.displayName[0]
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _primaryNavy,
                                      fontSize: 16,
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

              // ── Student Profile & Quick Action Card ────────
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  padding: const EdgeInsets.all(16),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _primaryNavy.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _primaryNavy.withValues(alpha: 0.2),
                              ),
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
                                  fontWeight: FontWeight.bold,
                                  color: _primaryNavy,
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
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _primaryNavy
                                            .withValues(alpha: 0.08),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Student',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: _primaryNavy,
                                        ),
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
                      const Divider(height: 1, color: _outlineVariant),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          key: const Key('student_join_class_button'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryNavy,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
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
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: const Key('student_logout_button'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: BorderSide(
                              color: Colors.redAccent.withValues(alpha: 0.4),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: _handleLogout,
                          icon: const Icon(Icons.logout, size: 16),
                          label: const Text(
                            'Log Out',
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
                stream: _studentProfile != null
                    ? ClassService()
                        .getStudentJoinedClassesStream(_studentProfile!.uid)
                    : const Stream.empty(),
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
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _outlineVariant),
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
                                  borderRadius: BorderRadius.circular(8),
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
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
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
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color:
                                            _primaryNavy.withValues(alpha: 0.04),
                                        borderRadius:
                                            const BorderRadius.vertical(
                                          top: Radius.circular(13),
                                        ),
                                        border: const Border(
                                          bottom: BorderSide(
                                              color: _outlineVariant),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
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
                                                    color: _textPrimary,
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
                                                    color: _textSecondary,
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
                                              color: _surfaceWhite,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: _outlineVariant,
                                              ),
                                            ),
                                            child: Text(
                                              classItem.joinCode,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: _primaryNavy,
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
    );
  }
}

