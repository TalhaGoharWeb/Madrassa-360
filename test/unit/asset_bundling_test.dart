/// Asset-bundling regression test (2026-09-30).
///
/// Root cause of a real shipped bug: `pubspec.yaml` declared only `assets/`,
/// but Flutter bundles directory assets NON-recursively
/// (flutter_tools `asset.dart`: `_parseAssetsFromFolder` calls
/// `listSync()` without `recursive: true`). As a result
/// `assets/images/app_logo.png` was never inside the APK/AAB — the login
/// screen and drawer silently rendered their `errorBuilder` fallback tile
/// instead of the real Madrassa-360 mark, and nobody noticed because the
/// fallback looks intentional.
///
/// Contract pinned here:
///   Every `assets/...` literal referenced under `lib/` must be covered by
///   a `flutter.assets` declaration in `pubspec.yaml`, using the SAME
///   non-recursive semantics Flutter uses: a file is covered only by an
///   exact file declaration or by a declaration of its IMMEDIATE parent
///   directory (a grandparent such as `assets/` does not cover
///   `assets/images/app_logo.png`).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<String> _declaredAssets() {
  final lines = File('pubspec.yaml').readAsLinesSync();
  final assets = <String>[];
  var inAssets = false;
  for (final line in lines) {
    if (RegExp(r'^  assets:\s*$').hasMatch(line)) {
      inAssets = true;
      continue;
    }
    if (!inAssets) continue;
    final m = RegExp(r'^    - (\S+)').firstMatch(line);
    if (m != null) {
      assets.add(m.group(1)!); // strips trailing comments
    } else if (line.trim().isNotEmpty && !line.startsWith('    #')) {
      break; // end of the assets list
    }
  }
  return assets;
}

Set<String> _referencedAssets() {
  final refs = <String>{};
  final libDir = Directory('lib');
  final literal = RegExp(r"""['"]assets/[^'"]+['"]""");
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final content = entity.readAsStringSync();
    for (final m in literal.allMatches(content)) {
      var ref = m.group(0)!;
      ref = ref.substring(1, ref.length - 1); // strip quotes
      refs.add(ref);
    }
  }
  return refs;
}

/// Mirrors Flutter's non-recursive directory-asset semantics.
bool _isCovered(String assetPath, List<String> declared) {
  for (final d in declared) {
    if (d == assetPath) return true; // exact file declaration
    if (d.endsWith('/')) {
      // directory declaration: covers only immediate children
      final dir = d; // e.g. 'assets/images/'
      if (assetPath.startsWith(dir) &&
          !assetPath.substring(dir.length).contains('/')) {
        return true;
      }
    }
  }
  return false;
}

void main() {
  test('pubspec declares an assets section', () {
    expect(_declaredAssets(), isNotEmpty);
  });

  test('every assets/ reference in lib/ is bundled (non-recursive rule)', () {
    final declared = _declaredAssets();
    final referenced = _referencedAssets();
    expect(referenced, isNotEmpty,
        reason: 'scanner should find asset references under lib/');
    final missing = referenced.where((r) => !_isCovered(r, declared)).toList()
      ..sort();
    expect(
      missing,
      isEmpty,
      reason: 'These assets are referenced in lib/ but would NOT be bundled '
          'into the APK/AAB because no flutter.assets declaration covers '
          'them under Flutter\'s non-recursive rule: $missing',
    );
  });

  test('app logo ships and is declared', () {
    final logo = File('assets/images/app_logo.png');
    expect(logo.existsSync(), isTrue);
    expect(logo.lengthSync(), greaterThan(10000));
    expect(_isCovered('assets/images/app_logo.png', _declaredAssets()), isTrue,
        reason: 'login screen + drawer footer load this asset');
  });

  test('coverage helper models non-recursive semantics', () {
    const declared = ['assets/', 'assets/images/'];
    expect(_isCovered('assets/.env', declared), isTrue); // top-level file
    expect(_isCovered('assets/images/app_logo.png', declared), isTrue);
    // grandparent does NOT cover nested files:
    expect(_isCovered('assets/images/app_logo.png', ['assets/']), isFalse);
    expect(_isCovered('assets/images/nested/x.png', declared), isFalse);
  });
}
