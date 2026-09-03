import 'package:flutter/material.dart';
import 'register_screen.dart';
import '../teacher/teacher_home_screen.dart';
import '../student/student_home_screen.dart';

/// Login screen matching the Studexa design system.
///
/// Features:
/// - Lavender-to-blue gradient background
/// - Centered logo, app title, and role indicator
/// - Email & password input fields
/// - "Log In" and "Sign in with Google" buttons with equal visual weight
/// - Link/toggle to the matching register screen
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.role = 'Student'});

  final String role;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // ── Design tokens ───────────────────────────────────────────
  static const _primaryNavy = Color(0xFF1A237E);
  static const _gradientStart = Color(0xFFF3F0FF);
  static const _gradientEnd = Color(0xFFEFF6FF);
  static const _surfaceWhite = Color(0xFFFBF9F8);
  static const _outlineVariant = Color(0xFFC6C5D4);
  static const _textPrimary = Color(0xFF1B1C1C);
  static const _textSecondary = Color(0xFF454652);
  static const _textOutline = Color(0xFF767683);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _navigateToHome() {
    // TODO: Wire backend auth in future phase
    if (widget.role == 'Teacher') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TeacherHomeScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const StudentHomeScreen()),
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
          child: Column(
            children: [
              // ── Scrollable content ──────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 48),

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

                      // ── App name ────────────────────────────
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

                      // ── Tagline ─────────────────────────────
                      const Text(
                        'Create Quizzes from Your\nStudy Materials',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _textPrimary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // ── Role badge ──────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _primaryNavy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Logging in as ${widget.role}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _primaryNavy,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ── Email label ─────────────────────────
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(left: 4, bottom: 4),
                          child: Text(
                            'Email',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _textSecondary,
                            ),
                          ),
                        ),
                      ),

                      // ── Email field ─────────────────────────
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(
                          fontSize: 15,
                          color: _textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: widget.role == 'Teacher'
                              ? 'teacher@school.edu'
                              : 'student@university.edu',
                          hintStyle: const TextStyle(
                            color: _textOutline,
                            fontSize: 15,
                          ),
                          prefixIcon: const Icon(
                            Icons.mail_outlined,
                            size: 20,
                            color: _textSecondary,
                          ),
                          filled: true,
                          fillColor: _surfaceWhite,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: _outlineVariant,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: _outlineVariant,
                            ),
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
                      const SizedBox(height: 16),

                      // ── Password label ──────────────────────
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(left: 4, bottom: 4),
                          child: Text(
                            'Password',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _textSecondary,
                            ),
                          ),
                        ),
                      ),

                      // ── Password field ──────────────────────
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: const TextStyle(
                          fontSize: 15,
                          color: _textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: '••••••••',
                          hintStyle: const TextStyle(
                            color: _textOutline,
                            fontSize: 15,
                          ),
                          prefixIcon: const Icon(
                            Icons.lock_outlined,
                            size: 20,
                            color: _textSecondary,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: _textSecondary,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                          filled: true,
                          fillColor: _surfaceWhite,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: _outlineVariant,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: _outlineVariant,
                            ),
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
                      const SizedBox(height: 24),

                      // ── Log In button (Equal visual weight) ──
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryNavy,
                            foregroundColor: Colors.white,
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _navigateToHome,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Log In',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(Icons.arrow_forward, size: 18),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── OR divider ──────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: _outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'or',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _textOutline,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: _outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Google sign-in button (Equal visual weight) ──
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _surfaceWhite,
                            foregroundColor: _textPrimary,
                            elevation: 1,
                            side: const BorderSide(color: _outlineVariant),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _navigateToHome,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'G',
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF4285F4),
                                ),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Sign in with Google',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: _textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),

              // ── Footer: Register link/toggle ───────────────
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Don't have an account? ",
                      style: TextStyle(
                        fontSize: 14,
                        color: _textPrimary,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                RegisterScreen(role: widget.role),
                          ),
                        );
                      },
                      child: const Text(
                        'Register',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _primaryNavy,
                        ),
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
