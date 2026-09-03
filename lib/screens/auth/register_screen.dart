import 'package:flutter/material.dart';
import 'login_screen.dart';
import '../teacher/teacher_home_screen.dart';
import '../student/student_home_screen.dart';

/// Registration screen matching the Studexa design system.
///
/// Features:
/// - Lavender-to-blue gradient background
/// - Centered logo, app title, and role indicator
/// - Name, email, password, and confirm-password fields
/// - "Register" and "Sign up with Google" buttons with equal visual weight
/// - Link/toggle back to the login screen
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.role = 'Student'});

  final String role;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

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
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
                      const SizedBox(height: 40),

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
                      const SizedBox(height: 20),

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
                      const SizedBox(height: 6),

                      // ── Header ──────────────────────────────
                      const Text(
                        'Create Your Account',
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
                          'Registering as ${widget.role}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _primaryNavy,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Full Name label ─────────────────────
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(left: 4, bottom: 4),
                          child: Text(
                            'Full Name',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _textSecondary,
                            ),
                          ),
                        ),
                      ),

                      // ── Full Name field ─────────────────────
                      TextField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        style: const TextStyle(
                          fontSize: 15,
                          color: _textPrimary,
                        ),
                        decoration: _buildInputDecoration(
                          hintText: 'Alex Morgan',
                          prefixIcon: Icons.person_outlined,
                        ),
                      ),
                      const SizedBox(height: 14),

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
                        decoration: _buildInputDecoration(
                          hintText: widget.role == 'Teacher'
                              ? 'teacher@school.edu'
                              : 'student@university.edu',
                          prefixIcon: Icons.mail_outlined,
                        ),
                      ),
                      const SizedBox(height: 14),

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
                        decoration: _buildInputDecoration(
                          hintText: '••••••••',
                          prefixIcon: Icons.lock_outlined,
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
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ── Confirm password label ──────────────
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(left: 4, bottom: 4),
                          child: Text(
                            'Confirm Password',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _textSecondary,
                            ),
                          ),
                        ),
                      ),

                      // ── Confirm password field ──────────────
                      TextField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        style: const TextStyle(
                          fontSize: 15,
                          color: _textPrimary,
                        ),
                        decoration: _buildInputDecoration(
                          hintText: '••••••••',
                          prefixIcon: Icons.lock_outlined,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: _textSecondary,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Register button (Equal visual weight) ──
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
                                'Register',
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

                      // ── Google sign-up button (Equal visual weight) ──
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
                                'Sign up with Google',
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

              // ── Footer: Sign In link/toggle ────────────────
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(
                        fontSize: 14,
                        color: _textPrimary,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        } else {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  LoginScreen(role: widget.role),
                            ),
                          );
                        }
                      },
                      child: const Text(
                        'Sign In',
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

  /// Builds a consistent input decoration matching the design system.
  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: _textOutline,
        fontSize: 15,
      ),
      prefixIcon: Icon(
        prefixIcon,
        size: 20,
        color: _textSecondary,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _surfaceWhite,
      contentPadding: const EdgeInsets.symmetric(
        vertical: 14,
        horizontal: 16,
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
    );
  }
}
