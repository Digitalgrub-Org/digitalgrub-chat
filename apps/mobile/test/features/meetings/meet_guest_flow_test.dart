import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/meetings/presentation/meet_screen.dart';
import 'package:flutter/material.dart';
import 'package:dg_chat/core/config/app_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/test_app_config.dart';

Future<GoRouter> _pump(WidgetTester tester) async {
  final auth = FakeAuthRepository();
  addTearDown(auth.dispose);
  final router = GoRouter(
    initialLocation: '/meet/brj-hqmr-cph',
    routes: [
      GoRoute(
        path: '/meet/:roomId',
        builder: (context, state) =>
            MeetScreen(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/call/:roomId',
        builder: (context, state) =>
            Text('call ${state.uri}', textDirection: TextDirection.ltr),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            Text('login ${state.uri}', textDirection: TextDirection.ltr),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWith((ref) async => auth),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('a signed-out visitor is asked for a name, not an account', (
    tester,
  ) async {
    await _pump(tester);

    // The meeting link is for people without accounts too; the account door
    // stays available but stops being the front one.
    expect(find.text('Join this meeting'), findsOneWidget);
    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('Sign in instead'), findsOneWidget);
  });

  testWidgets('a name is enough to reach the call', (tester) async {
    final router = await _pump(tester);

    await tester.enterText(find.byType(TextField), '  Guest Dev ');
    await tester.tap(find.text('Join meeting'));
    await tester.pumpAndSettle();

    final location = router.state.uri.toString();
    expect(location, startsWith('/call/brj-hqmr-cph'));
    // Trimmed, carried as the guest identity, and never rings the room.
    expect(location, contains('guest=Guest%20Dev'));
    expect(location, contains('ring=0'));
  });

  testWidgets('an empty name goes nowhere', (tester) async {
    final router = await _pump(tester);

    await tester.tap(find.text('Join meeting'));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/meet/brj-hqmr-cph');
  });

  testWidgets('sign in instead keeps the meeting as the destination', (
    tester,
  ) async {
    final router = await _pump(tester);

    await tester.tap(find.text('Sign in instead'));
    await tester.pumpAndSettle();

    expect(
      router.state.uri.toString(),
      '/login?next=${Uri.encodeComponent('/meet/brj-hqmr-cph')}',
    );
  });
}
