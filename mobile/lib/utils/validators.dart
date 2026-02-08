class Validators {
  // Email validation
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }
    
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    
    if (value.length > 255) {
      return 'Email must be less than 255 characters';
    }
    
    return null;
  }

  // Password validation
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    
    if (value.length > 128) {
      return 'Password must be less than 128 characters';
    }
    
    // Check for at least one lowercase letter
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain at least one lowercase letter';
    }
    
    // Check for at least one uppercase letter
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain at least one uppercase letter';
    }
    
    // Check for at least one digit
    if (!RegExp(r'\d').hasMatch(value)) {
      return 'Password must contain at least one number';
    }
    
    return null;
  }

  // Name validation
  static String? validateName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Name is required';
    }
    
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      return 'Name must be at least 2 characters';
    }
    
    if (trimmed.length > 100) {
      return 'Name must be less than 100 characters';
    }
    
    final nameRegex = RegExp(r"^[a-zA-Z\s'-]+$");
    if (!nameRegex.hasMatch(trimmed)) {
      return 'Name can only contain letters, spaces, hyphens, and apostrophes';
    }
    
    return null;
  }

  // Username validation
  static String? validateUsername(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Username is optional
    }
    
    final trimmed = value.trim();
    if (trimmed.length < 3) {
      return 'Username must be at least 3 characters';
    }
    
    if (trimmed.length > 30) {
      return 'Username must be less than 30 characters';
    }
    
    final usernameRegex = RegExp(r'^[a-zA-Z0-9_]+$');
    if (!usernameRegex.hasMatch(trimmed)) {
      return 'Username can only contain letters, numbers, and underscores';
    }
    
    return null;
  }

  // Bio validation
  static String? validateBio(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Bio is optional
    }
    
    if (value.length > 200) {
      return 'Bio must be 200 characters or less';
    }
    
    return null;
  }

  // Trip title validation
  static String? validateTripTitle(String? value) {
    if (value == null || value.isEmpty) {
      return 'Trip title is required';
    }
    
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Trip title cannot be empty';
    }
    
    if (trimmed.length > 100) {
      return 'Trip title must be less than 100 characters';
    }
    
    return null;
  }

  // Trip description validation
  static String? validateTripDescription(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Description is optional
    }
    
    if (value.length > 500) {
      return 'Description must be less than 500 characters';
    }
    
    return null;
  }

  // Destination validation
  static String? validateDestination(String? value) {
    if (value == null || value.isEmpty) {
      return 'Destination is required';
    }
    
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Destination cannot be empty';
    }
    
    if (trimmed.length > 100) {
      return 'Destination name is too long';
    }
    
    return null;
  }

  // Thread entry content validation
  static String? validateThreadContent(String? value, {required String type}) {
    switch (type.toUpperCase()) {
      case 'TEXT':
        if (value == null || value.trim().isEmpty) {
          return 'Text content is required';
        }
        break;
      case 'LOCATION':
        if (value == null || value.trim().isEmpty) {
          return 'Location name is required';
        }
        break;
      default:
        break;
    }
    
    if (value != null && value.length > 1000) {
      return 'Content must be less than 1000 characters';
    }
    
    return null;
  }

  // Location name validation
  static String? validateLocationName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Location name is required';
    }
    
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Location name cannot be empty';
    }
    
    if (trimmed.length > 200) {
      return 'Location name must be less than 200 characters';
    }
    
    return null;
  }

  // URL validation
  static String? validateUrl(String? value) {
    if (value == null || value.isEmpty) {
      return null; // URL is optional
    }
    
    final urlRegex = RegExp(
      r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)$'
    );
    
    if (!urlRegex.hasMatch(value)) {
      return 'Please enter a valid URL';
    }
    
    if (value.length > 2048) {
      return 'URL is too long';
    }
    
    return null;
  }

  // Date validation
  static String? validateDate(DateTime? value, {DateTime? minDate, DateTime? maxDate}) {
    if (value == null) {
      return null; // Date is optional
    }
    
    if (minDate != null && value.isBefore(minDate)) {
      return 'Date cannot be in the past';
    }
    
    if (maxDate != null && value.isAfter(maxDate)) {
      return 'Date is too far in the future';
    }
    
    return null;
  }

  // Date range validation
  static String? validateDateRange(DateTime? startDate, DateTime? endDate) {
    if (startDate == null || endDate == null) {
      return null;
    }
    
    if (endDate.isBefore(startDate)) {
      return 'End date must be after start date';
    }
    
    return null;
  }

  // File validation
  static String? validateFile(String? filename, int? fileSize) {
    if (filename == null || filename.isEmpty) {
      return 'File is required';
    }
    
    // Check file extension
    final allowedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'mp4', 'mov', 'avi'];
    final extension = filename.split('.').last.toLowerCase();
    
    if (!allowedExtensions.contains(extension)) {
      return 'File type not supported';
    }
    
    // Check file size (50MB limit)
    if (fileSize != null && fileSize > 50 * 1024 * 1024) {
      return 'File size cannot exceed 50MB';
    }
    
    return null;
  }

  // Sanitize input to prevent XSS
  static String sanitizeInput(String input) {
    return input
        .trim()
        .replaceAll(RegExp(r'[<>]'), '') // Remove potential HTML tags
        .replaceAll(RegExp(r'javascript:', caseSensitive: false), '') // Remove javascript: protocol
        .replaceAll(RegExp(r'on\w+=', caseSensitive: false), ''); // Remove event handlers
  }
}