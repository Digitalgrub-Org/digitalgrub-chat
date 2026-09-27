import 'package:dg_chat/core/storage/hidden_event_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'hidden events persist and remain isolated by account and room',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesHiddenEventStore(preferences);

      await store.hide('@alice:test', '!one:test', r'$event');

      expect(await store.read('@alice:test', '!one:test'), {r'$event'});
      expect(await store.read('@alice:test', '!two:test'), isEmpty);
      expect(await store.read('@bob:test', '!one:test'), isEmpty);
    },
  );
}
