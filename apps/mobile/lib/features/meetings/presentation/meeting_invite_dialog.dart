import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/features/meetings/application/meeting_providers.dart';
import 'package:dg_chat/features/meetings/domain/meeting_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Creates a meeting and presents its invitation. One entry point for every
/// surface that offers "New meeting", so the flow cannot fork.
Future<void> startNewMeeting(BuildContext context, WidgetRef ref) async {
  try {
    final repository = await ref.read(meetingRepositoryProvider.future);
    if (!context.mounted) return;
    final meeting = await repository.createMeeting(
      context.l10n.meetingDefaultTitle,
    );
    if (!context.mounted) return;
    await showMeetingInviteDialog(context, meeting);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.meetingCreateFailed)));
    }
  }
}

/// Shown the moment a meeting is created: the link, and the ways to hand it
/// to people. The link is the invitation, so this dialog is the product.
Future<void> showMeetingInviteDialog(BuildContext context, Meeting meeting) {
  return showDialog<void>(
    context: context,
    builder: (context) => _MeetingInviteDialog(meeting: meeting),
  );
}

class _MeetingInviteDialog extends StatelessWidget {
  const _MeetingInviteDialog({required this.meeting});

  final Meeting meeting;

  @override
  Widget build(BuildContext context) {
    final link = meetingLink(meeting);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: const Icon(Icons.video_call_rounded),
      title: Text(context.l10n.meetingReady),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.meetingShareHint),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.maxFinite,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              link,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              // The system share sheet: WhatsApp, SMS, whatever the person
              // actually uses to reach the people they are inviting. Meet's
              // whole gesture is this button.
              FilledButton.tonalIcon(
                onPressed: () {
                  SharePlus.instance
                      .share(
                        ShareParams(
                          text: context.l10n.meetingInviteBody(link),
                          subject: context.l10n.meetingInviteSubject,
                        ),
                      )
                      .catchError(
                        (_) => const ShareResult(
                          '',
                          ShareResultStatus.unavailable,
                        ),
                      );
                },
                icon: const Icon(Icons.share_rounded, size: 18),
                label: Text(context.l10n.shareLink),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.l10n.linkCopied)),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(context.l10n.copyLink),
              ),
              TextButton.icon(
                onPressed: () {
                  // mailto keeps credentials out of the app entirely: the
                  // invite goes from the user's own mail account, which is
                  // also who the recipient expects it from.
                  final uri = Uri(
                    scheme: 'mailto',
                    query:
                        'subject=${Uri.encodeComponent(context.l10n.meetingInviteSubject)}'
                        '&body=${Uri.encodeComponent(context.l10n.meetingInviteBody(link))}',
                  );
                  launchUrl(uri).catchError((_) => false);
                },
                icon: const Icon(Icons.mail_outline_rounded, size: 18),
                label: Text(context.l10n.emailInvite),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(context);
            openCall(context, meeting.roomId, withVideo: true, ring: false);
          },
          icon: const Icon(Icons.videocam_rounded),
          label: Text(context.l10n.joinNow),
        ),
      ],
    );
  }
}
