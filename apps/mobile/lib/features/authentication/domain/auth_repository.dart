/// Shortest password the homeserver will accept.
///
/// Kept deliberately low for an internal team deployment. It must stay in step
/// with `password_config.policy.minimum_length` in
/// `deploy/synapse/render_config.py`: a client that accepts less than the
/// server does fails registration only after the form has been submitted.
const int minimumPasswordLength = 6;

class AuthSession {
  const AuthSession({
    required this.userId,
    this.profileSetupIncomplete = false,
  });

  final String userId;
  final bool profileSetupIncomplete;
}

class RegistrationRequest {
  const RegistrationRequest({
    required this.username,
    required this.password,
    required this.displayName,
    this.mobileNumber,
    this.inviteCode,
  });

  final String username;
  final String password;
  final String displayName;
  final String? mobileNumber;

  /// The code that buys entry to a closed server. Null on a server that
  /// still takes all comers.
  final String? inviteCode;
}

enum AuthFailureCode {
  invalidCredentials,
  registrationDisabled,

  /// The homeserver has no email support configured, so nothing can be sent.
  /// Distinct from a failure: there is nothing the person can retry.
  emailUnsupported,

  /// No account carries that address. Deliberately not shown to the person
  /// who typed it -- see the note on [AuthRepository.requestPasswordReset].
  emailUnknown,

  /// The emailed link has not been followed yet, so the server will not
  /// accept the new password.
  emailNotVerified,

  /// Another account already claims that address.
  emailInUse,

  /// The invite code was wrong, spent, or expired.
  invalidInviteCode,
  usernameTaken,
  invalidUsername,
  rateLimited,
  serverUnavailable,
  sessionExpired,
  unknown,
}

/// How thoroughly the homeserver should discard the account's content when it
/// is deleted. [erase] additionally asks the server to redact the user's
/// messages where it can.
enum AccountDeletionScope { deactivate, erase }

class AuthFailure implements Exception {
  const AuthFailure(this.code, {this.retryAfter});

  final AuthFailureCode code;
  final Duration? retryAfter;
}

/// A reset or verification the server has emailed a link for.
///
/// Matrix splits this across two calls with an email in between: the server
/// mints a session, the person proves they read the mail by following its
/// link, and only then is the new password accepted. Both identifiers have to
/// survive that gap, which is why they are handed back rather than kept
/// inside the repository -- the app may be closed and reopened in between.
class EmailVerification {
  const EmailVerification({
    required this.sid,
    required this.clientSecret,
    required this.email,
    this.sendAttempt = 1,
  });

  final String sid;
  final String clientSecret;
  final String email;

  /// Bumped on each resend. The server only sends another mail when this
  /// rises, which is what stops a retry loop from mailing somebody ten times.
  final int sendAttempt;

  EmailVerification withNextAttempt(String sid) => EmailVerification(
    sid: sid,
    clientSecret: clientSecret,
    email: email,
    sendAttempt: sendAttempt + 1,
  );
}

abstract interface class AuthRepository {
  Future<AuthSession?> restoreSession();

  Stream<AuthSession?> get sessionChanges;

  Future<AuthSession> login({
    required String username,
    required String password,
  });

  Future<AuthSession> register(RegistrationRequest request);

  Future<void> logout();

  /// Permanently deletes the signed-in account on the homeserver and removes
  /// every local trace of it. The homeserver re-authenticates the request, so
  /// the current [password] is required.
  ///
  /// Required by App Store review guideline 5.1.1(v): an account-based app must
  /// let a user delete the account itself, not merely sign out.
  Future<void> deleteAccount({
    required String password,
    AccountDeletionScope scope = AccountDeletionScope.erase,
  });

  /// Asks the homeserver to email a reset link to [email].
  ///
  /// Throws [AuthFailureCode.emailUnknown] when no account carries the
  /// address. The caller is expected NOT to show that to the person who typed
  /// it: "no account has this address" turns the form into a way of asking
  /// the server who is registered. The screen says the same thing either way
  /// and only the logs know the difference.
  Future<EmailVerification> requestPasswordReset(String email);

  /// Sends the reset mail again, for a link that never arrived.
  Future<EmailVerification> resendPasswordReset(EmailVerification pending);

  /// Sets [newPassword], once the emailed link has been followed.
  ///
  /// Throws [AuthFailureCode.emailNotVerified] when it has not been, which is
  /// the ordinary case for somebody who pressed the button too early.
  Future<void> completePasswordReset({
    required EmailVerification pending,
    required String newPassword,
  });

  /// Verified email addresses on the signed-in account.
  Future<List<String>> emailAddresses();

  /// Starts attaching [email] to the signed-in account.
  Future<EmailVerification> addEmailAddress(String email);

  /// Finishes attaching, once the emailed link has been followed. The
  /// homeserver re-authenticates this, so the current [password] is required.
  Future<void> confirmEmailAddress({
    required EmailVerification pending,
    required String password,
  });

  /// Detaches [email] from the signed-in account.
  Future<void> removeEmailAddress(String email);
}
