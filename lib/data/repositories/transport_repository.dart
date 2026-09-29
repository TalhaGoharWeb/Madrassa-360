/// ٹرانسپورٹ ریپوزیٹری
/// Transport repository — isolated boundary for the transport module
/// (Phase 8).
///
/// BACKEND STATUS: no transport tables exist in the Supabase migrations
/// (001–023) or in the local Drift database — see
/// `docs/audit-backend-capabilities.md`. The models and the
/// [TransportRepository] interface below are the complete, stable
/// contract the UI is built against. [UnavailableTransportRepository] is
/// the current implementation: every call throws
/// [BackendUnavailableException] so the UI renders an honest
/// backend-unavailable state instead of fake data or fake success.
///
/// When the backend lands (tables + RLS + sync envelope), only a new
/// implementation class is needed — no UI or provider changes.

import '../../core/errors/app_exceptions.dart';

/// گاڑی — a vehicle in the fleet.
class TransportVehicle {
  final String id;
  final String tenantId;
  final String plateNumber;
  final String vehicleType; // e.g. بس، وین، کوسٹر
  final int capacity;
  final String? modelYear;
  final String? notes;

  const TransportVehicle({
    required this.id,
    required this.tenantId,
    required this.plateNumber,
    required this.vehicleType,
    this.capacity = 0,
    this.modelYear,
    this.notes,
  });
}

/// ڈرائیور — a driver record.
class TransportDriver {
  final String id;
  final String tenantId;
  final String name;
  final String? phone;
  final String? licenseNumber;

  const TransportDriver({
    required this.id,
    required this.tenantId,
    required this.name,
    this.phone,
    this.licenseNumber,
  });
}

/// راستہ — a transport route.
class TransportRoute {
  final String id;
  final String tenantId;
  final String name;
  final String? startPoint;
  final String? endPoint;

  const TransportRoute({
    required this.id,
    required this.tenantId,
    required this.name,
    this.startPoint,
    this.endPoint,
  });
}

/// اسٹاپ — an ordered stop on a route.
class TransportStop {
  final String id;
  final String tenantId;
  final String routeId;
  final String name;
  final int sequence;

  const TransportStop({
    required this.id,
    required this.tenantId,
    required this.routeId,
    required this.name,
    this.sequence = 0,
  });
}

/// اسائنمنٹ — vehicle + driver + route assignment (optionally per student).
class TransportAssignment {
  final String id;
  final String tenantId;
  final String vehicleId;
  final String routeId;
  final String? driverId;
  final String? studentId;
  final String? studentName;
  final bool active;

  const TransportAssignment({
    required this.id,
    required this.tenantId,
    required this.vehicleId,
    required this.routeId,
    this.driverId,
    this.studentId,
    this.studentName,
    this.active = true,
  });
}

/// خلاصہ — fleet summary (served by the real backend when it exists).
class TransportSummary {
  final int vehicles;
  final int drivers;
  final int routes;
  final int activeAssignments;

  const TransportSummary({
    this.vehicles = 0,
    this.drivers = 0,
    this.routes = 0,
    this.activeAssignments = 0,
  });
}

// ─────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────

/// Stable contract for transport data. Deletions are archive-style when
/// the backend exists (soft delete / `deleted_at`); the unavailable
/// implementation throws before any of that matters.
abstract class TransportRepository {
  // گاڑیاں
  Future<List<TransportVehicle>> vehicles(String tenantId);
  Future<TransportVehicle?> vehicleById(String id, String tenantId);
  Future<TransportVehicle> saveVehicle(TransportVehicle vehicle);
  Future<void> deleteVehicle(String id, String tenantId);

  // ڈرائیور
  Future<List<TransportDriver>> drivers(String tenantId);
  Future<TransportDriver?> driverById(String id, String tenantId);
  Future<TransportDriver> saveDriver(TransportDriver driver);
  Future<void> deleteDriver(String id, String tenantId);

  // راستے اور اسٹاپ
  Future<List<TransportRoute>> routes(String tenantId);
  Future<TransportRoute?> routeById(String id, String tenantId);
  Future<TransportRoute> saveRoute(TransportRoute route);
  Future<void> deleteRoute(String id, String tenantId);
  Future<List<TransportStop>> stops(String routeId, String tenantId);
  Future<TransportStop> saveStop(TransportStop stop);
  Future<void> deleteStop(String id, String tenantId);

  // اسائنمنٹس
  Future<List<TransportAssignment>> assignments(String tenantId);
  Future<TransportAssignment> saveAssignment(TransportAssignment assignment);
  Future<void> deleteAssignment(String id, String tenantId);

  // خلاصہ
  Future<TransportSummary> summary(String tenantId);
}

// ─────────────────────────────────────────────
// Current implementation: backend pending
// ─────────────────────────────────────────────

/// Current transport implementation. No transport tables exist yet, so
/// every operation throws [BackendUnavailableException] — the providers
/// catch it and render the honest unavailable state. No fake data, no
/// fake success, no silent no-ops.
class UnavailableTransportRepository implements TransportRepository {
  const UnavailableTransportRepository();

  static const _ex = BackendUnavailableException(
    technicalDetails:
        'transport tables not provisioned (see docs/audit-backend-capabilities.md)',
  );

  @override
  Future<List<TransportVehicle>> vehicles(String tenantId) async => throw _ex;

  @override
  Future<TransportVehicle?> vehicleById(String id, String tenantId) async =>
      throw _ex;

  @override
  Future<TransportVehicle> saveVehicle(TransportVehicle vehicle) async =>
      throw _ex;

  @override
  Future<void> deleteVehicle(String id, String tenantId) async => throw _ex;

  @override
  Future<List<TransportDriver>> drivers(String tenantId) async => throw _ex;

  @override
  Future<TransportDriver?> driverById(String id, String tenantId) async =>
      throw _ex;

  @override
  Future<TransportDriver> saveDriver(TransportDriver driver) async => throw _ex;

  @override
  Future<void> deleteDriver(String id, String tenantId) async => throw _ex;

  @override
  Future<List<TransportRoute>> routes(String tenantId) async => throw _ex;

  @override
  Future<TransportRoute?> routeById(String id, String tenantId) async =>
      throw _ex;

  @override
  Future<TransportRoute> saveRoute(TransportRoute route) async => throw _ex;

  @override
  Future<void> deleteRoute(String id, String tenantId) async => throw _ex;

  @override
  Future<List<TransportStop>> stops(String routeId, String tenantId) async =>
      throw _ex;

  @override
  Future<TransportStop> saveStop(TransportStop stop) async => throw _ex;

  @override
  Future<void> deleteStop(String id, String tenantId) async => throw _ex;

  @override
  Future<List<TransportAssignment>> assignments(String tenantId) async =>
      throw _ex;

  @override
  Future<TransportAssignment> saveAssignment(
          TransportAssignment assignment) async =>
      throw _ex;

  @override
  Future<void> deleteAssignment(String id, String tenantId) async => throw _ex;

  @override
  Future<TransportSummary> summary(String tenantId) async => throw _ex;
}
