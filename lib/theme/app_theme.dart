import 'package:flutter/material.dart';

/// Centralized design tokens and ThemeData for the Studexa application.
/// Provides unified colors, typography, spacing, corner radii, shadows,
/// and Material 3 theme configurations across all student and teacher screens.
class AppTheme {
  /// Private constructor to prevent instantiation of this static utility class.
  AppTheme._();

  // ── 1. Color System ───────────────────────────────────────────
  /// Primary brand navy color used for buttons, headers, and active highlights.
  static const Color primaryNavy = Color(0xFF1A237E);

  /// Deep navy shade used for gradients, tooltips, and high-contrast accents.
  static const Color darkNavy = Color(0xFF000666);

  /// Soft indigo tint used for chip backgrounds, badges, and subtle containers.
  static const Color primaryContainer = Color(0xFFE8EAF6);

  /// Foreground text/icon color displayed on top of [primaryNavy] surfaces.
  static const Color onPrimary = Color(0xFFFFFFFF);

  // Background & Surface
  /// Top-left starting tint for the global [backgroundGradient].
  static const Color gradientStart = Color(0xFFF3F0FF);

  /// Bottom-right ending tint for the global [backgroundGradient].
  static const Color gradientEnd = Color(0xFFEFF6FF);

  /// Default warm white surface color for cards, dialogs, and scaffolds.
  static const Color surfaceWhite = Color(0xFFFBF9F8);

  /// Secondary surface tint for nested panels and subtle section backgrounds.
  static const Color surfaceAlt = Color(0xFFF4F5F9);

  // Outlines & Borders
  /// Standard border color for input fields and outlined buttons.
  static const Color outlineVariant = Color(0xFFC6C5D4);

  /// Hairline border color for cards, dividers, and containers.
  static const Color outlineSubtle = Color(0xFFE2E2EA);

  // Typography Colors
  /// Primary high-contrast color for headings and body text.
  static const Color textPrimary = Color(0xFF1B1C1C);

  /// Medium-emphasis color for subtitles, descriptions, and labels.
  static const Color textSecondary = Color(0xFF454652);

  /// Low-emphasis color for hints, timestamps, and disabled text.
  static const Color textTertiary = Color(0xFF767683);

  // Status & Semantic Colors
  /// Semantic green for positive outcomes, passed quizzes, and ready states.
  static const Color success = Color(0xFF2E7D32);
  static const Color successContainer = Color(0xFFE8F5E9);
  static const Color successBorder = Color(0xFFC8E6C9);

  /// Semantic orange for warnings, pending actions, and unposted drafts.
  static const Color warning = Color(0xFFE65100);
  static const Color warningContainer = Color(0xFFFFF3E0);
  static const Color warningBorder = Color(0xFFFFE0B2);

  /// Semantic red for validation errors, failed states, and destructive actions.
  static const Color error = Color(0xFFC62828);
  static const Color errorContainer = Color(0xFFFFEBEE);
  static const Color errorBorder = Color(0xFFFFCDD2);

  /// Semantic blue for informational banners and neutral notices.
  static const Color info = Color(0xFF1565C0);
  static const Color infoContainer = Color(0xFFE3F2FD);
  static const Color infoBorder = Color(0xFFBBDEFB);

  // ── 2. Spacing Scale ──────────────────────────────────────────
  /// Extra-small 4px spacing unit.
  static const double spacingXs = 4.0;

  /// Small 8px spacing unit.
  static const double spacingSm = 8.0;

  /// Medium 12px spacing unit.
  static const double spacingMd = 12.0;

  /// Large 16px standard padding/margin unit.
  static const double spacingLg = 16.0;

  /// Extra-large 20px spacing unit.
  static const double spacingXl = 20.0;

  /// Double extra-large 24px section spacing unit.
  static const double spacingXxl = 24.0;

  /// Triple extra-large 32px layout spacing unit.
  static const double spacingXxxl = 32.0;

  // ── 3. Corner Radii ───────────────────────────────────────────
  /// Small 8px corner radius for compact elements and tooltips.
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0; // Inputs, buttons
  static const double radiusLg = 18.0; // Standard cards
  static const double radiusXl = 24.0; // Dialogs, large chips

  /// Pill radius (999px) for fully rounded status badges and tags.
  static const double radiusPill = 999.0;

