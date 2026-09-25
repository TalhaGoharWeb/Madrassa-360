/// Bilingual (Urdu/English) crash screen shown when the app hits an
/// unrecoverable error: a failed bootstrap, or an uncaught async error that
/// escaped to the root zone (see lib/main.dart).
///
/// Offers a single "Restart" action that re-runs bootstrap + runApp without
/// killing the process (Phoenix-style soft restart). The crash itself is
/// already persisted to %APPDATA%/Madrassa360/logs/crashes/ by AppLogger.

import 'package:flutter/material.dart';

class CrashScreen extends StatefulWidget {
  const CrashScreen({
    super.key,
    required this.onRestart,
    this.details,
  });

  /// Re-runs bootstrap and re-invokes runApp with the main widget tree.
  final Future<void> Function() onRestart;

  /// Short, already-redacted description of what failed (optional).
  final String? details;

  @override
  State<CrashScreen> createState() => _CrashScreenState();
}

class _CrashScreenState extends State<CrashScreen> {
  bool _busy = false;

  Future<void> _restart() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onRestart();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const emerald = Color(0xFF0B6E4F);
    const gold = Color(0xFFD4AF37);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFFF6F8F7),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                margin: const EdgeInsets.all(24),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: gold, width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: emerald,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: gold,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'کچھ غلط ہو گیا',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: emerald,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Something went wrong',
                        style: TextStyle(fontSize: 15, color: Colors.black54),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'ایپ کو ایک غیر متوقع خرابی کا سامنا کرنا پڑا۔\nآپ کا ڈیٹا محفوظ ہے — دوبارہ شروع کرنے کی کوشش کریں۔',
                        style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.6),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'The app hit an unexpected error. Your data is safe — please try restarting.',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                        textAlign: TextAlign.center,
                      ),
                      if (widget.details != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.details!,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Colors.black54,
                            ),
                            textDirection: TextDirection.ltr,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _busy ? null : _restart,
                          icon: const Icon(Icons.refresh),
                          label: Text(
                            _busy ? 'شروع ہو رہا ہے…' : 'دوبارہ شروع کریں  •  Restart',
                            style: const TextStyle(fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: emerald,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
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
