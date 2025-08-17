class TextUtils {
  /// Capitalizes the first letter of each word in a string
  static String capitalizeWords(String input) {
    if (input.isEmpty) return input;
    
    return input.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Capitalizes only the first letter of a string
  static String capitalizeFirst(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1);
  }

  /// Formats a name properly (capitalizes each word)
  static String formatName(String name) {
    return capitalizeWords(name.trim());
  }

  /// Formats a username (lowercase, no spaces)
  static String formatUsername(String username) {
    return username.toLowerCase().replaceAll(' ', '');
  }

  /// Formats trip title (capitalizes first letter of each word)
  static String formatTripTitle(String title) {
    return capitalizeWords(title.trim());
  }

  /// Formats location/destination names
  static String formatLocation(String location) {
    return capitalizeWords(location.trim());
  }

  /// Formats general text content (capitalizes first letter)
  static String formatContent(String content) {
    return capitalizeFirst(content.trim());
  }

  /// Formats bio text (capitalizes first letter)
  static String formatBio(String bio) {
    return capitalizeFirst(bio.trim());
  }
}