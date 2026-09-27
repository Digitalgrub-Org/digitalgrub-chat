import 'dart:async';

import 'package:dg_chat/features/authentication/domain/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.session, this.loginFailure, this.registerFailure});

  final _sessionController = StreamController<AuthSession?>.broadcast();

  AuthSession? session;
  AuthFailure? loginFailure;
  AuthFailure? registerFailure;
  AuthFailure? deleteFailure;
  String? lastUsername;
  String? lastPassword;
  String? lastDeletePassword;
  RegistrationRequest? lastRegistration;
  int logoutCount = 0;
  int deleteCount = 0;

  @override
  Stream<AuthSession?> get sessionChanges => _sessionController.stream;

  @override
  Future<AuthSession?> restoreSession() async => session;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    lastUsername = username;
    lastPassword = password;
    final failure = loginFailure;
    if (failure != null) throw failure;
    final authenticatedSession = AuthSession(userId: '@$username:test');
    session = authenticatedSession;
    _sessionController.add(authenticatedSession);
    return authenticatedSession;
  }

  @override
  Future<AuthSession> register(RegistrationRequest request) async {
    lastRegistration = request;
    final failure = registerFailure;
    if (failure != null) throw failure;
    final authenticatedSession = AuthSession(
      userId: '@${request.username}:test',
    );
    session = authenticatedSession;
    _sessionController.add(authenticatedSession);
    return authenticatedSession;
  }

  @override
  Future<void> logout() async {
    logoutCount++;
    emitSession(null);
  }

  @override
  Future<void> deleteAccount({
    required String password,
    AccountDeletionScope scope = AccountDeletionScope.erase,
  }) async {
    lastDeletePassword = password;
    final failure = deleteFailure;
    if (failure != null) throw failure;
    deleteCount++;
    emitSession(null);
  }

  // --- email / password reset ---

  AuthFailure? resetRequestFailure;
  AuthFailure? resetCompleteFailure;
  String? lastResetEmail;
  String? lastNewPassword;
  int resendCount = 0;
  List<String> emails = <String>[];

  @override
  Future<EmailVerification> requestPasswordReset(String email) async {
    lastResetEmail = email;
    final failure = resetRequestFailure;
    if (failure != null) throw failure;
    return EmailVerification(
      sid: 'sid-1',
      clientSecret: 'secret-1',
      email: email,
    );
  }

  @override
  Future<EmailVerification> resendPasswordReset(
    EmailVerification pending,
  ) async {
    resendCount++;
    final failure = resetRequestFailure;
    if (failure != null) throw failure;
    return pending.withNextAttempt('sid-${pending.sendAttempt + 1}');
  }

  @override
  Future<void> completePasswordReset({
    required EmailVerification pending,
    required String newPassword,
  }) async {
    lastNewPassword = newPassword;
    final failure = resetCompleteFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<List<String>> emailAddresses() async => List.of(emails);

  @override
  Future<EmailVerification> addEmailAddress(String email) async =>
      EmailVerification(sid: 'sid-1', clientSecret: 'secret-1', email: email);

  @override
  Future<void> confirmEmailAddress({
    required EmailVerification pending,
    required String password,
  }) async => emails = [...emails, pending.email];

  @override
  Future<void> removeEmailAddress(String email) async => emails = [
    for (final e in emails)
      if (e != email) e,
  ];

  void emitSession(AuthSession? nextSession) {
    session = nextSession;
    _sessionController.add(nextSession);
  }

  Future<void> dispose() => _sessionController.close();
}
