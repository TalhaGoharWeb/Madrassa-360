import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/app_theme.dart';
import 'core/constants/app_strings.dart';
import 'core/observability/app_logger.dart';
import 'core/observability/health_metrics.dart';
import 'core/update/update_service.dart';
import 'core/services/storage_service.dart';
import 'core/services/supabase_service.dart';
import 'core/services/tenant_context.dart';
import 'core/sync/sync_providers.dart';
import 'core/widgets/master_admin_guard.dart';
import 'data/local/app_database.dart';
import 'data/local/database_provider.dart';
import 'presentation/screens/crash_screen.dart';
import 'providers/tenant_branding_provider.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/master_admin/master_admin_shell.dart';

/// مدرسہ  360 — ایپ انٹری پوائنٹ
/// Madrasa 360 — Main Entry Point
///
/// Multi-tenant: institution identity (name, logo, contact, colours) is
/// loaded per-tenant at runtime from Supabase via tenantBrandingProvider —
/// no per-client source edits needed.
/// Supabase credentials:
///   assets/.env  (copy from assets/.env.example)
///
/// Features:
/// - RTL (Right-to-Left) Support for Urdu
/// - Noto Nastaliq Urdu Font
/// - Riverpod State Management
/// - Material 3 Design
/// - Supabase Backend + Offline Cache
///
/// Crash handling: the whole bootstrap runs inside [runZonedGuarded].
/// [FlutterError.onError] logs framework errors to the rotating file log;
/// uncaught async errors are persisted as crash reports under
/// %APPDATA%/Madrassa360/logs/crashes/ and surface a bilingual
/// [CrashScreen] with a soft-restart action.

// Keep in sync with version.json + pubspec.yaml (single source of truth
// lives in version.json; mirrored here for the session-start log marker).
const String kAppVersion = '1.0.0+1';

/// The shared local Drift database, opened once in [_bootstrap].
AppDatabase? _db;

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // File logging FIRST — everything below can log. Log dir:
    // %APPDATA%/Madrassa360/logs (Windows), never Program Files.
    await AppLogger().init(version: kAppVersion);

    // Health metrics: count this session as crash-free iff the previous
    // session exited cleanly. Best-effort; never throws.
    await HealthMetrics.instance.markSessionStarted();
    // Best-effort clean-exit marker for the NEXT session's crash-free count.
    // (Desktop: fires on window close; mobile: not guaranteed — documented
    // as a proxy, not a crash reporter.)
    WidgetsBinding.instance.addObserver(_CleanExitObserver());

    // Framework errors → file log (redacted). The framework renders
    // ErrorWidget for the broken subtree; the app keeps running.
    FlutterError.onError = (FlutterErrorDetails details) {
      AppLogger().error(
        'Flutter framework error: ${details.exceptionAsString()}',
        stackTrace: details.stack,
        context: {'library': details.library ?? 'unknown'},
      );
    };

    try {
      _db = await _bootstrap();
    } catch (e, st) {
      await AppLogger().logCrash('bootstrap', e, st);
      runApp(CrashScreen(
        onRestart: restartApp,
        details: _shortError(e),
      ));
      return;
    }
    _runMainApp();
  }, (Object error, StackTrace stack) {
    // Uncaught async error that escaped every local handler.
    // (SyncEngine's fire-and-forget calls catch+log their own errors, so
    // reaching here means something genuinely unexpected.)
    unawaited(AppLogger().logCrash('uncaught-async', error, stack));
    runApp(CrashScreen(
      onRestart: restartApp,
      details: _shortError(error),
    ));
  });
}

/// One-time startup: storage → Supabase → local DB → system chrome.
Future<AppDatabase> _bootstrap() async {
  // Initialize local storage
  await StorageService.init();

  // Initialize Supabase (idempotent — safe on soft restart)
  await SupabaseService.init();

  // Phase 5: the offline-first sync engine starts via Riverpod
  // (syncEngineProvider is watched in Madrasa360App below). The legacy
  // SharedPreferences queue (OfflineSyncService) is retired — local writes
  // go to Drift + sync_queue, pushed by SyncEngine.
  //
  // Phase 5 (worker 2): open the local Drift database. This is the single
  // instance shared by the whole app; sync_providers.dart consumes
  // appDatabaseProvider (also worker 2's) from here.
  final db = await openDatabase();

  // Set preferred orientations (Portrait only for now)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  return db;
}

