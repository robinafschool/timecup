import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Reads Supabase connection details from the environment, loaded from a
/// local `.env` file (see `.env.example` for the required keys). `.env` is
/// gitignored, so these values are never committed.
class SupabaseConfig {
  static String get url => dotenv.env['SUPABASE_URL'] ?? '';
  static String get publishableKey =>
      dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ?? '';
}
