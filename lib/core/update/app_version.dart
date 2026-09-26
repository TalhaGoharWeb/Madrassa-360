/// ایپ کا مقامی ورژن
/// Local app version reader.
///
/// Single source of truth: `version.json` at the repo root (the same file
/// the release workflows read; declared as a bundled asset in pubspec.yaml).
/// Falls back to [kFallbackAppVersion] when the asset cannot be read
/// (e.g. unit tests without a Flutter binding) — never throws.

import 'dart:convert';

import 'package:flutter/services.dart';

/// Must stay in sync with pubspec `version:` and root `version.json`.
const String kFallbackAppVersion = '1.0.0';

/// Reads the app's own version string (e.g. "1.0.0"). Never throws.
Future<String> readLocalAppVersion() async {
  try {
    final raw = await rootBundle.loadString('version.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final v = (map['version'] as String?)?.trim();
    if (v != null && v.isNotEmpty) return v;
  } catch (_) {
    // Offline-safe / test-safe: fall through to the compiled-in fallback.
  }
  return kFallbackAppVersion;
}
