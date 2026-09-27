import 'dart:async';
import 'dart:typed_data';

import 'package:dg_chat/core/media/avatar_picker.dart';
import 'package:dg_chat/features/moderation/domain/report_repository.dart';
import 'package:dg_chat/features/profile/domain/profile_repository.dart';

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({Map<String, UserProfile>? profiles})
    : _profiles = profiles ?? {};

  final Map<String, UserProfile> _profiles;
  final _updates = StreamController<UserProfile>.broadcast();
  final _blockedUpdates = StreamController<List<UserProfile>>.broadcast();

  final List<String> displayNames = [];
  final List<String> abouts = [];
  final List<String?> mobileNumbers = [];
  final List<AvatarUpload?> avatars = [];
  final List<String> blocked = [];
  final List<String> unblocked = [];

  ProfileFailure? failure;

  @override
  Stream<UserProfile> watchProfile(String userId) async* {
    final profile = _profiles[userId];
    if (profile == null) {
      throw const ProfileFailure(ProfileFailureCode.userNotFound);
    }
    yield profile;
    yield* _updates.stream.where((update) => update.userId == userId);
  }

  void emit(UserProfile profile) {
    _profiles[profile.userId] = profile;
    _updates.add(profile);
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    displayNames.add(displayName);
    _throwIfConfigured();
  }

  @override
  Future<void> updateAbout(String about) async {
    abouts.add(about);
    _throwIfConfigured();
  }

  @override
  Future<void> updateMobileNumber(String? mobileNumber) async {
    mobileNumbers.add(mobileNumber);
    _throwIfConfigured();
  }

  @override
  Future<void> updateAvatar(AvatarUpload? avatar) async {
    avatars.add(avatar);
    _throwIfConfigured();
  }

  @override
  Stream<List<UserProfile>> watchBlockedUsers() async* {
    yield _profiles.values
        .where((profile) => profile.isBlocked)
        .toList(growable: false);
    yield* _blockedUpdates.stream;
  }

  void emitBlocked(List<UserProfile> users) => _blockedUpdates.add(users);

  @override
  Future<void> blockUser(String userId) async {
    blocked.add(userId);
    _throwIfConfigured();
  }

  @override
  Future<void> unblockUser(String userId) async {
    unblocked.add(userId);
    _throwIfConfigured();
  }

  void _throwIfConfigured() {
    final value = failure;
    if (value != null) throw value;
  }

  Future<void> dispose() async {
    await _updates.close();
    await _blockedUpdates.close();
  }
}

class FakeReportRepository implements ReportRepository {
  final List<ContentReport> submitted = [];
  ReportFailure? failure;

  @override
  Future<void> submit(ContentReport report) async {
    submitted.add(report);
    final value = failure;
    if (value != null) throw value;
  }
}

class FakeAvatarPicker implements AvatarPicker {
  FakeAvatarPicker({this.result, this.throwOnPick = false});

  AvatarUpload? result;
  bool throwOnPick;
  int pickCount = 0;

  static AvatarUpload sample() => AvatarUpload(
    bytes: Uint8List.fromList(const [1, 2, 3, 4]),
    fileName: 'avatar.jpg',
  );

  @override
  Future<AvatarUpload?> pick() async {
    pickCount++;
    if (throwOnPick) throw StateError('picker unavailable');
    return result;
  }
}
