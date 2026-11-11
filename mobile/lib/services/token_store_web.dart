import 'package:shared_preferences/shared_preferences.dart';

/// Browser session store for the Docker web UI.
///
/// `flutter_secure_storage` on web encrypts every write with WebCrypto and can
/// sit for minutes on the first login, which leaves the splash screen up after
/// the API has already returned. Local storage matches that package's actual
/// persistence (the browser has no keychain) without the stall.
class TokenStore {
  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> init() async {
    await _ensure();
  }

  Future<void> write({required String key, required String value}) async {
    await (await _ensure()).setString(key, value);
  }

  Future<String?> read({required String key}) async {
    return (await _ensure()).getString(key);
  }

  Future<void> delete({required String key}) async {
    await (await _ensure()).remove(key);
  }
}
