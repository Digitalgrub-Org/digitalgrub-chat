import 'package:dg_chat/core/layout/breakpoints.dart';
import 'package:dg_chat/features/authentication/presentation/authentication_screen.dart';
import 'package:dg_chat/features/authentication/presentation/password_reset_screen.dart';
import 'package:dg_chat/features/calls/presentation/call_screen.dart';
import 'package:dg_chat/features/chats/presentation/app_shell.dart';
import 'package:dg_chat/features/chats/presentation/chat_list_screen.dart';
import 'package:dg_chat/features/contacts/presentation/contacts_screen.dart';
import 'package:dg_chat/features/contacts/presentation/user_search_screen.dart';
import 'package:dg_chat/features/conversation/presentation/conversation_screen.dart';
import 'package:dg_chat/features/groups/presentation/group_add_members_screen.dart';
import 'package:dg_chat/features/meetings/presentation/meet_screen.dart';
import 'package:dg_chat/features/groups/presentation/group_activity_screen.dart';
import 'package:dg_chat/features/groups/presentation/group_details_screen.dart';
import 'package:dg_chat/features/groups/presentation/new_group_screen.dart';
import 'package:dg_chat/features/profile/presentation/blocked_users_screen.dart';
import 'package:dg_chat/features/profile/presentation/email_address_screen.dart';
import 'package:dg_chat/features/admin/presentation/user_management_screen.dart';
import 'package:dg_chat/features/profile/presentation/user_profile_screen.dart';
import 'package:dg_chat/features/settings/presentation/settings_screen.dart';
import 'package:dg_chat/features/startup/presentation/onboarding_screen.dart';
import 'package:dg_chat/features/startup/presentation/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

abstract final class AppRoutes {
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const register = '/register';
  static const passwordReset = '/password-reset';
  static const chats = '/chats';
  static const contacts = '/contacts';
  static const settings = '/settings';
  static const userSearch = '/people/search';

  static const conversation = '/chats/room/:roomId';
  static const newGroup = '/groups/new';
  static const groupDetails = '/groups/:roomId';
  static const groupActivity = '/groups/:roomId/activity';

  static String groupActivityPath(String roomId) =>
      '/groups/${Uri.encodeComponent(roomId)}/activity';
  static const groupAddMembers = '/groups/:roomId/members/add';
  static const userProfile = '/people/:userId';
  static const blockedUsers = '/settings/blocked-users';
  static const emailAddress = '/settings/email';
  static const userManagement = '/settings/users';
  static const call = '/call/:roomId';
  static const meet = '/meet/:roomId';

  static String meetPath(String roomId) =>
      '/meet/${Uri.encodeComponent(roomId)}';

  static String callPath(
    String roomId, {
    required bool withVideo,
    required bool ring,
  }) =>
      '/call/${Uri.encodeComponent(roomId)}'
      '?video=${withVideo ? 1 : 0}&ring=${ring ? 1 : 0}';

  static String conversationPath(String roomId) =>
      '/chats/room/${Uri.encodeComponent(roomId)}';

  static String groupDetailsPath(String roomId) =>
      '/groups/${Uri.encodeComponent(roomId)}';

  static String groupAddMembersPath(String roomId) =>
      '/groups/${Uri.encodeComponent(roomId)}/members/add';

  static String userProfilePath(String userId) =>
      '/people/${Uri.encodeComponent(userId)}';
}

/// Where the app should boot for the URL it was opened on.
///
/// Routing lives in the fragment (`/#/chats/...`), but the link people are
/// handed for a meeting carries the code in the *path* —
/// `chat.example.com/meet/abc-defg-hij` — because a link someone reads
/// aloud or pastes into WhatsApp should not need a `#` in it. A path has an
/// empty fragment, and an empty fragment used to mean "start at splash":
/// the app booted, threw the meeting address away, and delivered the guest
/// to the chat list. Every meeting room on the server had exactly one
/// member — the person who created it.
///
/// Only the meet path is honoured. Everything else keeps booting through
/// splash, which is what decides between chats, login and onboarding.
@visibleForTesting
String initialLocationForUri(Uri base) {
  final segments = base.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length == 2 && segments.first == 'meet') {
    return AppRoutes.meetPath(segments[1]);
  }
  return AppRoutes.splash;
}

/// Starts or joins a call in [roomId], full screen over everything.
///
/// Deliberately not part of the /chats location: a call is modal, not a place
/// you deep-link into — refreshing a browser mid-call cannot resume media, so
/// encoding the call in the URL would restore a lie.
void openCall(
  BuildContext context,
  String roomId, {
  required bool withVideo,
  required bool ring,
}) {
  context.push(AppRoutes.callPath(roomId, withVideo: withVideo, ring: ring));
}

