import 'package:dg_chat/features/notifications/data/tab_badge.dart';

/// The mobile side of the conditional import. Android and iOS badge the app
/// icon through the system notification centre, not through anything here,
/// but the code still has to compile for them.
class _NoTabToBadge implements TabBadge {
  const _NoTabToBadge();

  @override
  void show({required bool marked}) {}
}

TabBadge createTabBadge() => const _NoTabToBadge();
