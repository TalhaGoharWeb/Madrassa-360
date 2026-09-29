/// دارالاقامہ فراہم کنندہ
/// Hostel provider (Phase 8) — UI state over [HostelRepository].
///
/// The current repository implementation throws
/// [BackendUnavailableException] on every call (no hostel tables exist
/// yet), so [load] lands in [HostelState.backendUnavailable] and the
/// screens render the honest unavailable state. Writes surface the same
/// error through [HostelState.error] — never fake success.
///
/// When a real repository implementation is wired into
/// [hostelRepositoryProvider], no screen or provider change is needed.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exceptions.dart';
import '../core/services/tenant_context.dart';
import '../data/repositories/hostel_repository.dart';

/// Loading lifecycle for the hostel module.
enum HostelLoadStatus {
  initial,
  loading,
  ready,
  unavailable,
  error,
}

class HostelState {
  final HostelLoadStatus status;
  final List<HostelBuilding> buildings;
  final List<HostelRoom> rooms;
  final List<HostelBed> beds;
  final List<HostelAllocation> allocations;
  final HostelSummary summary;
  final String? error;

  const HostelState({
    this.status = HostelLoadStatus.initial,
    this.buildings = const [],
    this.rooms = const [],
    this.beds = const [],
    this.allocations = const [],
    this.summary = const HostelSummary(),
    this.error,
  });

  bool get backendUnavailable => status == HostelLoadStatus.unavailable;
  bool get isLoading => status == HostelLoadStatus.loading;

  HostelState copyWith({
    HostelLoadStatus? status,
    List<HostelBuilding>? buildings,
    List<HostelRoom>? rooms,
    List<HostelBed>? beds,
    List<HostelAllocation>? allocations,
    HostelSummary? summary,
    String? error,
    bool clearError = false,
  }) =>
      HostelState(
        status: status ?? this.status,
        buildings: buildings ?? this.buildings,
        rooms: rooms ?? this.rooms,
        beds: beds ?? this.beds,
        allocations: allocations ?? this.allocations,
        summary: summary ?? this.summary,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Repository seam — swap the implementation when the backend lands.
final hostelRepositoryProvider = Provider<HostelRepository>(
  (ref) => const UnavailableHostelRepository(),
);

class HostelNotifier extends StateNotifier<HostelState> {
  HostelNotifier(this._ref) : super(const HostelState());

  final Ref _ref;

  String? get _tenantId => _ref.read(currentTenantIdProvider);
  HostelRepository get _repo => _ref.read(hostelRepositoryProvider);

  /// Loads all hostel data. With no backend this resolves to
  /// [HostelLoadStatus.unavailable] — an honest state, not an error.
  Future<void> load() async {
    final tenantId = _tenantId;
    if (tenantId == null) {
      state = state.copyWith(
          status: HostelLoadStatus.error, error: 'براہ کرم پہلے لاگ اِن کریں۔');
      return;
    }
    state = state.copyWith(status: HostelLoadStatus.loading, clearError: true);
    try {
      final results = await Future.wait([
        _repo.buildings(tenantId),
        _repo.rooms(tenantId),
        _repo.beds(tenantId),
        _repo.allocations(tenantId),
        _repo.summary(tenantId),
      ]);
      state = state.copyWith(
        status: HostelLoadStatus.ready,
        buildings: results[0] as List<HostelBuilding>,
        rooms: results[1] as List<HostelRoom>,
        beds: results[2] as List<HostelBed>,
        allocations: results[3] as List<HostelAllocation>,
        summary: results[4] as HostelSummary,
        clearError: true,
      );
    } on BackendUnavailableException catch (e) {
      // Honest state: UI architecture is ready, the data service is not.
      state = state.copyWith(
          status: HostelLoadStatus.unavailable, error: e.userMessageUr);
    } catch (e) {
      state = state.copyWith(
          status: HostelLoadStatus.error,
          error: AppException.fromSupabase(e).userMessageUr);
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

  Future<bool> saveBuilding(HostelBuilding building) =>
      _write(() async => _repo.saveBuilding(building));

  Future<bool> deleteBuilding(String id) => _write(() async {
        final tenantId = _tenantId;
        if (tenantId == null) throw const TenantException();
        await _repo.deleteBuilding(id, tenantId);
      });

  Future<bool> saveRoom(HostelRoom room) =>
      _write(() async => _repo.saveRoom(room));

  Future<bool> deleteRoom(String id) => _write(() async {
        final tenantId = _tenantId;
        if (tenantId == null) throw const TenantException();
        await _repo.deleteRoom(id, tenantId);
      });

  Future<bool> saveBed(HostelBed bed) => _write(() async => _repo.saveBed(bed));

  Future<bool> deleteBed(String id) => _write(() async {
        final tenantId = _tenantId;
        if (tenantId == null) throw const TenantException();
        await _repo.deleteBed(id, tenantId);
      });

  Future<bool> allocate(HostelAllocation allocation) =>
      _write(() async => _repo.allocate(allocation));

  Future<bool> endAllocation(String id) => _write(() async {
        final tenantId = _tenantId;
        if (tenantId == null) throw const TenantException();
        await _repo.endAllocation(id, tenantId);
      });

  /// Clears a surfaced write error (e.g. after the snackbar shows).
  void clearError() => state = state.copyWith(clearError: true);
}

final hostelProvider =
    StateNotifierProvider<HostelNotifier, HostelState>((ref) {
  return HostelNotifier(ref);
});
