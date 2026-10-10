import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color ink = Color(0xFF1C1917);
  static const Color cream = Color(0xFFFAF8F4);
  static const Color card = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFFC2692A);
  static const Color accentDark = Color(0xFFD4773A);
  static const Color muted = Color(0xFFEDE7DC);
  static const Color mutedForeground = Color(0xFF78716C);
  static const Color inputFill = Color(0xFFF5F1EB);
  static const Color accentSoft = Color(0x14C2692A);
  static const Color likeRose = Color(0xFFE11D48);
  static const Color live = Color(0xFF059669);
  static const Color upcoming = Color(0xFFD97706);
  static const Color ended = Color(0xFFDC2626);

  static const Color darkBackground = Color(0xFF18140F);
  static const Color darkCard = Color(0xFF211C15);
  static const Color darkText = Color(0xFFF0EAE0);
  static const Color darkMuted = Color(0xFF2E2720);
  static const Color darkMutedForeground = Color(0xFFA09080);

  /// Selectable FilterChip / ChoiceChip with guaranteed contrast on warm surfaces.
  static Widget selectableChip({
    required BuildContext context,
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
    bool choice = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final labelWidget = Text(
      label,
      style: TextStyle(
        color: selected ? Colors.white : scheme.onSurface,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        fontSize: 13,
      ),
    );
    if (choice) {
      return ChoiceChip(
        label: labelWidget,
        selected: selected,
        onSelected: onSelected,
        selectedColor: accent,
        backgroundColor: scheme.surfaceContainerHighest,
        checkmarkColor: Colors.white,
        side: BorderSide(
          color: selected ? accent : scheme.outlineVariant,
        ),
      );
    }
    return FilterChip(
      label: labelWidget,
      selected: selected,
      onSelected: onSelected,
      selectedColor: accent,
      backgroundColor: scheme.surfaceContainerHighest,
      checkmarkColor: Colors.white,
      side: BorderSide(
        color: selected ? accent : scheme.outlineVariant,
      ),
    );
  }

  static const Color primaryColor = ink;
  static const Color primaryVariant = Color(0xFF292524);
  static const Color secondaryColor = accent;
  static const Color backgroundColor = cream;
  static const Color surfaceColor = card;
  static const Color errorColor = Color(0xFFD4183D);
  static const Color textPrimary = ink;
  static const Color textSecondary = mutedForeground;
  static const Color textTertiary = Color(0xFFA8A29E);

  static ThemeData get lightTheme => _build(
        brightness: Brightness.light,
        background: cream,
        surface: card,
        onSurface: ink,
        mutedSurface: muted,
        mutedText: mutedForeground,
        accentColor: accent,
        input: inputFill,
      );

  static ThemeData get darkTheme => _build(
        brightness: Brightness.dark,
        background: darkBackground,
        surface: darkCard,
        onSurface: darkText,
        mutedSurface: darkMuted,
        mutedText: darkMutedForeground,
        accentColor: accentDark,
        input: darkMuted,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color onSurface,
    required Color mutedSurface,
    required Color mutedText,
    required Color accentColor,
    required Color input,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? darkText : ink,
      onPrimary: isDark ? darkBackground : cream,
      secondary: accentColor,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: onSurface,
      error: errorColor,
      onError: Colors.white,
      outline: mutedText.withValues(alpha: 0.35),
      outlineVariant: mutedText.withValues(alpha: 0.2),
      primaryContainer: mutedSurface,
      onPrimaryContainer: onSurface,
      // Opaque enough for M3 chips / selected filters (accentSoft alone is ~8%).
      secondaryContainer: Color.alphaBlend(
        accentColor.withValues(alpha: isDark ? 0.28 : 0.18),
        surface,
      ),
      onSecondaryContainer: isDark ? darkText : ink,
      surfaceContainerHighest: mutedSurface,
      surfaceContainerLow: background,
    );

    final text = _textTheme(onSurface, mutedText);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge?.copyWith(
          fontFamily: GoogleFonts.playfairDisplay().fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 20,
          color: onSurface,
          inherit: false,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.secondary,
          foregroundColor: scheme.onSecondary,
          disabledBackgroundColor: scheme.secondary.withValues(alpha: 0.4),
          disabledForegroundColor: scheme.onSecondary.withValues(alpha: 0.8),
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: _sans(fontSize: 16, weight: FontWeight.w600, color: scheme.onSecondary),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.secondary,
          foregroundColor: scheme.onSecondary,
          disabledBackgroundColor: scheme.secondary.withValues(alpha: 0.4),
          disabledForegroundColor: scheme.onSecondary.withValues(alpha: 0.8),
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: _sans(fontSize: 16, weight: FontWeight.w600, color: scheme.onSecondary),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: _sans(fontSize: 16, weight: FontWeight.w600, color: onSurface),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: _sans(fontSize: 14, weight: FontWeight.w600, color: accentColor),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: input,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accentColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorColor),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorColor, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: _sans(fontSize: 14, color: mutedText),
        labelStyle: _sans(fontSize: 14, color: onSurface),
        floatingLabelStyle: _sans(fontSize: 12, color: accentColor),
        helperStyle: _sans(fontSize: 12, color: mutedText),
        errorStyle: _sans(fontSize: 12, color: errorColor),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: mutedSurface,
        selectedColor: accentColor,
        disabledColor: mutedSurface,
        checkmarkColor: Colors.white,
        deleteIconColor: onSurface,
        labelStyle: _sans(fontSize: 13, weight: FontWeight.w500, color: onSurface),
        secondaryLabelStyle: _sans(
          fontSize: 13,
          weight: FontWeight.w600,
          color: Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: scheme.outlineVariant),
        // Ensure selected FilterChip / ChoiceChip labels stay white on terracotta.
        brightness: brightness,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? darkText : ink,
        contentTextStyle: _sans(
          fontSize: 14,
          color: isDark ? darkBackground : cream,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: onSurface,
        textColor: onSurface,
        titleTextStyle: _sans(fontSize: 16, color: onSurface),
        subtitleTextStyle: _sans(fontSize: 14, color: mutedText),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: background,
        selectedItemColor: isDark ? darkText : ink,
        unselectedItemColor: mutedText,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: _sans(fontSize: 12, weight: FontWeight.w600),
        unselectedLabelStyle: _sans(fontSize: 12),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accentColor),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
    );
  }

  static TextTheme _textTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: _display(fontSize: 32, color: primary),
      displayMedium: _display(fontSize: 28, color: primary),
      displaySmall: _display(fontSize: 24, color: primary),
      headlineLarge: _display(fontSize: 22, color: primary),
      headlineMedium: _display(fontSize: 20, color: primary),
      headlineSmall: _display(fontSize: 18, color: primary),
      titleLarge: _sans(fontSize: 16, weight: FontWeight.w600, color: primary),
      titleMedium: _sans(fontSize: 14, weight: FontWeight.w500, color: primary),
      titleSmall: _sans(fontSize: 12, weight: FontWeight.w500, color: secondary),
      bodyLarge: _sans(fontSize: 16, color: primary, height: 1.45),
      bodyMedium: _sans(fontSize: 14, color: secondary, height: 1.45),
      bodySmall: _sans(fontSize: 12, color: secondary, height: 1.4),
      labelLarge: _sans(fontSize: 14, weight: FontWeight.w600, color: primary),
    );
  }

  static TextStyle _display({required double fontSize, required Color color}) {
    return GoogleFonts.playfairDisplay(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      color: color,
      height: 1.25,
    ).copyWith(inherit: false);
  }

  static TextStyle _sans({
    required double fontSize,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
  }) {
    return GoogleFonts.dmSans(
      fontSize: fontSize,
      fontWeight: weight,
      color: color,
      height: height,
    ).copyWith(inherit: false, textBaseline: TextBaseline.alphabetic);
  }
}
