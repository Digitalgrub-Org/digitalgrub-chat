import 'call_fullscreen_stub.dart'
    if (dart.library.js_interop) 'call_fullscreen_web.dart'
    as impl;

/// Takes the browser itself fullscreen while a shared screen is expanded.
///
/// Expanding inside the app already fills the app's own window, which is the
/// whole fix on a phone. On the web that still leaves the browser's chrome,
/// the tab strip and the OS bar eating the top third of a laptop screen --
/// and a shared document is exactly the thing you want the pixels for. So the
/// web build asks for real fullscreen as well.
///
/// Every call is best-effort. Browsers refuse the request outside a user
/// gesture, and some refuse it entirely; a refusal must leave the in-app
/// expansion working rather than throwing into the call UI.
abstract interface class CallFullscreen {
  /// Whether the browser will even consider it. False everywhere but the web.
  bool get isSupported;

  /// Asks the browser to go fullscreen. Must be called from a tap.
  void enter();

  /// Returns from fullscreen, if this page is in it.
  void exit();
}

CallFullscreen createCallFullscreen() => impl.createCallFullscreen();
