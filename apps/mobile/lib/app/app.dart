import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/core/diagnostics/pointer_diagnostics.dart';
import 'package:dg_chat/app/theme/theme_controller.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/features/chats/domain/unread_tally.dart';
import 'package:dg_chat/features/notifications/data/tab_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The browser tab's favicon, which lives as long as the app does.
final tabBadgeProvider = Provider<TabBadge>((ref) => createTabBadge());

class DigitalgrubChatApp extends ConsumerWidget {
  const DigitalgrubChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(
      appThemeSettingProvider.select((setting) => setting.themeMode),
    );

    // Watched rather than listened to, because the title is rebuilt from it
    // below. Off the web this is a cheap no-op: the tally is derived from a
    // list the chat screen already watches, and nothing renders a title.
    final unread = ref.watch(unreadTallyProvider);
    ref.read(tabBadgeProvider).show(marked: unread.hasAnything);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      // The title goes through Flutter rather than being written onto
      // `document.title` directly. Flutter owns that property -- it rewrites
      // it from here on every rebuild -- so anything set behind its back
      // lasts until the next frame and no longer.
      onGenerateTitle: (context) =>
          titleForUnread(AppLocalizations.of(context).appName, unread),
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      // Wraps every screen so a click anywhere is accounted for, including
      // the ones that appear to do nothing. Draws and costs nothing unless
      // the page was opened with ?diag=1.
      builder: (context, child) =>
          PointerDiagnostics(child: child ?? const SizedBox.shrink()),
    );
  }
}
