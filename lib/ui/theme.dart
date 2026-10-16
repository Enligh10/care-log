import 'package:flutter/material.dart';

import '../models.dart';

const defaultSeed = Color(0xFF3B6E8F);

/// Preset theme colors offered in Settings → Appearance.
const themePresets = <(String, int)>[
  ('Ocean', 0xFF3B6E8F),
  ('Sage', 0xFF4F7D63),
  ('Lavender', 0xFF6E5AA8),
  ('Rose', 0xFFB4527A),
  ('Coral', 0xFFC8664A),
  ('Sunflower', 0xFFB08A1E),
  ('Sky', 0xFF3E7FC1),
  ('Plum', 0xFF7C3F6E),
  ('Slate', 0xFF4C5A67),
];

class ThemePrefs {
  const ThemePrefs(this.seed, this.mode);

  final Color seed;
  final ThemeMode mode;

  @override
  bool operator ==(Object other) =>
      other is ThemePrefs && other.seed.toARGB32() == seed.toARGB32() && other.mode == mode;

  @override
  int get hashCode => Object.hash(seed.toARGB32(), mode);
}

/// App-wide theme, updated from the signed-in account's settings.
final themeController = ValueNotifier<ThemePrefs>(const ThemePrefs(defaultSeed, ThemeMode.system));

ThemeMode parseThemeMode(String s) => switch (s) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

void applyUserTheme(UserPrefs p) {
  final next = ThemePrefs(
    p.themeSeed == null ? defaultSeed : Color(p.themeSeed!),
    parseThemeMode(p.themeMode),
  );
  if (themeController.value != next) themeController.value = next;
}

ThemeData buildTheme(Brightness brightness, Color seed) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Colors for 0–10 symptom severity, light to dark.
Color severityColor(int s, ColorScheme scheme) {
  if (s <= 0) return scheme.surfaceContainerHighest;
  if (s <= 3) return const Color(0xFFF2D46B);
  if (s <= 6) return const Color(0xFFEE9A4D);
  if (s <= 8) return const Color(0xFFE0603E);
  return const Color(0xFFB8322E);
}

String severityLabel(int s) {
  if (s <= 0) return 'None';
  if (s <= 3) return 'Mild';
  if (s <= 6) return 'Moderate';
  return 'Severe';
}

/// Text color that reads on top of [bg].
Color onColor(Color bg) =>
    bg.computeLuminance() > 0.45 ? const Color(0xFF1B1B1F) : Colors.white;

/// Width at which layouts switch to two columns (e.g. Fold inner screen).
const wideBreakpoint = 720.0;
