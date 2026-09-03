import 'package:flutter/material.dart';

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
  static const _primaryNavy = Color(0xFF1A237E);
  static const _gradientStart = Color(0xFFF3F0FF);
  static const _gradientEnd = Color(0xFFEFF6FF);
  static const _surfaceWhite = Color(0xFFFBF9F8);
  static const _outlineVariant = Color(0xFFC6C5D4);
  static const _textPrimary = Color(0xFF1B1C1C);
  static const _textSecondary = Color(0xFF454652);

  // ── Local confirmation state ────────────────────────────────
  bool _isJoined = false;
  String? _joinedClassName;
  String? _joinedTeacherName;
  String? _joinedCode;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _handleJoin() {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a class join code.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // TODO: Wire to Firestore classMemberships query/creation
    setState(() {
      _isJoined = true;
      _joinedCode = code.toUpperCase();
      _joinedClassName = 'Biology 101 - Cell Biology';
      _joinedTeacherName = 'Prof. Davis';
    });
  }

  void _resetForm() {
    setState(() {
      _isJoined = false;
      _joinedClassName = null;
      _joinedTeacherName = null;
      _joinedCode = null;
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: _isJoined ? _buildConfirmationState() : _buildEntryState(),
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
            style: TextStyle(
              fontSize: 14,
              color: _textSecondary,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 36),

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
            prefixIcon: const Icon(
              Icons.tag,
              color: _primaryNavy,
              size: 20,
            ),
            filled: true,
            fillColor: _surfaceWhite,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: _primaryNavy,
                width: 1.5,
              ),
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
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _handleJoin,
            child: const Row(
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
          child: const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 48,
          ),
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
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
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
                style: const TextStyle(
                  fontSize: 14,
                  color: _textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.quiz_outlined, size: 16, color: _primaryNavy),
                  SizedBox(width: 8),
                  Text(
                    '3 Practice Quizzes currently active',
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
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Back to My Classes',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
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
