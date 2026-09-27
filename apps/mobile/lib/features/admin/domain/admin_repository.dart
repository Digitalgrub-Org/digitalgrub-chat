/// Why an admin action was refused, in terms the screen can explain.
enum AdminFailureCode {
  /// The signed-in account is not a server admin, or the session expired.
  notAdmin,

  /// Somebody already has that username.
  usernameTaken,

  /// The target is itself an admin account, which is reset on the server
  /// and never from here.
  adminAccount,

  /// No account with that username.
  notFound,

  /// The service is switched off in this build.
  unavailable,
  serverUnavailable,
  unknown,
}

class AdminFailure implements Exception {
  const AdminFailure(this.code);

  final AdminFailureCode code;
}

/// The two admin operations the app offers, and only those.
///
/// Synapse's own admin API is deliberately unreachable from the internet --
/// it can mint a login token for any account. These go through a service
/// that exposes exactly this much of it, authorised by the caller's own
/// session; see deploy/dg-admin.
abstract interface class AdminRepository {
  /// Creates an ordinary account. Returns its Matrix id.
  Future<String> createUser({
    required String username,
    required String password,
    String? displayName,
  });

  /// Replaces [username]'s password and signs out every session it had.
  Future<void> resetPassword({
    required String username,
    required String password,
  });

  /// Whether the signed-in account is a server admin, by the service's own
  /// check. False for every failure: the answer only decides whether a
  /// screen is offered, and the operations are refused server-side anyway.
  Future<bool> isSelfAdmin();
}
