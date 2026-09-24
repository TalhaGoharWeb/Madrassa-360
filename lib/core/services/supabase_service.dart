/// سپابیس کی خدمت
/// Supabase Initialization & Client Accessor
///
/// ─────────────────────────────────────────────
/// DEVELOPER: to change Supabase credentials for a new madrassa,
/// edit  assets/.env  (copy from assets/.env.example).
/// Required keys: SUPABASE_URL and SUPABASE_ANON_KEY
/// ─────────────────────────────────────────────

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._(); // private constructor — static-only class

  /// Global Supabase client. Use everywhere in the app.
  static SupabaseClient get client => Supabase.instance.client;

  /// Call once from main() before runApp().
  static Future<void> init() async {
    // Load .env from assets
    await dotenv.load(fileName: 'assets/.env');

    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      // Use implicit flow — more reliable for email/password auth on physical devices
      // (PKCE requires deep-link callback which can fail if app loses focus)
    );
  }

  /// Convenience: current logged-in Supabase user (nullable).
  static User? get currentUser => client.auth.currentUser;

  /// Convenience: true when a session exists.
  static bool get isSignedIn => currentUser != null;
}
