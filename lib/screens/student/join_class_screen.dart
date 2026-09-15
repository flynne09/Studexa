import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/class_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_feedback.dart';
import '../../widgets/studexa_background.dart';

/// Screen where students enter a class join code, submit, and see
/// a confirmation state displaying the joined class details.
class JoinClassScreen extends StatefulWidget {
  const JoinClassScreen({super.key});

  @override
  State<JoinClassScreen> createState() => _JoinClassScreenState();
}

class _JoinClassScreenState extends State<JoinClassScreen> {
  final _codeController = TextEditingController();

  // ── Design tokens ───────────────────────────────────────────
  static const _primaryNavy = AppTheme.primaryNavy;
  static const _surfaceWhite = AppTheme.surfaceWhite;
  static const _outlineVariant = AppTheme.outlineVariant;
  static const _textPrimary = AppTheme.textPrimary;
  static const _textSecondary = AppTheme.textSecondary;

  // ── Local confirmation state ────────────────────────────────
  bool _isLoading = false;
  String? _errorMessage;
  bool _isJoined = false;
  String? _joinedClassName;
  String? _joinedTeacherName;
  String? _joinedCode;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleJoin() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      AppFeedback.warning(
        context,
        'Enter the join code shared by your teacher.',
        title: 'Join code required',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = AuthService().currentUser;
      if (user == null) {
        throw const ClassJoinException(
          'You are not currently logged in. Please sign in with your student account first.',
        );
      }
      final studentId = user.uid;
      final studentName = user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : (user.email != null && user.email!.contains('@')
                ? user.email!.split('@').first
                : 'Student');
      final studentEmail = user.email?.trim() ?? '';

      final joinedClass = await ClassService().joinClassByCode(
        joinCode: code,
        studentId: studentId,
        studentName: studentName,
        studentEmail: studentEmail,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _isJoined = true;
        _joinedCode = joinedClass.joinCode;
        _joinedClassName = joinedClass.name;
        _joinedTeacherName = joinedClass.teacherName.isNotEmpty
            ? joinedClass.teacherName
            : 'Instructor';
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e is ClassJoinException ? e.message : e.toString();
      setState(() {
        _isLoading = false;
        _errorMessage = msg;
      });
      AppFeedback.error(context, msg, title: 'Unable to join class');
    }
  }

  void _resetForm() {
    setState(() {
      _isJoined = false;
      _joinedClassName = null;
      _joinedTeacherName = null;
      _joinedCode = null;
      _errorMessage = null;
      _codeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Join a Class',
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
      body: StudexaBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTheme.maxContentWidthMobile,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: _isJoined
                    ? _buildConfirmationState()
                    : _buildEntryState(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Initial state: single text field for join code and Join button.
  Widget _buildEntryState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _primaryNavy.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.vpn_key_outlined,
              size: 34,
              color: _primaryNavy,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Center(
          child: Text(
            'Enter Class Join Code',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'Ask your teacher for the unique join code to access their quizzes and study materials.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: _textSecondary, height: 1.4),
          ),
        ),
        const SizedBox(height: 32),

        // Error message banner
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: AppTheme.borderRadiusMd,
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Single text field for entering join code
        const Text(
          'Join Code',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _codeController,
          enabled: !_isLoading,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            color: _textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'e.g. BIO-4921',
            hintStyle: const TextStyle(
              fontSize: 16,
              letterSpacing: 1.0,
              fontWeight: FontWeight.normal,
              color: _outlineVariant,
            ),
            prefixIcon: const Icon(Icons.tag, color: _primaryNavy, size: 20),
            filled: true,
            fillColor: _surfaceWhite,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: AppTheme.borderRadiusMd,
              borderSide: const BorderSide(color: _outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppTheme.borderRadiusMd,
              borderSide: const BorderSide(color: _outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppTheme.borderRadiusMd,
              borderSide: const BorderSide(color: _primaryNavy, width: 1.5),
            ),
          ),
          onSubmitted: (_) => _handleJoin(),
        ),
        const SizedBox(height: 24),

        // Join button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryNavy,
              foregroundColor: Colors.white,
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: AppTheme.borderRadiusMd,
              ),
            ),
            onPressed: _isLoading ? null : _handleJoin,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Join Class',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  /// Confirmation state: shows joined class name and details.
  Widget _buildConfirmationState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        ),
        const SizedBox(height: 20),
        const Text(
          'You\'re In!',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'You have successfully joined the class.',
          style: TextStyle(fontSize: 14, color: _textSecondary),
        ),
        const SizedBox(height: 32),

        // Confirmation Card showing the class name
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _surfaceWhite,
            borderRadius: AppTheme.borderRadiusLg,
            border: Border.all(color: _outlineVariant),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Enrolled',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                  Text(
                    'Code: $_joinedCode',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _primaryNavy,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _joinedClassName ?? '',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Instructor: ${_joinedTeacherName ?? ''}',
                style: const TextStyle(fontSize: 14, color: _textSecondary),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.quiz_outlined, size: 16, color: _primaryNavy),
                  SizedBox(width: 8),
                  Text(
                    'Class materials and practice quizzes are ready.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _primaryNavy,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Navigation back to classes
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryNavy,
              foregroundColor: Colors.white,
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: AppTheme.borderRadiusMd,
              ),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Back to My Classes',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Join another class toggle
        TextButton(
          onPressed: _resetForm,
          child: const Text(
            'Join Another Class',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _primaryNavy,
            ),
          ),
        ),
      ],
    );
  }
}
