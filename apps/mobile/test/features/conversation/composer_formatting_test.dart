import 'package:dg_chat/features/conversation/presentation/composer_formatting.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingController _controller(String text, int start, int end) {
  return TextEditingController.fromValue(
    TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: start, extentOffset: end),
    ),
  );
}

void main() {
  group('applyMessageStyle', () {
    test('wraps the selection', () {
      final controller = _controller('hello world', 6, 11);
      addTearDown(controller.dispose);

      applyMessageStyle(controller, MessageStyle.bold);

      expect(controller.text, 'hello **world**');
    });

    test('leaves the words selected so styles can be stacked', () {
      final controller = _controller('hello world', 6, 11);
      addTearDown(controller.dispose);

      applyMessageStyle(controller, MessageStyle.bold);
      // The selection must still cover "world" and not the new markers.
      expect(
        controller.text.substring(
          controller.selection.start,
          controller.selection.end,
        ),
        'world',
      );

      applyMessageStyle(controller, MessageStyle.italic);
      expect(controller.text, 'hello **_world_**');
    });

    test('unwraps when the selection is already wrapped', () {
      // Tapping Bold twice has to return the original text rather than
      // producing ****world****.
      final controller = _controller('hello world', 6, 11);
      addTearDown(controller.dispose);

      applyMessageStyle(controller, MessageStyle.bold);
      applyMessageStyle(controller, MessageStyle.bold);

      expect(controller.text, 'hello world');
    });

    test('unwraps when the markers are inside the selection', () {
      final controller = _controller('hello **world**', 6, 15);
      addTearDown(controller.dispose);

      applyMessageStyle(controller, MessageStyle.bold);

      expect(controller.text, 'hello world');
    });

    test('does nothing without a selection', () {
      final controller = _controller('hello', 5, 5);
      addTearDown(controller.dispose);

      applyMessageStyle(controller, MessageStyle.bold);

      expect(controller.text, 'hello');
    });

    test('applies each style with its own marker', () {
      for (final (style, expected) in [
        (MessageStyle.bold, '**a**'),
        (MessageStyle.italic, '_a_'),
        (MessageStyle.strikethrough, '~~a~~'),
        (MessageStyle.code, '`a`'),
      ]) {
        final controller = _controller('a', 0, 1);
        addTearDown(controller.dispose);
        applyMessageStyle(controller, style);
        expect(controller.text, expected);
      }
    });
  });

  group('composerShortcuts', () {
    // SingleActivator has no value equality, so the bindings cannot be probed
    // by map lookup -- CallbackShortcuts matches by asking each activator
    // whether it accepts the chord. These go through the real path instead.
    Future<String> press(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      required LogicalKeyboardKey modifier,
      bool shift = false,
    }) async {
      final controller = _controller('hello world', 6, 11);
      addTearDown(controller.dispose);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallbackShortcuts(
              bindings: composerShortcuts(controller),
              child: TextField(controller: controller, focusNode: focusNode),
            ),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(modifier);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      return controller.text;
    }

    testWidgets('a focused text field still lets the chord through', (
      tester,
    ) async {
      // The binding sits above the TextField, so this is really asking whether
      // the field swallows the chord before it can bubble up.
      expect(
        await press(
          tester,
          LogicalKeyboardKey.keyB,
          modifier: LogicalKeyboardKey.controlLeft,
        ),
        'hello **world**',
      );
    });

    testWidgets('Command works as well as Control', (tester) async {
      // Bound for both rather than switched on platform, so a Mac browser and
      // a Windows browser behave the same for anyone moving between them.
      expect(
        await press(
          tester,
          LogicalKeyboardKey.keyB,
          modifier: LogicalKeyboardKey.metaLeft,
        ),
        'hello **world**',
      );
    });

    testWidgets('each chord applies its own style', (tester) async {
      expect(
        await press(
          tester,
          LogicalKeyboardKey.keyI,
          modifier: LogicalKeyboardKey.controlLeft,
        ),
        'hello _world_',
      );
      expect(
        await press(
          tester,
          LogicalKeyboardKey.keyE,
          modifier: LogicalKeyboardKey.controlLeft,
        ),
        'hello `world`',
      );
      expect(
        await press(
          tester,
          LogicalKeyboardKey.keyX,
          modifier: LogicalKeyboardKey.controlLeft,
          shift: true,
        ),
        'hello ~~world~~',
      );
    });
  });

  group('insertEmoji', () {
    test('inserts at the caret', () {
      final controller = _controller('ab', 1, 1);
      addTearDown(controller.dispose);

      insertEmoji(controller, '🎉');

      expect(controller.text, 'a🎉b');
      // The caret sits after the emoji, so typing continues where expected.
      expect(controller.selection.baseOffset, 1 + '🎉'.length);
    });

    test('replaces a selection', () {
      final controller = _controller('hello world', 6, 11);
      addTearDown(controller.dispose);

      insertEmoji(controller, '👍');

      expect(controller.text, 'hello 👍');
    });

    test('appends when the field was never focused', () {
      final controller = TextEditingController(text: 'hi');
      addTearDown(controller.dispose);

      insertEmoji(controller, '😀');

      expect(controller.text, 'hi😀');
    });
  });
}
