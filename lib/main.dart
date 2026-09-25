import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/app_theme.dart';
import 'core/constants/app_strings.dart';
import 'core/services/storage_service.dart';
import 'core/services/supabase_service.dart';
import 'core/sync/sync_providers.dart';
import 'core/widgets/master_admin_guard.dart';
import 'data/local/database_provider.dart';
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
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize local storage
  await StorageService.init();

  // Initialize Supabase
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
  SystemChrome.setPreferredOrientations([
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

  runApp(
    // Wrap with ProviderScope for Riverpod. The local DB instance is
    // injected here so every repository / the sync engine shares it.
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: const Madrasa360App(),
    ),
  );
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
