// User labels: prefer username (no @) or full name. No handle prefix in UI.

String userPrimaryLabel({
  required String id,
  String? username,
  String? name,
}) {
  final u = username?.trim();
  if (u != null && u.isNotEmpty) return u;
  final n = name?.trim();
  if (n != null && n.isNotEmpty) return n;
  final short = id.length >= 8 ? id.substring(0, 8) : id;
  return short;
}

/// Prefer full name (first + last) for money / settlements; fall back to username.
String userPersonName({
  required String id,
  String? username,
  String? name,
}) {
  final n = name?.trim();
  if (n != null && n.isNotEmpty) return n;
  return userPrimaryLabel(id: id, username: username, name: name);
}

/// Secondary line: full name when it adds information beyond the username.
String? userSecondaryName({String? username, String? name}) {
  final n = name?.trim();
  final u = username?.trim();
  if (n == null || n.isEmpty) return null;
  if (u != null && u.isNotEmpty && n.toLowerCase() == u.toLowerCase()) {
    return null;
  }
  return n;
}

/// First character for avatars: prefer name, then username.
String userAvatarInitial({String? username, String? name}) {
  final n = name?.trim();
  if (n != null && n.isNotEmpty) return n.substring(0, 1).toUpperCase();
  final u = username?.trim();
  if (u != null && u.isNotEmpty) return u.substring(0, 1).toUpperCase();
  return 'U';
}
