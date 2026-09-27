import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Published contact point for content complaints. App Review guideline 1.2
/// requires it to be reachable from inside the app, and commits us to acting on
/// reports within 24 hours, so this mailbox has to be monitored.
const String moderationContactEmail = 'moderation@example.com';

/// Shows the community rules and records acceptance. Returns true when the
/// user agrees.
///
/// Guideline 1.2 requires an app carrying user-generated content to obtain
/// agreement to the rules before a user can post, alongside the reporting and
/// blocking that already exist.
Future<bool> showContentAgreement(BuildContext context) async {
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (context) => const _ContentAgreementSheet(),
  );
  return accepted ?? false;
}

/// Returns true when the user may post: either they have already accepted, or
/// they accept the prompt shown now.
Future<bool> ensureContentAgreement(BuildContext context, WidgetRef ref) async {
  final preferences = ref.read(appPreferencesProvider);
  if (preferences.hasAcceptedContentAgreement) return true;

  final accepted = await showContentAgreement(context);
  if (accepted) await preferences.acceptContentAgreement();
  return accepted;
}

class _ContentAgreementSheet extends StatelessWidget {
  const _ContentAgreementSheet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, size: 40, color: scheme.primary),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.l10n.contentAgreementTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(context.l10n.contentAgreementBody),
              const SizedBox(height: AppSpacing.md),
              _Rule(
                icon: Icons.flag_outlined,
                text: context.l10n.contentAgreementReport,
              ),
              _Rule(
                icon: Icons.block_rounded,
                text: context.l10n.contentAgreementBlock,
              ),
              _Rule(
                icon: Icons.mail_outline_rounded,
                text: context.l10n.contentAgreementContact(
                  moderationContactEmail,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(context.l10n.contentAgreementAccept),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(context.l10n.contentAgreementDecline),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
