// User labels: @username first when present, else name / id prefix.

String userPrimaryLabel({
  required String id,
  String? username,
  String? name,
}) {
  final u = username?.trim();
  if (u != null && u.isNotEmpty) return '@$u';
  final n = name?.trim();
  if (n != null && n.isNotEmpty) return n;
  final short = id.length >= 8 ? id.substring(0, 8) : id;
  return '@$short';
}

/// Secondary line: full name when it adds information beyond the handle.
String? userSecondaryName({String? username, String? name}) {
  final n = name?.trim();
  final u = username?.trim();
  if (n == null || n.isEmpty) return null;
  if (u != null && u.isNotEmpty && n.toLowerCase() == u.toLowerCase()) {
    return null;
  }
  return n;
}

/// First character for avatars: prefer username, then name.
String userAvatarInitial({String? username, String? name}) {
  final u = username?.trim();
  if (u != null && u.isNotEmpty) return u.substring(0, 1).toUpperCase();
  final n = name?.trim();
  if (n != null && n.isNotEmpty) return n.substring(0, 1).toUpperCase();
  return 'U';
}
