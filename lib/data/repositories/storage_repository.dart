/// اسٹوریج ریپوزیٹری
/// Storage Repository — photo upload/download via Supabase Storage

import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';

// ─────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────

abstract class IStorageRepository {
  /// Upload a student photo and return its public URL
  Future<String> uploadStudentPhoto(String studentId, File file);

  /// Upload a staff member photo and return its public URL
  Future<String> uploadStaffPhoto(String staffId, File file);

  /// Delete a student photo from storage
  Future<void> deleteStudentPhoto(String studentId);

  /// Delete a staff photo from storage
  Future<void> deleteStaffPhoto(String staffId);

  /// Get a public URL for an existing path
  String getPublicUrl(String bucket, String path);
}

// ─────────────────────────────────────────────
// Mock Implementation (no actual uploads)
// ─────────────────────────────────────────────

class MockStorageRepository implements IStorageRepository {
  // Phase 4: no external placeholder URLs (was via.placeholder.com — an
  // external tracking surface). Dead under kUseSupabase=true; returns ''
  // so callers must handle "no photo" instead of persisting a fake URL.
  @override
  Future<String> uploadStudentPhoto(String studentId, File file) async => '';

  @override
  Future<String> uploadStaffPhoto(String staffId, File file) async => '';

  @override
  Future<void> deleteStudentPhoto(String studentId) async {}

  @override
  Future<void> deleteStaffPhoto(String staffId) async {}

  @override
  String getPublicUrl(String bucket, String path) => '';
}

// ─────────────────────────────────────────────
// Supabase Implementation
// ─────────────────────────────────────────────

class SupabaseStorageRepository implements IStorageRepository {
  SupabaseClient get _client => SupabaseService.client;

  static const String _studentsBucket = 'student-photos';
  static const String _staffBucket = 'staff-photos';

  String _extension(File file) {
    final name = file.path.split(Platform.pathSeparator).last;
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : 'jpg';
  }

  @override
  Future<String> uploadStudentPhoto(String studentId, File file) async {
    final ext = _extension(file);
    final path = '$studentId.$ext';
    await _client.storage.from(_studentsBucket).upload(
          path,
          file,
          fileOptions: const FileOptions(upsert: true),
        );
    return _client.storage.from(_studentsBucket).getPublicUrl(path);
  }

  @override
  Future<String> uploadStaffPhoto(String staffId, File file) async {
    final ext = _extension(file);
    final path = '$staffId.$ext';
    await _client.storage.from(_staffBucket).upload(
          path,
          file,
          fileOptions: const FileOptions(upsert: true),
        );
    return _client.storage.from(_staffBucket).getPublicUrl(path);
  }

  @override
  Future<void> deleteStudentPhoto(String studentId) async {
    // Try both common extensions
    for (final ext in ['jpg', 'jpeg', 'png', 'webp']) {
      try {
        await _client.storage
            .from(_studentsBucket)
            .remove(['$studentId.$ext']);
      } catch (_) {
        // Ignore if file doesn't exist
      }
    }
  }

  @override
  Future<void> deleteStaffPhoto(String staffId) async {
    for (final ext in ['jpg', 'jpeg', 'png', 'webp']) {
      try {
        await _client.storage
            .from(_staffBucket)
            .remove(['$staffId.$ext']);
      } catch (_) {}
    }
  }

  @override
  String getPublicUrl(String bucket, String path) =>
      _client.storage.from(bucket).getPublicUrl(path);
}
