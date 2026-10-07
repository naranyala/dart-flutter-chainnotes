import 'package:flutter/material.dart';

/// Design tokens ported from `frontend-vue/src/styles/tokens.css`.
abstract final class WorkspaceColors {
  static const Color background = Color(0xFF17191E);
  static const Color surface = Color(0xFF1D2026);
  static const Color surfaceRaised = Color(0xFF22262E);
  static const Color text = Color(0xFFD6D9E0);
  static const Color textMuted = Color(0xFF8B919C);
  static const Color accent = Color(0xFF8AB4F8);
  static const Color accentInk = Color(0xFF102027);
  static const Color danger = Color(0xFFF2A6A6);
  static const Color border = Color(0xFF353A44);
  static const Color borderSubtle = Color(0xFF2C3038);
  static const Color card = Color(0xFF1F232A);
  static const Color cardHover = Color(0xFF262B34);
}

const double topBarHeight = 56;
const double statusBarHeight = 30;

ThemeData buildWorkspaceTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      surface: WorkspaceColors.background,
      primary: WorkspaceColors.accent,
      onPrimary: WorkspaceColors.accentInk,
      error: WorkspaceColors.danger,
      outline: WorkspaceColors.border,
    ),
    scaffoldBackgroundColor: WorkspaceColors.background,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.white10,
    fontFamily: 'Roboto',
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: WorkspaceColors.text,
      displayColor: WorkspaceColors.text,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: WorkspaceColors.surface,
      hintStyle: const TextStyle(color: WorkspaceColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: WorkspaceColors.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: WorkspaceColors.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: WorkspaceColors.accent),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: WorkspaceColors.accent,
        foregroundColor: WorkspaceColors.accentInk,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        minimumSize: const Size(0, 36),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: WorkspaceColors.text,
        side: const BorderSide(color: WorkspaceColors.border),
        textStyle: const TextStyle(fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        minimumSize: const Size(0, 36),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: WorkspaceColors.accent,
        textStyle: const TextStyle(fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        minimumSize: const Size(0, 32),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: WorkspaceColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: WorkspaceColors.borderSubtle),
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      side: const BorderSide(color: WorkspaceColors.border),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? WorkspaceColors.accent
            : Colors.transparent,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: WorkspaceColors.borderSubtle,
      thickness: 1,
      space: 1,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white24),
      radius: const Radius.circular(4),
      thickness: WidgetStateProperty.all(8),
    ),
  );
}
