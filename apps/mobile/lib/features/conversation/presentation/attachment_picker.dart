import 'dart:async';
import 'dart:ui' as ui;

import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Lets the user choose what to share and turns the pick into a draft.
///
/// Returns null when the sheet or the platform picker is dismissed, which is
/// a normal outcome rather than an error.
Future<AttachmentDraft?> pickAttachment(BuildContext context) async {
  final source = await showModalBottomSheet<_AttachmentSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(context.l10n.sendPhoto),
              onTap: () => Navigator.pop(context, _AttachmentSource.gallery),
            ),
            // The camera is a phone affordance. On web and desktop the picker
            // either does nothing or opens a broken capture flow, so the row
            // is not offered there at all.
            if (_hasCamera)
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: Text(context.l10n.takePhoto),
                onTap: () => Navigator.pop(context, _AttachmentSource.camera),
              ),
            ListTile(
              leading: const Icon(Icons.attach_file_rounded),
              title: Text(context.l10n.sendFile),
              onTap: () => Navigator.pop(context, _AttachmentSource.file),
            ),
          ],
        ),
      ),
    ),
  );

  return switch (source) {
    null => null,
    _AttachmentSource.gallery => _pickImage(ImageSource.gallery),
    _AttachmentSource.camera => _pickImage(ImageSource.camera),
    _AttachmentSource.file => _pickFile(),
  };
}

enum _AttachmentSource { gallery, camera, file }

bool get _hasCamera =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Photos are downscaled and re-encoded at pick time. A modern camera photo
/// is 3-8MB of pixels nobody zooms into in a chat; 2048px at quality 85 is
/// the Telegram-style trade of visually identical for a fraction of the
/// upload. Sending an original stays possible through the file picker, which
/// does not touch bytes.
Future<AttachmentDraft?> _pickImage(ImageSource source) async {
  final XFile? file;
  try {
    file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
  } catch (_) {
    // A device without a camera, or a denied permission: the platform picker
    // already told the user what it could; there is nothing to add.
    return null;
  }
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return draftFromBytes(bytes, file.name, mimeType: file.mimeType);
}

Future<AttachmentDraft?> _pickFile() async {
  final XFile? file;
  try {
    file = await openFile();
  } catch (_) {
    return null;
  }
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return draftFromBytes(bytes, file.name, mimeType: file.mimeType);
}

/// Builds the draft, measuring pixel dimensions when the bytes decode as an
/// image so receivers can reserve the right space in their timeline.
@visibleForTesting
Future<AttachmentDraft> draftFromBytes(
  Uint8List bytes,
  String fileName, {
  String? mimeType,
}) async {
  double? width;
  double? height;
  // Decoding is attempted from the bytes rather than trusted from the mime
  // type: pickers routinely report null or octet-stream for images, and the
  // codec is the one authority on whether these bytes draw.
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    width = descriptor.width.toDouble();
    height = descriptor.height.toDouble();
    descriptor.dispose();
    buffer.dispose();
  } catch (_) {
    // Not an image, which is fine: the draft simply carries no dimensions.
  }
  return AttachmentDraft(
    bytes: bytes,
    fileName: fileName,
    mimeType: mimeType,
    width: width,
    height: height,
  );
}
