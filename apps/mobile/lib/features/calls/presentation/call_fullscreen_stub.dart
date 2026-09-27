import 'package:dg_chat/features/calls/presentation/call_fullscreen.dart';

/// Phones and desktop have no browser chrome to escape: expanding the tile
/// inside the app is already the whole screen.
class _NoFullscreen implements CallFullscreen {
  const _NoFullscreen();

  @override
  bool get isSupported => false;

  @override
  void enter() {}

  @override
  void exit() {}
}

CallFullscreen createCallFullscreen() => const _NoFullscreen();
