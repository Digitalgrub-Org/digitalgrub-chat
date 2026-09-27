import 'dart:typed_data';

import 'package:dg_chat/features/conversation/presentation/attachment_picker.dart';
import 'package:flutter_test/flutter_test.dart';

/// A valid 1x1 transparent PNG. Small enough to inline, real enough for the
/// codec to decode, which is what the dimension probe relies on.
final _onePixelPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, // IDAT
  0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, // IEND
  0x42, 0x60, 0x82,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('draftFromBytes', () {
    test('measures an image so receivers can reserve its space', () async {
      final draft = await draftFromBytes(_onePixelPng, 'pixel.png');

      expect(draft.width, 1);
      expect(draft.height, 1);
      expect(draft.fileName, 'pixel.png');
      expect(draft.sizeBytes, _onePixelPng.length);
    });

    test('carries no dimensions for bytes that are not an image', () async {
      // The mime type is deliberately a lie: pickers routinely report wrong
      // or missing types, so the codec is the authority, not the label.
      final draft = await draftFromBytes(
        Uint8List.fromList('just a text file'.codeUnits),
        'notes.txt',
        mimeType: 'image/png',
      );

      expect(draft.width, isNull);
      expect(draft.height, isNull);
    });

    test('keeps the picker-reported mime type on the draft', () async {
      final draft = await draftFromBytes(
        _onePixelPng,
        'pixel.png',
        mimeType: 'image/png',
      );
      expect(draft.mimeType, 'image/png');
    });
  });
}
