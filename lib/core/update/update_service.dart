/// آٹو اپ ڈیٹ چیک
/// Auto-update check: compares the installed build against the
/// `platform_config` row in Supabase and gates the app on forced updates.
///
/// WIRING (one line, done by the integrator in main.dart):
/// ```dart
/// runApp(ProviderScope(child: UpdateGate(child: const Madrasa360App())));
/// ```
/// [UpdateGate] must wrap the app ABOVE MaterialApp so a forced update can
/// replace the whole screen. It runs the check once per app start.
///
/// OFFLINE CONTRACT (hard requirement): any network/parse failure returns
/// [UpdateDecision.unknown] and the app continues normally — no error
/// dialogs, no blocking, no retry storms. Offline users are NEVER bricked
/// by the update check.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/supabase_service.dart';
import 'app_version.dart';

// ─────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────

/// Outcome of one update check.
enum UpdateDecision {
  /// Local build is current (or newer than the published latest).
  upToDate,

  /// A newer version exists; user may dismiss (once per version).
  optionalUpdate,

  /// Local build is older than `minimum_supported_version`; the app is
  /// replaced with a blocking screen until the user updates.
  forcedUpdate,

  /// Check could not complete (offline, timeout, bad row). Behave exactly
  /// like [upToDate]: continue silently.
  unknown,
}

class UpdateCheckResult {
  final UpdateDecision decision;
  final String? latestVersion;
  final String? minimumVersion;
  final String? downloadUrl;
  final String? notesEn;
  final String? notesUr;

  const UpdateCheckResult({
    required this.decision,
    this.latestVersion,
    this.minimumVersion,
    this.downloadUrl,
    this.notesEn,
    this.notesUr,
  });

  /// The notes in the app's primary language (Urdu first), with English fallback.
  String get notes => (notesUr?.trim().isNotEmpty ?? false)
      ? notesUr!.trim()
      : (notesEn?.trim() ?? '');

  bool get hasUpdate =>
      decision == UpdateDecision.optionalUpdate ||
      decision == UpdateDecision.forcedUpdate;
}

// ─────────────────────────────────────────────
// Semantic version comparison
// ─────────────────────────────────────────────

/// Compares two semver-ish strings ("1.0.0", "1.0.0+1", "1.2").
/// Returns -1 / 0 / 1. Build metadata ("+…") and pre-release ("-…") are
/// ignored; missing segments are treated as 0. Never throws.
int compareSemver(String a, String b) {
  List<int> parts(String v) {
    final core = v.split('+').first.split('-').first;
    final segs = core.split('.');
    return List<int>.generate(
      3,
      (i) => i < segs.length ? int.tryParse(segs[i].trim()) ?? 0 : 0,
    );
  }

  final pa = parts(a);
  final pb = parts(b);
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
  }
  return 0;
}

// ─────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────

/// Reads `platform_config` (anon-readable, so this works pre-login) and
/// decides whether the installed build needs an update.
///
/// Every failure mode — no network, timeout, missing row, malformed
/// version — collapses to [UpdateDecision.unknown].
class UpdateService {
  final SupabaseClient _client;

