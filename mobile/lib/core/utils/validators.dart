/// Form field validators shared by the auth screens (tasks 1.2.5–1.2.7).
///
/// Client-side validation is a UX affordance only — it catches typos before a round
/// trip. Supabase re-validates on its side, and the database's constraints + RLS remain
/// the real authority (`MyBill.md` §11).
class Validators {
  const Validators._();

  /// Deliberately permissive: the only reliable proof an address works is a delivered
  /// email, so this rejects obvious typos without second-guessing valid exotic addresses.
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Matches the default minimum enforced by Supabase Auth; raising it here without
  /// raising it in the dashboard would only produce confusing client-side rejections.
  static const int minPasswordLength = 8;

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email is required';
    if (!_emailPattern.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Password is required';
    if (password.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if ((value ?? '').isEmpty) return 'Confirm your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }

  static String? required(String? value, String fieldName) {
    if ((value ?? '').trim().isEmpty) return '$fieldName is required';
    return null;
  }
}
