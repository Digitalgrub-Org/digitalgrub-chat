import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/core/widgets/profile_avatar.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(chatListProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.contacts),
        actions: [
          IconButton(
            tooltip: context.l10n.searchPeople,
            onPressed: () => context.push(AppRoutes.userSearch),
            icon: const Icon(Icons.person_search_rounded),
          ),
        ],
      ),
      body: chats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(context.l10n.chatListFailed)),
        data: (items) {
          final directChats = items.where((chat) => chat.isDirect).toList();
          if (directChats.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_outline_rounded,
                      size: 52,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      context.l10n.noContactsTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      context.l10n.noContactsBody,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: () => context.push(AppRoutes.userSearch),
                      icon: const Icon(Icons.person_search_rounded),
                      label: Text(context.l10n.findPeople),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: directChats.length,
            separatorBuilder: (_, _) => const Divider(indent: 80),
            itemBuilder: (context, index) {
              final chat = directChats[index];
              return ListTile(
                minTileHeight: 68,
                leading: ProfileAvatar(
                  label: chat.name,
                  imageUrl: chat.avatarUrl,
                  httpHeaders: chat.avatarHeaders,
                ),
                title: Text(chat.name),
                subtitle: Text(
                  chat.lastMessage.isEmpty
                      ? context.l10n.noMessagesYet
                      : chat.lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => openConversation(context, chat.roomId),
              );
            },
          );
        },
      ),
    );
  }
}
