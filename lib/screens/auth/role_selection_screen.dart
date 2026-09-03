import 'package:flutter/material.dart';
import 'login_screen.dart';

/// Screen where the user selects their role (Teacher or Student)
/// before proceeding to the login screen.
///
/// Design follows the Studexa "subtle tint" style:
/// - Lavender-to-blue gradient background
/// - Navy primary color (#1A237E)
/// - Clean typography
/// - Rounded card components with subtle borders
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  // ── Design tokens ───────────────────────────────────────────
  static const _primaryNavy = Color(0xFF1A237E);
  static const _gradientStart = Color(0xFFF3F0FF);
  static const _gradientEnd = Color(0xFFEFF6FF);
  static const _surfaceWhite = Color(0xFFFBF9F8);
  static const _outlineVariant = Color(0xFFC6C5D4);

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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                const Spacer(flex: 2),

                // ── Studexa Logo ─────────────────────────────
                Container(
                  width: 88,
                  height: 88,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _surfaceWhite,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _outlineVariant.withValues(alpha: 0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _primaryNavy.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/images/studexa_logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF2979FF),
                                Color(0xFF9C27B0),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.assignment_turned_in_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── App name ──────────────────────────────────
                const Text(
                  'Studexa',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                    color: _primaryNavy,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),

                // ── Tagline ───────────────────────────────────
                const Text(
                  'Choose Your Role',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B1C1C),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 40),

                // ── Teacher card ──────────────────────────────
                _RoleCard(
                  icon: Icons.school_outlined,
                  label: 'Teacher',
                  subtitle: 'Create and manage quizzes',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LoginScreen(role: 'Teacher'),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                // ── Student card ──────────────────────────────
                _RoleCard(
                  icon: Icons.menu_book_outlined,
                  label: 'Student',
                  subtitle: 'Join classes and take quizzes',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LoginScreen(role: 'Student'),
                      ),
                    );
                  },
                ),

                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable role-selection card matching the Studexa surface style.
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFBF9F8),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFC6C5D4),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: const Color(0xFF1A237E),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1B1C1C),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF454652),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Color(0xFF767683),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
