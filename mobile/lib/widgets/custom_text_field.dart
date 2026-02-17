import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hintText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final int maxLines;
  final int? maxLength;
  final int errorMaxLines;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final TextCapitalization textCapitalization;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.maxLines = 1,
    this.maxLength,
    this.errorMaxLines = 2,
    this.enabled = true,
    this.onChanged,
    this.onTap,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    
    // Create base text styles with all required properties (fontSize and textBaseline for inherit: false)
    final baseBodyLarge = textTheme.bodyLarge ?? const TextStyle(fontSize: 16, textBaseline: TextBaseline.alphabetic);
    final baseBodyMedium = textTheme.bodyMedium ?? const TextStyle(fontSize: 14, textBaseline: TextBaseline.alphabetic);
    final baseBodySmall = textTheme.bodySmall ?? const TextStyle(fontSize: 12, textBaseline: TextBaseline.alphabetic);
    
    // Ensure fontSize and textBaseline are preserved when setting inherit: false
    final inputStyle = TextStyle(
      fontSize: baseBodyLarge.fontSize ?? 16,
      textBaseline: baseBodyLarge.textBaseline ?? TextBaseline.alphabetic,
      color: baseBodyLarge.color,
      fontFamily: baseBodyLarge.fontFamily,
      fontWeight: baseBodyLarge.fontWeight,
      inherit: false,
    );
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: (textTheme.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          maxLines: maxLines,
          maxLength: maxLength,
          enabled: enabled,
          onChanged: onChanged,
          onTap: onTap,
          textCapitalization: textCapitalization,
          style: inputStyle,
          decoration: InputDecoration(
            hintText: hintText ?? label,
            errorMaxLines: errorMaxLines,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
            suffixIcon: suffixIcon,
            hintStyle: TextStyle(
              fontSize: baseBodyMedium.fontSize ?? 14,
              textBaseline: baseBodyMedium.textBaseline ?? TextBaseline.alphabetic,
              color: colorScheme.onSurface.withOpacity(0.6),
              fontFamily: baseBodyMedium.fontFamily,
              inherit: false,
            ),
            errorStyle: TextStyle(
              fontSize: baseBodySmall.fontSize ?? 12,
              textBaseline: baseBodySmall.textBaseline ?? TextBaseline.alphabetic,
              color: colorScheme.error,
              fontFamily: baseBodySmall.fontFamily,
              inherit: false,
            ),
            labelStyle: TextStyle(
              fontSize: baseBodyMedium.fontSize ?? 14,
              textBaseline: baseBodyMedium.textBaseline ?? TextBaseline.alphabetic,
              color: colorScheme.onSurface,
              fontFamily: baseBodyMedium.fontFamily,
              inherit: false,
            ),
            floatingLabelStyle: TextStyle(
              fontSize: baseBodySmall.fontSize ?? 12,
              textBaseline: baseBodySmall.textBaseline ?? TextBaseline.alphabetic,
              color: colorScheme.primary,
              fontFamily: baseBodySmall.fontFamily,
              inherit: false,
            ),
            helperStyle: TextStyle(
              fontSize: baseBodySmall.fontSize ?? 12,
              textBaseline: baseBodySmall.textBaseline ?? TextBaseline.alphabetic,
              color: colorScheme.onSurface.withOpacity(0.6),
              fontFamily: baseBodySmall.fontFamily,
              inherit: false,
            ),
            counterStyle: TextStyle(
              fontSize: baseBodySmall.fontSize ?? 12,
              textBaseline: baseBodySmall.textBaseline ?? TextBaseline.alphabetic,
              color: colorScheme.onSurface.withOpacity(0.6),
              fontFamily: baseBodySmall.fontFamily,
              inherit: false,
            ),
          ),
        ),
      ],
    );
  }
}
