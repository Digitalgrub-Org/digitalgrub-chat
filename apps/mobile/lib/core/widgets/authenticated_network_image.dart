import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// An image from the homeserver, fetched with the access token it demands.
///
/// Matrix media is authenticated now: every download carries an
/// `Authorization` header or comes back 401. On phones the cache manager
/// sends that header, which is why images render there. A browser will not —
/// an `<img>` cannot be given headers, and the request goes out bare — so on
/// web the picture has to be fetched as bytes and handed to the decoder,
/// exactly as voice messages already are.
class AuthenticatedNetworkImage extends StatelessWidget {
  const AuthenticatedNetworkImage({
    required this.url,
    required this.headers,
    required this.placeholder,
    required this.error,
    this.fit,
    super.key,
  });

  final Uri url;
  final Map<String, String> headers;
  final WidgetBuilder placeholder;
  final WidgetBuilder error;
  final BoxFit? fit;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      // Keep the cache manager on phones: it caches to disk, so a scrolled-past
      // photo is not re-downloaded on every app start.
      return CachedNetworkImage(
        imageUrl: url.toString(),
        httpHeaders: headers,
        fit: fit,
        placeholder: (context, _) => placeholder(context),
        errorWidget: (context, _, _) => error(context),
      );
    }
    return Image(
      image: AuthenticatedImage(url, headers: headers),
      fit: fit,
      frameBuilder: (context, child, frame, wasSync) =>
          frame == null && !wasSync ? placeholder(context) : child,
      errorBuilder: (context, _, _) => error(context),
    );
  }
}

/// Fetches the bytes with headers, then decodes them.
///
/// Being an [ImageProvider] rather than a FutureBuilder means Flutter's own
/// image cache holds the decoded result, so a picture opened full-screen does
/// not download a second time.
@immutable
class AuthenticatedImage extends ImageProvider<AuthenticatedImage> {
  const AuthenticatedImage(this.url, {this.headers = const {}, this.scale = 1});

  final Uri url;
  final Map<String, String> headers;
  final double scale;

  @override
  Future<AuthenticatedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<AuthenticatedImage>(this);

  @override
  ImageStreamCompleter loadImage(
    AuthenticatedImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _fetch(key, decode),
      scale: key.scale,
      debugLabel: key.url.toString(),
    );
  }

  Future<ui.Codec> _fetch(
    AuthenticatedImage key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final response = await http.get(key.url, headers: key.headers);
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        // Thrown rather than returning a blank frame: the caller's
        // errorBuilder is what tells the user the picture is missing.
        throw NetworkImageLoadException(
          statusCode: response.statusCode,
          uri: key.url,
        );
      }
      // Awaited inside the try rather than returned from it: a returned future
      // completes after the try has exited, so a decode failure on corrupt
      // bytes would sail past the catch below and never evict.
      return await decode(
        await ui.ImmutableBuffer.fromUint8List(response.bodyBytes),
      );
    } catch (error) {
      // Flutter's image cache keeps failed loads, so one bad moment -- a
      // fetch racing the send, a flaky connection -- froze the bubble on
      // "Image unavailable" until a full reload, even though the very next
      // request would have succeeded. Evicting turns the next rebuild into a
      // retry, and the timeline rebuilds on every sync.
      //
      // Which is exactly why a picture the server says is gone must NOT be
      // evicted: attachments are purged after 30 days, and retrying one on
      // every sync is a doomed request per rebuild, for as long as the message
      // stays on screen.
      if (!_isGoneForGood(error)) {
        scheduleMicrotask(() {
          PaintingBinding.instance.imageCache.evict(key);
        });
      }
      rethrow;
    }
  }

  /// Whether the server has said the picture will never load, as opposed to
  /// not having loaded this time.
  static bool _isGoneForGood(Object error) =>
      error is NetworkImageLoadException &&
      (error.statusCode == 404 || error.statusCode == 410);

  @override
  bool operator ==(Object other) =>
      other is AuthenticatedImage && other.url == url && other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() => 'AuthenticatedImage("$url", scale: $scale)';
}
