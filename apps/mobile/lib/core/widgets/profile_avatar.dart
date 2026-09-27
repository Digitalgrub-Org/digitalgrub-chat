import 'package:dg_chat/core/widgets/authenticated_network_image.dart';
import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.label,
    this.imageUrl,
    this.httpHeaders = const {},
    this.radius = 24,
    this.online,
    super.key,
  });

  final String label;
  final Uri? imageUrl;
  final Map<String, String> httpHeaders;
  final double radius;

  /// True draws the presence dot; false draws nothing rather than a grey
  /// one, because "offline" is most people most of the time and a grey dot
  /// on every row is a page full of noise. Null means presence does not
  /// apply here -- a group, or a screen that does not show it.
  final bool? online;

  @override
  Widget build(BuildContext context) {
    final initial = label.trim().isEmpty ? '?' : label.trim()[0].toUpperCase();
    final fallback = Center(
      child: Text(
        initial,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final avatar = Semantics(
      image: true,
      label: label,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: ClipOval(
          child: SizedBox.square(
            dimension: radius * 2,
            child: imageUrl == null
                ? fallback
                : AuthenticatedNetworkImage(
                    url: imageUrl!,
                    headers: httpHeaders,
                    fit: BoxFit.cover,
                    placeholder: (_) => fallback,
                    error: (_) => fallback,
                  ),
          ),
        ),
      ),
    );
    if (online != true) return avatar;
    // Ringed in the surface colour so the dot reads against a photo as well
    // as against the initial.
    final dot = radius * 0.4;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            key: const ValueKey('presence-dot'),
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF2FBF71),
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
