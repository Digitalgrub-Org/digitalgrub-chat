import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Settings switch for message previews in phone notifications.
///
/// Stored in shared preferences rather than on the account: whether a
/// message shows on a lock screen is about the phone in someone's hand, and
/// a work phone and a personal one can reasonably disagree.
final notificationPreviewsProvider =
    StateNotifierProvider<NotificationPreviewsController, bool>(
      (ref) =>
          NotificationPreviewsController(ref.watch(appPreferencesProvider)),
    );

class NotificationPreviewsController extends StateNotifier<bool> {
  NotificationPreviewsController(this._preferences)
    : super(_preferences.showsNotificationPreviews);

  final AppPreferences _preferences;

  Future<void> set(bool value) async {
    if (state == value) return;
    state = value;
    await _preferences.setShowsNotificationPreviews(value);
  }
}
