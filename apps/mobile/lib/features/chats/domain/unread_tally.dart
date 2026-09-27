/// How much unread there is across every chat, and how that should read on a
/// browser tab.
///
/// Two numbers rather than one, because they mean different things to the
/// person reading them. [highlights] is "you were named" — someone is waiting
/// on you. [rooms] is "something arrived" — worth a glance, not an
/// interruption. Collapsing them into a single count is what makes a chat
/// with forty routine messages shout as loudly as the one that mentioned you.
class UnreadTally {
  const UnreadTally({required this.rooms, required this.highlights});

  static const none = UnreadTally(rooms: 0, highlights: 0);

  /// How many chats have anything unread. Deliberately a count of *chats*,
  /// not of messages: "3 conversations need you" survives someone pasting
  /// thirty lines into one of them, and a message count does not.
  final int rooms;

  /// Total messages that mention this account across every chat.
  final int highlights;

  bool get hasAnything => rooms > 0 || highlights > 0;

  @override
  bool operator ==(Object other) =>
      other is UnreadTally &&
      other.rooms == rooms &&
      other.highlights == highlights;

  @override
  int get hashCode => Object.hash(rooms, highlights);

  @override
  String toString() => 'UnreadTally(rooms: $rooms, highlights: $highlights)';
}

/// The window/tab title for [tally], given the app's own name.
///
/// A mention shows its count, because the number is the useful part — you
/// decide differently for one than for twelve. Plain unread gets a dot and no
/// number: the count would be noise, and a tab narrowed to its favicon cannot
/// show it anyway.
String titleForUnread(String appName, UnreadTally tally) {
  if (tally.highlights > 0) {
    final shown = tally.highlights > 99 ? '99+' : '${tally.highlights}';
    return '($shown) $appName';
  }
  if (tally.rooms > 0) return '• $appName';
  return appName;
}
