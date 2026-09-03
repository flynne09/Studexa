import 'package:flutter/material.dart';

/// Teacher Results Screen showing per-class, per-quiz student completion
/// statuses and scores with at least 5 enrolled students.
class TeacherResultsScreen extends StatefulWidget {
  const TeacherResultsScreen({
    super.key,
    this.className = 'Biology 101 - Cell Biology',
    this.quizTitle = 'Cellular Respiration Practice',
  });

  final String className;
  final String quizTitle;

  @override
  State<TeacherResultsScreen> createState() => _TeacherResultsScreenState();
}

class _TeacherResultsScreenState extends State<TeacherResultsScreen> {
  // ── Design tokens ───────────────────────────────────────────
  static const _primaryNavy = Color(0xFF1A237E);
  static const _gradientStart = Color(0xFFF3F0FF);
  static const _gradientEnd = Color(0xFFEFF6FF);
  static const _surfaceWhite = Color(0xFFFBF9F8);
  static const _outlineVariant = Color(0xFFC6C5D4);
  static const _textPrimary = Color(0xFF1B1C1C);
  static const _textSecondary = Color(0xFF454652);

  String _selectedFilter = 'All';

  // ── Dummy data: 6 enrolled students ─────────────────────────
  final List<Map<String, dynamic>> _students = [
    {
      'id': 'stu_01',
      'name': 'Alex Morgan',
      'email': 'alex.m@university.edu',
      'attempted': true,
      'score': 9,
      'maxScore': 10,
      'percentage': 90,
      'submittedAt': '2 hours ago',
    },
    {
      'id': 'stu_02',
      'name': 'Samantha Smith',
      'email': 's.smith@university.edu',
      'attempted': true,
      'score': 10,
      'maxScore': 10,
      'percentage': 100,
      'submittedAt': '3 hours ago',
    },
    {
      'id': 'stu_03',
      'name': 'Jordan Lee',
      'email': 'jordan.l@university.edu',
      'attempted': true,
      'score': 8,
      'maxScore': 10,
      'percentage': 80,
      'submittedAt': '5 hours ago',
    },
    {
      'id': 'stu_04',
      'name': 'Marcus Vance',
      'email': 'm.vance@university.edu',
      'attempted': true,
      'score': 7,
      'maxScore': 10,
      'percentage': 70,
      'submittedAt': 'Yesterday',
    },
    {
      'id': 'stu_05',
      'name': 'Elena Rostova',
      'email': 'e.rostova@university.edu',
      'attempted': false,
      'score': null,
      'maxScore': 10,
      'percentage': null,
      'submittedAt': 'Not submitted',
    },
    {
      'id': 'stu_06',
      'name': 'David Kim',
      'email': 'd.kim@university.edu',
      'attempted': false,
      'score': null,
      'maxScore': 10,
      'percentage': null,
      'submittedAt': 'Not submitted',
    },
  ];

  List<Map<String, dynamic>> get _filteredStudents {
    if (_selectedFilter == 'Completed') {
      return _students.where((s) => s['attempted'] == true).toList();
    }
    if (_selectedFilter == 'Pending') {
      return _students.where((s) => s['attempted'] == false).toList();
    }
    return _students;
  }

  void _showStudentDetail(Map<String, dynamic> student) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surfaceWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final attempted = student['attempted'] as bool;
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    student['name'] as String,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: attempted
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      attempted ? 'Attempted' : 'Not Attempted',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: attempted ? Colors.green[800] : Colors.orange[800],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                student['email'] as String,
                style: const TextStyle(fontSize: 13, color: _textSecondary),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              if (attempted) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _DetailStat(
                      label: 'Raw Score',
                      value: '${student['score']}/${student['maxScore']}',
                    ),
                    _DetailStat(
                      label: 'Percentage',
                      value: '${student['percentage']}%',
                    ),
                    _DetailStat(
                      label: 'Submitted',
                      value: student['submittedAt'] as String,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Per-question attempt details will be synced from Firestore quizAttempts.',
                  style: TextStyle(fontSize: 12, color: _textSecondary),
                ),
              ] else ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'This student has not yet submitted an attempt for this quiz.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _textSecondary),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryNavy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final completedCount = _students.where((s) => s['attempted'] == true).length;
    final totalCount = _students.length;
    final avgScore = (completedCount > 0)
        ? (_students
                    .where((s) => s['attempted'] == true)
                    .map((s) => s['percentage'] as int)
                    .reduce((a, b) => a + b) /
                completedCount)
            .round()
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Quiz Results',
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header Information ─────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.className,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _primaryNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.quizTitle,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Overview Summary Cards ─────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        label: 'Completion',
                        value: '$completedCount / $totalCount',
                        icon: Icons.assignment_turned_in_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricCard(
                        label: 'Average Score',
                        value: '$avgScore%',
                        icon: Icons.insights,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Filter Chips ───────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'All ($totalCount)',
                      isSelected: _selectedFilter == 'All',
                      onSelected: () => setState(() => _selectedFilter = 'All'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Completed ($completedCount)',
                      isSelected: _selectedFilter == 'Completed',
                      onSelected: () =>
                          setState(() => _selectedFilter = 'Completed'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Pending (${totalCount - completedCount})',
                      isSelected: _selectedFilter == 'Pending',
                      onSelected: () =>
                          setState(() => _selectedFilter = 'Pending'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Student List ───────────────────────────────
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  itemCount: _filteredStudents.length,
                  itemBuilder: (context, index) {
                    final student = _filteredStudents[index];
                    final attempted = student['attempted'] as bool;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: _surfaceWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _outlineVariant),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: _primaryNavy.withValues(alpha: 0.1),
                          child: Text(
                            (student['name'] as String).substring(0, 1),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _primaryNavy,
                            ),
                          ),
                        ),
                        title: Text(
                          student['name'] as String,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          attempted
                              ? 'Submitted ${student['submittedAt']}'
                              : 'Not attempted yet',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _textSecondary,
                          ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (attempted) ...[
                              Text(
                                '${student['score']} / ${student['maxScore']}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: _primaryNavy,
                                ),
                              ),
                              Text(
                                '${student['percentage']}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: (student['percentage'] as int) >= 75
                                      ? Colors.green[700]
                                      : Colors.orange[800],
                                ),
                              ),
                            ] else ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Not Attempted',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        onTap: () => _showStudentDetail(student),
                      ),
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
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    const primaryNavy = Color(0xFF1A237E);
    const surfaceWhite = Color(0xFFFBF9F8);
    const outlineVariant = Color(0xFFC6C5D4);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryNavy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: primaryNavy, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B1C1C),
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF454652),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    const primaryNavy = Color(0xFF1A237E);
    const surfaceWhite = Color(0xFFFBF9F8);
    const outlineVariant = Color(0xFFC6C5D4);

    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? primaryNavy : surfaceWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primaryNavy : outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF454652),
          ),
        ),
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  const _DetailStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A237E),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF454652),
          ),
        ),
      ],
    );
  }
}
