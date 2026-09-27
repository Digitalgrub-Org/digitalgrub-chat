import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Confirms and performs permanent account deletion. Returns true once the
/// account is gone, so the caller can route back to sign-in.
///
/// Deletion is deliberately gated behind the account password: the homeserver
/// re-authenticates the request, and it stops a deletion from an unattended
/// unlocked device.
Future<bool> showDeleteAccountDialog(BuildContext context) async {
  final deleted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _DeleteAccountDialog(),
  );
  return deleted ?? false;
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_deleting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _deleting = true;
      _error = null;
    });
    final failure = await ref
        .read(authControllerProvider.notifier)
        .deleteAccount(_passwordController.text);
    if (!mounted) return;

    if (failure == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _deleting = false;
      _error = _failureMessage(context, failure);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: scheme.error),
      title: Text(context.l10n.deleteAccount),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.deleteAccountWarning),
            const SizedBox(height: AppSpacing.md),
            Text(context.l10n.deleteAccountPasswordPrompt),
            const SizedBox(height: AppSpacing.sm),
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _passwordController,
                enabled: !_deleting,
                obscureText: true,
                // Same reason as the sign-in form: a password is an exact
                // string, and handwriting it is guesswork.
                stylusHandwritingEnabled: false,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: context.l10n.password,
                  errorText: _error,
                ),
                validator: (value) =>
                    (value ?? '').isEmpty ? context.l10n.requiredField : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.pop(context, false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: _deleting ? null : _delete,
          icon: _deleting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_forever_rounded),
          label: Text(
            _deleting
                ? context.l10n.deletingAccount
                : context.l10n.confirmDelete,
          ),
        ),
      ],
    );
  }
}

String _failureMessage(BuildContext context, AuthFailure failure) {
  return switch (failure.code) {
    AuthFailureCode.invalidCredentials => context.l10n.invalidCredentials,
    AuthFailureCode.rateLimited => context.l10n.rateLimited,
    AuthFailureCode.sessionExpired => context.l10n.sessionExpired,
    AuthFailureCode.serverUnavailable => context.l10n.serverUnavailable,
    _ => context.l10n.deleteAccountFailed,
  };
}
