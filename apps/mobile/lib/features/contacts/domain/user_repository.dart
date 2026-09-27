class UserSearchResult {
  const UserSearchResult({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.avatarHeaders = const {},
  });

  final String userId;
  final String displayName;
  final Uri? avatarUrl;
  final Map<String, String> avatarHeaders;
}

enum UserFailureCode {
  invalidQuery,
  rateLimited,
  serverUnavailable,
  sessionExpired,

  unknown,
}

class UserFailure implements Exception {
  const UserFailure(this.code);

  final UserFailureCode code;
}

abstract interface class UserRepository {
  Future<List<UserSearchResult>> search(String query);

  /// Everyone on this homeserver, for the admin roster.
  Future<List<UserSearchResult>> listServerUsers();

  /// Opens a direct chat with [userId], reusing one that already exists.
  Future<String> startDirectConversation(String userId);
}
