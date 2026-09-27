import 'package:dg_chat/features/profile/domain/profile_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Picking is abstracted so the platform picker can be replaced in tests and
/// so no feature layer depends on `image_picker` directly.
abstract interface class AvatarPicker {
  /// Returns the chosen image, or null when the user cancels.
  Future<AvatarUpload?> pick();
}

class ImagePickerAvatarPicker implements AvatarPicker {
  ImagePickerAvatarPicker([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  /// Avatars are only ever rendered small, so the picker downscales and
  /// re-encodes before the bytes reach us. This is the compression step the
  /// product requirements ask for.
  static const _maxDimension = 512.0;
  static const _quality = 85;

  final ImagePicker _picker;

  @override
  Future<AvatarUpload?> pick() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: _maxDimension,
      maxHeight: _maxDimension,
      imageQuality: _quality,
    );
    if (file == null) return null;
    return AvatarUpload(bytes: await file.readAsBytes(), fileName: file.name);
  }
}

final avatarPickerProvider = Provider<AvatarPicker>(
  (ref) => ImagePickerAvatarPicker(),
);
