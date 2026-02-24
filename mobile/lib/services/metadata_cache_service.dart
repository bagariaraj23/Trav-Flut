import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripthread/models/follow_status.dart';
import 'package:tripthread/models/user.dart';

/// Persists current user metadata (profile, stats, follow requests) to local
/// storage so the app can show data immediately on launch and avoid repeated
/// DB fetches. Data is refreshed in the background after load.
class MetadataCacheService {
  static const String _keyPrefix = 'user_metadata_';
  static const String _cachedAtKeySuffix = '_cached_at';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  SharedPreferences get _store {
    final p = _prefs;
    if (p == null) {
      throw StateError(
        'MetadataCacheService not initialized. Call init() first.',
      );
    }
    return p;
  }

  String _key(String userId) => '$_keyPrefix$userId';
  String _cachedAtKey(String userId) => '${_keyPrefix}$userId$_cachedAtKeySuffix';

  /// Saves user metadata for [userId]. Pass null for any field to leave existing value unchanged (not used when saving full snapshot).
  Future<void> saveUserMetadata({
    required String userId,
    User? user,
    UserStats? stats,
    List<FollowRequestDto>? pendingFollowRequests,
  }) async {
    try {
      await init();
      final existing = await loadUserMetadata(userId);
      final userJson = user != null ? user.toJson() : existing['user'];
      final statsJson = stats != null ? stats.toJson() : existing['stats'];
      final requestsJson = pendingFollowRequests != null
          ? pendingFollowRequests
              .map((e) => _followRequestToJson(e))
              .toList()
          : existing['pendingFollowRequests'];

      final map = <String, dynamic>{
        if (userJson != null) 'user': userJson,
        if (statsJson != null) 'stats': statsJson,
        if (requestsJson != null) 'pendingFollowRequests': requestsJson,
        'cachedAt': DateTime.now().toUtc().toIso8601String(),
      };
      final jsonStr = jsonEncode(map);
      await _store.setString(_key(userId), jsonStr);
      await _store.setString(
        _cachedAtKey(userId),
        map['cachedAt'] as String,
      );
    } catch (e, st) {
      debugPrint('[MetadataCacheService] saveUserMetadata error: $e\n$st');
    }
  }

  /// Loads cached metadata for [userId]. Returns map with keys user (Map?), stats (Map?), pendingFollowRequests (List?), cachedAt (String?).
  Future<Map<String, dynamic>> loadUserMetadata(String userId) async {
    try {
      await init();
      final jsonStr = _store.getString(_key(userId));
      if (jsonStr == null || jsonStr.isEmpty) return {};
      final map = jsonDecode(jsonStr) as Map<String, dynamic>?;
      if (map == null) return {};
      return map;
    } catch (e, st) {
      debugPrint('[MetadataCacheService] loadUserMetadata error: $e\n$st');
      return {};
    }
  }

  /// Returns cached-at time for [userId], or null if not cached.
  Future<DateTime?> getCachedAt(String userId) async {
    try {
      await init();
      final s = _store.getString(_cachedAtKey(userId));
      if (s == null) return null;
      return DateTime.tryParse(s);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _followRequestToJson(FollowRequestDto e) {
    final m = e.toJson();
    m['follower'] = e.follower.toJson();
    return m;
  }

  /// Clears cached metadata for [userId] (e.g. on logout).
  Future<void> clearUserMetadata(String userId) async {
    try {
      await init();
      await _store.remove(_key(userId));
      await _store.remove(_cachedAtKey(userId));
    } catch (e, st) {
      debugPrint('[MetadataCacheService] clearUserMetadata error: $e\n$st');
    }
  }

  /// Clears all metadata keys (use on logout).
  Future<void> clearAll() async {
    try {
      await init();
      final keys = _store.getKeys().where(
            (k) => k.startsWith(_keyPrefix),
          );
      for (final k in keys) {
        await _store.remove(k);
      }
    } catch (e, st) {
      debugPrint('[MetadataCacheService] clearAll error: $e\n$st');
    }
  }
}
