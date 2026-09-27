/// Whether somebody is around, as far as the homeserver can tell.
///
/// [online] is the server's word for "their app is syncing right now".
/// [lastActive] is when it last was, and is null for somebody the server has
/// never seen -- which reads as nothing, not as "last seen never".
class UserPresence {
  const UserPresence({required this.online, this.lastActive});

  final bool online;
  final DateTime? lastActive;
}
