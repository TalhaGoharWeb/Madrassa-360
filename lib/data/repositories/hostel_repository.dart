/// دارالاقامہ ریپوزیٹری
/// Hostel repository — isolated boundary for the hostel module (Phase 8).
///
/// BACKEND STATUS: no hostel tables exist in the Supabase migrations
/// (001–023) or in the local Drift database — see
/// `docs/audit-backend-capabilities.md`. The models and the
/// [HostelRepository] interface below are the complete, stable contract
/// the UI is built against. [UnavailableHostelRepository] is the current
/// implementation: every call throws [BackendUnavailableException] so the
/// UI renders an honest backend-unavailable state instead of fake data
/// or fake success.
///
/// When the backend lands (tables + RLS + sync envelope), only a new
/// implementation class is needed — no UI or provider changes.

import '../../core/errors/app_exceptions.dart';

/// بستر کی حالت
enum HostelBedStatus {
  available, // خالی
  occupied, // مصروف
  maintenance, // مرمت میں
}

/// رہائش کی حالت
enum HostelAllocationStatus {
  active, // فعال
  ended, // ختم شدہ
}

/// عمارت — hostel building / block.
class HostelBuilding {
  final String id;
  final String tenantId;
  final String name;
  final String? wardenName;
  final String? notes;

  const HostelBuilding({
    required this.id,
    required this.tenantId,
    required this.name,
    this.wardenName,
    this.notes,
  });
}

/// کمرہ — a room inside a building.
class HostelRoom {
  final String id;
  final String tenantId;
  final String buildingId;
  final String roomNo;
  final String? floor;
  final int capacity;

  const HostelRoom({
    required this.id,
    required this.tenantId,
    required this.buildingId,
    required this.roomNo,
    this.floor,
    this.capacity = 0,
  });
}

/// بستر — a single bed inside a room.
class HostelBed {
  final String id;
  final String tenantId;
  final String roomId;
  final String bedNo;
  final HostelBedStatus status;

  const HostelBed({
    required this.id,
    required this.tenantId,
    required this.roomId,
    required this.bedNo,
    this.status = HostelBedStatus.available,
  });
}

/// رہائش — a student's allocation to a bed.
class HostelAllocation {
  final String id;
  final String tenantId;
  final String bedId;
  final String studentId;
  final String studentName;
  final DateTime fromDate;
  final DateTime? toDate;
  final HostelAllocationStatus status;

  const HostelAllocation({
    required this.id,
    required this.tenantId,
    required this.bedId,
    required this.studentId,
    required this.studentName,
    required this.fromDate,
    this.toDate,
    this.status = HostelAllocationStatus.active,
  });
}

/// خلاصہ — occupancy summary (served by the real backend when it exists).
class HostelSummary {
  final int buildings;
  final int rooms;
  final int beds;
  final int occupiedBeds;

  const HostelSummary({
    this.buildings = 0,
    this.rooms = 0,
    this.beds = 0,
    this.occupiedBeds = 0,
  });
}

// ─────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────

/// Stable contract for hostel data. Deletions are archive-style when the
/// backend exists (soft delete / `deleted_at`); the unavailable
/// implementation throws before any of that matters.
abstract class HostelRepository {
  // عمارتیں
  Future<List<HostelBuilding>> buildings(String tenantId);
  Future<HostelBuilding?> buildingById(String id, String tenantId);
  Future<HostelBuilding> saveBuilding(HostelBuilding building);
  Future<void> deleteBuilding(String id, String tenantId);

  // کمرے
  Future<List<HostelRoom>> rooms(String tenantId, {String? buildingId});
  Future<HostelRoom?> roomById(String id, String tenantId);
  Future<HostelRoom> saveRoom(HostelRoom room);
  Future<void> deleteRoom(String id, String tenantId);

  // بستر
  Future<List<HostelBed>> beds(String tenantId, {String? roomId});
  Future<HostelBed> saveBed(HostelBed bed);
  Future<void> deleteBed(String id, String tenantId);

  // رہائش
  Future<List<HostelAllocation>> allocations(String tenantId,
      {String? studentId});
  Future<HostelAllocation> allocate(HostelAllocation allocation);
  Future<void> endAllocation(String id, String tenantId);

  // خلاصہ
  Future<HostelSummary> summary(String tenantId);
}

// ─────────────────────────────────────────────
// Current implementation: backend pending
// ─────────────────────────────────────────────

/// Current hostel implementation. No hostel tables exist yet, so every
/// operation throws [BackendUnavailableException] — the providers catch
/// it and render the honest unavailable state. No fake data, no fake
/// success, no silent no-ops.
class UnavailableHostelRepository implements HostelRepository {
  const UnavailableHostelRepository();

  static const _ex = BackendUnavailableException(
    technicalDetails:
        'hostel tables not provisioned (see docs/audit-backend-capabilities.md)',
  );

  @override
  Future<List<HostelBuilding>> buildings(String tenantId) async => throw _ex;

  @override
  Future<HostelBuilding?> buildingById(String id, String tenantId) async =>
      throw _ex;

  @override
  Future<HostelBuilding> saveBuilding(HostelBuilding building) async =>
      throw _ex;

  @override
  Future<void> deleteBuilding(String id, String tenantId) async => throw _ex;

  @override
  Future<List<HostelRoom>> rooms(String tenantId, {String? buildingId}) async =>
      throw _ex;

  @override
  Future<HostelRoom?> roomById(String id, String tenantId) async => throw _ex;

  @override
  Future<HostelRoom> saveRoom(HostelRoom room) async => throw _ex;

  @override
  Future<void> deleteRoom(String id, String tenantId) async => throw _ex;

  @override
  Future<List<HostelBed>> beds(String tenantId, {String? roomId}) async =>
      throw _ex;

  @override
  Future<HostelBed> saveBed(HostelBed bed) async => throw _ex;

  @override
  Future<void> deleteBed(String id, String tenantId) async => throw _ex;

  @override
  Future<List<HostelAllocation>> allocations(String tenantId,
          {String? studentId}) async =>
      throw _ex;

  @override
  Future<HostelAllocation> allocate(HostelAllocation allocation) async =>
      throw _ex;

  @override
  Future<void> endAllocation(String id, String tenantId) async => throw _ex;

  @override
  Future<HostelSummary> summary(String tenantId) async => throw _ex;
}
