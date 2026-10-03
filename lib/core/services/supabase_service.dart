/// سپابیس کی خدمت
/// Supabase Initialization & Client Accessor
///
/// ─────────────────────────────────────────────
/// DEVELOPER: to change Supabase credentials for a new madrassa,
/// edit  assets/.env  (copy from assets/.env.example).
/// Required keys: SUPABASE_URL and SUPABASE_ANON_KEY
/// ─────────────────────────────────────────────
///
/// SEC-H11: the auth session (access + refresh tokens) is persisted through
/// [SecureAuthStorage] (flutter_secure_storage — Keychain / EncryptedShared
/// Preferences / Credential Vault), never plaintext SharedPreferences.
/// A one-time migration copies any legacy plaintext session into secure
/// storage on first launch after the upgrade.

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../security/secure_auth_storage.dart';

class SupabaseService {
  SupabaseService._(); // private constructor — static-only class

  static bool _initialized = false;

  /// The secure session store in use. Exposed for tests and for the
  /// logout wipe (which must not delete the session — the SDK owns that).
  static SecureAuthStorage? _authStorage;
  static SecureAuthStorage? get authStorage => _authStorage;

  /// Global Supabase client. Use everywhere in the app.
  static SupabaseClient get client => Supabase.instance.client;

  /// Builds the auth options for [Supabase.initialize], factored out so
  /// unit tests can assert the secure adapters are wired without
  /// initializing the SDK (which needs platform channels).
  static FlutterAuthClientOptions buildAuthOptions(String supabaseUrl) {
    final persistSessionKey =
        'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';
    _authStorage = SecureAuthStorage(persistSessionKey: persistSessionKey);
    return FlutterAuthClientOptions(
      localStorage: _authStorage,
      pkceAsyncStorage: SecureGotrueAsyncStorage(),
      // The SDK's own deep-link observer turns recovery links
      // (io.supabase.madrasa360://login-callback) into PASSWORD_RECOVERY
      // events — required for the forgot-password flow.
      detectSessionInUri: true,
    );
  }

  /// Call once from main() before runApp().
  /// Idempotent — safe to call again on soft restart (see CrashScreen).
  static Future<void> init() async {
    if (_initialized) return;
    // Load .env from assets
    await dotenv.load(fileName: 'assets/.env');

    final url = dotenv.env['SUPABASE_URL']!;
    await Supabase.initialize(
      url: url,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      authOptions: buildAuthOptions(url),
      // Use implicit flow — more reliable for email/password auth on physical devices
      // (PKCE requires deep-link callback which can fail if app loses focus)
    );
    // Move any pre-SEC-H11 plaintext session into secure storage (best
    // effort — never blocks startup).
    await _authStorage?.migrateFromLegacy();
    _initialized = true;
  }

  /// Convenience: current logged-in Supabase user (nullable).
  static User? get currentUser => client.auth.currentUser;

  /// Convenience: true when a session exists.
  static bool get isSignedIn => currentUser != null;
}
