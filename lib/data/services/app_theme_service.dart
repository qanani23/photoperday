import 'package:flutter/material.dart';
import 'package:photo_per_day/core/theme/app_palette.dart';
import 'package:photo_per_day/data/services/app_theme_storage.dart';

/// Central domain service responsible for managing the active theme palette and appearance.
class AppThemeService extends ChangeNotifier with WidgetsBindingObserver {
  AppThemeService({AppThemeStorage? storage})
    : _storage = storage ?? AppThemeStorage();

  static AppThemeService _instance = AppThemeService();

  /// Global singleton instance.
  static AppThemeService get instance => _instance;

  @visibleForTesting
  static void setTestInstance(AppThemeService testInstance) {
    _instance = testInstance;
  }

  @visibleForTesting
  static void resetTestInstance() {
    try {
      _instance.dispose();
    } catch (_) {}
    _instance = AppThemeService();
  }

  AppThemeStorage _storage;
  AppPalette _currentPalette = AppPalettes.dariaRedLight;
  bool _followSystem = false;
  bool _isInitialized = false;

  /// Currently active color palette.
  AppPalette get currentPalette => _currentPalette;

  /// Whether current active palette is dark.
  bool get isDark => _currentPalette.isDark;

  /// Whether the app automatically syncs palette with device light/dark mode.
  bool get followSystem => _followSystem;

  /// Whether the theme service has loaded persisted preferences.
  bool get isInitialized => _isInitialized;

  /// Initializes the service and restores persisted palette preference or system brightness.
  Future<void> init({AppThemeStorage? storage}) async {
    if (storage != null) _storage = storage;

    // Register observer to track OS brightness adjustments if followSystem is on
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}

    final settings = await _storage.loadSettings();
    _followSystem = settings.followSystem;

    if (settings.paletteId != null && !_followSystem) {
      _currentPalette = AppPalettes.byId(settings.paletteId!);
    } else if (_followSystem) {
      _currentPalette = _resolveSystemPalette();
    } else {
      _currentPalette = AppPalettes.dariaRedLight;
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Changes the active palette, disables followSystem, and persists choice to disk.
  Future<void> setPalette(AppPalette palette) async {
    _followSystem = false;
    if (_currentPalette == palette) {
      await _storage.saveSettings(paletteId: palette.id, followSystem: false);
      return;
    }
    _currentPalette = palette;
    await _storage.saveSettings(paletteId: palette.id, followSystem: false);
    notifyListeners();
  }

  /// Toggles between light mode (Daria Red Light) and dark mode (Daria Red).
  Future<void> toggleDarkLight() async {
    final nextPalette = _currentPalette.isDark
        ? AppPalettes.dariaRedLight
        : AppPalettes.dariaRed;
    await setPalette(nextPalette);
  }

  /// Sets whether the app should follow the phone's system light/dark theme.
  Future<void> setFollowSystem(bool follow) async {
    if (_followSystem == follow) return;
    _followSystem = follow;
    if (follow) {
      _currentPalette = _resolveSystemPalette();
    }
    await _storage.saveSettings(
      paletteId: _currentPalette.id,
      followSystem: follow,
    );
    notifyListeners();
  }

  @override
  void didChangePlatformBrightness() {
    if (_followSystem) {
      final target = _resolveSystemPalette();
      if (_currentPalette != target) {
        _currentPalette = target;
        notifyListeners();
      }
    }
  }

  AppPalette _resolveSystemPalette() {
    try {
      final brightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      return brightness == Brightness.dark
          ? AppPalettes.dariaRed
          : AppPalettes.dariaRedLight;
    } catch (_) {
      return AppPalettes.dariaRedLight;
    }
  }

  @override
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    super.dispose();
  }
}
