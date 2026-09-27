import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/core/config/app_config.dart';
import 'package:dg_chat/core/widgets/profile_avatar.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart'
    show minimumPasswordLength;
import 'package:dg_chat/features/contacts/domain/user_repository.dart'
    show UserSearchResult;
import 'package:dg_chat/features/admin/application/admin_providers.dart';
import 'package:dg_chat/features/admin/domain/admin_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Everyone on the server, with what an admin does for them: create an
/// account, reset a password.
///
/// Opens as a list rather than a search box: an admin who has to guess a
/// name before seeing anything cannot find the person they came for.
class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() =>
      _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  String _filter = '';

  String _adminMessage(AdminFailure failure) => switch (failure.code) {
    AdminFailureCode.notAdmin => context.l10n.adminNotAdmin,
    AdminFailureCode.usernameTaken => context.l10n.adminUsernameTaken,
    AdminFailureCode.adminAccount => context.l10n.adminAccountOnServer,
    AdminFailureCode.notFound => context.l10n.adminUserNotFound,
    AdminFailureCode.unavailable => context.l10n.adminUnavailable,
    _ => context.l10n.serverUnavailable,
  };

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createUser() async {
    final draft = await showDialog<_NewUserDraft>(
      context: context,
      builder: (context) => const _NewUserDialog(),
    );
    if (draft == null || !mounted) return;
    try {
      final repository = await ref.read(adminRepositoryProvider.future);
      final userId = await repository.createUser(
        username: draft.username,
        password: draft.password,
        displayName: draft.displayName,
      );
      _say(context.l10n.adminUserCreated(userId));
      ref.invalidate(serverUsersProvider);
    } on AdminFailure catch (failure) {
      _say(_adminMessage(failure));
    } catch (_) {
      _say(context.l10n.serverUnavailable);
    }
  }

  Future<void> _resetPassword(UserSearchResult user) async {
    final password = await showDialog<String>(
      context: context,
      builder: (context) => _PasswordDialog(
        title: context.l10n.adminResetPasswordTitle(user.displayName),
        hint: context.l10n.adminResetPasswordHint,
        confirmLabel: context.l10n.adminResetPassword,
      ),
    );
    if (password == null || !mounted) return;
    try {
      final repository = await ref.read(adminRepositoryProvider.future);
      await repository.resetPassword(username: user.userId, password: password);
      _say(context.l10n.adminPasswordReset);
    } on AdminFailure catch (failure) {
      _say(_adminMessage(failure));
    } catch (_) {
      _say(context.l10n.serverUnavailable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(serverUsersProvider);
    // Absent, not disabled, when the build has no admin service to talk to.
    final adminActions = ref.watch(appConfigProvider).adminUrl != null;

    return Scaffold(
      floatingActionButton: adminActions
          ? FloatingActionButton.extended(
              onPressed: _createUser,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(context.l10n.adminNewUser),
            )
          : null,
      appBar: AppBar(
        title: Text(context.l10n.userManagement),
        actions: [
          IconButton(
            tooltip: context.l10n.refresh,
            onPressed: () {
              ref.invalidate(serverUsersProvider);
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: SearchBar(
              hintText: context.l10n.peopleSearchHint,
              leading: const Icon(Icons.search_rounded),
              onChanged: (value) =>
                  setState(() => _filter = value.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: roster.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  _Message(message: context.l10n.serverUnavailable),
              data: (users) {
                final visible =
                    users.where((user) {
                      if (_filter.isEmpty) return true;
                      return user.displayName.toLowerCase().contains(_filter) ||
                          user.userId.toLowerCase().contains(_filter);
                    }).toList()..sort(
                      (a, b) => a.displayName.toLowerCase().compareTo(
                        b.displayName.toLowerCase(),
                      ),
                    );
                if (visible.isEmpty) {
                  return _Message(message: context.l10n.noPeopleFound);
                }
                return ListView.builder(
                  itemCount: visible.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.xs,
                          AppSpacing.md,
                          AppSpacing.sm,
                        ),
                        child: Text(
                          context.l10n.userManagementCount(users.length),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      );
                    }
                    final user = visible[index - 1];
                    return ListTile(
                      leading: ProfileAvatar(
                        label: user.displayName,
                        imageUrl: user.avatarUrl,
                        httpHeaders: user.avatarHeaders,
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        user.userId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (adminActions)
                            PopupMenuButton<String>(
                              tooltip: context.l10n.adminActions,
                              onSelected: (_) => _resetPassword(user),
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'reset',
                                  child: Text(context.l10n.adminResetPassword),
                                ),
                              ],
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }
}

class _NewUserDraft {
  const _NewUserDraft({
    required this.username,
    required this.password,
    this.displayName,
  });

  final String username;
  final String password;
  final String? displayName;
}

/// Username, display name, password. The password is shown, not masked: the
/// admin is about to read it out to somebody, and a masked field they cannot
/// re-read is how the wrong password gets handed over.
class _NewUserDialog extends StatefulWidget {
  const _NewUserDialog();

  @override
  State<_NewUserDialog> createState() => _NewUserDialogState();
}

class _NewUserDialogState extends State<_NewUserDialog> {
  static final _usernamePattern = RegExp(r'^[a-z0-9._=-]{3,32}$');
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _NewUserDraft(
        username: _username.text.trim().toLowerCase(),
        password: _password.text,
        displayName: _displayName.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.adminNewUserTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.adminNewUserHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _username,
              autofocus: true,
              autocorrect: false,
              decoration: InputDecoration(labelText: context.l10n.username),
              validator: (value) =>
                  _usernamePattern.hasMatch((value ?? '').trim().toLowerCase())
                  ? null
                  : context.l10n.usernameValidation,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _displayName,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: context.l10n.displayName),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _password,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: context.l10n.password),
              onFieldSubmitted: (_) => _submit(),
              validator: (value) => (value?.length ?? 0) < minimumPasswordLength
                  ? context.l10n.passwordValidation(minimumPasswordLength)
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(context.l10n.adminCreateUser),
        ),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({
    required this.title,
    required this.hint,
    required this.confirmLabel,
  });

  final String title;
  final String hint;
  final String confirmLabel;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.hint, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _password,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: context.l10n.newPassword),
              onFieldSubmitted: (_) => _submit(),
              validator: (value) => (value?.length ?? 0) < minimumPasswordLength
                  ? context.l10n.passwordValidation(minimumPasswordLength)
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
