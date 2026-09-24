/// تصدیق کرنے والے
/// Input Validation Utilities

class Validators {
  /// Validate if field is not empty
  static String? required(String? value, {String? fieldName}) {
    if (value == null || value.trim().isEmpty) {
      return '${fieldName ?? "یہ فیلڈ"} ضروری ہے';
    }
    return null;
  }

  /// Validate email format
  static String? email(String? value) {
    if (value == null || value.isEmpty) {
      return 'ای میل ضروری ہے';
    }
    
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    
    if (!emailRegex.hasMatch(value)) {
      return 'غلط ای میل فارمیٹ';
    }
    return null;
  }

  /// Validate phone number (Pakistani format)
  static String? phone(String? value) {
    if (value == null || value.isEmpty) {
      return 'فون نمبر ضروری ہے';
    }
    
    // Remove spaces and dashes
    final cleanPhone = value.replaceAll(RegExp(r'[\s-]'), '');
    
    // Pakistani phone numbers: 03xxxxxxxxx (11 digits) or +923xxxxxxxxx (13 chars)
    final phoneRegex = RegExp(r'^(03\d{9}|\+923\d{9})$');
    
    if (!phoneRegex.hasMatch(cleanPhone)) {
      return 'غلط فون نمبر فارمیٹ (03xxxxxxxxx)';
    }
    return null;
  }

  /// Validate CNIC format (Pakistani National ID)
  static String? cnic(String? value) {
    if (value == null || value.isEmpty) {
      return 'شناختی کارڈ نمبر ضروری ہے';
    }
    
    // Remove dashes
    final cleanCnic = value.replaceAll('-', '');
    
    // CNIC: 13 digits (xxxxx-xxxxxxx-x)
    final cnicRegex = RegExp(r'^\d{13}$');
    
    if (!cnicRegex.hasMatch(cleanCnic)) {
      return 'غلط شناختی کارڈ فارمیٹ (xxxxx-xxxxxxx-x)';
    }
    return null;
  }

  /// Validate minimum length
  static String? minLength(String? value, int length, {String? fieldName}) {
    if (value == null || value.isEmpty) {
      return '${fieldName ?? "یہ فیلڈ"} ضروری ہے';
    }
    
    if (value.length < length) {
      return '${fieldName ?? "یہ فیلڈ"} کم از کم $length حروف کا ہونا چاہیے';
    }
    return null;
  }

  /// Validate maximum length
  static String? maxLength(String? value, int length, {String? fieldName}) {
    if (value != null && value.length > length) {
      return '${fieldName ?? "یہ فیلڈ"} $length حروف سے زیادہ نہیں ہو سکتا';
    }
    return null;
  }

  /// Validate numeric value
  static String? numeric(String? value, {String? fieldName}) {
    if (value == null || value.isEmpty) {
      return '${fieldName ?? "یہ فیلڈ"} ضروری ہے';
    }
    
    if (double.tryParse(value) == null) {
      return '${fieldName ?? "یہ فیلڈ"} صرف نمبر ہونا چاہیے';
    }
    return null;
  }

  /// Validate positive number
  static String? positiveNumber(String? value, {String? fieldName}) {
    final numericError = numeric(value, fieldName: fieldName);
    if (numericError != null) return numericError;
    
    final number = double.parse(value!);
    if (number <= 0) {
      return '${fieldName ?? "یہ فیلڈ"} صفر سے زیادہ ہونا چاہیے';
    }
    return null;
  }

  /// Validate range
  static String? range(String? value, double min, double max, {String? fieldName}) {
    final numericError = numeric(value, fieldName: fieldName);
    if (numericError != null) return numericError;
    
    final number = double.parse(value!);
    if (number < min || number > max) {
      return '${fieldName ?? "یہ فیلڈ"} $min اور $max کے درمیان ہونا چاہیے';
    }
    return null;
  }

  /// Validate password strength
  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'پاسورڈ ضروری ہے';
    }
    
    if (value.length < 6) {
      return 'پاسورڈ کم از کم 6 حروف کا ہونا چاہیے';
    }
    
    // Optional: Add more complex password rules
    // if (!RegExp(r'[A-Z]').hasMatch(value)) {
    //   return 'پاسورڈ میں کم از کم ایک بڑا حرف ہونا چاہیے';
    // }
    
    return null;
  }

  /// Validate username
  static String? username(String? value) {
    if (value == null || value.isEmpty) {
      return 'صارف نام ضروری ہے';
    }
    
    if (value.length < 3) {
      return 'صارف نام کم از کم 3 حروف کا ہونا چاہیے';
    }
    
    // Only alphanumeric and underscore
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
      return 'صارف نام میں صرف حروف، نمبر اور (_) استعمال کر سکتے ہیں';
    }
    
    return null;
  }

  /// Validate roll number format
  static String? rollNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'رول نمبر ضروری ہے';
    }
    
    // Roll number should be alphanumeric
    if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(value)) {
      return 'غلط رول نمبر فارمیٹ';
    }
    
    return null;
  }

  /// Combine multiple validators
  static String? Function(String?) combine(
    List<String? Function(String?)> validators,
  ) {
    return (String? value) {
      for (final validator in validators) {
        final error = validator(value);
        if (error != null) return error;
      }
      return null;
    };
  }
}
