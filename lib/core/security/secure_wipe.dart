/// محفوظ صفائی
/// Secure tenant-data wipe (SEC-H12) — run on sign-out and account switch.
///
/// On shared school devices the next device user must not inherit the
/// previous tenant's data. This wipes, best-effort and never throwing:
///   1. the sync engine (stops all network sync),
///   2. the local Drift database file (+ WAL/SHM/journal) and re-creates an
///      empty one,
///   3. the Flutter image cache + cached_network_image disk cache,
///   4. the `Madrassa360` support dir (logo/report/branding caches),
///   5. SharedPreferences except an allowlist of non-sensitive UI settings.
///
/// The Supabase session itself is revoked separately by `auth.signOut()`
/// (which clears the secure-storage session via [SecureAuthStorage]).

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../observability/app_logger.dart';
import '../sync/sync_providers.dart';

class SecureWipe {
  SecureWipe._();

  /// Non-sensitive UI-only preference keys that survive the wipe.
  /// Everything else in SharedPreferences is deleted (auth state, tenant
  /// choice, remembered e-mail, profile name, permission/delegation caches,
  /// and any legacy plaintext session key from pre-SEC-H11 installs).
  static const Set<String> _prefsAllowlist = {
    'update_dismissed_version',
  };

  /// Wipe all tenant data for the signed-out / switched-away account.
  /// Safe to call when already wiped; never throws.
  static Future<void> wipeOnSignOut(Ref ref) async {
    // 1. Stop the sync engine first — no more network or DB writes.
    try {
      ref.invalidate(syncEngineProvider);
    } catch (e) {
      AppLogger().warning('[Wipe] sync engine invalidate failed', error: e);
    }

    // 2. Close, delete and re-create the local database.
    try {
      await wipeAndReopenDatabase();
      ref.invalidate(appDatabaseProvider);
    } catch (e) {
      AppLogger().warning('[Wipe] database wipe failed', error: e);
    }

    // 3. Image caches (memory + disk).
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (e) {
      AppLogger().warning('[Wipe] image cache clear failed', error: e);
    }
    try {
      await DefaultCacheManager().emptyCache();
    } catch (e) {
      AppLogger().warning('[Wipe] disk image cache clear failed', error: e);
    }

    // 4. Branding / report caches under <support>/Madrassa360.
    try {
      final supportDir =
          testSupportDirOverride ?? await getApplicationSupportDirectory();
      final dir = Directory(p.join(supportDir.path, 'Madrassa360'));
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
    } catch (e) {
      AppLogger().warning('[Wipe] support-dir clear failed', error: e);
    }

    // 5. SharedPreferences — everything except the UI allowlist.
    try {
      final prefs = await SharedPreferences.getInstance();
      final doomed = prefs.getKeys().where((k) => !_prefsAllowlist.contains(k));
      for (final key in doomed) {
        await prefs.remove(key);
      }
    } catch (e) {
      AppLogger().warning('[Wipe] preferences clear failed', error: e);
    }

    AppLogger().info('[Wipe] tenant data wiped on sign-out');
  }
}
