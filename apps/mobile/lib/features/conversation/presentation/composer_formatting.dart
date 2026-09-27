import 'package:dg_chat/app/localization/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The inline styles the composer can apply, and the markdown that carries
/// them. The Matrix SDK converts these to a `formatted_body` on send, so what
/// is typed here is what other clients render.
enum MessageStyle {
  bold('**'),
  // Underscores rather than a single asterisk, which would be a prefix of the
  // bold marker: italicising an already-bold selection would then see the `**`
  // around it as its own markers and strip the bold instead of nesting inside
  // it. Markdown treats `_x_` as emphasis but leaves underscores inside a word
  // alone, so file_names_like_this are still safe to type.
  italic('_'),
  strikethrough('~~'),
  code('`');

  const MessageStyle(this.marker);

  /// Wrapped around the selection on both sides.
  final String marker;
}

/// Applies [style] to the controller's current selection.
///
/// Toggles: wrapping text that is already wrapped removes the markers instead
/// of nesting a second pair, so tapping Bold twice returns the original text
/// rather than producing `****text****`.
void applyMessageStyle(TextEditingController controller, MessageStyle style) {
  final value = controller.value;
  final selection = value.selection;
  if (!selection.isValid || selection.isCollapsed) return;

  final text = value.text;
  final selected = text.substring(selection.start, selection.end);
  final marker = style.marker;
  final length = marker.length;

  // Markers already inside the selection, as happens when the user selects the
  // formatted text along with its markers.
  final wrappedInside =
      selected.length >= length * 2 &&
      selected.startsWith(marker) &&
      selected.endsWith(marker);
  // Markers just outside it, as happens when the user re-selects only the
  // words and taps the same button again.
  final wrappedOutside =
      selection.start >= length &&
      selection.end + length <= text.length &&
      text.substring(selection.start - length, selection.start) == marker &&
      text.substring(selection.end, selection.end + length) == marker;

  final String updated;
  final TextSelection updatedSelection;
  if (wrappedInside) {
    final stripped = selected.substring(length, selected.length - length);
    updated = text.replaceRange(selection.start, selection.end, stripped);
    updatedSelection = TextSelection(
      baseOffset: selection.start,
      extentOffset: selection.start + stripped.length,
    );
  } else if (wrappedOutside) {
    updated = text.replaceRange(
      selection.start - length,
      selection.end + length,
      selected,
    );
    updatedSelection = TextSelection(
      baseOffset: selection.start - length,
      extentOffset: selection.start - length + selected.length,
    );
  } else {
    updated = text.replaceRange(
      selection.start,
      selection.end,
      '$marker$selected$marker',
    );
    // Keep the words selected, not the markers, so styles can be stacked.
    updatedSelection = TextSelection(
      baseOffset: selection.start + length,
      extentOffset: selection.end + length,
    );
  }

  controller.value = value.copyWith(
    text: updated,
    selection: updatedSelection,
    composing: TextRange.empty,
  );
}

/// Adds formatting entries to the composer's text-selection menu.
///
/// This rides on the platform's own selection toolbar rather than adding a
/// permanent formatting bar, so the composer stays a single line until the
/// user actually selects something — which is also where they are looking when
/// they want to format it.
Widget buildComposerContextMenu(
  BuildContext context,
  EditableTextState editableState,
  TextEditingController controller,
) {
  final items = [...editableState.contextMenuButtonItems];
  final selection = controller.selection;
  if (selection.isValid && !selection.isCollapsed) {
    items.addAll([
      ContextMenuButtonItem(
        label: context.l10n.formatBold,
        onPressed: () {
          ContextMenuController.removeAny();
          applyMessageStyle(controller, MessageStyle.bold);
        },
      ),
      ContextMenuButtonItem(
        label: context.l10n.formatItalic,
        onPressed: () {
          ContextMenuController.removeAny();
          applyMessageStyle(controller, MessageStyle.italic);
        },
      ),
      ContextMenuButtonItem(
        label: context.l10n.formatStrikethrough,
        onPressed: () {
          ContextMenuController.removeAny();
          applyMessageStyle(controller, MessageStyle.strikethrough);
        },
      ),
      ContextMenuButtonItem(
        label: context.l10n.formatCode,
        onPressed: () {
          ContextMenuController.removeAny();
          applyMessageStyle(controller, MessageStyle.code);
        },
      ),
    ]);
  }
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableState.contextMenuAnchors,
    buttonItems: items,
  );
}

/// Keyboard shortcuts for the composer, for the platforms that have a
/// keyboard.
///
/// The selection toolbar is the discoverable route on a touch screen, but on
/// web and desktop nobody selects text and hunts for a menu — they press
/// Ctrl+B. These are the bindings Telegram, Discord and Slack all share, so
/// they are what someone will try first.
Map<ShortcutActivator, VoidCallback> composerShortcuts(
  TextEditingController controller,
) {
  void apply(MessageStyle style) => applyMessageStyle(controller, style);
  return {
    for (final meta in [true, false])
    // Control on Windows and Linux, Command on macOS. Binding both rather
    // than branching on platform keeps a Mac browser and a Windows browser
    // behaving the same way for anyone who moves between them.
    ...{
      SingleActivator(
        LogicalKeyboardKey.keyB,
        control: !meta,
        meta: meta,
      ): () =>
          apply(MessageStyle.bold),
      SingleActivator(
        LogicalKeyboardKey.keyI,
        control: !meta,
        meta: meta,
      ): () =>
          apply(MessageStyle.italic),
      SingleActivator(
        LogicalKeyboardKey.keyX,
        control: !meta,
        meta: meta,
        shift: true,
      ): () =>
          apply(MessageStyle.strikethrough),
      SingleActivator(
        LogicalKeyboardKey.keyE,
        control: !meta,
        meta: meta,
      ): () =>
          apply(MessageStyle.code),
    },
  };
}

/// Inserts [emoji] at the caret, replacing any selection.
void insertEmoji(TextEditingController controller, String emoji) {
  final value = controller.value;
  final selection = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: value.text.length);
  final updated = value.text.replaceRange(
    selection.start,
    selection.end,
    emoji,
  );
  controller.value = value.copyWith(
    text: updated,
    selection: TextSelection.collapsed(offset: selection.start + emoji.length),
    composing: TextRange.empty,
  );
}
