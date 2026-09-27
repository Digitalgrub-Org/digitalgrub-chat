import 'dart:async';

import 'package:dg_chat/features/profile/domain/profile_repository.dart';
import 'package:flutter/foundation.dart' show debugPrint;
// The SDK exports its own `UserProfile`; the domain type is the one meant here.
import 'package:matrix/matrix.dart' hide UserProfile;

class MatrixProfileRepository implements ProfileRepository {
  MatrixProfileRepository(this._client);

  /// Shared with the registration flow, which seeds the mobile number here.
  static const privateProfileType = 'com.digitalgrub.profile';
  static const _maxAvatarBytes = 2 * 1024 * 1024;

  final Client _client;

  @override
  Stream<UserProfile> watchProfile(String userId) async* {
    yield await _readProfile(userId);

    // Profile edits, avatar changes, and ignore-list updates all land as sync
    // responses, so one signal covers every field on this screen.
    await for (final _ in _client.onSync.stream) {
      yield await _readProfile(userId);
    }
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    final value = displayName.trim();
    if (value.isEmpty || value.length > maxDisplayNameLength) {
      throw const ProfileFailure(ProfileFailureCode.invalidDisplayName);
    }
    final userId = _requireUserId();
    await _guard(
      () => _client.setProfileField(userId, 'displayname', {
        'displayname': value,
      }),
    );
  }

  @override
  Future<void> updateAbout(String about) async {
    final value = about.trim();
    if (value.length > maxAboutLength) {
      throw const ProfileFailure(ProfileFailureCode.invalidAbout);
    }
    await _updatePrivateProfile({'about': value});
  }

  @override
  Future<void> updateMobileNumber(String? mobileNumber) async {
    final value = mobileNumber?.trim() ?? '';
    if (value.isNotEmpty && !_mobileNumberPattern.hasMatch(value)) {
      throw const ProfileFailure(ProfileFailureCode.invalidMobileNumber);
    }
    await _updatePrivateProfile({
      'mobile_number': value.isEmpty ? null : value,
      // Editing the number cannot vouch for it; SMS verification is not built.
      'mobile_number_verified': false,
    });
  }

  @override
  Future<void> updateAvatar(AvatarUpload? avatar) async {
    if (avatar != null && avatar.bytes.lengthInBytes > _maxAvatarBytes) {
      throw const ProfileFailure(ProfileFailureCode.avatarTooLarge);
    }
    await _guard(
      () => _client.setAvatar(
        avatar == null
            ? null
            : MatrixFile(bytes: avatar.bytes, name: avatar.fileName),
      ),
    );
  }

  @override
  Stream<List<UserProfile>> watchBlockedUsers() async* {
    yield await _readBlockedUsers();

    await for (final _ in _client.onSync.stream) {
      yield await _readBlockedUsers();
    }
  }

  /// Blocks [userId], and reports them to the homeserver's moderators.
  ///
  /// App Review guideline 1.2 asks that blocking also notify the developer,
  /// so every block is a report too: the same endpoint the Report button
  /// uses, with a reason that says it came from a block. The report is best
  /// effort. The block is what the person asked for and it has already
  /// happened, so a report the server refuses must not come back as an error.
  @override
  Future<void> blockUser(String userId) async {
    final value = _requireOtherUser(userId);
    await _guard(() => _client.ignoreUser(value));
    try {
      await _client.reportUser(value, _blockReport(value));
    } catch (error) {
      debugPrint('Block was not reported: ${error.runtimeType}');
    }
  }

  /// The same shape as a Report button submission, so moderators read one
  /// format whichever way a report arrived.
  String _blockReport(String userId) => [
    'category: blocked',
    'reported_user: $userId',
    'reported_at: ${DateTime.now().toUtc().toIso8601String()}',
    'comment: Blocked by the reporting user.',
  ].join('\n');

  @override
  Future<void> unblockUser(String userId) async {
    final value = _requireOtherUser(userId);
    await _guard(() => _client.unignoreUser(value));
  }

