import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/features/admin/application/admin_providers.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/settings/presentation/settings_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';

final _previewsSwitch = find.widgetWithText(SwitchListTile, 'Message previews');

Future<SharedPreferences> _pumpSettings(
  WidgetTester tester, {
  Map<String, Object> stored = const {},
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final preferences = await SharedPreferences.getInstance();
  final auth = FakeAuthRepository(
    session: const AuthSession(userId: '@me:test'),
  );
  addTearDown(auth.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authRepositoryProvider.overrideWith((ref) async => auth),
        isAdminProvider.overrideWith((ref) async => false),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return preferences;
}

/// Runs [body] as though on [platform], and puts the platform back whatever
/// happens: a leaked override fails every test after this one.
Future<void> _on(TargetPlatform platform, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  testWidgets(
    'Android offers the switch, on until someone turns it off',
    (tester) => _on(TargetPlatform.android, () async {
      final preferences = await _pumpSettings(tester);

      expect(_previewsSwitch, findsOneWidget);
      expect(tester.widget<SwitchListTile>(_previewsSwitch).value, isTrue);

      await tester.tap(_previewsSwitch);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(_previewsSwitch).value, isFalse);
      // What the background push handler reads, in its own isolate.
      expect(AppPreferences(preferences).showsNotificationPreviews, isFalse);
    }),
  );

  testWidgets('Android remembers a switch turned off earlier', (tester) {
    return _on(TargetPlatform.android, () async {
      await _pumpSettings(tester, stored: {'notification_previews': false});
      expect(tester.widget<SwitchListTile>(_previewsSwitch).value, isFalse);
    });
  });

  testWidgets(
    'an iPhone gets no switch, since it would change nothing',
    (tester) => _on(TargetPlatform.iOS, () async {
      await _pumpSettings(tester);
      expect(find.text('Message previews'), findsNothing);
    }),
  );
}
