/// Network timeout helper for Supabase queries.
///
/// Supabase queries have no built-in timeout — a stalled network request
/// hangs forever, leaving every screen that watches the provider stuck on
/// its loading skeleton with no error and no retry. Wrapping queries with
/// [withNetworkTimeout] fails fast to a [TimeoutException], which providers
/// surface as an error state (with a retry button) instead of infinite
/// loading.
library;

import 'dart:async';

/// Default timeout for a single Supabase query batch.
const networkTimeout = Duration(seconds: 20);

extension NetworkTimeout<T> on Future<T> {
  /// Fails with [TimeoutException] if this future doesn't complete in
  /// [limit] (default 20s).
  Future<T> withNetworkTimeout([Duration limit = networkTimeout]) =>
      timeout(limit);
}