  Future<UserProfile> _readProfile(String userId) async {
    final isSelf = userId == _client.userID;
    Profile? profile;
    try {
      profile = await _client.getProfileFromUserId(userId);
    } on MatrixException catch (error) {
      if (error.error == MatrixError.M_NOT_FOUND) {
        throw const ProfileFailure(ProfileFailureCode.userNotFound);
      }
      // A lookup failure should not blank an otherwise usable screen.
    } catch (_) {
      // Same: fall back to the identifier below.
    }

    final avatarUrl = await _thumbnail(profile?.avatarUrl);
    final displayName = profile?.displayName?.trim();
    final private = isSelf ? await _readPrivateProfile() : const {};

    return UserProfile(
      userId: userId,
      displayName: displayName == null || displayName.isEmpty
          ? userId
          : displayName,
      isSelf: isSelf,
      about: private['about'] as String? ?? '',
      mobileNumber: private['mobile_number'] as String?,
      isBlocked: !isSelf && _client.ignoredUsers.contains(userId),
      avatarUrl: avatarUrl,
      avatarHeaders: avatarUrl == null ? const {} : _mediaHeaders,
    );
  }

  Future<List<UserProfile>> _readBlockedUsers() async {
    final blocked = _client.ignoredUsers;
    final profiles = await Future.wait(
      blocked.map((userId) async {
        String? displayName;
        Uri? avatarUrl;
        try {
          final profile = await _client.getProfileFromUserId(userId);
          displayName = profile.displayName?.trim();
          avatarUrl = await _thumbnail(profile.avatarUrl);
        } catch (_) {
          // A blocked user must stay unblockable even when unreachable.
        }
        return UserProfile(
          userId: userId,
          displayName: displayName == null || displayName.isEmpty
              ? userId
              : displayName,
          isSelf: false,
          isBlocked: true,
          avatarUrl: avatarUrl,
          avatarHeaders: avatarUrl == null ? const {} : _mediaHeaders,
        );
      }),
    );
    profiles.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return profiles;
  }

  Future<Map<String, Object?>> _readPrivateProfile() async {
    final content = _client.accountData[privateProfileType]?.content;
    return content ?? const {};
  }

  /// Merges into the existing private profile so one field cannot erase another.
  Future<void> _updatePrivateProfile(Map<String, Object?> changes) async {
    final userId = _requireUserId();
    final current = Map<String, Object?>.from(await _readPrivateProfile());
    for (final entry in changes.entries) {
      if (entry.value == null) {
        current.remove(entry.key);
      } else {
        current[entry.key] = entry.value;
      }
    }
    await _guard(
      () => _client.setAccountData(userId, privateProfileType, current),
    );
  }

  Future<Uri?> _thumbnail(Uri? source) async {
    if (source == null) return null;
    try {
      final thumbnail = await source.getThumbnailUri(
        _client,
        width: 192,
        height: 192,
      );
      return thumbnail.hasScheme ? thumbnail : null;
    } catch (_) {
      return null;
    }
  }

  String _requireUserId() {
    final userId = _client.userID;
    if (userId == null) {
      throw const ProfileFailure(ProfileFailureCode.sessionExpired);
    }
    return userId;
  }

  String _requireOtherUser(String userId) {
    final value = userId.trim();
    if (!value.isValidMatrixIdStrict() || value == _client.userID) {
      throw const ProfileFailure(ProfileFailureCode.notPermitted);
    }
    return value;
  }

  Map<String, String> get _mediaHeaders {
    final token = _client.accessToken;
    return token == null ? const {} : {'authorization': 'Bearer $token'};
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on MatrixException catch (error) {
      throw _mapFailure(error);
    } on ProfileFailure {
      rethrow;
    } catch (_) {
      throw const ProfileFailure(ProfileFailureCode.serverUnavailable);
    }
  }

  ProfileFailure _mapFailure(MatrixException error) {
    return switch (error.error) {
      MatrixError.M_FORBIDDEN => const ProfileFailure(
        ProfileFailureCode.notPermitted,
      ),
      MatrixError.M_LIMIT_EXCEEDED => const ProfileFailure(
        ProfileFailureCode.rateLimited,
      ),
      MatrixError.M_UNKNOWN_TOKEN => const ProfileFailure(
        ProfileFailureCode.sessionExpired,
      ),
      MatrixError.M_NOT_FOUND => const ProfileFailure(
        ProfileFailureCode.userNotFound,
      ),
      MatrixError.M_TOO_LARGE => const ProfileFailure(
        ProfileFailureCode.avatarTooLarge,
      ),
      _ => const ProfileFailure(ProfileFailureCode.serverUnavailable),
    };
  }
}

final _mobileNumberPattern = RegExp(r'^\+?[0-9 \-]{7,20}$');
