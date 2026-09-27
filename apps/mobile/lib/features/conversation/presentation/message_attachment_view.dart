import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/core/widgets/authenticated_network_image.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/features/conversation/presentation/voice_message_player.dart';
import 'package:flutter/material.dart';

/// Renders the file a message carries.
///
/// Images are shown inline because that is the whole point of sending one;
/// everything else is a row naming the file, since this app has no player and
/// a fake one would be worse than an honest listing.
class MessageAttachmentView extends StatelessWidget {
  const MessageAttachmentView({
    required this.attachment,
    this.onOpenImage,
    super.key,
  });

  final MessageAttachment attachment;

  /// Invoked with the full-size image URL when an image is tapped.
  final void Function(MessageAttachment attachment)? onOpenImage;

  @override
  Widget build(BuildContext context) {
    if (attachment.isVoice) {
      return VoiceMessagePlayer(attachment: attachment);
    }
    if (attachment.isImage && attachment.url != null) {
      return _ImageAttachment(attachment: attachment, onOpen: onOpenImage);
    }
    return _FileAttachment(attachment: attachment);
  }
}

class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({required this.attachment, this.onOpen});

  final MessageAttachment attachment;
  final void Function(MessageAttachment attachment)? onOpen;

  /// Images are boxed rather than shown at their own size: a screenshot from a
  /// desktop is wider than any phone, and a panorama would push the timestamp
  /// off screen.
  static const _maxHeight = 260.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = attachment.width;
    final height = attachment.height;
    // The sender's reported dimensions reserve the right space, so the
    // timeline does not jump when the bytes arrive.
    final ratio = (width != null && height != null && height > 0)
        ? width / height
        : 4 / 3;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: _maxHeight),
        child: AspectRatio(
          aspectRatio: ratio.clamp(0.5, 2.5),
          child: Material(
            color: scheme.surfaceContainerHighest,
            child: InkWell(
              onTap: onOpen == null ? null : () => onOpen!(attachment),
              child: AuthenticatedNetworkImage(
                url: attachment.thumbnailUrl ?? attachment.url!,
                headers: attachment.headers,
                fit: BoxFit.cover,
                placeholder: (context) =>
                    const Center(child: CircularProgressIndicator()),
                // A failed image still has to say something: silence here is
                // what made missing attachments invisible in the first place.
                error: (context) => _AttachmentFallback(
                  icon: Icons.broken_image_outlined,
                  label: context.l10n.attachmentUnavailable,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileAttachment extends StatelessWidget {
  const _FileAttachment({required this.attachment});

  final MessageAttachment attachment;

  IconData get _icon => switch (attachment.kind) {
    AttachmentKind.video => Icons.videocam_rounded,
    AttachmentKind.audio => Icons.mic_rounded,
    _ => Icons.insert_drive_file_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = attachment.sizeBytes;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  size == null
                      ? context.l10n.attachmentFile
                      : formatFileSize(size),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentFallback extends StatelessWidget {
  const _AttachmentFallback({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: scheme.onSurfaceVariant),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Formats a byte count the way a file listing would.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  // One decimal below 10 so 1.4 MB does not read as 1 MB, none above it where
  // the extra digit is noise.
  final text = value >= 10
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

/// Full-screen viewer for a tapped image.
Future<void> showAttachmentViewer(
  BuildContext context,
  MessageAttachment attachment,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 5,
              child: AuthenticatedNetworkImage(
                url: attachment.url!,
                headers: attachment.headers,
                fit: BoxFit.contain,
                placeholder: (context) =>
                    const Center(child: CircularProgressIndicator()),
                error: (context) => _AttachmentFallback(
                  icon: Icons.broken_image_outlined,
                  label: context.l10n.attachmentUnavailable,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: context.l10n.close,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
