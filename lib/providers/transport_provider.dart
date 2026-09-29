/// ٹرانسپورٹ فراہم کنندہ
/// Transport provider (Phase 8) — UI state over [TransportRepository].
///
/// The current repository implementation throws
/// [BackendUnavailableException] on every call (no transport tables exist
/// yet), so [load] lands in [TransportState.backendUnavailable] and the
/// screens render the honest unavailable state. Writes surface the same
/// error through [TransportState.error] — never fake success.
///
/// When a real repository implementation is wired into
/// [transportRepositoryProvider], no screen or provider change is needed.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exceptions.dart';
import '../core/services/tenant_context.dart';
import '../data/repositories/transport_repository.dart';

/// Loading lifecycle for the transport module.
enum TransportLoadStatus {
  initial,
  loading,
  ready,
  unavailable,
  error,
}

class TransportState {
  final TransportLoadStatus status;
  final List<TransportVehicle> vehicles;
  final List<TransportDriver> drivers;
  final List<TransportRoute> routes;
  final List<TransportStop> stops;
  final List<TransportAssignment> assignments;
  final TransportSummary summary;
  final String? error;

  /// Route whose stops are currently expanded in the detail screen.
  final String? activeRouteId;

  const TransportState({
    this.status = TransportLoadStatus.initial,
    this.vehicles = const [],
    this.drivers = const [],
    this.routes = const [],
    this.stops = const [],
    this.assignments = const [],
    this.activeRouteId,
    this.summary = const TransportSummary(),
    this.error,
  });

  bool get backendUnavailable => status == TransportLoadStatus.unavailable;
  bool get isLoading => status == TransportLoadStatus.loading;

  TransportState copyWith({
    TransportLoadStatus? status,
    List<TransportVehicle>? vehicles,
    List<TransportDriver>? drivers,
    List<TransportRoute>? routes,
    List<TransportStop>? stops,
    List<TransportAssignment>? assignments,
    String? Function()? activeRouteId,
    TransportSummary? summary,
    String? error,
    bool clearError = false,
  }) =>
      TransportState(
        status: status ?? this.status,
        vehicles: vehicles ?? this.vehicles,
        drivers: drivers ?? this.drivers,
        routes: routes ?? this.routes,
        stops: stops ?? this.stops,
        assignments: assignments ?? this.assignments,
        activeRouteId:
            activeRouteId == null ? this.activeRouteId : activeRouteId(),
        summary: summary ?? this.summary,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Repository seam — swap the implementation when the backend lands.
final transportRepositoryProvider = Provider<TransportRepository>(
  (ref) => const UnavailableTransportRepository(),
);

class TransportNotifier extends StateNotifier<TransportState> {
  TransportNotifier(this._ref) : super(const TransportState());

  final Ref _ref;

  String? get _tenantId => _ref.read(currentTenantIdProvider);
  TransportRepository get _repo => _ref.read(transportRepositoryProvider);

  /// Loads all transport data. With no backend this resolves to
  /// [TransportLoadStatus.unavailable] — an honest state, not an error.
  Future<void> load() async {
    final tenantId = _tenantId;
    if (tenantId == null) {
      state = state.copyWith(
          status: TransportLoadStatus.error,
          error: 'براہ کرم پہلے لاگ اِن کریں۔');
      return;
    }
    state =
        state.copyWith(status: TransportLoadStatus.loading, clearError: true);
    try {
      final results = await Future.wait([
        _repo.vehicles(tenantId),
        _repo.drivers(tenantId),
        _repo.routes(tenantId),
        _repo.assignments(tenantId),
        _repo.summary(tenantId),
      ]);
      state = state.copyWith(
        status: TransportLoadStatus.ready,
        vehicles: results[0] as List<TransportVehicle>,
        drivers: results[1] as List<TransportDriver>,
        routes: results[2] as List<TransportRoute>,
        assignments: results[3] as List<TransportAssignment>,
        summary: results[4] as TransportSummary,
        clearError: true,
      );
    } on BackendUnavailableException catch (e) {
      // Honest state: UI architecture is ready, the data service is not.
      state = state.copyWith(
          status: TransportLoadStatus.unavailable, error: e.userMessageUr);
    } catch (e) {
      state = state.copyWith(
          status: TransportLoadStatus.error,
          error: AppException.fromSupabase(e).userMessageUr);
    }
  }

  /// Loads stops for one route (detail screen).
  Future<void> loadStops(String routeId) async {
    final tenantId = _tenantId;
    if (tenantId == null) return;
    state = state.copyWith(activeRouteId: () => routeId, clearError: true);
    try {
      final stops = await _repo.stops(routeId, tenantId);
      state = state.copyWith(stops: stops);
    } on BackendUnavailableException catch (e) {
      state = state.copyWith(
          status: TransportLoadStatus.unavailable, error: e.userMessageUr);
    } catch (e) {
      state = state.copyWith(error: AppException.fromSupabase(e).userMessageUr);
    }
  }

  /// Runs a write through the repository. Returns true only when the
  /// backend actually accepted it — never fake success.
  Future<bool> _write(Future<void> Function() op) async {
    state = state.copyWith(clearError: true);
    try {
      await op();
      await load();
      return true;
    } on BackendUnavailableException catch (e) {
      state = state.copyWith(error: e.userMessageUr);
      return false;
    } catch (e) {
      state = state.copyWith(error: AppException.fromSupabase(e).userMessageUr);
      return false;
    }
  }

  Future<bool> saveVehicle(TransportVehicle vehicle) =>
      _write(() async => _repo.saveVehicle(vehicle));

  Future<bool> deleteVehicle(String id) => _write(() async {
        final tenantId = _tenantId;
        if (tenantId == null) throw const TenantException();
        await _repo.deleteVehicle(id, tenantId);
      });

  Future<bool> saveDriver(TransportDriver driver) =>
      _write(() async => _repo.saveDriver(driver));

  Future<bool> deleteDriver(String id) => _write(() async {
        final tenantId = _tenantId;
        if (tenantId == null) throw const TenantException();
        await _repo.deleteDriver(id, tenantId);
      });

  Future<bool> saveRoute(TransportRoute route) =>
      _write(() async => _repo.saveRoute(route));

  Future<bool> deleteRoute(String id) => _write(() async {
        final tenantId = _tenantId;
        if (tenantId == null) throw const TenantException();
        await _repo.deleteRoute(id, tenantId);
      });

  Future<bool> saveStop(TransportStop stop) =>
      _write(() async => _repo.saveStop(stop));

  Future<bool> deleteStop(String id) => _write(() async {
        final tenantId = _tenantId;
        if (tenantId == null) throw const TenantException();
        await _repo.deleteStop(id, tenantId);
      });

  Future<bool> saveAssignment(TransportAssignment assignment) =>
      _write(() async => _repo.saveAssignment(assignment));

  Future<bool> deleteAssignment(String id) => _write(() async {
        final tenantId = _tenantId;
        if (tenantId == null) throw const TenantException();
        await _repo.deleteAssignment(id, tenantId);
      });

  /// Clears a surfaced write error (e.g. after the snackbar shows).
  void clearError() => state = state.copyWith(clearError: true);
}

final transportProvider =
    StateNotifierProvider<TransportNotifier, TransportState>((ref) {
  return TransportNotifier(ref);
});
