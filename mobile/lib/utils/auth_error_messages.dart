/// Maps backend/technical auth error messages to user-friendly ones.
/// Similar to how apps like Gmail, Instagram show generic messages for login failures.
class AuthErrorMessages {
  AuthErrorMessages._();

  /// User-friendly message for wrong credentials (login).
  static const String loginCredentialsInvalid =
      'Username or password incorrect. Please check and try again.';

  /// User-friendly message for signup failures.
  static const String signupFailed =
      'Couldn\'t create account. Please check your details and try again.';

  /// User-friendly message for forgot password.
  static const String forgotPasswordFailed =
      'Couldn\'t send reset email. Please check the email and try again.';

  /// User-friendly message for reset password.
  static const String resetPasswordFailed =
      'Couldn\'t reset password. The link may have expired. Please request a new one.';

  /// User-friendly message for profile completion.
  static const String completeProfileFailed =
      'Couldn\'t complete profile. Please check your details and try again.';

  /// Technical phrases that should be replaced with user-friendly messages.
  static const List<String> _loginCredentialPhrases = [
    'authentication failed',
    'authentication error',
    'authentication required',
    'invalid credentials',
    'invalid email or password',
    'invalid username or password',
    'wrong password',
    'incorrect password',
    'unauthorized',
    'invalid login',
    'login failed',
    'invalid token',
  ];

  static const List<String> _genericAuthPhrases = [
    'token expired',
    'session expired',
  ];

  /// Returns a user-friendly message for login/sign-in errors.
  static String toLoginFriendly(String? message) {
    if (message == null || message.trim().isEmpty) {
      return loginCredentialsInvalid;
    }
    final lower = message.toLowerCase().trim();
    if (_loginCredentialPhrases.any((p) => lower.contains(p))) {
      return loginCredentialsInvalid;
    }
    if (_genericAuthPhrases.any((p) => lower.contains(p))) {
      return 'Please sign in again.';
    }
    // Backend may already return "Invalid email or password" - keep it
    if (lower.contains('invalid') && (lower.contains('email') || lower.contains('password'))) {
      return loginCredentialsInvalid;
    }
    return loginCredentialsInvalid;
  }

  /// Returns a user-friendly message for signup errors.
  static String toSignupFriendly(String? message) {
    if (message == null || message.trim().isEmpty) {
      return signupFailed;
    }
    final lower = message.toLowerCase().trim();
    if (_isUserFriendlyValidation(lower)) {
      return message;
    }
    if (_loginCredentialPhrases.any((p) => lower.contains(p)) ||
        _genericAuthPhrases.any((p) => lower.contains(p))) {
      return signupFailed;
    }
    return signupFailed;
  }

  /// Returns a user-friendly message for forgot-password errors.
  static String toForgotPasswordFriendly(String? message) {
    if (message == null || message.trim().isEmpty) {
      return forgotPasswordFailed;
    }
    final lower = message.toLowerCase().trim();
    if (_isUserFriendlyValidation(lower)) {
      return message;
    }
    return forgotPasswordFailed;
  }

  /// Returns a user-friendly message for reset-password errors.
  static String toResetPasswordFriendly(String? message) {
    if (message == null || message.trim().isEmpty) {
      return resetPasswordFailed;
    }
    final lower = message.toLowerCase().trim();
    if (_isUserFriendlyValidation(lower)) {
      return message;
    }
    if (lower.contains('expired') || lower.contains('invalid token')) {
      return 'This reset link has expired. Please request a new one.';
    }
    return resetPasswordFailed;
  }

  /// Returns a user-friendly message for complete-profile errors.
  static String toCompleteProfileFriendly(String? message) {
    if (message == null || message.trim().isEmpty) {
      return completeProfileFailed;
    }
    final lower = message.toLowerCase().trim();
    if (_isUserFriendlyValidation(lower)) {
      return message;
    }
    return completeProfileFailed;
  }

  static bool _isUserFriendlyValidation(String lower) {
    const keepPatterns = [
      'already in use',
      'already taken',
      'is taken',
      'must be',
      'required',
      'at least',
      'between',
      'invalid format',
      'invalid email',
    ];
    return keepPatterns.any((p) => lower.contains(p));
  }
}
