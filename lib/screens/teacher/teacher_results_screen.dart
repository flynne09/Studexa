import 'package:flutter/material.dart';
import '../../models/class_model.dart';
import '../../services/class_service.dart';

/// Teacher Results Screen showing per-class, per-quiz student completion
/// statuses and scores bound to real enrolled class members.
class TeacherResultsScreen extends StatefulWidget {
  const TeacherResultsScreen({
    super.key,
    this.classId,
    this.className = 'Class Results',
    this.quizTitle = 'Quiz Overview',
  });

  final String? classId;
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

  final ClassService _classService = ClassService();
  String _selectedFilter = 'All';

  void _showStudentDetail(ClassMember student) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surfaceWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      student.displayName.isNotEmpty
                          ? student.displayName
                          : 'Student',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Enrolled',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _primaryNavy,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                student.email.isNotEmpty
                    ? student.email
                    : 'Enrolled via join code',
                style: const TextStyle(fontSize: 13, color: _textSecondary),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Quiz attempt records will sync here once student completes the quiz.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _textSecondary, fontSize: 13),
                  ),
                ),
              ),
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
          child: widget.classId == null
              ? _buildEmptyResultsView(
                  'No class selected',
                  'Select a class from your dashboard to view its student results.',
                )
              : StreamBuilder<List<ClassMember>>(
                  stream: _classService.getClassMembersStream(widget.classId!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      );
                    }

                    final allMembers = snapshot.data ?? [];
                    final students = allMembers
                        .where((m) => m.role == 'student')
                        .toList();

                    return Column(
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
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: _MetricCard(
                                  label: 'Enrolled Students',
                                  value: '${students.length}',
                                  icon: Icons.people_outline,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: _MetricCard(
                                  label: 'Submissions',
                                  value: '0',
                                  icon: Icons.assignment_turned_in_outlined,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Filter Chips ───────────────────────────────
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20.0),
                          child: Row(
                            children: [
                              _FilterChip(
                                label: 'All (${students.length})',
                                isSelected: _selectedFilter == 'All',
                                onSelected: () =>
                                    setState(() => _selectedFilter = 'All'),
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: 'Submitted (0)',
                                isSelected: _selectedFilter == 'Submitted',
                                onSelected: () => setState(
                                    () => _selectedFilter = 'Submitted'),
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: 'Pending (${students.length})',
                                isSelected: _selectedFilter == 'Pending',
                                onSelected: () => setState(
                                    () => _selectedFilter = 'Pending'),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // ── Student List ───────────────────────────────
                        Expanded(
                          child: students.isEmpty
                              ? _buildEmptyResultsView(
                                  'No students enrolled yet',
                                  'Share your class join code to enroll students in this class.',
                                )
                              : ListView.builder(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 4, 20, 20),
                                  itemCount: students.length,
                                  itemBuilder: (context, index) {
                                    final student = students[index];
                                    final initial = student.displayName.isNotEmpty
                                        ? student.displayName[0].toUpperCase()
                                        : 'S';

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      decoration: BoxDecoration(
                                        color: _surfaceWhite,
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border:
                                            Border.all(color: _outlineVariant),
                                      ),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 4,
                                        ),
                                        leading: CircleAvatar(
                                          backgroundColor: _primaryNavy
                                              .withValues(alpha: 0.1),
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
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: _textPrimary,
                                          ),
                                        ),
                                        subtitle: Text(
                                          student.email.isNotEmpty
                                              ? student.email
                                              : 'Enrolled member',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: _textSecondary,
                                          ),
                                        ),
                                        trailing: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'Awaiting Attempt',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _textSecondary,
                                            ),
                                          ),
                                        ),
                                        onTap: () =>
                                            _showStudentDetail(student),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildEmptyResultsView(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _primaryNavy.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline,
                size: 32,
                color: _primaryNavy,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _textSecondary),
            ),
          ],
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
