import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/theme_controller.dart';
import 'package:dg_chat/core/layout/centered_pane.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/admin/application/admin_providers.dart';
import 'package:dg_chat/features/authentication/presentation/delete_account_dialog.dart';
import 'package:dg_chat/features/notifications/application/notification_preview_setting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.logOut),
        content: Text(context.l10n.logOutConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.logOut),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final loggedOut = await ref.read(authControllerProvider.notifier).logout();
    if (!context.mounted) return;
    if (loggedOut) {
      context.go(AppRoutes.login);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.serverUnavailable)));
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmation = context.l10n.accountDeleted;
    final deleted = await showDeleteAccountDialog(context);
    if (!deleted || !context.mounted) return;
    context.go(AppRoutes.login);
    messenger.showSnackBar(SnackBar(content: Text(confirmation)));
  }

  Future<void> _showAppearance(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, sheetRef, _) {
          final selected = sheetRef.watch(appThemeSettingProvider);
          final options = [
            (
              AppThemeSetting.system,
              Icons.brightness_auto_rounded,
              context.l10n.themeSystem,
            ),
            (
              AppThemeSetting.light,
              Icons.light_mode_rounded,
              context.l10n.themeLight,
            ),
            (
              AppThemeSetting.dark,
              Icons.dark_mode_rounded,
              context.l10n.themeDark,
            ),
          ];
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(
                      context.l10n.appearance,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  for (final option in options)
                    ListTile(
                      leading: Icon(option.$2),
                      title: Text(option.$3),
                      trailing: selected == option.$1
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () async {
                        await sheetRef
                            .read(appThemeSettingProvider.notifier)
                            .setTheme(option.$1);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _themeLabel(BuildContext context, AppThemeSetting setting) {
    return switch (setting) {
      AppThemeSetting.system => context.l10n.themeSystem,
      AppThemeSetting.light => context.l10n.themeLight,
      AppThemeSetting.dark => context.l10n.themeDark,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggingOut = ref.watch(authControllerProvider).isLoading;
    final themeSetting = ref.watch(appThemeSettingProvider);
    final userId = ref.watch(authControllerProvider).valueOrNull?.userId;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settings)),
      body: CenteredPane(
        maxWidth: 640,
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: Text(context.l10n.myProfile),
              subtitle: userId == null ? null : Text(userId),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: userId == null
                  ? null
                  : () => context.push(AppRoutes.userProfilePath(userId)),
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: Text(context.l10n.appearance),
              subtitle: Text(_themeLabel(context, themeSetting)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _showAppearance(context, ref),
            ),
            // Android only, because only there does it change anything. The
            // web draws its notifications from the open tab and has always
            // shown the message. An iPhone's are drawn by Apple from fixed
            // text until the app ships a notification extension of its own,
            // and a switch that moves nothing would be a lie.
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
              SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: Text(context.l10n.notificationPreviews),
                subtitle: Text(context.l10n.notificationPreviewsSubtitle),
                value: ref.watch(notificationPreviewsProvider),
                onChanged: (value) =>
                    ref.read(notificationPreviewsProvider.notifier).set(value),
              ),
            ListTile(
              leading: const Icon(Icons.block_rounded),
              title: Text(context.l10n.blockedUsers),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(AppRoutes.blockedUsers),
            ),
            // An account with no address here can only be recovered by an
            // admin with a terminal, so this is not an optional extra.
            ListTile(
              leading: const Icon(Icons.mail_outline_rounded),
              title: Text(context.l10n.emailAddresses),
              subtitle: Text(context.l10n.emailAddressesSubtitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(AppRoutes.emailAddress),
            ),
            // Only the admin account sees this; for everyone else the
            // provider quietly resolves false and the tile never exists.
            // Invite codes are minted on the server, not here: the admin API
            // that creates them is deliberately unreachable from the
            // internet. See docs/admin-guide.md.
            if (ref.watch(isAdminProvider).asData?.value ?? false)
              ListTile(
                leading: const Icon(Icons.manage_accounts_rounded),
                title: Text(context.l10n.userManagement),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.userManagement),
              ),
            const Divider(),
            ListTile(
              enabled: !isLoggingOut,
              leading: const Icon(Icons.logout_rounded),
              title: Text(
                isLoggingOut ? context.l10n.loggingOut : context.l10n.logOut,
              ),
              onTap: isLoggingOut ? null : () => _logout(context, ref),
            ),
            ListTile(
              enabled: !isLoggingOut,
              leading: Icon(
                Icons.delete_forever_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                context.l10n.deleteAccount,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: isLoggingOut ? null : () => _deleteAccount(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
