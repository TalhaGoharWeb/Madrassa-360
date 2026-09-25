/// no_mock_check.dart — CI guard against mock/demo data in shipped code.
///
/// Scans `lib/` and FAILS (non-zero exit) if any mock-ish identifier
/// appears outside `test/` and outside explicitly allow-listed lines.
///
/// Pure Dart — no Flutter imports — so it runs with the plain `dart`
/// toolchain:
///
///   dart tool/no_mock_check.dart
///
/// To allow-list a genuinely-legitimate occurrence (e.g. a doc comment
/// describing a historical purge), append `// mock-guard:allow` to the
/// line. Every allow-listing is a conscious, reviewable decision.
///
/// Flagged identifiers: `Mock`, `mockData`, `fakeData`, `demoData`,
/// `sampleData`, `dummyData`, `loremIpsum`.
library;

import 'dart:io';

/// Identifier tokens that must never appear in shipped (non-test) code.
const List<String> _bannedTokens = [
  'Mock', // e.g. MockStudent, MockRepository, MockService
  'mockData',
  'fakeData',
  'demoData',
  'sampleData',
  'dummyData',
  'loremIpsum',
];

/// Per-line opt-out marker. Use sparingly; each use is greppable.
const String _allowMarker = 'mock-guard:allow';

/// Directories/files never scanned (dev-only seeds, test fixtures).
bool _isExcluded(String relativePath) {
  final p = relativePath.replaceAll(r'\', '/');
  return p.startsWith('test/') ||
      p.contains('/test/') ||
      p.endsWith('_test.dart');
}

void main(List<String> args) {
  final scriptDir = File(Platform.script.toFilePath()).parent;
  final repoRoot = scriptDir.parent;
  final libDir = Directory('${repoRoot.path}/lib');

  if (!libDir.existsSync()) {
    stderr.writeln('no-mock-check: lib/ not found at ${libDir.path}');
    exit(2);
  }

  final tokenPatterns = _bannedTokens
      .map((t) => RegExp('\\b${RegExp.escape(t)}'))
      .toList(growable: false);

  var violations = 0;
  var filesScanned = 0;

  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in dartFiles) {
    final rel =
        file.path.substring(repoRoot.path.length + 1).replaceAll(r'\', '/');
    if (_isExcluded(rel)) continue;
    filesScanned++;

    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains(_allowMarker)) continue;
      for (var t = 0; t < tokenPatterns.length; t++) {
        if (tokenPatterns[t].hasMatch(line)) {
          violations++;
          stdout.writeln(
              'VIOLATION $rel:${i + 1} — banned token "${_bannedTokens[t]}"\n'
              '    ${line.trim()}');
          break; // one report per line is enough
        }
      }
    }
  }

  stdout.writeln(
      'no-mock-check: scanned $filesScanned files, $violations violation(s).');
  if (violations > 0) {
    stderr.writeln('no-mock-check FAILED: mock-ish identifiers found in lib/. '
        'Remove them, or add "// $_allowMarker" with a justification.');
    exit(1);
  }
  stdout.writeln('no-mock-check PASSED.');
}
