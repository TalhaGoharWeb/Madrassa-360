/// no_raw_error_check.dart — CI guard against raw-exception interpolation
/// into user-visible widgets.
///
/// Scans `lib/presentation/` and FAILS (non-zero exit) if a user-visible
/// sink (snackbars, `Text`, dialogs, …) receives a string that interpolates
/// a caught exception object (`$e`, `${e}`, `$err`, …, `e.toString()`).
/// Raw driver/DB text must never reach the screen — route through
/// `ErrorBoundary.showErrorSnackBar` / `handleErrorSimple` instead, which
/// classifies the error, logs the technical detail, and returns a safe
/// localized message.
///
/// Pure Dart — no Flutter imports — so it runs with the plain `dart`
/// toolchain:
///
///   dart tool/no_raw_error_check.dart
///
/// To allow-list a genuinely-safe occurrence (e.g. `AppException.code`,
/// which is a stable machine code, never driver text), append
/// `// error-guard:allow` to any line inside the sink call. Every
/// allow-listing is a conscious, reviewable decision.
///
/// NOTE: `e.message` is deliberately NOT flagged: `AppException.message`
/// is the sanctioned safe localized message (used by the login and
/// forgot-password flows). Interpolating the exception *object* (`$e`)
/// or calling `.toString()` on it is never safe.
library;

import 'dart:io';

/// User-visible sinks: any string argument here can reach the screen.
const List<String> _sinks = [
  'showM360SnackBar',
  'showErrorSnackBar',
  'showErrorDialog',
  'showM360Dialog',
  'showM360ConfirmDialog',
  'SnackBar',
  'showDialog',
  'AlertDialog',
  'SimpleDialog',
  'ErrorDisplayWidget',
  'Text',
];

/// Interpolation / rendering of a raw caught-exception object.
/// `e.message` is intentionally excluded (see library doc comment).
final List<RegExp> _violationPatterns = [
  RegExp(r'''\$(e|err|ex)\b'''), // $e, $err, $ex
  RegExp(r'''\$\{(e|err|ex)\}'''), // ${e}, ${err}, ${ex}
  RegExp(r'''\b(e|err|ex)\.toString\(\)'''), // e.toString()
];

/// Per-span opt-out marker. Use sparingly; each use is greppable.
const String _allowMarker = 'error-guard:allow';

/// Directories never scanned.
bool _isExcluded(String relativePath) {
  final p = relativePath.replaceAll(r'\', '/');
  return p.startsWith('test/') ||
      p.contains('/test/') ||
      p.endsWith('_test.dart');
}

/// Finds `[start, end)` spans of each `name(` call in [src], matching
/// parentheses while skipping over strings and comments.
List<List<int>> _callSpans(String src, String name) {
  final spans = <List<int>>[];
  final pattern = RegExp('\\b${RegExp.escape(name)}\\s*\\(');
  for (final m in pattern.allMatches(src)) {
    var i = m.end; // just past '('
    var depth = 1;
    var inStr = ''; // '', "'", '"', "'''", '"""'
    var inLineComment = false;
    var inBlockComment = false;
    while (i < src.length && depth > 0) {
      final c = src[i];
      if (inLineComment) {
        if (c == '\n') inLineComment = false;
      } else if (inBlockComment) {
        if (c == '*' && i + 1 < src.length && src[i + 1] == '/') {
          inBlockComment = false;
          i++;
        }
      } else if (inStr.isNotEmpty) {
        if (c == '\\') {
          i++; // skip escaped char
        } else if (inStr.length == 3 ? src.startsWith(inStr, i) : c == inStr) {
          i += inStr.length - 1;
          inStr = '';
        }
      } else if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
        inLineComment = true;
        i++;
      } else if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
        inBlockComment = true;
        i++;
      } else if (c == "'" || c == '"') {
        if (i + 2 < src.length && src[i + 1] == c && src[i + 2] == c) {
          inStr = c * 3;
          i += 2;
        } else {
          inStr = c;
        }
      } else if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
      }
      i++;
    }
    spans.add([m.start, i]);
  }
  return spans;
}

void main(List<String> args) {
  final scriptDir = File(Platform.script.toFilePath()).parent;
  final repoRoot = scriptDir.parent;
  final presentationDir = Directory('${repoRoot.path}/lib/presentation');

  if (!presentationDir.existsSync()) {
    stderr.writeln(
        'no-raw-error-check: lib/presentation/ not found at ${presentationDir.path}');
    exit(2);
  }

  var violations = 0;
  var filesScanned = 0;
  var spansScanned = 0;

  final dartFiles = presentationDir
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

    final src = file.readAsStringSync();
    final seenSpans = <String>{};
    for (final sink in _sinks) {
      for (final span in _callSpans(src, sink)) {
        final key = '${span[0]}-${span[1]}';
        if (!seenSpans.add(key)) continue; // nested sinks share text
        spansScanned++;
        var text = src.substring(span[0], span[1]);
        // Also honor the marker on the line holding the closing paren
        // (e.g. `... isError: true); // error-guard:allow ...`).
        final closeParen = span[1] - 1;
        final closeLineStart = src.lastIndexOf('\n', closeParen) + 1;
        var closeLineEnd = src.indexOf('\n', closeParen);
        if (closeLineEnd == -1) closeLineEnd = src.length;
        text += '\n${src.substring(closeLineStart, closeLineEnd)}';
        if (text.contains(_allowMarker)) continue;
        final lines = text.split('\n');
        for (var li = 0; li < lines.length; li++) {
          final line = lines[li];
          for (final pattern in _violationPatterns) {
            final match = pattern.firstMatch(line);
            if (match != null) {
              violations++;
              // Map back to a file line number.
              final before = src.substring(0, span[0]);
              final lineNo = '\n'.allMatches(before).length + li + 1;
              stdout.writeln(
                  'VIOLATION $rel:$lineNo — raw exception "${match.group(0)}" '
                  'inside $sink(…)\n'
                  '    ${line.trim()}');
              break; // one report per line is enough
            }
          }
        }
      }
    }
  }

  stdout.writeln('no-raw-error-check: scanned $filesScanned files '
      '($spansScanned sink spans), $violations violation(s).');
  if (violations > 0) {
    stderr.writeln('no-raw-error-check FAILED: raw exceptions interpolated '
        'into user-visible widgets in lib/presentation/. Route them through '
        'ErrorBoundary (showErrorSnackBar / handleErrorSimple), or add '
        '"// $_allowMarker" with a justification.');
    exit(1);
  }
  stdout.writeln('no-raw-error-check PASSED.');
}
