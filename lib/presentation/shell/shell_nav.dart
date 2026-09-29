/// شیل نیویگیشن کی درخواست
/// Shell navigation requests — lets a screen ask the [AppShell] to switch
/// to another destination id (so the rail highlight stays in sync when a
/// hub's internal tab bar moves between destinations that each have their
/// own nav entry, e.g. the finance hub's sections).
///
/// Usage: `requestShellNav(ref, 'finance_ledger')`. The shell consumes the request
/// on the next frame and clears it; unknown ids are ignored.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pending destination id for the shell to switch to, or null.
final shellNavRequestProvider = StateProvider<String?>((ref) => null);

/// Asks the shell to navigate to [destinationId].
void requestShellNav(WidgetRef ref, String destinationId) {
  ref.read(shellNavRequestProvider.notifier).state = destinationId;
}
