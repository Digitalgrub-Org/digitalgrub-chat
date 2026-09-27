/// The joining code inside whatever somebody pasted.
///
/// People arrive with the code alone (`abc-defg-hij`), the full link, the
/// link with a trailing slash or query, or the whole invitation email with
/// the link somewhere in the middle. All of those mean the same meeting,
/// so all of them resolve; anything without a code in it resolves to null.
///
/// Codes are lower-case letters in three dash-separated groups, the shape
/// the server mints. Anything else is not a code, however link-like it
/// looks -- a chat room id in a `/meet/` link is handled by the route
/// itself, not here.
String? parseMeetingCode(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final fromLink = RegExp(
    r'/meet/([a-z]{3}-[a-z]{4}-[a-z]{3})(?=[/?#\s]|$)',
    caseSensitive: false,
  ).firstMatch(text);
  if (fromLink != null) return fromLink.group(1)!.toLowerCase();
  final bare = RegExp(
    r'^([a-z]{3}-[a-z]{4}-[a-z]{3})$',
    caseSensitive: false,
  ).firstMatch(text);
  return bare?.group(1)?.toLowerCase();
}
