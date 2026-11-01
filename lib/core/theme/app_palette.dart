import 'package:flutter/material.dart';

/// Immutable model defining a cohesive, minimal color palette for Daria.
@immutable
class AppPalette {
  const AppPalette({
    required this.id,
    required this.name,
    required this.description,
    required this.background,
    required this.surface,
    required this.surfaceSubtle,
    required this.surfaceMuted,
    required this.surfaceDark,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textOnMedia,
    required this.accent,
    required this.accentLight,
    required this.border,
    required this.borderSubtle,
    required this.dockBackground,
    required this.dockBorder,
    required this.dockCapturePill,
    this.isDark = false,
    this.customAccentForeground,
    this.customPrimaryButtonForeground,
    this.customPrimaryButtonBackground,
  });

  final String id;
  final String name;
  final String description;

  // Background & Surfaces
  final Color background;
  final Color surface;
  final Color surfaceSubtle;
  final Color surfaceMuted;
  final Color surfaceDark;

  // Typography
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textOnMedia;

  // Accents
  final Color accent;
  final Color accentLight;

  // Borders
  final Color border;
  final Color borderSubtle;

  // Navigation Dock
  final Color dockBackground;
  final Color dockBorder;
  final Color dockCapturePill;

  // Brightness Flag
  final bool isDark;

  final Color? customAccentForeground;
  final Color? customPrimaryButtonForeground;
  final Color? customPrimaryButtonBackground;

  /// High-contrast text/icon color contrasting against [accent].
  Color get accentForeground =>
      customAccentForeground ??
      (isDark ? const Color(0xFF0D1015) : Colors.white);

  /// High-contrast background color for primary action buttons.
  Color get primaryButtonBackground =>
      customPrimaryButtonBackground ?? (isDark ? accent : textPrimary);

  /// High-contrast text/icon color for primary action buttons.
  Color get primaryButtonForeground =>
      customPrimaryButtonForeground ??
      (isDark ? const Color(0xFF0D1015) : Colors.white);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppPalette && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Catalog of curated, photography-focused palettes for Daria.
abstract final class AppPalettes {
  /// 1. DARIA RED LIGHT (Default) - Signature crisp porcelain / pure white / deep ink / bold red accent
  static const AppPalette dariaRedLight = AppPalette(
    id: 'daria_red_light',
    name: 'Daria Red Light',
    description:
        'Signature crisp porcelain, bold red accent & deep ink typography',
    background: Color(0xFFFFF9F9),
    surface: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFFDF0F0),
    surfaceMuted: Color(0xFFFCE6E7),
    surfaceDark: Color(0xFF1E1416),
    textPrimary: Color(0xFF1B1416),
    textSecondary: Color(0xFF655356),
    textMuted: Color(0xFF98878A),
    textOnMedia: Color(0xFFFFFFFF),
    accent: Color(0xFFE50914),
    accentLight: Color(0xFFFDE8E9),
    border: Color(0xFFF2DADB),
    borderSubtle: Color(0xFFFBECEE),
    dockBackground: Color(0xFFFFFFFF),
    dockBorder: Color(0xFFF0D6D8),
    dockCapturePill: Color(0xFFFDECEE),
    isDark: false,
    customAccentForeground: Colors.white,
    customPrimaryButtonForeground: Colors.white,
    customPrimaryButtonBackground: Color(0xFFE50914),
  );

