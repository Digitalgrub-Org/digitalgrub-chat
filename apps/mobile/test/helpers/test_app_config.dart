import 'package:dg_chat/core/config/app_config.dart';

/// A configuration with every optional service switched on.
///
/// For tests of screens that change with the build's configuration -- the
/// call buttons, guest links, the admin actions -- so a test does not pass or
/// fail depending on which defaults a particular build compiled in.
final testAppConfig = AppConfig(
  homeserver: Uri.parse('https://chat.test'),
  pushGateway: Uri.parse('https://chat.test/_matrix/push/v1/notify'),
  livekitJwtUrl: Uri.parse('https://chat.test/livekit/jwt'),
  meetGuestUrl: Uri.parse('https://chat.test/livekit/guest'),
  adminUrl: Uri.parse('https://chat.test/dg/admin'),
);
