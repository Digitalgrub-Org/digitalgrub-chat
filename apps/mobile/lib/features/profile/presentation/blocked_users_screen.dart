import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/core/widgets/profile_avatar.dart';
import 'package:dg_chat/features/profile/application/profile_providers.dart';
import 'package:dg_chat/features/profile/domain/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  String? _pendingUserId;

  Future<void> _unblock(UserProfile user) async {
    if (_pendingUserId != null) return;
    setState(() => _pendingUserId = user.userId);
    try {
      final repository = await ref.read(profileRepositoryProvider.future);
      await repository.unblockUser(user.userId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.userUnblocked)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.blockFailed)));
      }
    } finally {
      if (mounted) setState(() => _pendingUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = ref.watch(blockedUsersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.blockedUsers)),
      body: blocked.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 44),
                const SizedBox(height: AppSpacing.md),
                Text(
                  context.l10n.blockedUsersFailed,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: () => ref.invalidate(blockedUsersProvider),
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
        data: (users) {
          if (users.isEmpty) return const _EmptyBlockedUsers();
          return ListView.separated(
            itemCount: users.length,
            separatorBuilder: (_, _) => const Divider(indent: 80),
            itemBuilder: (context, index) {
              final user = users[index];
              final pending = _pendingUserId == user.userId;
              return ListTile(
                minTileHeight: 72,
                leading: ProfileAvatar(
                  label: user.displayName,
                  imageUrl: user.avatarUrl,
                  httpHeaders: user.avatarHeaders,
                ),
                title: Text(
                  user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  user.userId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: pending
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : OutlinedButton(
                        onPressed: _pendingUserId == null
                            ? () => _unblock(user)
                            : null,
                        child: Text(context.l10n.unblockUser),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyBlockedUsers extends StatelessWidget {
  const _EmptyBlockedUsers();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.block_rounded,
                size: 52,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.l10n.noBlockedUsers,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.l10n.noBlockedUsersBody,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