  /// 2. DARIA RED (Dark) - Signature deep charcoal / near black / pure white / bold red accent
  static const AppPalette dariaRed = AppPalette(
    id: 'daria_red',
    name: 'Daria Red',
    description: 'Signature deep charcoal, pure white & bold red accent',
    background: Color(0xFF141416),
    surface: Color(0xFF1E1E22),
    surfaceSubtle: Color(0xFF28282E),
    surfaceMuted: Color(0xFF32323A),
    surfaceDark: Color(0xFF0D0D0F),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB4B4BC),
    textMuted: Color(0xFF7A7A85),
    textOnMedia: Color(0xFFFFFFFF),
    accent: Color(0xFFE50914),
    accentLight: Color(0xFF2C1518),
    border: Color(0xFF2E2E36),
    borderSubtle: Color(0xFF222228),
    dockBackground: Color(0xFF1E1E22),
    dockBorder: Color(0xFF2E2E36),
    dockCapturePill: Color(0xFF28282E),
    isDark: true,
    customAccentForeground: Colors.white,
    customPrimaryButtonForeground: Colors.white,
  );

  /// 2. MIDNIGHT - Deep navy charcoal / cool white / astral blue accent
  static const AppPalette midnight = AppPalette(
    id: 'midnight',
    name: 'Midnight',
    description: 'Deep navy, cool blue & crisp white',
    background: Color(0xFF12151B),
    surface: Color(0xFF1A1F27),
    surfaceSubtle: Color(0xFF232A35),
    surfaceMuted: Color(0xFF2D3643),
    surfaceDark: Color(0xFF0D1015),
    textPrimary: Color(0xFFF1F4F9),
    textSecondary: Color(0xFFB0B9C6),
    textMuted: Color(0xFF7A8699),
    textOnMedia: Color(0xFFFFFFFF),
    accent: Color(0xFF85A8D0),
    accentLight: Color(0xFF212C3B),
    border: Color(0xFF2B3442),
    borderSubtle: Color(0xFF202733),
    dockBackground: Color(0xFF1A1F27),
    dockBorder: Color(0xFF2E3847),
    dockCapturePill: Color(0xFF242C38),
    isDark: true,
  );

  /// 3. LINEN - Warm cream / soft beige / earthy brown / muted caramel
  static const AppPalette linen = AppPalette(
    id: 'linen',
    name: 'Linen',
    description: 'Warm cream, earthy brown & soft white',
    background: Color(0xFFFAF7F5),
    surface: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFF0ECE9),
    surfaceMuted: Color(0xFFE8E3DF),
    surfaceDark: Color(0xFF1E242B),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF55504D),
    textMuted: Color(0xFF8E8A87),
    textOnMedia: Color(0xFFFFFFFF),
    accent: Color(0xFFC4975F),
    accentLight: Color(0xFFF8F2EB),
    border: Color(0xFFEBE6E1),
    borderSubtle: Color(0xFFF3EFEB),
    dockBackground: Color(0xFFFFFFFF),
    dockBorder: Color(0xFFEAE5E0),
    dockCapturePill: Color(0xFFF2ECE7),
    isDark: false,
  );

  /// 4. EVERGREEN - Deep forest green / sage / crisp white
  static const AppPalette evergreen = AppPalette(
    id: 'evergreen',
    name: 'Evergreen',
    description: 'Deep forest green, sage & clean white',
    background: Color(0xFFF5F8F6),
    surface: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFE9F0EB),
    surfaceMuted: Color(0xFFDCE6DF),
    surfaceDark: Color(0xFF1A261D),
    textPrimary: Color(0xFF19241B),
    textSecondary: Color(0xFF4A574C),
    textMuted: Color(0xFF7C8D7F),
    textOnMedia: Color(0xFFFFFFFF),
    accent: Color(0xFF4A7C59),
    accentLight: Color(0xFFEBF4EE),
    border: Color(0xFFDEE8E0),
    borderSubtle: Color(0xFFEBF2ED),
    dockBackground: Color(0xFFFFFFFF),
    dockBorder: Color(0xFFDAE5DD),
    dockCapturePill: Color(0xFFE7EFEA),
    isDark: false,
  );

  /// 5. OCEAN - Deep teal / vibrant aqua / crisp white
  static const AppPalette ocean = AppPalette(
    id: 'ocean',
    name: 'Ocean',
    description: 'Deep teal, vibrant aqua & crisp white',
    background: Color(0xFFF4F8F9),
    surface: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFE6EFF1),
    surfaceMuted: Color(0xFFD8E6E9),
    surfaceDark: Color(0xFF162428),
    textPrimary: Color(0xFF152226),
    textSecondary: Color(0xFF48565A),
    textMuted: Color(0xFF788A8F),
    textOnMedia: Color(0xFFFFFFFF),
    accent: Color(0xFF2E8B9A),
    accentLight: Color(0xFFE8F6F8),
    border: Color(0xFFDCE7EA),
    borderSubtle: Color(0xFFE9F1F3),
    dockBackground: Color(0xFFFFFFFF),
    dockBorder: Color(0xFFD8E4E7),
    dockCapturePill: Color(0xFFE5EEF1),
    isDark: false,
  );

  /// 6. LAVENDER - Deep plum / calming lavender / soft white
  static const AppPalette lavender = AppPalette(
    id: 'lavender',
    name: 'Lavender',
    description: 'Deep plum, calming lavender & soft white',
    background: Color(0xFFF8F5FA),
    surface: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFEFE9F3),
    surfaceMuted: Color(0xFFE4DAEA),
    surfaceDark: Color(0xFF261D2B),
    textPrimary: Color(0xFF231A28),
    textSecondary: Color(0xFF574A5D),
    textMuted: Color(0xFF8B7B92),
    textOnMedia: Color(0xFFFFFFFF),
    accent: Color(0xFF8E6AA0),
    accentLight: Color(0xFFF6F0F8),
    border: Color(0xFFE8DFED),
    borderSubtle: Color(0xFFF1EBF5),
    dockBackground: Color(0xFFFFFFFF),
    dockBorder: Color(0xFFE5DBEB),
    dockCapturePill: Color(0xFFECE3F1),
    isDark: false,
  );

  /// Backward-compatible aliases for theme IDs
  static const AppPalette dariaLight = dariaRedLight;
  static const AppPalette sage = evergreen;
  static const AppPalette forest = evergreen;
  static const AppPalette dusk = lavender;
  static const AppPalette rose = lavender;
  static const AppPalette sand = linen;

  /// The 7 curated presets for Daria.
  static const List<AppPalette> all = [
    dariaRedLight,
    dariaRed,
    midnight,
    linen,
    evergreen,
    ocean,
    lavender,
  ];

  /// Resolves palette by ID with backward compatibility, defaulting to [dariaRedLight].
  static AppPalette byId(String id) {
    final normalized = id.toLowerCase().trim();
    switch (normalized) {
      case 'daria_red_light':
      case 'daria_light':
      case 'light_red':
      case 'red_light':
        return dariaRedLight;
      case 'daria_red':
      case 'daria':
      case 'red':
      case 'daria_dark':
        return dariaRed;
      case 'midnight':
      case 'dark':
        return midnight;
      case 'linen':
      case 'light':
      case 'sand':
        return linen;
      case 'evergreen':
      case 'sage':
      case 'forest':
        return evergreen;
      case 'ocean':
      case 'blue':
      case 'teal':
        return ocean;
      case 'lavender':
      case 'dusk':
      case 'rose':
        return lavender;
      default:
        return dariaRedLight;
    }
  }
}