/// Opens a conversation by navigating to its address.
///
/// The open room lives in the location — `/chats/room/<id>` — and the layout
/// decides how that address renders: a wide window keeps the list beside it
/// and fills the detail pane, a phone stacks the conversation over the list.
/// One address for both is what makes a browser refresh restore the room,
/// back/forward walk through rooms, and a pasted link land a teammate in the
/// right conversation regardless of their screen.
///
/// Screens the user should not return to — people search, group creation —
/// need no special casing: `go` replaces the whole location, which pops them.
void openConversation(BuildContext context, String roomId, {String? eventId}) {
  final path = AppRoutes.conversationPath(roomId);
  context.go(
    eventId == null ? path : '$path?event=${Uri.encodeComponent(eventId)}',
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: initialLocationForUri(Uri.base),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const AuthenticationScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) =>
            const AuthenticationScreen(isRegistration: true),
      ),
      GoRoute(
        path: AppRoutes.passwordReset,
        builder: (context, state) => const PasswordResetScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(
          navigationShell: navigationShell,
          // The shell's state carries the sub-route's parameters, so the open
          // room comes straight from the location instead of a side channel.
          selectedRoomId: state.pathParameters['roomId'] == null
              ? null
              : Uri.decodeComponent(state.pathParameters['roomId']!),
          selectedEventId: state.uri.queryParameters['event'],
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.chats,
                builder: (context, state) => const ChatListScreen(),
                routes: [
                  GoRoute(
                    path: 'room/:roomId',
                    pageBuilder: (context, state) {
                      final roomId = Uri.decodeComponent(
                        state.pathParameters['roomId']!,
                      );
                      // A phone stacks the conversation over the list, so
                      // back returns to it. A wide window already shows the
                      // conversation in the detail pane the shell fills from
                      // this location, so the sidebar should still be the
                      // list.
                      //
                      // It used to get there by pushing a transparent, empty
                      // page and letting the real list show through from
                      // underneath. That works for painting and fails for
                      // touch: every route is a ModalRoute, every ModalRoute
                      // lays a ModalBarrier across the navigator, and that
                      // barrier is an opaque gesture detector. The list was
                      // visible and completely dead -- open one chat and no
                      // other row in the sidebar could be clicked again until
                      // the route was reset.
                      //
                      // So the page renders the list itself and is the thing
                      // being clicked. The key is constant on purpose: moving
                      // between rooms reuses this page instead of building a
                      // new one, which is what keeps the sidebar's scroll
                      // position and search text from resetting on every
                      // room change.
                      if (!context.windowSize.hasSidePanes) {
                        return MaterialPage(
                          key: state.pageKey,
                          child: ConversationScreen(
                            roomId: roomId,
                            initialEventId: state.uri.queryParameters['event'],
                          ),
                        );
                      }
                      return const NoTransitionPage(
                        key: ValueKey('chats-sidebar'),
                        child: ChatListScreen(),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.contacts,
                builder: (context, state) => const ContactsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.userSearch,
        builder: (context, state) => const UserSearchScreen(),
      ),
      // The address this route lived at before it moved under /chats. A web
      // tab or bookmark from an older build still resolves.
      GoRoute(
        path: '/conversation/:roomId',
        redirect: (context, state) => AppRoutes.conversationPath(
          Uri.decodeComponent(state.pathParameters['roomId']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.newGroup,
        builder: (context, state) => const NewGroupScreen(),
      ),
      GoRoute(
        path: AppRoutes.groupActivity,
        builder: (context, state) => GroupActivityScreen(
          roomId: Uri.decodeComponent(state.pathParameters['roomId']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.groupDetails,
        builder: (context, state) => GroupDetailsScreen(
          roomId: Uri.decodeComponent(state.pathParameters['roomId']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.groupAddMembers,
        builder: (context, state) => GroupAddMembersScreen(
          roomId: Uri.decodeComponent(state.pathParameters['roomId']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.userProfile,
        builder: (context, state) => UserProfileScreen(
          userId: Uri.decodeComponent(state.pathParameters['userId']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.blockedUsers,
        builder: (context, state) => const BlockedUsersScreen(),
      ),
      GoRoute(
        path: AppRoutes.emailAddress,
        builder: (context, state) => const EmailAddressScreen(),
      ),
      GoRoute(
        path: AppRoutes.userManagement,
        builder: (context, state) => const UserManagementScreen(),
      ),
      GoRoute(
        path: AppRoutes.meet,
        builder: (context, state) => MeetScreen(
          roomId: Uri.decodeComponent(state.pathParameters['roomId']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.call,
        builder: (context, state) => CallScreen(
          roomId: Uri.decodeComponent(state.pathParameters['roomId']!),
          withVideo: state.uri.queryParameters['video'] == '1',
          ring: state.uri.queryParameters['ring'] == '1',
          guestName: state.uri.queryParameters['guest'],
        ),
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});
