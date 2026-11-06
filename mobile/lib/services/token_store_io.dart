import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keychain / encrypted store used by the iOS, Android, and desktop builds.
class TokenStore {
  late final FlutterSecureStorage _storage;

  Future<void> init() async {
    _storage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );
  }

  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  Future<String?> read({required String key}) {
    return _storage.read(key: key);
  }

  Future<void> delete({required String key}) {
    return _storage.delete(key: key);
  }
}
