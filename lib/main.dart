import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/app_theme.dart';
import 'core/constants/app_strings.dart';
import 'core/services/offline_sync_service.dart';
import 'core/services/storage_service.dart';
import 'core/services/supabase_service.dart';
import 'core/widgets/master_admin_guard.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/master_admin/master_admin_shell.dart';

/// مدرسہ  360 — ایپ انٹری پوائنٹ
/// Madrasa 360 — Main Entry Point
/// 
/// Deploy for a new madrassa? Edit ONE file:
///   lib/core/config/madrassa_config.dart
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

  // Initialize offline sync queue (listens for connectivity, flushes pending attendance)
  OfflineSyncService.init();
  
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
    // Wrap with ProviderScope for Riverpod
    const ProviderScope(
      child: Madrasa360App(),
    ),
  );
}

/// مدرسہ 360 ایپ
/// Main Application Widget
class Madrasa360App extends StatelessWidget {
  const Madrasa360App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // App Info
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      
      // Theme
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      
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
  }
}
