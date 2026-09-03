import 'package:flutter/material.dart';
import 'join_class_screen.dart';
import 'answer_quiz_screen.dart';

/// Student Home Screen displaying enrolled classes and assigned Practice Quizzes
/// with explicit availability statuses: open, closed, or past deadline.
class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

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

  // ── Hardcoded dummy data for joined classes and practice quizzes ─
  final List<Map<String, dynamic>> _enrolledClasses = [
    {
      'classId': 'cls_01',
      'className': 'Biology 101 - Cell Biology',
      'teacherName': 'Prof. Davis',
      'joinCode': 'BIO-4921',
      'quizzes': [
        {
          'quizId': 'q_bio_01',
          'title': 'Cellular Respiration & ATP Synthesis',
          'questionCount': 10,
          'status': 'open', // open | closed | past deadline
          'statusLabel': 'Open • Due in 2 days',
          'deadline': 'Tomorrow, 11:59 PM',
          'attempted': false,
        },
        {
          'quizId': 'q_bio_02',
          'title': 'Mitosis & Meiosis Practice Drill',
          'questionCount': 8,
          'status': 'closed',
          'statusLabel': 'Closed • Ended by teacher',
          'deadline': 'Closed',
          'attempted': true,
          'score': '7/8',
        },
        {
          'quizId': 'q_bio_03',
          'title': 'Organic Macromolecules Intro',
          'questionCount': 12,
          'status': 'past_deadline',
          'statusLabel': 'Past Deadline • Closed Sep 1',
          'deadline': 'Sep 1, 2026',
          'attempted': false,
        },
      ],
    },
    {
      'classId': 'cls_02',
      'className': 'CS 201 - Data Structures',
      'joinCode': 'CS-8812',
      'teacherName': 'Dr. Vance',
      'quizzes': [
        {
          'quizId': 'q_cs_01',
          'title': 'Binary Trees & Traversals',
          'questionCount': 10,
          'status': 'open',
          'statusLabel': 'Open • Due Sunday',
          'deadline': 'Sunday, 11:59 PM',
          'attempted': false,
        },
        {
          'quizId': 'q_cs_02',
          'title': 'Big-O Complexity Analysis',
          'questionCount': 5,
          'status': 'past_deadline',
          'statusLabel': 'Past Deadline • Closed Aug 28',
          'deadline': 'Aug 28, 2026',
          'attempted': true,
          'score': '5/5',
        },
      ],
    },
  ];

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
                                  Icons.menu_book,
                                  size: 16,
                                  color: _primaryNavy,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Student Portal',
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
                            'My Classes & Quizzes',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: _textPrimary,
                            ),
                          ),
                        ],
                      ),
                      // Join Class Action Button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryNavy,
                          foregroundColor: Colors.white,
                          elevation: 1,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
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
                    ],
                  ),
                ),
              ),

              // ── Class Sections ─────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, classIndex) {
                      final classItem = _enrolledClasses[classIndex];
                      final quizzes =
                          classItem['quizzes'] as List<Map<String, dynamic>>;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: _surfaceWhite,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _outlineVariant),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Class Header Card
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: _primaryNavy.withValues(alpha: 0.04),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(15),
                                ),
                                border: const Border(
                                  bottom: BorderSide(color: _outlineVariant),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        classItem['className'] as String,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: _textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Instructor: ${classItem['teacherName']}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: _textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _surfaceWhite,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: _outlineVariant,
                                      ),
                                    ),
                                    child: Text(
                                      classItem['joinCode'] as String,
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

                            // Practice Quizzes within class
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Assigned Practice Quizzes',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _textSecondary,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ...quizzes.map((quiz) {
                                    return _PracticeQuizItem(
                                      title: quiz['title'] as String,
                                      questionCount:
                                          quiz['questionCount'] as int,
                                      status: quiz['status'] as String,
                                      statusLabel:
                                          quiz['statusLabel'] as String,
                                      score: quiz['score'] as String?,
                                      onTap: () {
                                        if (quiz['status'] == 'open') {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  AnswerQuizScreen(
                                                quizTitle:
                                                    quiz['title'] as String,
                                              ),
                                            ),
                                          );
                                        } else {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'This quiz is ${quiz['status'] == 'closed' ? 'closed by teacher' : 'past its submission deadline'}.',
                                              ),
                                              backgroundColor: _primaryNavy,
                                            ),
                                          );
                                        }
                                      },
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    childCount: _enrolledClasses.length,
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

/// Item component rendering a single practice quiz with availability badge.
class _PracticeQuizItem extends StatelessWidget {
  const _PracticeQuizItem({
    required this.title,
    required this.questionCount,
    required this.status,
    required this.statusLabel,
    required this.onTap,
    this.score,
  });

  final String title;
  final int questionCount;
  final String status; // 'open' | 'closed' | 'past_deadline'
  final String statusLabel;
  final String? score;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const primaryNavy = Color(0xFF1A237E);
    const outlineVariant = Color(0xFFC6C5D4);
    const textPrimary = Color(0xFF1B1C1C);
    const textSecondary = Color(0xFF454652);

    final isOpen = status == 'open';
    final isClosed = status == 'closed';

    Color badgeBg;
    Color badgeText;
    IconData statusIcon;

    if (isOpen) {
      badgeBg = Colors.green.withValues(alpha: 0.12);
      badgeText = Colors.green[800]!;
      statusIcon = Icons.check_circle_outline;
    } else if (isClosed) {
      badgeBg = Colors.grey.withValues(alpha: 0.15);
      badgeText = Colors.grey[800]!;
      statusIcon = Icons.lock_outline;
    } else {
      // past_deadline
      badgeBg = Colors.orange.withValues(alpha: 0.12);
      badgeText = Colors.orange[900]!;
      statusIcon = Icons.schedule;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOpen
              ? primaryNavy.withValues(alpha: 0.2)
              : outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(statusIcon, size: 18, color: badgeText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: badgeText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$questionCount Qs',
                      style: const TextStyle(
                        fontSize: 11,
                        color: textSecondary,
                      ),
                    ),
                    if (score != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '• Score: $score',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: primaryNavy,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isOpen)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryNavy,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: const Size(64, 32),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: onTap,
              child: const Text('Start', style: TextStyle(fontSize: 12)),
            )
          else
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: textSecondary,
                side: const BorderSide(color: outlineVariant),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: const Size(64, 32),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: onTap,
              child: Text(
                isClosed ? 'Closed' : 'Ended',
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
