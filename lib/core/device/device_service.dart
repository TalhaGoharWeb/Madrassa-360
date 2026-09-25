/// ڈیوائس رجسٹریشن
/// Per-install device identity + registration in Supabase.
///
/// WHAT THIS IS NOT (deliberate design):
/// * NOT a hardware fingerprint — [deviceId] is a random v4 UUID minted on
///   first run and stored at `%APPDATA%\Madrassa360\device.json` (Windows)
///   or the platform app-support dir (other OSes). No MAC address, no disk
///   serial, no TPM handle, no advertising ID is ever collected.
/// * NOT a lock-out mechanism — users are NEVER blocked from signing in
///   because of device state. Revocation is admin-initiated (see the
///   `device_sessions` table and migration 018's enforcement contract);
///   a revoked device fails CLOSED only where the enforcement hook is
///   wired, and the app itself never bricks on revocation state.
/// * The identity file lives OUTSIDE the app database directory on
///   purpose: restoring a DB backup must NOT change the device identity.
///
/// CALL SITES (integrator):
/// ```dart
/// // after successful sign-in, once the active tenant is known:
/// await DeviceService.registerOnLogin(tenantId: tenantId);
/// // opportunistically, e.g. on app resume (never awaited critically):
/// unawaited(DeviceService.heartbeat());
/// // on sign-out (best-effort):
/// await DeviceService.closeSession();
/// ```

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../services/supabase_service.dart';
import '../update/app_version.dart';

class DeviceService {
  DeviceService._(); // static-only

  static const _identityFileName = 'device.json';
  static const _heartbeatPrefKey = 'device_last_heartbeat_ms';

  /// How often `last_active` may be written (server heartbeat throttle).
  static const heartbeatInterval = Duration(hours: 1);

  static String? _cachedDeviceId;

  // ─────────────────────────────────────────────
  // Identity: stable per-install UUID
  // ─────────────────────────────────────────────

  /// Returns the stable per-install device UUID, minting and persisting it
  /// on first run. Never throws — falls back to an in-memory UUID when the
  /// file cannot be written (the install simply re-registers next run).
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    try {
      final file = await _identityFile();
      if (await file.exists()) {
        final raw = await file.readAsString();
        final id = ((jsonDecode(raw) as Map<String, dynamic>)['device_id'] as String?)
            ?.trim();
        if (id != null && id.isNotEmpty) {
          return _cachedDeviceId = id;
        }
      }
      final fresh = const Uuid().v4();
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(
          jsonEncode({'device_id': fresh, 'created_at': DateTime.now().toIso8601String()}),
          flush: true,
        );
      } catch (_) {
        // Disk write failed — use the in-memory id; next run mints again.
      }
      return _cachedDeviceId = fresh;
    } catch (_) {
      final fallback = const Uuid().v4();
      return _cachedDeviceId = fallback;
    }
  }

  /// Identity file location.
  ///
  /// Windows: `%APPDATA%\Madrassa360\device.json` — deliberately NOT under
  /// the database/backup directory, so a DB restore never resets identity.
  /// Other platforms: `<app-support>/Madrassa360/device.json`.
  static Future<File> _identityFile() async {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return File('$appData\\Madrassa360\\$_identityFileName');
      }
      // Fall through to path_provider if %APPDATA% is somehow unset.
    }
    final support = await getApplicationSupportDirectory();
    return File('${support.path}${Platform.pathSeparator}Madrassa360'
        '${Platform.pathSeparator}$_identityFileName');
  }

  // ─────────────────────────────────────────────
  // Registration (called after login)
  // ─────────────────────────────────────────────

  /// Upserts this install into the `devices` table and opens a
  /// `device_sessions` row for the new login.
  ///
  /// Best-effort by contract: ANY failure is swallowed so registration can
  /// never fail a login. Callers must not depend on its completion.
  static Future<void> registerOnLogin({required String tenantId}) async {
    try {
      final client = SupabaseService.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null || tenantId.isEmpty) return;

      final deviceId = await getDeviceId();
      final appVersion = await readLocalAppVersion();
      final now = DateTime.now().toUtc().toIso8601String();

      String? deviceRowId;
      try {
        final upserted = await client.from('devices').upsert(
          {
            'device_id': deviceId,
            'user_id': userId,
            'tenant_id': tenantId,
            'os': Platform.operatingSystem,
            'os_version': Platform.operatingSystemVersion,
            'app_version': appVersion,
            'last_active': now,
          },
          onConflict: 'device_id',
        ).select('id').maybeSingle();
        deviceRowId = upserted?['id'] as String?;
      } catch (_) {
        // Registration upsert failed (offline, RLS, …) — login continues.
        return;
      }

      // Record this login as a session row (revocable by user/tenant admin).
      if (deviceRowId != null) {
        try {
          await client.from('device_sessions').insert({
            'device_id': deviceRowId,
            'user_id': userId,
            'tenant_id': tenantId,
          });
        } catch (_) {
          // Session row is advisory; ignore.
        }
      }

      // Mark the heartbeat clock so registerOnLogin counts as the first beat.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
            _heartbeatPrefKey, DateTime.now().millisecondsSinceEpoch);
      } catch (_) {}
    } catch (_) {
      // Absolute backstop: device registration must never fail login.
    }
  }

  /// Opportunistic `last_active` heartbeat, throttled to [heartbeatInterval].
  /// Best-effort: never throws, never awaited on a critical path.
  static Future<void> heartbeat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_heartbeatPrefKey) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - last <
          heartbeatInterval.inMilliseconds) {
        return; // Throttled.
      }

      final client = SupabaseService.client;
      if (client.auth.currentUser == null) return;

      final deviceId = await getDeviceId();
      await client.from('devices').update({
        'last_active': DateTime.now().toUtc().toIso8601String(),
      }).eq('device_id', deviceId);

      await prefs.setInt(
          _heartbeatPrefKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Heartbeat is telemetry — silence is the correct failure mode.
    }
  }

  /// Marks this install's open session rows as revoked on sign-out.
  /// Best-effort: never throws.
  ///
  /// NOTE: this is the *user's own* sign-out hygiene, not the admin
  /// revocation path (admins set `revoked_at` via RLS-guarded UPDATE, which
  /// the revoke-only trigger restricts to that single column, one-way).
  static Future<void> closeSession() async {
    try {
      final client = SupabaseService.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      final deviceId = await getDeviceId();
      final deviceRow = await client
          .from('devices')
          .select('id')
          .eq('device_id', deviceId)
          .maybeSingle();
      final deviceRowId = deviceRow?['id'] as String?;
      if (deviceRowId == null) return;

      await client.from('device_sessions').update({
        'revoked_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('device_id', deviceRowId).isFilter('revoked_at', null);
    } catch (_) {
      // Sign-out must never fail because of session bookkeeping.
    }
  }
}
