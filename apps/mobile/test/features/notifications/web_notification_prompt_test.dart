import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/notifications/application/web_notification_listener.dart';
import 'package:dg_chat/features/notifications/data/web_notification_presenter.dart';
import 'package:dg_chat/features/notifications/data/web_notifications.dart';
import 'package:dg_chat/features/notifications/presentation/web_notification_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeWebNotifications implements WebNotifications {
  _FakeWebNotifications(this._permission, {this.grantOnRequest});

  WebNotificationPermission _permission;
  final WebNotificationPermission? grantOnRequest;
  int requestCount = 0;

  @override
  WebNotificationPermission get permission => _permission;

  @override
  Future<WebNotificationPermission> requestPermission() async {
    requestCount++;
    if (grantOnRequest != null) _permission = grantOnRequest!;
    return _permission;
  }

  @override
  void show({
    required String tag,
    required String title,
    String? body,
    void Function()? onClick,
  }) {}

  @override
  void close(String tag) {}
}

Future<_FakeWebNotifications> _pumpPrompt(
  WidgetTester tester, {
  required WebNotificationPermission permission,
  WebNotificationPermission? grantOnRequest,
  bool alreadyDismissed = false,
}) async {
  SharedPreferences.setMockInitialValues({
    if (alreadyDismissed) 'notification_prompt_hidden': true,
  });
  final preferences = await SharedPreferences.getInstance();
  final browser = _FakeWebNotifications(
    permission,
    grantOnRequest: grantOnRequest,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        webNotificationPresenterProvider.overrideWithValue(
          WebNotificationPresenter(notifications: browser),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: WebNotificationPrompt(isWeb: true)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return browser;
}

void main() {
  testWidgets('offers to turn notifications on', (tester) async {
    final browser = await _pumpPrompt(
      tester,
      permission: WebNotificationPermission.prompt,
      grantOnRequest: WebNotificationPermission.granted,
    );

    expect(find.textContaining('Get notified'), findsOneWidget);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();

    // Asked once, and gone whether or not the answer was yes.
    expect(browser.requestCount, 1);
    expect(find.textContaining('Get notified'), findsNothing);
  });

  testWidgets('says so when the browser refuses', (tester) async {
    await _pumpPrompt(
      tester,
      permission: WebNotificationPermission.prompt,
      grantOnRequest: WebNotificationPermission.denied,
    );

    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();

    // Silence would look like a bug; the browser has to be blamed by name,
    // because only its own settings can undo this.
    expect(find.textContaining('blocking notifications'), findsOneWidget);
  });

  testWidgets('stays hidden once waved away', (tester) async {
    await _pumpPrompt(
      tester,
      permission: WebNotificationPermission.prompt,
      alreadyDismissed: true,
    );

    expect(find.textContaining('Get notified'), findsNothing);
  });

  testWidgets('never appears for a browser that already answered', (
    tester,
  ) async {
    for (final permission in [
      WebNotificationPermission.granted,
      WebNotificationPermission.denied,
    ]) {
      await _pumpPrompt(tester, permission: permission);
      expect(
        find.textContaining('Get notified'),
        findsNothing,
        reason: permission.name,
      );
    }
  });

  testWidgets('draws nothing at all off the web', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          webNotificationPresenterProvider.overrideWithValue(
            WebNotificationPresenter(
              notifications: _FakeWebNotifications(
                WebNotificationPermission.prompt,
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // The default on Android and iOS, where notifications arrive
          // through the push gateway instead.
          home: Scaffold(body: WebNotificationPrompt(isWeb: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Get notified'), findsNothing);
  });
}
