import 'dart:js_interop';

import 'package:dg_chat/features/notifications/data/tab_badge.dart';
import 'package:web/web.dart' as web;

/// Draws the unread dot onto the favicon.
///
/// Everything here is guarded. A browser that refuses canvas, a favicon that
/// fails to load, a tainted canvas — all of them must leave the app working
/// and simply not badge. An unmarked tab is a nuisance; an exception thrown
/// out of the sync loop is a broken client.
class _FaviconBadge implements TabBadge {
  _FaviconBadge() {
    _link = _ownLink();
    _plain = _link?.href;
    _load();
  }

  static const _dotColour = '#E5484D';

  /// Bigger than any tab renders so the dot stays round after the browser
  /// scales it down. Drawing at 16px gives a visibly square blob.
  static const _size = 64.0;

  web.HTMLLinkElement? _link;

  /// The untouched favicon, so taking the dot off restores the original
  /// rather than a re-encoded copy of it.
  String? _plain;
  String? _dotted;

  /// What the caller last asked for. The base image loads asynchronously, so
  /// a request arriving before it is ready is remembered and applied on
  /// arrival instead of being dropped.
  bool _wanted = false;
  bool _applied = false;

  @override
  void show({required bool marked}) {
    if (marked == _wanted && _applied) return;
    _wanted = marked;
    _apply();
  }

  void _apply() {
    final link = _link;
    if (link == null) return;
    final href = _wanted ? _dotted : _plain;
    // Not ready yet, or nothing to go back to. _load applies again when the
    // image arrives.
    if (href == null) return;
    link.href = href;
    _applied = true;
  }

  /// The `<link rel="icon">` this class owns, creating one if the page has
  /// none. Reusing the existing element matters: appending a second icon link
  /// leaves the browser free to keep showing the first.
  web.HTMLLinkElement? _ownLink() {
    try {
      final existing =
          web.document.querySelector('link[rel~="icon"]')
              as web.HTMLLinkElement?;
      if (existing != null) return existing;
      final created = web.document.createElement('link') as web.HTMLLinkElement;
      created.rel = 'icon';
      created.type = 'image/png';
      created.href = 'favicon.png';
      web.document.head?.appendChild(created);
      return created;
    } catch (_) {
      return null;
    }
  }

  void _load() {
    final source = _plain;
    if (source == null || source.isEmpty) return;
    try {
      final image = web.document.createElement('img') as web.HTMLImageElement;
      image.addEventListener(
        'load',
        ((web.Event _) {
          _dotted = _draw(image);
          _apply();
        }).toJS,
      );
      // A favicon that will not load is not worth retrying: the title still
      // carries the count, which is the part that can be read anyway.
      image.src = source;
    } catch (_) {
      // Leave _dotted null; show() then does nothing.
    }
  }

  /// The favicon with a dot punched into its lower-right corner.
  ///
  /// The gap around the dot is transparent rather than white, so it separates
  /// the dot from the icon on a light tab strip and a dark one alike — the
  /// browser's own background shows through either way.
  String? _draw(web.HTMLImageElement image) {
    try {
      final canvas =
          web.document.createElement('canvas') as web.HTMLCanvasElement;
      canvas.width = _size.toInt();
      canvas.height = _size.toInt();
      final context = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
      if (context == null) return null;

      context.drawImage(image, 0, 0, _size, _size);

      context.globalCompositeOperation = 'destination-out';
      context.beginPath();
      context.arc(_size - 18, _size - 18, 17, 0, 3.1415926535 * 2);
      context.fill();

      context.globalCompositeOperation = 'source-over';
      context.fillStyle = _dotColour.toJS;
      context.beginPath();
      context.arc(_size - 18, _size - 18, 13, 0, 3.1415926535 * 2);
      context.fill();

      return canvas.toDataURL('image/png');
    } catch (_) {
      // A cross-origin favicon taints the canvas and toDataURL throws.
      return null;
    }
  }
}

TabBadge createTabBadge() => _FaviconBadge();
