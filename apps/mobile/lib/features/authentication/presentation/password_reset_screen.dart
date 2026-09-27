import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Matches the shape of an address rather than the RFC, which no regex covers.
/// The server is the thing that decides; this only catches a missing @.
final emailPattern = RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]+$');

/// Resetting a forgotten password, in the two halves Matrix splits it into.
///
/// The server mails a link, the person proves they can read that mailbox by
/// following it, and only then is a new password accepted. The screen has to
/// wait in the middle, which is why it is a small state machine rather than
/// one form.
class PasswordResetScreen extends ConsumerStatefulWidget {
  const PasswordResetScreen({super.key});

  @override
  ConsumerState<PasswordResetScreen> createState() =>
      _PasswordResetScreenState();
}

class _PasswordResetScreenState extends ConsumerState<PasswordResetScreen> {
  final _emailKey = GlobalKey<FormState>();
  final _passwordKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  EmailVerification? _pending;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(AuthRepository) action) async {
    setState(() => _busy = true);
    try {
      final repository = await ref.read(authRepositoryProvider.future);
      await action(repository);
    } on AuthFailure catch (failure) {
      if (mounted) _say(_messageFor(context.l10n, failure));
    } catch (_) {
      if (mounted) _say(context.l10n.serverUnavailable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _requestLink() async {
    if (!_emailKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    await _run((repository) async {
      try {
        final pending = await repository.requestPasswordReset(email);
        if (mounted) setState(() => _pending = pending);
      } on AuthFailure catch (failure) {
        // An unknown address must look exactly like a known one. Otherwise
        // this form answers "is this person registered here?" for anyone who
        // asks, which is a directory nobody agreed to publish.
        if (failure.code != AuthFailureCode.emailUnknown) rethrow;
        if (mounted) {
          setState(
            () => _pending = EmailVerification(
              sid: '',
              clientSecret: '',
              email: email,
            ),
          );
        }
      }
    });
  }

  Future<void> _resend() async {
    final pending = _pending;
    if (pending == null || pending.sid.isEmpty) {
      // Nothing was really sent, and saying so here would leak what the
      // previous step went out of its way not to say.
      _say(context.l10n.resetLinkResent);
      return;
    }
    await _run((repository) async {
      final next = await repository.resendPasswordReset(pending);
      if (mounted) {
        setState(() => _pending = next);
        _say(context.l10n.resetLinkResent);
      }
    });
  }

  Future<void> _setPassword() async {
    if (!_passwordKey.currentState!.validate()) return;
    final pending = _pending;
    if (pending == null) return;
    if (pending.sid.isEmpty) {
      // The address was never on an account, so there is nothing to change.
      // The same refusal a real-but-unopened link would give.
      _say(context.l10n.emailNotVerified);
      return;
    }
    await _run((repository) async {
      await repository.completePasswordReset(
        pending: pending,
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      _say(context.l10n.passwordResetDone);
      Navigator.of(context).pop();
    });
  }

  String _messageFor(AppLocalizations l10n, AuthFailure failure) =>
      switch (failure.code) {
        AuthFailureCode.emailNotVerified => l10n.emailNotVerified,
        AuthFailureCode.emailUnsupported => l10n.emailNotConfigured,
        AuthFailureCode.rateLimited => l10n.rateLimited,
        AuthFailureCode.serverUnavailable => l10n.serverUnavailable,
        _ => l10n.unknownAuthenticationError,
      };

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.resetPasswordTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: pending == null
                  ? _askForEmail(context)
                  : _askForPassword(context, pending),
            ),
          ),
        ),
      ),
    );
  }

  Widget _askForEmail(BuildContext context) => Form(
    key: _emailKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.resetPasswordSubtitle,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          controller: _emailController,
          enabled: !_busy,
          autocorrect: false,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(
            labelText: context.l10n.emailAddress,
            prefixIcon: const Icon(Icons.mail_outline_rounded),
          ),
          onFieldSubmitted: (_) => _requestLink(),
          validator: (value) => emailPattern.hasMatch(value?.trim() ?? '')
              ? null
              : context.l10n.emailValidation,
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _busy ? null : _requestLink,
          child: Text(
            _busy ? context.l10n.sendingResetLink : context.l10n.sendResetLink,
          ),
        ),
      ],
    ),
  );

  Widget _askForPassword(BuildContext context, EmailVerification pending) =>
      Form(
        key: _passwordKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.resetLinkSentTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l10n.resetLinkSentBody(pending.email),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _passwordController,
              enabled: !_busy,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: context.l10n.newPassword,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: context.l10n.password,
                  onPressed: _busy
                      ? null
                      : () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) => (value?.length ?? 0) < minimumPasswordLength
                  ? context.l10n.passwordValidation(minimumPasswordLength)
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _confirmController,
              enabled: !_busy,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: context.l10n.confirmNewPassword,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
              ),
              onFieldSubmitted: (_) => _setPassword(),
              validator: (value) => value == _passwordController.text
                  ? null
                  : context.l10n.passwordsDoNotMatch,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _busy ? null : _setPassword,
              child: Text(context.l10n.setNewPassword),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _busy ? null : _resend,
              child: Text(context.l10n.resendResetLink),
            ),
          ],
        ),
      );
}
