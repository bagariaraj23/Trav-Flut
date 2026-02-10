import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:tripthread/config/app_config.dart';

/// Result of calling Google Sign-In (native flow).
sealed class GoogleSignInNativeResult {}

class GoogleSignInNativeSuccess extends GoogleSignInNativeResult {
  final String idToken;
  GoogleSignInNativeSuccess(this.idToken);
}

class GoogleSignInNativeCancelled extends GoogleSignInNativeResult {}

/// ApiException 10 = DEVELOPER_ERROR (SHA-1 / OAuth client not configured).
class GoogleSignInNativeDeveloperError extends GoogleSignInNativeResult {}

class GoogleSignInNativeFailure extends GoogleSignInNativeResult {
  final String message;
  GoogleSignInNativeFailure(this.message);
}

class GoogleSignInService {
  GoogleSignIn? _googleSignIn;

  GoogleSignIn? get _client {
    _googleSignIn ??= GoogleSignIn(
      scopes: ['email', 'profile'],
      serverClientId: AppConfig.googleClientId.isNotEmpty
          ? AppConfig.googleClientId
          : null,
    );
    return _googleSignIn;
  }

  /// Triggers Google Sign-In. Returns success with idToken, cancelled, developerError (code 10), or failure.
  Future<GoogleSignInNativeResult> signIn() async {
    try {
      final account = await _client?.signIn();
      if (account == null) {
        return GoogleSignInNativeCancelled();
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        debugPrint('[GoogleSignInService] idToken not available');
        return GoogleSignInNativeFailure('ID token not returned');
      }
      return GoogleSignInNativeSuccess(idToken);
    } on PlatformException catch (e, st) {
      debugPrint('[GoogleSignInService] signIn error: $e\n$st');
      final code = e.code;
      final message = e.message ?? '';
      if (code == 'sign_in_failed' && message.contains('ApiException: 10')) {
        return GoogleSignInNativeDeveloperError();
      }
      return GoogleSignInNativeFailure(message.isNotEmpty ? message : 'Sign-in failed');
    } catch (e, st) {
      debugPrint('[GoogleSignInService] signIn error: $e\n$st');
      return GoogleSignInNativeFailure(e.toString());
    }
  }

  Future<void> signOut() async {
    try {
      await _client?.signOut();
    } catch (e) {
      debugPrint('[GoogleSignInService] signOut error: $e');
    }
  }
}