  /// [client] is injectable for tests; defaults to the global client.
  UpdateService({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  /// Runs one update check. Never throws.
  Future<UpdateCheckResult> checkForUpdate() async {
    try {
      final row = await _client
          .from('platform_config')
          .select(
            'latest_version, minimum_supported_version, download_url, '
            'release_notes, release_notes_urdu',
          )
          .eq('key', 'default')
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (row == null) {
        return const UpdateCheckResult(decision: UpdateDecision.unknown);
      }

      final latest = (row['latest_version'] as String?)?.trim() ?? '';
      final minimum =
          (row['minimum_supported_version'] as String?)?.trim() ?? '';
      if (latest.isEmpty || minimum.isEmpty) {
        return const UpdateCheckResult(decision: UpdateDecision.unknown);
      }

      final local = await readLocalAppVersion();

      if (compareSemver(local, latest) >= 0) {
        return const UpdateCheckResult(decision: UpdateDecision.upToDate);
      }

      final forced = compareSemver(local, minimum) < 0;
      return UpdateCheckResult(
        decision: forced
            ? UpdateDecision.forcedUpdate
            : UpdateDecision.optionalUpdate,
        latestVersion: latest,
        minimumVersion: minimum,
        downloadUrl: (row['download_url'] as String?)?.trim(),
        notesEn: row['release_notes'] as String?,
        notesUr: row['release_notes_urdu'] as String?,
      );
    } catch (_) {
      // Offline, timeout, auth hiccup, malformed row — all become "unknown".
      return const UpdateCheckResult(decision: UpdateDecision.unknown);
    }
  }

  /// Opens the download URL in the system browser. Returns false when the
  /// URL is missing/invalid or the launch failed. Never throws.
  Future<bool> openDownload(UpdateCheckResult result) async {
    try {
      final raw = result.downloadUrl;
      if (raw == null || raw.trim().isEmpty) return false;
      final uri = Uri.tryParse(raw.trim());
      if (uri == null || !uri.hasScheme) return false;
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

// ─────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────

/// Riverpod-friendly accessor for [UpdateService].
final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

/// Runs the update check once per app start. Consumers (see [UpdateGate])
/// should treat [UpdateDecision.unknown] exactly like [UpdateDecision.upToDate].
final updateCheckProvider = FutureProvider<UpdateCheckResult>((ref) async {
  return ref.watch(updateServiceProvider).checkForUpdate();
});

// ─────────────────────────────────────────────
// UpdateGate widget
// ─────────────────────────────────────────────

/// Wraps the app and enforces the update policy exactly once per start:
/// * [UpdateDecision.forcedUpdate] → replaces the whole app with a
///   blocking, non-dismissible screen (no back button, no skip).
/// * [UpdateDecision.optionalUpdate] → shows a dismissible dialog ONCE per
///   version (dismissal persisted in SharedPreferences).
/// * [UpdateDecision.upToDate] / [UpdateDecision.unknown] → renders [child]
///   untouched.
class UpdateGate extends ConsumerStatefulWidget {
  final Widget child;

  const UpdateGate({super.key, required this.child});

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  static const _dismissedVersionKey = 'update_dismissed_version';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCheck());
  }

  Future<void> _runCheck() async {
    UpdateCheckResult result;
    try {
      result = await ref.read(updateCheckProvider.future);
    } catch (_) {
      return; // Defensive: provider itself must never break startup.
    }
    if (!mounted) return;

    switch (result.decision) {
      case UpdateDecision.forcedUpdate:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ForcedUpdateScreen(result: result),
          ),
        );
      case UpdateDecision.optionalUpdate:
        await _maybeShowOptionalDialog(result);
      case UpdateDecision.upToDate:
      case UpdateDecision.unknown:
        break; // Render the app normally; stay silent.
    }
  }

  Future<void> _maybeShowOptionalDialog(UpdateCheckResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getString(_dismissedVersionKey);
    final latest = result.latestVersion ?? '';
    if (dismissed == latest || latest.isEmpty || !mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _OptionalUpdateDialog(result: result),
    );
    // Remember the dismissal even if the dialog was dismissed by tapping
    // outside — the user has seen this version.
    await prefs.setString(_dismissedVersionKey, latest);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─────────────────────────────────────────────
// Optional-update dialog (dismissible)
// ─────────────────────────────────────────────

class _OptionalUpdateDialog extends ConsumerWidget {
  final UpdateCheckResult result;

  const _OptionalUpdateDialog({required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('نئی اپ ڈیٹ دستیاب ہے'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'New version ${result.latestVersion} is available.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (result.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(result.notes),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('بعد میں / Later'),
          ),
          FilledButton(
            onPressed: () async {
              final ok =
                  await ref.read(updateServiceProvider).openDownload(result);
              if (context.mounted) {
                if (!ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'ڈاؤن لوڈ لنک نہیں کھل سکا / Could not open download link',
                      ),
                    ),
                  );
                }
                Navigator.of(context).pop();
              }
            },
            child: const Text('اپ ڈیٹ کریں / Update'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Forced-update screen (blocking, non-dismissible)
// ─────────────────────────────────────────────

/// Full-screen gate shown when the installed build is older than
/// `minimum_supported_version`. There is deliberately NO dismiss, NO back
/// navigation, and NO way to reach the app behind it.
class ForcedUpdateScreen extends ConsumerWidget {
  final UpdateCheckResult result;

  const ForcedUpdateScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false, // Back button / gesture cannot escape this screen.
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.system_update,
                          size: 72, color: Colors.deepOrange),
                      const SizedBox(height: 24),
                      Text(
                        'اپ ڈیٹ ضروری ہے',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Update required to continue',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'آپ کا ورژن (${result.minimumVersion} سے پرانا) اب تعاون یافتہ نہیں۔ '
                        'جاری رکھنے کے لیے تازہ ترین ورژن ڈاؤن لوڈ کریں۔',
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        'Your version is no longer supported. '
                        'Download version ${result.latestVersion} to continue.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (result.notes.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Theme.of(context).dividerColor),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(result.notes),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        icon: const Icon(Icons.download),
                        label: const Text(
                            'اپ ڈیٹ ڈاؤن لوڈ کریں / Download update'),
                        onPressed: () async {
                          final ok = await ref
                              .read(updateServiceProvider)
                              .openDownload(result);
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'ڈاؤن لوڈ لنک نہیں کھل سکا / Could not open download link',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
