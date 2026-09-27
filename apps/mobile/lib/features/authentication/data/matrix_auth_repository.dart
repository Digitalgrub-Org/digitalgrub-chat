import 'dart:async';
import 'dart:math';

import 'package:dg_chat/core/config/app_config.dart';
import 'package:dg_chat/core/storage/hidden_event_store.dart';
import 'package:dg_chat/core/storage/outgoing_message_store.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:matrix/matrix.dart';

class MatrixAuthRepository implements AuthRepository {
  MatrixAuthRepository({
    required Client client,
    required AppConfig config,
    required OutgoingMessageStore outgoingMessageStore,
    required HiddenEventStore hiddenEventStore,
  }) : _client = client,
       _config = config,
       _outgoingMessageStore = outgoingMessageStore,
       _hiddenEventStore = hiddenEventStore;

  static const _deviceName = 'Digitalgrub Chat Mobile';

  /// Not in the SDK's AuthenticationTypes: the spec added it later.
  static const _registrationTokenStage = 'm.login.registration_token';
  static const _privateProfileType = 'com.digitalgrub.profile';

  final Client _client;
  final AppConfig _config;
  final OutgoingMessageStore _outgoingMessageStore;
  final HiddenEventStore _hiddenEventStore;

  @override
  Stream<AuthSession?> get sessionChanges => _client.onLoginStateChanged.stream
      .map((_) => _currentSession())
      .distinct((previous, next) => previous?.userId == next?.userId);

