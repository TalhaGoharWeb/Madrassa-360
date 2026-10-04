/// ڈیمو ڈیٹا سروس — one-click demo data install/remove.
///
/// Calls the hardened `manage-demo-data` Edge Function. The server derives
/// authorization from the JWT (membership + `settings.manage` permission);
/// the tenant ID here is only a routing hint and is re-validated server-side.

import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of a demo-data status check.
class DemoDataStatus {
  const DemoDataStatus({required this.installed, required this.counts});

  final bool installed;
  final Map<String, int> counts;

  /// Total demo rows across all tables.
  int get totalRows => counts.values.fold(0, (a, b) => a + b);

  factory DemoDataStatus.fromJson(Map<String, dynamic> json) {
    final rawCounts = json['counts'] as Map<String, dynamic>? ?? {};
    return DemoDataStatus(
      installed: json['installed'] as bool? ?? false,
      counts: rawCounts.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
    );
  }
}

/// Thrown when the demo-data function call fails.
class DemoDataException implements Exception {
  const DemoDataException(this.message);
  final String message;

  @override
  String toString() => 'DemoDataException: $message';
}

class DemoDataService {
  DemoDataService(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> _invoke(String tenantId, String action) async {
    final FunctionResponse res;
    try {
      res = await _client.functions.invoke(
        'manage-demo-data',
        body: {'tenant_id': tenantId, 'action': action},
      );
    } on FunctionException catch (e) {
      throw DemoDataException(_friendlyError(e));
    } catch (_) {
      throw const DemoDataException('سرور سے رابطہ ناکام — دوبارہ کوشش کریں');
    }
    final data = res.data;
    if (data is! Map<String, dynamic>) {
      throw const DemoDataException('سرور کا جواب غیر متوقع تھا');
    }
    if (data['error'] != null) {
      throw DemoDataException(_errorMessage(data['error'] as String?));
    }
    return data;
  }

  /// Is demo data currently installed for this tenant?
  Future<DemoDataStatus> status(String tenantId) async {
    final data = await _invoke(tenantId, 'status');
    return DemoDataStatus.fromJson(data);
  }

  /// Install the demo dataset (idempotent).
  Future<DemoDataStatus> install(String tenantId) async {
    final data = await _invoke(tenantId, 'install');
    if (data['already_installed'] == true) {
      return status(tenantId);
    }
    return DemoDataStatus.fromJson(data);
  }

  /// Remove all demo rows (only is_demo rows — never real data).
  Future<void> remove(String tenantId) async {
    await _invoke(tenantId, 'remove');
  }

  String _friendlyError(FunctionException e) {
    final code = _edgeErrorCode(e);
    if (code == 'forbidden') {
      return 'آپ کو اس عمل کی اجازت نہیں — صرف منتظم ڈیمو ڈیٹا لگا سکتا ہے';
    }
    // details shape varies by supabase_flutter version; fall back to status.
    final status = (e as dynamic).status;
    if (status == 429) {
      return 'بہت زیادہ کوششیں — کچھ دیر بعد دوبارہ کوشش کریں';
    }
    return 'سرور سے رابطہ ناکام — دوبارہ کوشش کریں';
  }

  /// Extracts the edge-function `{error: code}` from FunctionException.details.
  String? _edgeErrorCode(FunctionException e) {
    try {
      final details = (e as dynamic).details;
      if (details is Map) {
        final code = details['error'];
        if (code is String && code.isNotEmpty) return code;
        final nested = details['data'];
        if (nested is Map && nested['error'] is String) {
          return nested['error'] as String;
        }
      }
    } catch (_) {}
    return null;
  }

  String _errorMessage(String? code) {
    return switch (code) {
      'forbidden' =>
        'آپ کو اس عمل کی اجازت نہیں — صرف منتظم ڈیمو ڈیٹا لگا سکتا ہے',
      _ => 'سرور میں خرابی — دوبارہ کوشش کریں',
    };
  }
}
