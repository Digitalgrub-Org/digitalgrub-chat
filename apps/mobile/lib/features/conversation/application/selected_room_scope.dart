import 'package:flutter/widgets.dart';

/// The room the current location says is open, made readable below the shell.
///
/// The URL is the source of truth for which conversation is open — that is
/// what lets a browser refresh restore it, back/forward walk through rooms,
/// and a pasted link land in the right place. But the chat list lives inside
/// the branch navigator, whose own route state does not carry the sub-route's
/// parameters, so the shell passes the value down as plain inherited state
/// instead of anyone keeping a second copy that could drift.
class SelectedRoomScope extends InheritedWidget {
  const SelectedRoomScope({
    required this.roomId,
    required super.child,
    super.key,
  });

  /// The room in the location bar, or null when none is open.
  final String? roomId;

  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SelectedRoomScope>()?.roomId;

  @override
  bool updateShouldNotify(SelectedRoomScope oldWidget) =>
      oldWidget.roomId != roomId;
}
