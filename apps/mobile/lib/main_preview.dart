import 'package:dg_chat/app/app.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/demo/demo_repositories.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/features/contacts/application/user_search_controller.dart';
import 'package:dg_chat/features/conversation/application/conversation_providers.dart';
import 'package:dg_chat/features/groups/application/group_providers.dart';
import 'package:dg_chat/features/moderation/application/report_providers.dart';
import 'package:dg_chat/features/profile/application/profile_providers.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  await preferences.setBool('onboarding_complete', true);
  const previewTheme = String.fromEnvironment('DG_PREVIEW_THEME');
  if (const {'system', 'light', 'dark'}.contains(previewTheme)) {
    await preferences.setString('theme_mode', previewTheme);
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authRepositoryProvider.overrideWith(
          (ref) async => DemoAuthRepository(),
        ),
        chatRepositoryProvider.overrideWith(
          (ref) async => DemoChatRepository(),
        ),
        userRepositoryProvider.overrideWith(
          (ref) async => DemoUserRepository(),
        ),
        messageRepositoryProvider.overrideWith(
          (ref) async => DemoMessageRepository(),
        ),
        groupRepositoryProvider.overrideWith(
          (ref) async => DemoGroupRepository(),
        ),
        profileRepositoryProvider.overrideWith(
          (ref) async => DemoProfileRepository(),
        ),
        reportRepositoryProvider.overrideWith(
          (ref) async => DemoReportRepository(),
        ),
        messagingRuntimeProvider.overrideWith(
          (ref) async => DemoMessagingRuntime(),
        ),
        // Offline by default, because the preview has no server and saying
        // so is honest. Screenshots want the ordinary connected state, so
        // the entry point takes it as a define rather than forcing either.
        messagingStatusProvider.overrideWith(
          (ref) => Stream.value(_previewStatus),
        ),
      ],
      child: const DigitalgrubChatApp(),
    ),
  );
}

/// Connection state the preview reports, from `DG_PREVIEW_STATUS`.
///
/// Anything unrecognised falls back to offline, so a typo in a build command
/// cannot quietly dress the app up as connected when it is not.
MessagingConnectionState get _previewStatus =>
    switch (const String.fromEnvironment('DG_PREVIEW_STATUS')) {
      'online' => MessagingConnectionState.online,
      'synchronizing' => MessagingConnectionState.synchronizing,
      _ => MessagingConnectionState.offline,
    };
