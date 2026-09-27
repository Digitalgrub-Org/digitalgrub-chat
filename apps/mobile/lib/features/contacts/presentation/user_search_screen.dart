import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/core/widgets/profile_avatar.dart';
import 'package:dg_chat/features/contacts/application/user_search_controller.dart';
import 'package:dg_chat/features/contacts/domain/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class UserSearchScreen extends ConsumerWidget {
  const UserSearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(userSearchControllerProvider);
    final controller = ref.read(userSearchControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.searchPeople)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: SearchBar(
              autoFocus: true,
              hintText: context.l10n.peopleSearchHint,
              leading: const Icon(Icons.search_rounded),
              onChanged: controller.setQuery,
            ),
          ),
          if (state.isSearching) const LinearProgressIndicator(),
          Expanded(child: _SearchContent(state: state)),
        ],
      ),
    );
  }
}

class _SearchContent extends ConsumerWidget {
  const _SearchContent({required this.state});

  final UserSearchState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.failure != null) {
      return _SearchMessage(
        icon: Icons.cloud_off_rounded,
        message: _failureMessage(context, state.failure!),
      );
    }
    if (state.query.length < 2) {
      return _SearchMessage(
        icon: Icons.person_search_rounded,
        message: context.l10n.peopleSearchInstructions,
      );
    }
    if (!state.isSearching && state.results.isEmpty) {
      return _SearchMessage(
        icon: Icons.search_off_rounded,
        message: context.l10n.noPeopleFound,
      );
    }
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: state.results.length,
      separatorBuilder: (_, _) => const Divider(indent: 80),
      itemBuilder: (context, index) {
        final person = state.results[index];
        final starting = state.startingUserId == person.userId;
        return ListTile(
          minTileHeight: 72,
          leading: ProfileAvatar(
            label: person.displayName,
            imageUrl: person.avatarUrl,
            httpHeaders: person.avatarHeaders,
          ),
          title: Text(person.displayName),
          subtitle: Text(person.userId),
          trailing: starting
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: context.l10n.userProfile,
                  onPressed: () =>
                      context.push(AppRoutes.userProfilePath(person.userId)),
                  icon: const Icon(Icons.info_outline_rounded),
                ),
          enabled: state.startingUserId == null,
          onTap: () async {
            final roomId = await ref
                .read(userSearchControllerProvider.notifier)
                .startConversation(person.userId);
            if (roomId != null && context.mounted) {
              openConversation(context, roomId);
            }
          },
        );
      },
    );
  }

  String _failureMessage(BuildContext context, UserFailure failure) {
    return switch (failure.code) {
      UserFailureCode.rateLimited => context.l10n.rateLimited,
      UserFailureCode.sessionExpired => context.l10n.sessionExpired,
      _ => context.l10n.peopleSearchFailed,
    };
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
