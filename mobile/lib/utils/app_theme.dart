import 'package:flutter/material.dart';

class AppTheme {
  // Colors
  static const Color primaryColor = Color(0xFF6366F1); // Indigo
  static const Color primaryVariant = Color(0xFF4F46E5);
  static const Color secondaryColor = Color(0xFF10B981); // Emerald
  static const Color backgroundColor = Color(0xFFF9FAFB);
  static const Color surfaceColor = Colors.white;
  static const Color errorColor = Color(0xFFEF4444);

  // Text Colors
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: surfaceColor,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),

      // App Bar Theme
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
          inherit: false, // Explicitly set to prevent interpolation issues
        ),
      ),

      // Text Theme
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          fontFamily: 'Inter',
          inherit: false, // Explicitly set to prevent interpolation issues
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          fontFamily: 'Inter',
          inherit: false,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          fontFamily: 'Inter',
          inherit: false,
        ),
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          fontFamily: 'Inter',
          inherit: false,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          fontFamily: 'Inter',
          inherit: false,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          fontFamily: 'Inter',
          inherit: false,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          fontFamily: 'Inter',
          inherit: false,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textPrimary,
          fontFamily: 'Inter',
          inherit: false,
        ),
        titleSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textSecondary,
          fontFamily: 'Inter',
          inherit: false,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: textPrimary,
          fontFamily: 'Inter',
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: textSecondary,
          fontFamily: 'Inter',
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.normal,
          color: textTertiary,
          fontFamily: 'Inter',
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
      ),

      // Button Themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
            textBaseline: TextBaseline.alphabetic,
            inherit: false, // Explicitly set to prevent interpolation issues
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
            textBaseline: TextBaseline.alphabetic,
            inherit: false, // Explicitly set to prevent interpolation issues
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
            textBaseline: TextBaseline.alphabetic,
            inherit: false, // Explicitly set to prevent interpolation issues
          ),
        ),
      ),

      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: errorColor),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: errorColor, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: const TextStyle(
          color: textTertiary,
          fontFamily: 'Inter',
          fontSize: 14,
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        labelStyle: const TextStyle(
          color: textPrimary,
          fontFamily: 'Inter',
          fontSize: 14,
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        floatingLabelStyle: const TextStyle(
          color: primaryColor,
          fontFamily: 'Inter',
          fontSize: 12,
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        helperStyle: const TextStyle(
          color: textSecondary,
          fontFamily: 'Inter',
          fontSize: 12,
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        errorStyle: const TextStyle(
          color: errorColor,
          fontFamily: 'Inter',
          fontSize: 12,
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        prefixStyle: const TextStyle(
          color: textPrimary,
          fontFamily: 'Inter',
          fontSize: 14,
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        suffixStyle: const TextStyle(
          color: textPrimary,
          fontFamily: 'Inter',
          fontSize: 14,
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        counterStyle: const TextStyle(
          color: textSecondary,
          fontFamily: 'Inter',
          fontSize: 12,
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
      ),

      // Card Theme
      cardTheme: const CardThemeData(
        color: surfaceColor,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),

      // List Tile Theme
      listTileTheme: ListTileThemeData(
        dense: false,
        shape: const RoundedRectangleBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minLeadingWidth: 40,
        minVerticalPadding: 8,
        minTileHeight: 56,
        horizontalTitleGap: 16,
        enableFeedback: true,
        visualDensity: VisualDensity.standard,
        iconColor: textPrimary,
        textColor: textPrimary,
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: textPrimary,
          fontFamily: 'Inter',
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        subtitleTextStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: textSecondary,
          fontFamily: 'Inter',
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        leadingAndTrailingTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: textPrimary,
          fontFamily: 'Inter',
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
      ),

      // Bottom Navigation Bar Theme
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: primaryColor,
        unselectedItemColor: textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }

  static ThemeData get darkTheme {
    // Dark mode text colors
    const darkTextPrimary = Colors.white;
    const darkTextSecondary = Color(0xFF9CA3AF);
    const darkTextTertiary = Color(0xFF6B7280);
    const darkSurfaceColor = Color(0xFF1F2937);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: darkSurfaceColor,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: darkTextPrimary,
        onError: Colors.white,
      ),

      // App Bar Theme
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurfaceColor,
        foregroundColor: darkTextPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: darkTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
          inherit: false,
        ),
      ),

      // Text Theme
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: darkTextPrimary,
          fontFamily: 'Inter',
          inherit: false,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: darkTextPrimary,
          fontFamily: 'Inter',
          inherit: false,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
          fontFamily: 'Inter',
          inherit: false,
        ),
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
          fontFamily: 'Inter',
          inherit: false,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
          fontFamily: 'Inter',
          inherit: false,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
          fontFamily: 'Inter',
          inherit: false,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
          fontFamily: 'Inter',
          inherit: false,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: darkTextPrimary,
          fontFamily: 'Inter',
          inherit: false,
        ),
        titleSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: darkTextSecondary,
          fontFamily: 'Inter',
          inherit: false,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: darkTextPrimary,
          fontFamily: 'Inter',
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: darkTextSecondary,
          fontFamily: 'Inter',
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.normal,
          color: darkTextTertiary,
          fontFamily: 'Inter',
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
      ),

      // Button Themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
            textBaseline: TextBaseline.alphabetic,
            inherit: false,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
            textBaseline: TextBaseline.alphabetic,
            inherit: false,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
            textBaseline: TextBaseline.alphabetic,
            inherit: false, // Explicitly set to prevent interpolation issues
          ),
        ),
      ),

      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF374151),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF4B5563)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF4B5563)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: errorColor),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: errorColor, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: const TextStyle(
          color: darkTextTertiary,
          fontFamily: 'Inter',
          fontSize: 14,
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        labelStyle: const TextStyle(
          color: darkTextPrimary,
          fontFamily: 'Inter',
          fontSize: 14,
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        floatingLabelStyle: const TextStyle(
          color: primaryColor,
          fontFamily: 'Inter',
          fontSize: 12,
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        helperStyle: const TextStyle(
          color: darkTextSecondary,
          fontFamily: 'Inter',
          fontSize: 12,
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        errorStyle: const TextStyle(
          color: errorColor,
          fontFamily: 'Inter',
          fontSize: 12,
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        prefixStyle: const TextStyle(
          color: darkTextPrimary,
          fontFamily: 'Inter',
          fontSize: 14,
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        suffixStyle: const TextStyle(
          color: darkTextPrimary,
          fontFamily: 'Inter',
          fontSize: 14,
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        counterStyle: const TextStyle(
          color: darkTextSecondary,
          fontFamily: 'Inter',
          fontSize: 12,
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
      ),

      // Card Theme
      cardTheme: const CardThemeData(
        color: darkSurfaceColor,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),

      // List Tile Theme
      listTileTheme: ListTileThemeData(
        dense: false,
        shape: const RoundedRectangleBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minLeadingWidth: 40,
        minVerticalPadding: 8,
        minTileHeight: 56,
        horizontalTitleGap: 16,
        enableFeedback: true,
        visualDensity: VisualDensity.standard,
        iconColor: darkTextPrimary,
        textColor: darkTextPrimary,
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: darkTextPrimary,
          fontFamily: 'Inter',
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        subtitleTextStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: darkTextSecondary,
          fontFamily: 'Inter',
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
        leadingAndTrailingTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: darkTextPrimary,
          fontFamily: 'Inter',
          textBaseline: TextBaseline.alphabetic,
          inherit: false,
        ),
      ),

      // Bottom Navigation Bar Theme
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkSurfaceColor,
        selectedItemColor: primaryColor,
        unselectedItemColor: darkTextTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
}