  @override
  Future<AuthSession?> restoreSession() async => _currentSession();

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    try {
      await _prepareHomeserver();
      await _client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username.trim()),
        password: password,
        initialDeviceDisplayName: _deviceName,
        refreshToken: true,
      );
      return _requireCurrentSession();
    } on MatrixException catch (error) {
      throw _mapMatrixError(error, isRegistration: false);
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(AuthFailureCode.serverUnavailable);
    }
  }

  @override
  Future<AuthSession> register(RegistrationRequest request) async {
    try {
      await _prepareHomeserver();
      final username = request.username.trim();
      final available = await _client.checkUsernameAvailability(username);
      if (available == false) {
        throw const AuthFailure(AuthFailureCode.usernameTaken);
      }

      await _registerWithInteractiveAuth(request, username);
      final userId = _client.userID;
      if (userId == null) {
        throw const AuthFailure(AuthFailureCode.unknown);
      }

      var profileSetupIncomplete = false;
      try {
        await _client.setProfileField(userId, 'displayname', {
          'displayname': request.displayName.trim(),
        });
        final mobileNumber = request.mobileNumber?.trim();
        if (mobileNumber != null && mobileNumber.isNotEmpty) {
          await _client.setAccountData(userId, _privateProfileType, {
            'mobile_number': mobileNumber,
            'mobile_number_verified': false,
          });
        }
      } catch (_) {
        profileSetupIncomplete = true;
      }

      return AuthSession(
        userId: userId,
        profileSetupIncomplete: profileSetupIncomplete,
      );
    } on MatrixException catch (error) {
      throw _mapMatrixError(error, isRegistration: true);
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(AuthFailureCode.serverUnavailable);
    }
  }

  @override
  Future<void> logout() async {
    final userId = _client.userID;
    try {
      await _client.logout();
    } catch (_) {
      try {
        if (_client.isLogged()) await _client.clear();
      } catch (_) {
        throw const AuthFailure(AuthFailureCode.serverUnavailable);
      }
    } finally {
      if (userId != null) {
        await _outgoingMessageStore.deleteForUser(userId);
        // Delete-for-me records are local only, so nothing else removes them
        // when the account signs out.
        await _hiddenEventStore.deleteForUser(userId);
      }
    }
  }

  Future<void> _prepareHomeserver() =>
      _client.checkHomeserver(_config.homeserver).then((_) {});

  @override
  Future<void> deleteAccount({
    required String password,
    AccountDeletionScope scope = AccountDeletionScope.erase,
  }) async {
    final userId = _client.userID;
    if (userId == null) {
      throw const AuthFailure(AuthFailureCode.sessionExpired);
    }
    if (password.isEmpty) {
      throw const AuthFailure(AuthFailureCode.invalidCredentials);
    }

    try {
      // Deactivation is user-interactive: the first call is expected to be
      // refused with a session id, which the password stage then answers.
      try {
        await _client.deactivateAccount(
          erase: scope == AccountDeletionScope.erase,
        );
      } on MatrixException catch (error) {
        if (!error.requireAdditionalAuthentication || error.session == null) {
          rethrow;
        }
        await _client.deactivateAccount(
          erase: scope == AccountDeletionScope.erase,
          auth: AuthenticationPassword(
            session: error.session,
            password: password,
            identifier: AuthenticationUserIdentifier(user: userId),
          ),
        );
      }
    } on MatrixException catch (error) {
      throw _mapMatrixError(error, isRegistration: false);
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(AuthFailureCode.serverUnavailable);
    }

    // The account is gone server-side; local state must not survive it, and a
    // failure to tidy up must not make a completed deletion look failed.
    try {
      await _client.logout();
    } catch (_) {
      try {
        await _client.clear();
      } catch (_) {
        // The session is already invalid server-side.
      }
    }
    await _outgoingMessageStore.deleteForUser(userId);
    await _hiddenEventStore.deleteForUser(userId);
  }

  @override
  Future<EmailVerification> requestPasswordReset(String email) async {
    final normalized = email.trim();
    if (normalized.isEmpty) {
      throw const AuthFailure(AuthFailureCode.emailUnknown);
    }
    final secret = _clientSecret();
    try {
      await _prepareHomeserver();
      final response = await _client.requestTokenToResetPasswordEmail(
        secret,
        normalized,
        1,
      );
      return EmailVerification(
        sid: response.sid,
        clientSecret: secret,
        email: normalized,
      );
    } on MatrixException catch (error) {
      throw _mapEmailError(error);
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(AuthFailureCode.serverUnavailable);
    }
  }

  @override
  Future<EmailVerification> resendPasswordReset(
    EmailVerification pending,
  ) async {
    try {
      await _prepareHomeserver();
      // Same client secret and a higher send_attempt: that pair is what tells
      // the server this is a resend of one request rather than a new one, so
      // the earlier sid keeps working if the first mail turns up late.
      final response = await _client.requestTokenToResetPasswordEmail(
        pending.clientSecret,
        pending.email,
        pending.sendAttempt + 1,
      );
      return pending.withNextAttempt(response.sid);
    } on MatrixException catch (error) {
      throw _mapEmailError(error);
    } catch (_) {
      throw const AuthFailure(AuthFailureCode.serverUnavailable);
    }
  }

  @override
  Future<void> completePasswordReset({
    required EmailVerification pending,
    required String newPassword,
  }) async {
    try {
      await _prepareHomeserver();
      await _client.changePassword(
        newPassword,
        auth: AuthenticationThreePidCreds(
          type: AuthenticationTypes.emailIdentity,
          threepidCreds: ThreepidCreds(
            sid: pending.sid,
            clientSecret: pending.clientSecret,
          ),
        ),
        // Whoever prompted this reset may be the reason it was needed. Ending
        // every other session is the point, not a side effect.
        logoutDevices: true,
      );
    } on MatrixException catch (error) {
      throw _mapEmailError(error);
    } catch (_) {
      throw const AuthFailure(AuthFailureCode.serverUnavailable);
    }
  }

  @override
  Future<List<String>> emailAddresses() async {
    try {
      final identifiers = await _client.getAccount3PIDs();
      return [
        for (final identifier in identifiers ?? const <ThirdPartyIdentifier>[])
          if (identifier.medium == ThirdPartyIdentifierMedium.email)
            identifier.address,
      ];
    } on MatrixException catch (error) {
      throw _mapMatrixError(error, isRegistration: false);
    } catch (_) {
      throw const AuthFailure(AuthFailureCode.serverUnavailable);
    }
  }

  @override
  Future<EmailVerification> addEmailAddress(String email) async {
    final normalized = email.trim();
    if (normalized.isEmpty) {
      throw const AuthFailure(AuthFailureCode.emailUnknown);
    }
    final secret = _clientSecret();
    try {
      final response = await _client.requestTokenTo3PIDEmail(
        secret,
        normalized,
        1,
      );
      return EmailVerification(
        sid: response.sid,
        clientSecret: secret,
        email: normalized,
      );
    } on MatrixException catch (error) {
      throw _mapEmailError(error);
    } catch (_) {
      throw const AuthFailure(AuthFailureCode.serverUnavailable);
    }
  }

  @override
  Future<void> confirmEmailAddress({
    required EmailVerification pending,
    required String password,
  }) async {
    final userId = _client.userID;
    if (userId == null) {
      throw const AuthFailure(AuthFailureCode.sessionExpired);
    }
    try {
      // User-interactive, like deactivation: the first call is expected to be
      // refused with a session id, which the password stage then answers.
      try {
        await _client.add3PID(pending.clientSecret, pending.sid);
      } on MatrixException catch (error) {
        if (!error.requireAdditionalAuthentication || error.session == null) {
          rethrow;
        }
        await _client.add3PID(
          pending.clientSecret,
          pending.sid,
          auth: AuthenticationPassword(
            session: error.session,
            password: password,
            identifier: AuthenticationUserIdentifier(user: userId),
          ),
        );
      }
    } on MatrixException catch (error) {
      throw _mapEmailError(error);
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(AuthFailureCode.serverUnavailable);
    }
  }

  @override
  Future<void> removeEmailAddress(String email) async {
    try {
      await _client.delete3pidFromAccount(
        email.trim(),
        ThirdPartyIdentifierMedium.email,
      );
    } on MatrixException catch (error) {
      throw _mapEmailError(error);
    } catch (_) {
      throw const AuthFailure(AuthFailureCode.serverUnavailable);
    }
  }

  /// A fresh secret for one verification, in the alphabet the spec allows
  /// (`[0-9a-zA-Z.=_-]`). It ties the request to the confirmation, so it must
  /// not be guessable by whoever else can read the mailbox.
  String _clientSecret() {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return String.fromCharCodes([
      for (var i = 0; i < 32; i++)
        alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    ]);
  }

  AuthFailure _mapEmailError(MatrixException error) {
    // A server with no email configured answers the request endpoints with
    // M_UNRECOGNIZED or a 400 rather than anything email-shaped, and there is
    // nothing the person can do about it -- so it must not read as "wrong
    // address".
    final code = error.errcode;
    if (code == 'M_THREEPID_DENIED' || code == 'M_UNRECOGNIZED') {
      return const AuthFailure(AuthFailureCode.emailUnsupported);
    }
    if (code == 'M_THREEPID_NOT_FOUND') {
      return const AuthFailure(AuthFailureCode.emailUnknown);
    }
    if (code == 'M_THREEPID_IN_USE') {
      return const AuthFailure(AuthFailureCode.emailInUse);
    }
    if (code == 'M_THREEPID_AUTH_FAILED') {
      return const AuthFailure(AuthFailureCode.emailNotVerified);
    }
    return _mapMatrixError(error, isRegistration: false);
  }

  /// Walks the server's user-interactive auth for registration.
  ///
  /// A closed server asks for an invite code and then a dummy stage; an open
  /// one asks for dummy alone, or nothing at all. Rather than hard-coding
  /// either shape, this submits whichever stages the chosen flow lists and
  /// stops as soon as the server hands back an account.
  Future<void> _registerWithInteractiveAuth(
    RegistrationRequest request,
    String username,
  ) async {
    Future<void> attempt([AuthenticationData? auth]) => _client.register(
      username: username,
      password: request.password,
      initialDeviceDisplayName: _deviceName,
      refreshToken: true,
      auth: auth,
    );

    final MatrixException challenge;
    try {
      await attempt();
      return;
    } on MatrixException catch (error) {
      if (!error.requireAdditionalAuthentication || error.session == null) {
        rethrow;
      }
      challenge = error;
    }

    final inviteCode = request.inviteCode?.trim();
    bool canSatisfy(String stage) =>
        stage == AuthenticationTypes.dummy ||
        (stage == _registrationTokenStage &&
            inviteCode != null &&
            inviteCode.isNotEmpty);

    final flows = challenge.authenticationFlows ?? const [];
    final flow = flows
        .where((flow) => flow.stages.every(canSatisfy))
        .firstOrNull;
    if (flow == null) {
      // The only flows on offer need something this screen cannot provide.
      // When one of them wants a code, the code is what is missing.
      final wantsCode = flows.any(
        (flow) => flow.stages.contains(_registrationTokenStage),
      );
      throw AuthFailure(
        wantsCode
            ? AuthFailureCode.invalidInviteCode
            : AuthFailureCode.registrationDisabled,
      );
    }

    var session = challenge.session!;
    var completed = challenge.completedAuthenticationFlows.toSet();
    for (final stage in flow.stages) {
      if (completed.contains(stage)) continue;
      try {
        await attempt(
          AuthenticationData(
            type: stage,
            session: session,
            additionalFields: stage == _registrationTokenStage
                ? {'token': inviteCode}
                : null,
          ),
        );
        return;
      } on MatrixException catch (error) {
        if (!error.requireAdditionalAuthentication || error.session == null) {
          rethrow;
        }
        session = error.session!;
        completed = error.completedAuthenticationFlows.toSet();
        // The server answers a rejected stage with the same 401 it uses to
        // ask for the next one; the giveaway is that the stage we just sent
        // did not join the completed list.
        if (!completed.contains(stage)) {
          throw AuthFailure(
            stage == _registrationTokenStage
                ? AuthFailureCode.invalidInviteCode
                : AuthFailureCode.unknown,
          );
        }
      }
    }
  }

  AuthSession? _currentSession() {
    final userId = _client.userID;
    if (!_client.isLogged() || userId == null) return null;
    return AuthSession(userId: userId);
  }

  AuthSession _requireCurrentSession() {
    final session = _currentSession();
    if (session == null) throw const AuthFailure(AuthFailureCode.unknown);
    return session;
  }

  AuthFailure _mapMatrixError(
    MatrixException error, {
    required bool isRegistration,
  }) {
    final retryAfter = error.retryAfterMs == null
        ? null
        : Duration(milliseconds: error.retryAfterMs!);
    return switch (error.error) {
      MatrixError.M_FORBIDDEN => AuthFailure(
        isRegistration &&
                error.errorMessage.toLowerCase().contains('registration') &&
                error.errorMessage.toLowerCase().contains('disabled')
            ? AuthFailureCode.registrationDisabled
            : isRegistration
            ? AuthFailureCode.unknown
            : AuthFailureCode.invalidCredentials,
      ),
      MatrixError.M_USER_IN_USE => const AuthFailure(
        AuthFailureCode.usernameTaken,
      ),
      MatrixError.M_INVALID_USERNAME => const AuthFailure(
        AuthFailureCode.invalidUsername,
      ),
      MatrixError.M_LIMIT_EXCEEDED => AuthFailure(
        AuthFailureCode.rateLimited,
        retryAfter: retryAfter,
      ),
      MatrixError.M_UNKNOWN_TOKEN => const AuthFailure(
        AuthFailureCode.sessionExpired,
      ),
      // During sign-up the only thing being authorised is the invite code.
      MatrixError.M_UNAUTHORIZED => AuthFailure(
        isRegistration
            ? AuthFailureCode.invalidInviteCode
            : AuthFailureCode.invalidCredentials,
      ),
      _ => const AuthFailure(AuthFailureCode.unknown),
    };
  }
}
