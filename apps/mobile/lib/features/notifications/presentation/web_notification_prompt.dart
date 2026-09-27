import 'dart:async';

import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/notifications/application/push_providers.dart';
import 'package:dg_chat/features/notifications/application/web_notification_listener.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks, once, for permission to show desktop notifications on the web.
///
/// It has to be a tap rather than something done at start-up: browsers only
/// raise the permission prompt during a user gesture, and one that appears
/// unbidden is the reason people block notifications for a site forever.
class WebNotificationPrompt extends ConsumerStatefulWidget {
  const WebNotificationPrompt({this.isWeb = kIsWeb, super.key});

  /// Injected so the banner can be exercised off the web, where `kIsWeb` is
  /// a compile-time false and would optimise the whole widget away.
  final bool isWeb;

  @override
  ConsumerState<WebNotificationPrompt> createState() =>
      _WebNotificationPromptState();
}

class _WebNotificationPromptState extends ConsumerState<WebNotificationPrompt> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.isWeb || _hidden) return const SizedBox.shrink();
    final presenter = ref.watch(webNotificationPresenterProvider);
    // Only the undecided are asked. A browser that already said yes needs no
    // banner, and one that said no cannot be asked again from here anyway.
    if (!presenter.canRequestPermission) return const SizedBox.shrink();
    if (ref.watch(appPreferencesProvider).isNotificationPromptDismissed) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                size: 18,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  context.l10n.enableNotificationsPrompt,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
              TextButton(
                onPressed: _enable,
                child: Text(context.l10n.enableNotifications),
              ),
              IconButton(
                tooltip: context.l10n.dismiss,
                onPressed: _dismiss,
                icon: const Icon(Icons.close_rounded, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _enable() async {
    final granted = await ref
        .read(webNotificationPresenterProvider)
        .requestPermission();
    if (granted) {
      await ref.read(webNotificationListenerProvider).start();
      // Permission just arrived in a gesture, which is also the moment a
      // browser will hand out a push subscription; from here on a closed
      // tab still gets a (content-free) notification.
      unawaited(
        ref
            .read(pushRegistrationServiceProvider)
            .start(alertText: context.l10n.newMessageNotification),
      );
    }
    if (!mounted) return;
    // Either way the banner has served its purpose: granted means it works,
    // denied means the browser will not ask again.
    setState(() => _hidden = true);
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.notificationsBlocked)),
      );
    }
  }

  Future<void> _dismiss() async {
    await ref.read(appPreferencesProvider).dismissNotificationPrompt();
    if (mounted) setState(() => _hidden = true);
  }
}
