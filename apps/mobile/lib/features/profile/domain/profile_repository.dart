import 'dart:typed_data';

const int maxDisplayNameLength = 64;
const int maxAboutLength = 240;

/// A user as shown on the profile screen. [about] and [mobileNumber] are only
/// populated for the signed-in account: they live in private account data, so
/// the homeserver does not expose them for other users.
class UserProfile {
  const UserProfile({
    required this.userId,
    required this.displayName,
    required this.isSelf,
    this.about = '',
    this.mobileNumber,
    this.isBlocked = false,
    this.avatarUrl,
    this.avatarHeaders = const {},
  });

  final String userId;
  final String displayName;
  final bool isSelf;
  final String about;
  final String? mobileNumber;
  final bool isBlocked;
  final Uri? avatarUrl;
  final Map<String, String> avatarHeaders;
}

/// An image already reduced to avatar dimensions by the picker.
class AvatarUpload {
  const AvatarUpload({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

enum ProfileFailureCode {
  invalidDisplayName,
  invalidAbout,
  invalidMobileNumber,
  userNotFound,
  avatarTooLarge,
  notPermitted,
  rateLimited,
  serverUnavailable,
  sessionExpired,
  unknown,
}

class ProfileFailure implements Exception {
  const ProfileFailure(this.code);

  final ProfileFailureCode code;
}

abstract interface class ProfileRepository {
  /// Emits the profile and every later change to it, including block state.
  Stream<UserProfile> watchProfile(String userId);

  Future<void> updateDisplayName(String displayName);

  Future<void> updateAbout(String about);

  Future<void> updateMobileNumber(String? mobileNumber);

  Future<void> updateAvatar(AvatarUpload? avatar);

  /// The blocked users list, kept in sync with the Matrix ignore list.
  Stream<List<UserProfile>> watchBlockedUsers();

  Future<void> blockUser(String userId);

  Future<void> unblockUser(String userId);
}
