import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class HiddenEventStore {
  Future<Set<String>> read(String userId, String roomId);

  Future<void> hide(String userId, String roomId, String eventId);

  /// Drops every hidden-event record for an account. Called on logout so no
  /// per-account history remains on a signed-out device.
  Future<void> deleteForUser(String userId);
}

final hiddenEventStoreProvider = Provider<HiddenEventStore>((ref) {
  return SharedPreferencesHiddenEventStore(
    ref.watch(sharedPreferencesProvider),
  );
});

class SharedPreferencesHiddenEventStore implements HiddenEventStore {
  SharedPreferencesHiddenEventStore(this._preferences);

  final SharedPreferences _preferences;

  String _key(String userId, String roomId) =>
      '${_userPrefix(userId)}${Uri.encodeComponent(roomId)}';

  String _userPrefix(String userId) =>
      'hidden_events_${Uri.encodeComponent(userId)}_';

  @override
  Future<Set<String>> read(String userId, String roomId) async {
    return (_preferences.getStringList(_key(userId, roomId)) ?? const [])
        .toSet();
  }

  @override
  Future<void> hide(String userId, String roomId, String eventId) async {
    final key = _key(userId, roomId);
    final eventIds = (_preferences.getStringList(key) ?? const []).toSet()
      ..add(eventId);
    await _preferences.setStringList(key, eventIds.toList(growable: false));
  }

  @override
  Future<void> deleteForUser(String userId) async {
    final prefix = _userPrefix(userId);
    final keys = _preferences
        .getKeys()
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);
    for (final key in keys) {
      await _preferences.remove(key);
    }
  }
}
