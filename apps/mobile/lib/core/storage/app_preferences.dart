import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw StateError('SharedPreferences must be initialized in main.'),
);

final appPreferencesProvider = Provider<AppPreferences>(
  (ref) => AppPreferences(ref.watch(sharedPreferencesProvider)),
);

class AppPreferences {
  AppPreferences(this._preferences);

  static const _onboardingCompleteKey = 'onboarding_complete';
  static const _themeModeKey = 'theme_mode';
  static const _contentAgreementKey = 'content_agreement_version';
  static const _notificationPromptDismissedKey = 'notification_prompt_hidden';
  static const _notificationPreviewsKey = 'notification_previews';

  /// Raise this when the community rules change materially, so every user is
  /// asked to accept the new text.
  static const contentAgreementVersion = 1;

  final SharedPreferences _preferences;

  bool get isOnboardingComplete =>
      _preferences.getBool(_onboardingCompleteKey) ?? false;

  Future<void> completeOnboarding() =>
      _preferences.setBool(_onboardingCompleteKey, true);

  /// App Review guideline 1.2 requires the rules to be accepted before a user
  /// can post user-generated content.
  bool get hasAcceptedContentAgreement =>
      (_preferences.getInt(_contentAgreementKey) ?? 0) >=
      contentAgreementVersion;

  Future<void> acceptContentAgreement() =>
      _preferences.setInt(_contentAgreementKey, contentAgreementVersion);

  /// Whether the web notification prompt has been waved away. Asking once is
  /// a suggestion; asking on every reload is nagging.
  bool get isNotificationPromptDismissed =>
      _preferences.getBool(_notificationPromptDismissedKey) ?? false;

  Future<void> dismissNotificationPrompt() =>
      _preferences.setBool(_notificationPromptDismissedKey, true);

  /// Whether a phone notification says who wrote and what, or only that a
  /// message came. On unless turned off: a notification that names nobody
  /// turns every buzz into a trip into the app to find out who it was.
  bool get showsNotificationPreviews =>
      _preferences.getBool(_notificationPreviewsKey) ?? true;

  Future<void> setShowsNotificationPreviews(bool value) =>
      _preferences.setBool(_notificationPreviewsKey, value);

  String? get themeModeName => _preferences.getString(_themeModeKey);

  Future<void> setThemeModeName(String value) =>
      _preferences.setString(_themeModeKey, value);
}
