/// اسناد فراہم کنندہ
/// Certificate provider (Phase 8) — issuance-history state over
/// [CertificateRepository].
///
/// SCOPE: this provider covers issuance TRACKING only. Certificate
/// generation runs directly through the real reporting engine
/// ([ReportsService]) in the certificates screen — it never goes
/// through this provider.
///
/// The current repository implementation throws
/// [BackendUnavailableException] on every call (no issuance table
/// exists yet), so [loadHistory] lands in
/// [CertificateState.backendUnavailable] and the history tab renders
/// the honest unavailable state.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exceptions.dart';
import '../core/services/tenant_context.dart';
import '../data/repositories/certificate_repository.dart';

/// Loading lifecycle for the issuance-history view.
enum CertificateLoadStatus {
  initial,
  loading,
  ready,
  unavailable,
  error,
}

class CertificateState {
  final CertificateLoadStatus status;
  final List<CertificateIssuance> history;
  final String? error;

  const CertificateState({
    this.status = CertificateLoadStatus.initial,
    this.history = const [],
    this.error,
  });

  bool get backendUnavailable => status == CertificateLoadStatus.unavailable;
  bool get isLoading => status == CertificateLoadStatus.loading;

  CertificateState copyWith({
    CertificateLoadStatus? status,
    List<CertificateIssuance>? history,
    String? error,
    bool clearError = false,
  }) =>
      CertificateState(
        status: status ?? this.status,
        history: history ?? this.history,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Repository seam — swap the implementation when the backend lands.
final certificateRepositoryProvider = Provider<CertificateRepository>(
  (ref) => const UnavailableCertificateRepository(),
);

class CertificateNotifier extends StateNotifier<CertificateState> {
  CertificateNotifier(this._ref) : super(const CertificateState());

  final Ref _ref;

  String? get _tenantId => _ref.read(currentTenantIdProvider);
  CertificateRepository get _repo => _ref.read(certificateRepositoryProvider);

  /// Loads the issuance history. With no backend this resolves to
  /// [CertificateLoadStatus.unavailable] — an honest state, not an error.
  Future<void> loadHistory() async {
    final tenantId = _tenantId;
    if (tenantId == null) {
      state = state.copyWith(
          status: CertificateLoadStatus.error,
          error: 'براہ کرم پہلے لاگ اِن کریں۔');
      return;
    }
    state =
        state.copyWith(status: CertificateLoadStatus.loading, clearError: true);
    try {
      final rows = await _repo.history(tenantId);
      state = state.copyWith(
          status: CertificateLoadStatus.ready, history: rows, clearError: true);
    } on BackendUnavailableException catch (e) {
      state = state.copyWith(
          status: CertificateLoadStatus.unavailable, error: e.userMessageUr);
    } catch (e) {
      state = state.copyWith(
          status: CertificateLoadStatus.error,
          error: AppException.fromSupabase(e).userMessageUr);
    }
  }

  /// Attempts to log one issuance after a PDF was generated. Returns true
  /// only when the backend actually stored it. With no backend this
  /// returns false and surfaces the honest message — the caller (the
  /// certificates screen) must NOT treat this as a generation failure:
  /// the PDF itself was already produced by the real report pipeline.
  Future<bool> recordIssuance(CertificateIssuance issuance) async {
    try {
      await _repo.recordIssuance(issuance);
      await loadHistory();
      return true;
    } on BackendUnavailableException catch (e) {
      state = state.copyWith(error: e.userMessageUr);
      return false;
    } catch (e) {
      state = state.copyWith(error: AppException.fromSupabase(e).userMessageUr);
      return false;
    }
  }

  /// Clears a surfaced error (e.g. after the snackbar shows).
  void clearError() => state = state.copyWith(clearError: true);
}

final certificateProvider =
    StateNotifierProvider<CertificateNotifier, CertificateState>((ref) {
  return CertificateNotifier(ref);
});
