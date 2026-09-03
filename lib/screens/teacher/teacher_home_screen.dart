import 'package:flutter/material.dart';
import 'upload_generate_quiz_screen.dart';
import 'teacher_results_screen.dart';

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

  // ── Hardcoded dummy data ────────────────────────────────────
  final List<Map<String, dynamic>> _classes = [
    {
      'id': 'class_01',
      'className': 'Biology 101 - Cell Biology',
      'joinCode': 'BIO-4921',
      'rosterCount': 28,
      'recentQuiz': 'Cellular Respiration Practice',
    },
    {
      'id': 'class_02',
      'className': 'CS 201 - Data Structures',
      'joinCode': 'CS-8812',
      'rosterCount': 34,
      'recentQuiz': 'Binary Trees & Graphs Quiz',
    },
    {
      'id': 'class_03',
      'className': 'AP Chemistry - Period 3',
      'joinCode': 'CHEM-3104',
      'rosterCount': 22,
      'recentQuiz': 'Stoichiometry & Reactions',
    },
  ];

  final List<Map<String, dynamic>> _recentQuizzes = [
    {
      'title': 'Cellular Respiration Practice',
      'className': 'Biology 101',
      'quizKind': 'practice',
      'status': 'published',
      'submissions': '24/28 completed',
      'averageScore': '82%',
      'createdAt': '2 hours ago',
    },
    {
      'title': 'Binary Trees & Graphs Quiz',
      'className': 'CS 201',
      'quizKind': 'actual',
      'status': 'published',
      'submissions': '31/34 completed',
      'averageScore': '76%',
      'createdAt': 'Yesterday',
    },
    {
      'title': 'Organic Chemistry Midterm Prep',
      'className': 'AP Chemistry',
      'quizKind': 'practice',
      'status': 'draft',
      'submissions': 'Draft • Not published',
      'averageScore': '—',
      'createdAt': '3 days ago',
    },
  ];

  void _showCreateClassDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
            TextField(
              controller: nameController,
              autofocus: true,
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
            onPressed: () => Navigator.pop(ctx),
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
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                setState(() {
                  // TODO: Wire to Firestore classes collection
                  _classes.insert(0, {
                    'id': 'class_${DateTime.now().millisecondsSinceEpoch}',
                    'className': nameController.text.trim(),
                    'joinCode': 'CLS-${1000 + _classes.length * 111}',
                    'rosterCount': 0,
                    'recentQuiz': 'No quizzes yet',
                  });
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Class "${nameController.text.trim()}" created!'),
                    backgroundColor: _primaryNavy,
                  ),
                );
              }
            },
            child: const Text('Create'),
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
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _surfaceWhite,
                          shape: BoxShape.circle,
                          border: Border.all(color: _outlineVariant),
                        ),
                        child: const Icon(
                          Icons.person_outline,
                          color: _primaryNavy,
                          size: 22,
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
                          subtitle: 'Generate quiz from file',
                          icon: Icons.upload_file_outlined,
                          isPrimary: true,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const UploadGenerateQuizScreen(),
                              ),
                            );
                          },
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
                        '${_classes.length} total',
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

              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = _classes[index];
                      return _ClassItemCard(
                        className: item['className'] as String,
                        joinCode: item['joinCode'] as String,
                        rosterCount: item['rosterCount'] as int,
                        recentQuiz: item['recentQuiz'] as String,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TeacherResultsScreen(
                                className: item['className'] as String,
                                quizTitle: item['recentQuiz'] as String,
                              ),
                            ),
                          );
                        },
                      );
                    },
                    childCount: _classes.length,
                  ),
                ),
              ),

              // ── Section: Recent Quiz Activity ──────────────
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: Text(
                    'Recent Quiz Activity',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final quiz = _recentQuizzes[index];
                      return _RecentQuizCard(
                        title: quiz['title'] as String,
                        className: quiz['className'] as String,
                        quizKind: quiz['quizKind'] as String,
                        submissions: quiz['submissions'] as String,
                        averageScore: quiz['averageScore'] as String,
                        createdAt: quiz['createdAt'] as String,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TeacherResultsScreen(
                                className: quiz['className'] as String,
                                quizTitle: quiz['title'] as String,
                              ),
                            ),
                          );
                        },
                      );
                    },
                    childCount: _recentQuizzes.length,
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

/// Card representing a teacher's class with name, join code, and roster count.
class _ClassItemCard extends StatelessWidget {
  const _ClassItemCard({
    required this.className,
    required this.joinCode,
    required this.rosterCount,
    required this.recentQuiz,
    required this.onTap,
  });

  final String className;
  final String joinCode;
  final int rosterCount;
  final String recentQuiz;
  final VoidCallback onTap;

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
                    child: Text(
                      className,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  Container(
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
                          joinCode,
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
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.people_alt_outlined,
                    size: 15,
                    color: textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$rosterCount students enrolled',
                    style: const TextStyle(
                      fontSize: 13,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('•', style: TextStyle(color: outlineVariant)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      recentQuiz,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: textSecondary,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card showing recent quiz activity for the teacher.
class _RecentQuizCard extends StatelessWidget {
  const _RecentQuizCard({
    required this.title,
    required this.className,
    required this.quizKind,
    required this.submissions,
    required this.averageScore,
    required this.createdAt,
    required this.onTap,
  });

  final String title;
  final String className;
  final String quizKind;
  final String submissions;
  final String averageScore;
  final String createdAt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const primaryNavy = Color(0xFF1A237E);
    const surfaceWhite = Color(0xFFFBF9F8);
    const outlineVariant = Color(0xFFC6C5D4);
    const textPrimary = Color(0xFF1B1C1C);
    const textSecondary = Color(0xFF454652);

    final isActual = quizKind == 'actual';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isActual
                      ? const Color(0xFF002C6D).withValues(alpha: 0.1)
                      : primaryNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isActual ? Icons.assignment_outlined : Icons.quiz_outlined,
                  color: isActual ? const Color(0xFF002C6D) : primaryNavy,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isActual
                                ? const Color(0xFFE0E2EE)
                                : const Color(0xFFE0E0FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isActual ? 'Actual Quiz' : 'Practice Quiz',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isActual
                                  ? const Color(0xFF181B24)
                                  : primaryNavy,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$className • $submissions • Avg: $averageScore',
                      style: const TextStyle(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
