import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/core/media/avatar_picker.dart';
import 'package:dg_chat/core/widgets/profile_avatar.dart';
import 'package:dg_chat/features/contacts/application/user_search_controller.dart';
import 'package:dg_chat/features/moderation/presentation/report_sheet.dart';
import 'package:dg_chat/features/profile/application/profile_providers.dart';
import 'package:dg_chat/features/profile/domain/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({required this.userId, super.key});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider(userId));

    return profile.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(context.l10n.userProfile)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.userProfile)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 44),
                const SizedBox(height: AppSpacing.md),
                Text(
                  error is ProfileFailure &&
                          error.code == ProfileFailureCode.userNotFound
                      ? context.l10n.profileNotFound
                      : context.l10n.profileLoadFailed,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: () => ref.invalidate(userProfileProvider(userId)),
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (data) => _ProfileView(profile: data),
    );
  }
}

class _ProfileView extends ConsumerStatefulWidget {
  const _ProfileView({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<_ProfileView> {
  bool _busy = false;

  UserProfile get _profile => widget.profile;

  Future<void> _run(
    Future<void> Function(ProfileRepository repository) action, {
    String? successMessage,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repository = await ref.read(profileRepositoryProvider.future);
      await action(repository);
      if (mounted && successMessage != null) _showMessage(successMessage);
    } on ProfileFailure catch (failure) {
      if (mounted) _showMessage(_failureMessage(context, failure));
    } catch (_) {
      if (mounted) _showMessage(context.l10n.profileUpdateFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editDisplayName() async {
    final value = await _promptText(
      title: context.l10n.displayName,
      initialValue: _profile.displayName,
      maxLength: maxDisplayNameLength,
      isRequired: true,
    );
    if (value == null) return;
    await _run((repository) => repository.updateDisplayName(value));
  }

  Future<void> _editAbout() async {
    final value = await _promptText(
      title: context.l10n.about,
      initialValue: _profile.about,
      maxLength: maxAboutLength,
      isRequired: false,
      maxLines: 3,
    );
    if (value == null) return;
    await _run((repository) => repository.updateAbout(value));
  }

  Future<void> _editMobileNumber() async {
    final value = await _promptText(
      title: context.l10n.mobileNumber,
      initialValue: _profile.mobileNumber ?? '',
      maxLength: 20,
      isRequired: false,
      keyboardType: TextInputType.phone,
    );
    if (value == null) return;
    await _run(
      (repository) =>
          repository.updateMobileNumber(value.isEmpty ? null : value),
    );
  }

  Future<String?> _promptText({
    required String title,
    required String initialValue,
    required int maxLength,
    required bool isRequired,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => _TextPromptDialog(
        title: title,
        initialValue: initialValue,
        maxLength: maxLength,
        isRequired: isRequired,
        maxLines: maxLines,
        keyboardType: keyboardType,
      ),
    );
  }

  Future<void> _changePhoto() async {
    // Resolved before the picker suspends this method.
    final l10n = context.l10n;
    AvatarUpload? picked;
    try {
      picked = await ref.read(avatarPickerProvider).pick();
    } catch (_) {
      if (mounted) _showMessage(l10n.photoPickFailed);
      return;
    }
    if (picked == null) return;
    await _run(
      (repository) => repository.updateAvatar(picked),
      successMessage: l10n.photoUpdated,
    );
  }

  Future<void> _removePhoto() async {
    await _run(
      (repository) => repository.updateAvatar(null),
      successMessage: context.l10n.photoUpdated,
    );
  }

  Future<void> _toggleBlock() async {
    // Resolved before the confirmation dialog suspends this method.
    final l10n = context.l10n;
    if (_profile.isBlocked) {
      await _run(
        (repository) => repository.unblockUser(_profile.userId),
        successMessage: l10n.userUnblocked,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(context.l10n.blockUserConfirmation(_profile.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.block),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      (repository) => repository.blockUser(_profile.userId),
      successMessage: l10n.userBlocked,
    );
  }

  Future<void> _report() async {
    final submitted = await showReportSheet(
      context,
      reportedUserId: _profile.userId,
    );
    if (submitted && mounted) _showMessage(context.l10n.reportSubmitted);
  }

  Future<void> _startConversation() async {
    final roomId = await ref
        .read(userSearchControllerProvider.notifier)
        .startConversation(_profile.userId);
    if (roomId != null && mounted) {
      openConversation(context, roomId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          profile.isSelf ? context.l10n.myProfile : context.l10n.userProfile,
        ),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                ProfileAvatar(
                  label: profile.displayName,
                  imageUrl: profile.avatarUrl,
                  httpHeaders: profile.avatarHeaders,
                  radius: 48,
                ),
                if (profile.isSelf) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _busy ? null : _changePhoto,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(context.l10n.changePhoto),
                      ),
                      if (profile.avatarUrl != null)
                        TextButton(
                          onPressed: _busy ? null : _removePhoto,
                          child: Text(context.l10n.removePhoto),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text(
                  profile.displayName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (profile.isBlocked) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Chip(
                    avatar: const Icon(Icons.block_rounded, size: 16),
                    label: Text(context.l10n.blockUser),
                  ),
                ],
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.alternate_email_rounded),
            title: Text(context.l10n.matrixUsername),
            subtitle: Text(profile.userId),
          ),
          if (profile.isSelf) ...[
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(context.l10n.displayName),
              subtitle: Text(profile.displayName),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _busy ? null : _editDisplayName,
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(context.l10n.about),
              subtitle: Text(
                profile.about.isEmpty ? context.l10n.noAboutYet : profile.about,
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _busy ? null : _editAbout,
            ),
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: Text(context.l10n.mobileNumber),
              subtitle: Text(
                profile.mobileNumber == null || profile.mobileNumber!.isEmpty
                    ? context.l10n.noMobileNumber
                    : '${profile.mobileNumber} · '
                          '${context.l10n.mobileNumberUnverified}',
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _busy ? null : _editMobileNumber,
            ),
          ] else ...[
            if (profile.about.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(context.l10n.about),
                subtitle: Text(profile.about),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: Text(context.l10n.sendMessageTo),
              onTap: _busy ? null : _startConversation,
            ),
            ListTile(
              leading: Icon(
                profile.isBlocked
                    ? Icons.lock_open_rounded
                    : Icons.block_rounded,
                color: profile.isBlocked
                    ? null
                    : Theme.of(context).colorScheme.error,
              ),
              title: Text(
                profile.isBlocked
                    ? context.l10n.unblockUser
                    : context.l10n.blockUser,
                style: profile.isBlocked
                    ? null
                    : TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: _busy ? null : _toggleBlock,
            ),
            ListTile(
              leading: Icon(
                Icons.flag_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                context.l10n.reportUser,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: _busy ? null : _report,
            ),
          ],
        ],
      ),
    );
  }
}

/// Owns its editing controller so the field is torn down with the dialog
/// route rather than while it still holds focus.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.initialValue,
    required this.maxLength,
    required this.isRequired,
    required this.maxLines,
    this.keyboardType,
  });

  final String title;
  final String initialValue;
  final int maxLength;
  final bool isRequired;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: widget.maxLength,
          maxLines: widget.maxLines,
          keyboardType: widget.keyboardType,
          textCapitalization: TextCapitalization.sentences,
          validator: (value) {
            final text = value?.trim() ?? '';
            if (widget.isRequired && text.isEmpty) {
              return context.l10n.displayNameRequired;
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(context, _controller.text.trim());
          },
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}

String _failureMessage(BuildContext context, ProfileFailure failure) {
  return switch (failure.code) {
    ProfileFailureCode.invalidDisplayName => context.l10n.displayNameRequired,
    ProfileFailureCode.invalidAbout => context.l10n.aboutTooLong(
      maxAboutLength,
    ),
    ProfileFailureCode.invalidMobileNumber =>
      context.l10n.mobileNumberValidation,
    ProfileFailureCode.userNotFound => context.l10n.profileNotFound,
    ProfileFailureCode.avatarTooLarge => context.l10n.photoTooLarge,
    ProfileFailureCode.rateLimited => context.l10n.rateLimited,
    ProfileFailureCode.sessionExpired => context.l10n.sessionExpired,
    _ => context.l10n.profileUpdateFailed,
  };
}
