import 'dart:async';
import 'package:flutter/material.dart';
import 'auth/role_selection_screen.dart';

/// Animated Splash Screen displaying the Studexa logo with smooth
/// scale, fade, and glow entrance animations before transitioning
/// into the main application.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _glowAnimation;
  late final Animation<Offset> _slideAnimation;

  // ── Design tokens ───────────────────────────────────────────
  static const _gradientStart = Color(0xFFF3F0FF);
  static const _gradientEnd = Color(0xFFEFF6FF);
  static const _primaryNavy = Color(0xFF1A237E);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    // Springy scale effect for the logo mark
    _scaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
      ),
    );

    // Smooth fade in
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    // Pulsing subtle glow behind the logo
    _glowAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 1.0, curve: Curves.easeInOut),
      ),
    );

    // Subtle upward drift for the text
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward();

    // Auto-navigate to RoleSelectionScreen after animation finishes
    Timer(const Duration(milliseconds: 2800), _navigateToApp);
  }

  void _navigateToApp() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, animation, secondaryAnimation) =>
            const RoleSelectionScreen(),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        // Allow user to tap anywhere to skip animation
        onTap: _navigateToApp,
        child: Container(
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
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Animated background radial glow
                AnimatedBuilder(
                  animation: _glowAnimation,
                  builder: (context, child) {
                    return Container(
                      width: 260 * _glowAnimation.value,
                      height: 260 * _glowAnimation.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF6294FF).withValues(alpha: 0.22),
                            const Color(0xFF1A237E).withValues(alpha: 0.05),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    );
                  },
                ),

                // Centered Logo & Brand Content
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Animated Logo Card
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _fadeAnimation.value,
                          child: Transform.scale(
                            scale: _scaleAnimation.value,
                            child: child,
                          ),
                        );
                      },
                      child: Container(
                        width: 170,
                        height: 170,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: _primaryNavy.withValues(alpha: 0.12),
                              blurRadius: 28,
                              spreadRadius: 2,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
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
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.assignment_turned_in_rounded,
                                    color: Colors.white,
                                    size: 64,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),

                    // Staggered animated taglines
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return SlideTransition(
                          position: _slideAnimation,
                          child: Opacity(
                            opacity: _fadeAnimation.value,
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        children: [
                          const Text(
                            'STUDEXA',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 3.0,
                              color: _primaryNavy,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _primaryNavy.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'AI STUDY & QUIZ PLATFORM',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                                color: Color(0xFF454652),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Bottom loading indicator & skip hint
                Positioned(
                  bottom: 32,
                  child: AnimatedBuilder(
                    animation: _fadeAnimation,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _fadeAnimation.value,
                        child: child,
                      );
                    },
                    child: Column(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _primaryNavy.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tap anywhere to start',
                          style: TextStyle(
                            fontSize: 12,
                            color: const Color(0xFF767683)
                                .withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
