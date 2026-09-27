import 'package:flutter/material.dart';

/// Time of day for today, day/month for anything older -- the compact form
/// every chat row uses, and the one a "last seen" reads in.
String formatChatTimestamp(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
  }
  return '${local.day}/${local.month}';
}
