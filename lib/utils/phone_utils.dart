class PhoneUtils {
  /// Normalizes a phone number to its last 10 digits for consistent comparison.
  static String normalize(String? phoneNo) {
    if (phoneNo == null || phoneNo.isEmpty) return '';

    // Remove all non-numeric characters
    String clean = phoneNo.replaceAll(RegExp(r'\D'), '');

    // Take last 10 digits
    if (clean.length > 10) {
      return clean.substring(clean.length - 10);
    }

    return clean;
  }
}
