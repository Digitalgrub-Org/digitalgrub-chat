import 'package:dg_chat/features/contacts/domain/user_repository.dart';
import 'package:matrix/matrix.dart';

class MatrixUserRepository implements UserRepository {
  MatrixUserRepository(this._client);

  static const _resultLimit = 25;

  /// The roster is not a search, so it asks for far more than a search would.
  static const _rosterLimit = 500;

  final Client _client;

  @override
  Future<List<UserSearchResult>> listServerUsers() async {
    // The directory has no "list everyone" call, and an empty term returns
    // nothing. Every local user id ends in the server name, though, and the
    // directory matches on the id, so searching the server's own first label
    // enumerates the whole homeserver. Deactivated accounts are left out by
    // the directory itself, which is what an admin roster wants anyway.
    final userId = _client.userID ?? '';
    final colon = userId.indexOf(':');
    final serverName = colon == -1 ? '' : userId.substring(colon + 1);
    final label = serverName.split('.').first;
    if (label.length < 2) throw const UserFailure(UserFailureCode.unknown);
    final others = await _searchDirectory(label, limit: _rosterLimit);
    // The directory never returns the account doing the searching, so an
    // admin would otherwise be absent from their own roster and the total
    // would be short by one.
    if (others.any((user) => user.userId == userId)) return others;
    return [await _self(userId), ...others];
  }

  Future<UserSearchResult> _self(String userId) async {
    var displayName = userId;
    Uri? avatarUrl;
    try {
      final profile = await _client.getUserProfile(userId);
      final name = profile.displayname?.trim();
      if (name != null && name.isNotEmpty) displayName = name;
      final avatar = profile.avatarUrl;
      if (avatar != null) {
        final thumbnail = await avatar.getThumbnailUri(
          _client,
          width: 96,
          height: 96,
        );
        if (thumbnail.hasScheme) avatarUrl = thumbnail;
      }
    } catch (_) {
      // A missing profile is not worth failing the whole roster over.
    }
    return UserSearchResult(
      userId: userId,
      displayName: displayName,
      avatarUrl: avatarUrl,
      avatarHeaders: avatarUrl == null ? const {} : _mediaHeaders,
    );
  }

  @override
  Future<List<UserSearchResult>> search(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2) {
      throw const UserFailure(UserFailureCode.invalidQuery);
    }
    return _searchDirectory(normalized, limit: _resultLimit);
  }

  Future<List<UserSearchResult>> _searchDirectory(
    String term, {
    required int limit,
  }) async {
    try {
      final response = await _client.searchUserDirectory(term, limit: limit);
      final profiles = response.results.where(
        (profile) => profile.userId != _client.userID,
      );
      return await Future.wait(
        profiles.map((profile) async {
          Uri? avatarUrl;
          final avatar = profile.avatarUrl;
          if (avatar != null) {
            final thumbnail = await avatar.getThumbnailUri(
              _client,
              width: 96,
              height: 96,
            );
            if (thumbnail.hasScheme) avatarUrl = thumbnail;
          }
          return UserSearchResult(
            userId: profile.userId,
            displayName: profile.displayName?.trim().isNotEmpty == true
                ? profile.displayName!.trim()
                : profile.userId,
            avatarUrl: avatarUrl,
            avatarHeaders: avatarUrl == null ? const {} : _mediaHeaders,
          );
        }),
      );
    } on MatrixException catch (error) {
      throw _mapFailure(error);
    } on UserFailure {
      rethrow;
    } catch (_) {
      throw const UserFailure(UserFailureCode.serverUnavailable);
    }
  }

  @override
  Future<String> startDirectConversation(String userId) async {
    final normalized = userId.trim();
    if (!normalized.isValidMatrixIdStrict()) {
      throw const UserFailure(UserFailureCode.invalidQuery);
    }
    final String roomId;
    try {
      roomId = await _client.startDirectChat(
        normalized,
        enableEncryption: false,
      );
    } on MatrixException catch (error) {
      throw _mapFailure(error);
    } catch (_) {
      throw const UserFailure(UserFailureCode.serverUnavailable);
    }
    return roomId;
  }

  UserFailure _mapFailure(MatrixException error) {
    return switch (error.error) {
      MatrixError.M_LIMIT_EXCEEDED => const UserFailure(
        UserFailureCode.rateLimited,
      ),
      MatrixError.M_UNKNOWN_TOKEN => const UserFailure(
        UserFailureCode.sessionExpired,
      ),
      _ => const UserFailure(UserFailureCode.serverUnavailable),
    };
  }

  Map<String, String> get _mediaHeaders {
    final token = _client.accessToken;
    return token == null ? const {} : {'authorization': 'Bearer $token'};
  }
}