/// Phoenix-style soft restart: close the DB, re-run bootstrap, re-invoke
/// runApp with a fresh widget tree — no process kill needed.
Future<void> restartApp() async {
  AppLogger().info('soft restart requested');
  try {
    await closeDatabase();
  } catch (e) {
    AppLogger().warning('closeDatabase during restart failed', error: e);
  }
  _db = null;
  // Session boundary marker so the log shows the restart clearly.
  AppLogger().info('── soft restart: new session ──');
  try {
    _db = await _bootstrap();
  } catch (e, st) {
    await AppLogger().logCrash('bootstrap-restart', e, st);
    runApp(CrashScreen(
      onRestart: restartApp,
      details: _shortError(e),
    ));
    return;
  }
  _runMainApp();
}

void _runMainApp() {
  runApp(
    // Wrap with ProviderScope for Riverpod. The local DB instance is
    // injected here so every repository / the sync engine shares it.
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(_db!),
      ],
      // UpdateGate must sit inside ProviderScope (it is a ConsumerStatefulWidget).
      child: const UpdateGate(child: Madrasa360App()),
    ),
  );
}

/// Redacted, truncated one-liner for the crash screen's details box.
String _shortError(Object e) {
  final s = '${AppLogger.redact('$e')}';
  return s.length > 240 ? '${s.substring(0, 240)}…' : s;
}

/// Best-effort clean-exit marker so the next session can count this one as
/// crash-free. Not a crash reporter — a proxy, as documented in HealthMetrics.
class _CleanExitObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(HealthMetrics.instance.markCleanShutdown());
    }
  }
}

/// مدرسہ 360 ایپ
/// Main Application Widget
class Madrasa360App extends StatelessWidget {
  const Madrasa360App({super.key});

  @override
  Widget build(BuildContext context) {
    // Phase 4: the whole app's accent colours and dark mode follow the
    // active tenant's branding (tenant_settings). Logged out / still
    // resolving → the neutral product theme.
    return Consumer(
      builder: (context, ref, _) {
        // Keep the file logger's tenant tag in sync with the active
        // tenant (org id only — never user PII).
        ref.listen<String?>(currentTenantIdProvider, (_, next) {
          AppLogger().setTenantId(next);
        });
        // Phase 5: start the per-tenant sync engine (idempotent; recreated
        // automatically on tenant switch by syncEngineProvider).
        // Coordinator TODO: wire WidgetsBindingObserver
        // (didChangeAppLifecycleState → resumed) to
        // ref.read(syncEngineProvider)?.notifyAppResumed().
        ref.watch(syncEngineProvider);
        final branding = ref.watch(tenantBrandingProvider).valueOrNull;
        final theme = branding == null
            ? AppTheme.lightTheme
            : AppTheme.lightTheme.withTenantBranding(branding);
        final dark = branding == null
            ? AppTheme.darkTheme
            : AppTheme.darkTheme.withTenantBranding(branding);
        return MaterialApp(
      // App Info
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,

      // Theme — tenant-driven accents
      theme: theme,
      darkTheme: dark,
      themeMode: (branding?.darkModeEnabled ?? false)
          ? ThemeMode.dark
          : ThemeMode.light,

      // ⭐ FORCE RTL (Right-to-Left) for Urdu
      locale: const Locale('ur', 'PK'),

      // Localization Delegates
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // Supported Locales
      supportedLocales: const [
        Locale('ur', 'PK'),  // Urdu - Pakistan (Primary)
        Locale('en', 'US'),  // English - US (Fallback)
      ],

      // Force RTL Text Direction
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },

      // Home Screen - Start with Login
      home: const LoginScreen(),

      // Named routes — '/master' is the platform-operator console, gated by
      // MasterAdminGuard (platform_admins lookup; fails closed).
      routes: {
        '/master': (_) => const MasterAdminGuard(
              child: MasterAdminShell(),
            ),
      },
        );
      },
    );
  }
}