  /// Precomputed [BorderRadius] instances for consistent widget rounding.
  static final BorderRadius borderRadiusSm = BorderRadius.circular(radiusSm);
  static final BorderRadius borderRadiusMd = BorderRadius.circular(radiusMd);
  static final BorderRadius borderRadiusLg = BorderRadius.circular(radiusLg);
  static final BorderRadius borderRadiusXl = BorderRadius.circular(radiusXl);

  // ── 4. Shadows ────────────────────────────────────────────────
  /// Soft elevation shadow applied to standard content cards.
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x121A237E),
      blurRadius: 18,
      offset: Offset(0, 7),
    ),
    BoxShadow(
      color: Color(0x08FFFFFF),
      blurRadius: 2,
      offset: Offset(0, -1),
    ),
  ];

  /// Prominent shadow applied to hero banners and featured callout cards.
  static const List<BoxShadow> featureShadow = [
    BoxShadow(
      color: Color(0x281A237E),
      blurRadius: 28,
      offset: Offset(0, 12),
    ),
  ];

  /// Elevation shadow applied to modal dialogs and floating sheets.
  static const List<BoxShadow> modalShadow = [
    BoxShadow(
      color: Color(0x141A237E),
      blurRadius: 20,
      offset: Offset(0, 6),
    ),
  ];

  // ── 5. Standard Gradients ─────────────────────────────────────
  /// Soft multi-stop pastel gradient rendered behind application screens.
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, primaryContainer, gradientEnd],
    stops: [0, 0.52, 1],
  );

  /// Deep navy gradient used on hero headers, avatars, and primary banners.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryNavy, darkNavy],
  );

  // ── 6. Responsive Width Constraints ───────────────────────────
  /// Maximum width for single-column mobile/auth form containers.
  static const double maxContentWidthMobile = 600.0;

  /// Maximum width for wider tablet/desktop dashboard content views.
  static const double maxContentWidthTablet = 840.0;

  // ── 7. Unified ThemeData ──────────────────────────────────────
  /// Builds and returns the global Material 3 [ThemeData] for Studexa.
  static ThemeData get theme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryNavy,
      primary: primaryNavy,
      primaryContainer: primaryContainer,
      secondary: darkNavy,
      surface: surfaceWhite,
      error: error,
      onPrimary: onPrimary,
      onSurface: textPrimary,
      outline: outlineVariant,
      outlineVariant: outlineSubtle,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surfaceWhite,
      fontFamily: null, // Preserves platform default typography
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 30,
          height: 1.16,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
          color: textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 1.35,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          height: 1.5,
          color: textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.45,
          color: textSecondary,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: textTertiary,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),

      // AppBar Theme
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),

      // Card Theme
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceWhite,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: outlineSubtle),
        ),
        margin: EdgeInsets.zero,
      ),

      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceWhite,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacingLg,
          vertical: 14.0,
        ),
        hintStyle: const TextStyle(
          color: textTertiary,
          fontSize: 14,
        ),
        labelStyle: const TextStyle(
          color: textSecondary,
          fontSize: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: primaryNavy, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: error, width: 1.6),
        ),
      ),

      // Elevated Button Theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(88, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacingXxl,
            vertical: 14,
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      // Outlined Button Theme
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryNavy,
          elevation: 0,
          minimumSize: const Size(88, 48),
          side: const BorderSide(color: outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacingXl,
            vertical: 14,
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      // Text Button Theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryNavy,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Dialog Theme
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 14,
          color: textSecondary,
          height: 1.4,
        ),
      ),

      // Bottom Sheet Theme
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
      ),

      // Divider Theme
      dividerTheme: const DividerThemeData(
        color: outlineSubtle,
        thickness: 1,
        space: 1,
      ),

      // Selection controls and feedback stay within the brand palette.
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(spacingXs),
        ),
        side: const BorderSide(color: outlineVariant, width: 1.4),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primaryNavy
              : Colors.transparent,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primaryNavy
              : textTertiary,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryNavy,
        linearTrackColor: primaryContainer,
        circularTrackColor: primaryContainer,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: darkNavy,
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),

      // SnackBar Theme
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceWhite,
        selectedColor: primaryContainer,
        side: const BorderSide(color: outlineSubtle),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusPill),
        ),
        labelStyle: const TextStyle(
          color: textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: spacingSm),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primaryNavy,
        unselectedLabelColor: textSecondary,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        dividerColor: Colors.transparent,
      ),
    );
  }
}
