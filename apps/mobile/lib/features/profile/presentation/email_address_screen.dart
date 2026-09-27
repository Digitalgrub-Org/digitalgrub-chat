import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/authentication/presentation/password_reset_screen.dart'
    show emailPattern;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The address a password reset would be sent to.
///
/// Worth its own screen rather than a line in the profile: an account with no
/// address here cannot be recovered by the person who owns it, only by an
/// admin with a terminal. The empty state says so plainly instead of looking
/// like an optional extra nobody needs.
class EmailAddressScreen extends ConsumerStatefulWidget {
  const EmailAddressScreen({super.key});

  @override
  ConsumerState<EmailAddressScreen> createState() => _EmailAddressScreenState();
}

class _EmailAddressScreenState extends ConsumerState<EmailAddressScreen> {
  late Future<List<String>> _addresses = _load();
  bool _busy = false;

  Future<List<String>> _load() async {
    final repository = await ref.read(authRepositoryProvider.future);
    return repository.emailAddresses();
  }

  void _reload() => setState(() => _addresses = _load());

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _messageFor(AuthFailure failure) => switch (failure.code) {
    AuthFailureCode.emailUnsupported => context.l10n.emailNotConfigured,
    AuthFailureCode.emailInUse => context.l10n.emailInUse,
    AuthFailureCode.emailNotVerified => context.l10n.emailNotVerified,
    AuthFailureCode.invalidCredentials => context.l10n.invalidCredentials,
    AuthFailureCode.rateLimited => context.l10n.rateLimited,
    _ => context.l10n.serverUnavailable,
  };

  Future<void> _add() async {
    final email = await _promptForEmail();
    if (email == null || !mounted) return;

    setState(() => _busy = true);
    EmailVerification pending;
    try {
      final repository = await ref.read(authRepositoryProvider.future);
      pending = await repository.addEmailAddress(email);
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _busy = false);
      _say(_messageFor(failure));
      return;
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      _say(context.l10n.serverUnavailable);
      return;
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;

    // The server has mailed a link. Nothing is attached until it is opened,
    // so the confirm step is a separate prompt rather than an assumption.
    final password = await _promptForPassword(pending.email);
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final repository = await ref.read(authRepositoryProvider.future);
      await repository.confirmEmailAddress(
        pending: pending,
        password: password,
      );
      _say(context.l10n.emailAddressAdded);
      _reload();
    } on AuthFailure catch (failure) {
      _say(_messageFor(failure));
    } catch (_) {
      _say(context.l10n.serverUnavailable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String email) async {
    setState(() => _busy = true);
    try {
      final repository = await ref.read(authRepositoryProvider.future);
      await repository.removeEmailAddress(email);
      _say(context.l10n.emailAddressRemoved);
      _reload();
    } on AuthFailure catch (failure) {
      _say(_messageFor(failure));
    } catch (_) {
      _say(context.l10n.serverUnavailable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _promptForEmail() {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.addEmailAddress),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(labelText: context.l10n.emailAddress),
            validator: (value) => emailPattern.hasMatch(value?.trim() ?? '')
                ? null
                : context.l10n.emailValidation,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(context).pop(controller.text.trim());
            },
            child: Text(context.l10n.addEmailAddress),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptForPassword(String email) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.confirmWithPassword),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.verifyEmailSent(email)),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: context.l10n.currentPassword,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(context.l10n.confirmEmail),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.emailAddresses)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _add,
        icon: const Icon(Icons.add_rounded),
        label: Text(context.l10n.addEmailAddress),
      ),
      body: FutureBuilder<List<String>>(
        future: _addresses,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(context.l10n.serverUnavailable),
              ),
            );
          }
          final addresses = snapshot.data ?? const <String>[];
          if (addresses.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  context.l10n.noEmailAddress,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  context.l10n.emailAddressesSubtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final address in addresses)
                ListTile(
                  leading: const Icon(Icons.mail_outline_rounded),
                  title: Text(address),
                  trailing: TextButton(
                    onPressed: _busy ? null : () => _remove(address),
                    child: Text(context.l10n.removeEmailAddress),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
