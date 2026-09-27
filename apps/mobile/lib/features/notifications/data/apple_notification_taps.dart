import 'package:flutter/services.dart';

/// Receives notification taps that the messaging plugins do not deliver.
///
/// Notifications sent straight to APNs are drawn by the system and never pass
/// through the app, so neither `firebase_messaging` nor
/// `flutter_local_notifications` reports a tap on one. The app delegate takes
/// the notification-centre delegate and forwards the tapped room here instead.
class AppleNotificationTaps {
  AppleNotificationTaps({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'digitalgrub.chat/notification_taps';

  final MethodChannel _channel;

  /// Routes taps that arrive while the app is running.
  ///
  /// [onRoomSelected] returns true once the room has been recorded, which is
  /// what tells the native side to stop holding the tap. Returning false for
  /// an unusable payload leaves it pending rather than dropping it.
  void listen(bool Function(String roomId) onRoomSelected) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'openRoom') return null;
      final roomId = call.arguments;
      if (roomId is! String || roomId.isEmpty) return false;
      return onRoomSelected(roomId);
    });
  }

  /// Claims a tap that launched the app, which lands before Dart is listening.
  ///
  /// Returns null when the app was opened some other way. Safe to call on
  /// every platform: anywhere the channel is not implemented this is simply
  /// nothing rather than an error.
  Future<String?> takePending() async {
    try {
      final roomId = await _channel.invokeMethod<String>('takePendingRoom');
      return (roomId != null && roomId.isNotEmpty) ? roomId : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  void dispose() => _channel.setMethodCallHandler(null);
}
