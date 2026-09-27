import 'dart:js_interop';

import 'package:dg_chat/features/calls/presentation/call_fullscreen.dart';
import 'package:web/web.dart' as web;

class _BrowserFullscreen implements CallFullscreen {
  const _BrowserFullscreen();

  @override
  bool get isSupported {
    try {
      // False in an iframe without allowfullscreen, which is a real way for
      // this app to be embedded.
      return web.document.fullscreenEnabled;
    } catch (_) {
      return false;
    }
  }

  @override
  void enter() {
    try {
      final element = web.document.documentElement;
      if (element == null) return;
      if (web.document.fullscreenElement != null) return;
      // The promise is deliberately dropped: a rejection here means the
      // browser said no, which is not an error worth surfacing mid-call.
      element.requestFullscreen().toDart.catchError((Object _) => null);
    } catch (_) {
      // Not supported, or blocked by a permissions policy.
    }
  }

  @override
  void exit() {
    try {
      if (web.document.fullscreenElement == null) return;
      web.document.exitFullscreen().toDart.catchError((Object _) => null);
    } catch (_) {
      // Already out of fullscreen, or the browser refused.
    }
  }
}

CallFullscreen createCallFullscreen() => const _BrowserFullscreen();
