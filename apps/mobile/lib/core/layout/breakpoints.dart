import 'package:flutter/widgets.dart';

/// Window size classes, named after the Material 3 window size classes.
///
/// Every screen in this app was written phone-first, so [compact] is the
/// layout they all already assume. The wider classes exist because a browser
/// window is not a phone: without them the chat list stretches a row across
/// the whole window and opening a conversation hides the list entirely.
enum AppWindowSize {
  compact,
  medium,
  expanded;

  /// Whether there is room to show a conversation beside the list rather than
  /// on top of it.
  bool get hasSidePanes => this != AppWindowSize.compact;

  /// Width of the list pane. The conversation takes whatever is left, so the
  /// list stays a readable column instead of growing with the window.
  double get sidebarWidth => switch (this) {
    AppWindowSize.compact => double.infinity,
    AppWindowSize.medium => 288,
    AppWindowSize.expanded => 320,
  };
}

abstract final class AppBreakpoints {
  /// Below this, two panes would each be too cramped to be worth it, so the
  /// phone layout is still the better one.
  static const medium = 900.0;

  /// Above this there is room for a wider list pane alongside the
  /// conversation.
  static const expanded = 1400.0;

  static AppWindowSize of(double width) {
    if (width < medium) return AppWindowSize.compact;
    if (width < expanded) return AppWindowSize.medium;
    return AppWindowSize.expanded;
  }
}

extension WindowSizeExtension on BuildContext {
  /// Size class of the window, for widgets that are not already inside a
  /// [LayoutBuilder].
  AppWindowSize get windowSize =>
      AppBreakpoints.of(MediaQuery.sizeOf(this).width);
}
