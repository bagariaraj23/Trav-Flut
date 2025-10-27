import 'dart:convert';
import 'package:tripthread/models/place.dart';

class PlaceSearchCache {
  static final Map<String, _CacheEntry> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 5);

  static void cacheResults(String query, List<Place> results) {
    _cache[_normalizeQuery(query)] = _CacheEntry(
      results: results,
      timestamp: DateTime.now(),
    );
  }

  static List<Place>? getResults(String query) {
    final entry = _cache[_normalizeQuery(query)];
    if (entry == null) return null;

    // Check if cache is still valid (within 5 minutes)
    if (DateTime.now().difference(entry.timestamp) > _cacheDuration) {
      _cache.remove(_normalizeQuery(query));
      return null;
    }

    return entry.results;
  }

  static void clearCache() {
    _cache.clear();
  }

  // Normalize query for consistent cache keys
  static String _normalizeQuery(String query) {
    return query.trim().toLowerCase();
  }
}

class _CacheEntry {
  final List<Place> results;
  final DateTime timestamp;

  _CacheEntry({
    required this.results,
    required this.timestamp,
  });
}