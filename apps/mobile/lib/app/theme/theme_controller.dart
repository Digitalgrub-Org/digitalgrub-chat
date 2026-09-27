import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppThemeSetting {
  system(ThemeMode.system),
  light(ThemeMode.light),
  dark(ThemeMode.dark);

  const AppThemeSetting(this.themeMode);

  final ThemeMode themeMode;
}

final appThemeSettingProvider =
    StateNotifierProvider<AppThemeSettingController, AppThemeSetting>((ref) {
      return AppThemeSettingController(ref.watch(appPreferencesProvider));
    });

class AppThemeSettingController extends StateNotifier<AppThemeSetting> {
  AppThemeSettingController(this._preferences)
    : super(_fromStoredName(_preferences.themeModeName));

  final AppPreferences _preferences;

  Future<void> setTheme(AppThemeSetting setting) async {
    if (state == setting) return;
    state = setting;
    await _preferences.setThemeModeName(setting.name);
  }

  static AppThemeSetting _fromStoredName(String? name) {
    return AppThemeSetting.values.firstWhere(
      (setting) => setting.name == name,
      orElse: () => AppThemeSetting.system,
    );
  }
}
