import 'package:dg_chat/features/notifications/domain/push_repository.dart';
import 'package:matrix/matrix.dart';

/// Registers the device with the homeserver's pusher list so a Matrix push
/// gateway such as Sygnal can deliver notifications. No FCM or APNs secret is
/// held by the application; the gateway owns those credentials.
class MatrixPushRepository implements PushRepository {
  MatrixPushRepository(this._client);

  /// Sygnal expects the event id and room id only, leaving the client to read
  /// the message from its own cache. That keeps message content off the push
  /// path, which matters because the gateway is a separate service.
  static const _format = 'event_id_only';

  final Client _client;

  @override
  Future<void> register(PushRegistration registration) async {
    final token = registration.token.trim();
    if (token.isEmpty) {
      throw const PushFailure(PushFailureCode.invalidToken);
    }
    if (!registration.gatewayUrl.isScheme('https') &&
        !registration.gatewayUrl.isScheme('http')) {
      throw const PushFailure(PushFailureCode.notConfigured);
    }

    await _guard(
      () => _client.postPusher(
        Pusher(
          pushkey: token,
          appId: registration.appId,
          appDisplayName: registration.appDisplayName,
          deviceDisplayName: registration.deviceDisplayName,
          lang: registration.language,
          kind: 'http',
          data: PusherData(
            url: registration.gatewayUrl,
            format: _format,
            // The gateway reads default_payload straight off the pusher, so
            // it is carried here rather than configured server-side.
            additionalProperties: {
              if (registration.defaultPayload != null)
                'default_payload': registration.defaultPayload,
              ...registration.additionalData,
            },
          ),
        ),
        // Replaces any previous pusher for this device instead of stacking
        // duplicates, which is what produces double notifications.
        append: false,
      ),
    );
  }

  /// Rule id under our own namespace: ids beginning with a dot are reserved
  /// for the server's own defaults.
  static const _callRuleId = 'in.digitalgrub.call_ring';

  @override
  Future<void> ensureCallPushRule() async {
    await _guard(
      () => _client.setPushRule(
        PushRuleKind.override,
        _callRuleId,
        // A ring is not a message: it wants a sound even when the room is
        // muted for ordinary chatter, which is what an override rule buys.
        [
          'notify',
          {'set_tweak': 'sound', 'value': 'ring'},
          // Tweaks reach the push gateway whatever payload format the pusher
          // uses, so this marks the push as a call without putting any event
          // content on the push path. The gateway turns it into a VoIP push
          // on iOS and a call flag on Android; without it neither platform
          // can tell a ring from an ordinary message.
          {'set_tweak': callTweak, 'value': true},
        ],
        conditions: [
          PushCondition(
            kind: 'event_match',
            key: 'type',
            pattern: rtcNotificationEventType,
          ),
        ],
      ),
    );
  }

  @override
  Future<void> unregister(String token, {required String appId}) async {
    final value = token.trim();
    if (value.isEmpty) return;
    await _guard(
      () => _client.deletePusher(PusherId(pushkey: value, appId: appId)),
    );
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on MatrixException catch (error) {
      throw switch (error.error) {
        MatrixError.M_LIMIT_EXCEEDED => const PushFailure(
          PushFailureCode.rateLimited,
        ),
        MatrixError.M_UNKNOWN_TOKEN => const PushFailure(
          PushFailureCode.sessionExpired,
        ),
        _ => const PushFailure(PushFailureCode.serverUnavailable),
      };
    } on PushFailure {
      rethrow;
    } catch (_) {
      throw const PushFailure(PushFailureCode.serverUnavailable);
    }
  }
}
