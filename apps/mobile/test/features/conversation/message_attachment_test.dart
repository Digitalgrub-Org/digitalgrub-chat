import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/features/conversation/presentation/message_attachment_view.dart';
import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The attachment view reads localized labels, so it needs the delegates.
Widget wrapForTest(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

MessageAttachment _attachment({
  AttachmentKind kind = AttachmentKind.file,
  String fileName = 'report.pdf',
  int? sizeBytes,
  Uri? url,
}) {
  return MessageAttachment(
    kind: kind,
    fileName: fileName,
    sizeBytes: sizeBytes,
    url: url,
    headers: const {'authorization': 'Bearer token'},
  );
}

void main() {
  group('formatFileSize', () {
    test('uses the unit a file listing would', () {
      expect(formatFileSize(512), '512 B');
      expect(formatFileSize(2048), '2.0 KB');
      expect(formatFileSize(1024 * 1024 * 3), '3.0 MB');
      expect(formatFileSize(1024 * 1024 * 1024 * 2), '2.0 GB');
    });

    test('drops the decimal once it is noise', () {
      // 1.4 MB must not read as 1 MB, but 314.7 MB gains nothing from the .7.
      expect(formatFileSize((1.4 * 1024 * 1024).round()), '1.4 MB');
      expect(formatFileSize((314.7 * 1024 * 1024).round()), '315 MB');
    });
  });

  group('MessageAttachmentView', () {
    testWidgets('names a file and its size', (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          MessageAttachmentView(
            attachment: _attachment(fileName: 'budget.xlsx', sizeBytes: 4096),
          ),
        ),
      );

      expect(find.text('budget.xlsx'), findsOneWidget);
      expect(find.text('4.0 KB'), findsOneWidget);
    });

    testWidgets('still names a file whose size the sender omitted', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapForTest(
          MessageAttachmentView(attachment: _attachment(fileName: 'notes.txt')),
        ),
      );

      expect(find.text('notes.txt'), findsOneWidget);
    });

    testWidgets('falls back to a file row when an image has no url', (
      tester,
    ) async {
      // A redacted or malformed event has no content URI. Rendering an image
      // widget with a null source would throw; naming the file does not.
      await tester.pumpWidget(
        wrapForTest(
          MessageAttachmentView(
            attachment: _attachment(
              kind: AttachmentKind.image,
              fileName: 'photo.jpg',
            ),
          ),
        ),
      );

      expect(find.text('photo.jpg'), findsOneWidget);
    });

    testWidgets('marks video and audio with their own icon', (tester) async {
      for (final (kind, icon) in [
        (AttachmentKind.video, Icons.videocam_rounded),
        (AttachmentKind.audio, Icons.mic_rounded),
        (AttachmentKind.file, Icons.insert_drive_file_rounded),
      ]) {
        await tester.pumpWidget(
          wrapForTest(
            MessageAttachmentView(attachment: _attachment(kind: kind)),
          ),
        );
        expect(find.byIcon(icon), findsOneWidget, reason: '$kind');
      }
    });
  });

  group('MessageAttachment', () {
    test('only images render inline', () {
      expect(_attachment(kind: AttachmentKind.image).isImage, isTrue);
      for (final kind in [
        AttachmentKind.video,
        AttachmentKind.audio,
        AttachmentKind.file,
      ]) {
        expect(_attachment(kind: kind).isImage, isFalse);
      }
    });
  });
}
