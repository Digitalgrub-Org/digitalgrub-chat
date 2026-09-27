import 'tab_badge_stub.dart'
    if (dart.library.js_interop) 'tab_badge_web.dart'
    as impl;

/// Marks the browser tab when there is something unread.
///
/// The title carries the count and is what a wide tab shows; the favicon
/// carries a dot and is what a narrow or pinned tab shows, where the title
/// has been squeezed down to nothing. Slack does both for that reason, and
/// either one alone leaves a common case unmarked.
///
/// The title is *not* set here — Flutter owns `document.title` through
/// `onGenerateTitle` and rewrites it on every rebuild, so anything written
/// behind its back survives until the next frame and no longer. Only the
/// favicon, which Flutter never touches, is ours to change.
abstract interface class TabBadge {
  /// Draws a dot on the favicon, or takes it off again.
  ///
  /// Safe to call on every sync: redundant calls do no work.
  void show({required bool marked});
}

/// The browser implementation on web, and one that does nothing everywhere
/// else — a phone has no tab to badge.
TabBadge createTabBadge() => impl.createTabBadge();
