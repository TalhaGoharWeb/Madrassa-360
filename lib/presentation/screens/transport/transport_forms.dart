/// ٹرانسپورٹ فارم
/// Transport create/edit dialogs + destructive confirmations (Phase 8).
///
/// Built on the m360 component language ([M360Dialog], [M360TextField],
/// [M360Dropdown], [M360PrimaryButton]) and the real [TransportNotifier]
/// write methods. With no backend the writes fail honestly: the dialog
/// keeps the entered data and shows the backend error inline instead of
/// closing with a fake success.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/design/m360.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/repositories/transport_repository.dart';
import '../../../providers/transport_provider.dart';

const _uuid = Uuid();

/// Destructive confirmation for transport deletions (m360 destructive
/// pattern — red confirm, explicit warning, never silent).
///
/// Used by the widget test to assert the confirmation exists.
Future<bool> confirmTransportDelete(
  BuildContext context, {
  required String itemLabel,
}) {
  return showM360ConfirmDialog(
    context,
    title: 'حذف کرنے کی تصدیق',
    message:
        'کیا آپ واقعی "$itemLabel" حذف کرنا چاہتے ہیں؟ یہ عمل واپس نہیں ہوگا۔',
    confirmLabel: 'حذف کریں',
    danger: true,
  );
}

// ─────────────────────────────────────────────
// Shared dialog shell for transport forms
// ─────────────────────────────────────────────

class _TransportFormShell extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final List<Widget> fields;
  final Future<bool> Function() onSave;
  final String? Function() readError;

  const _TransportFormShell({
    required this.formKey,
    required this.fields,
    required this.onSave,
    required this.readError,
  });

  @override
  State<_TransportFormShell> createState() => _TransportFormShellState();
}

class _TransportFormShellState extends State<_TransportFormShell> {
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (!(widget.formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await widget.onSave();
    if (!mounted) return;
    if (ok) {
      showM360SnackBar(context, 'محفوظ ہو گیا۔');
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = widget.readError() ?? 'محفوظ نہیں ہو سکا۔ دوبارہ کوشش کریں۔';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...widget.fields,
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textDirection: TextDirection.rtl,
              style: const TextStyle(color: Colors.red),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              M360TertiaryButton(
                label: 'منسوخ',
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              M360PrimaryButton(
                label: 'محفوظ کریں',
                isLoading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _showTransportForm(
  BuildContext context, {
  required String title,
  required IconData icon,
  required _TransportFormShell Function() build,
}) {
  return showM360Dialog<void>(
    context,
    title: title,
    icon: icon,
    content: build(),
  );
}

// ─────────────────────────────────────────────
// Vehicle form
// ─────────────────────────────────────────────

/// Shows the create/edit vehicle dialog.
Future<void> showTransportVehicleForm(
  BuildContext context,
  WidgetRef ref, {
  TransportVehicle? existing,
}) {
  final plate = TextEditingController(text: existing?.plateNumber ?? '');
  final type = TextEditingController(text: existing?.vehicleType ?? '');
  final capacity = TextEditingController(
      text: existing == null ? '' : '${existing.capacity}');
  final modelYear = TextEditingController(text: existing?.modelYear ?? '');
  final notes = TextEditingController(text: existing?.notes ?? '');
  final formKey = GlobalKey<FormState>();

  String? need(String? v, String msg) =>
      (v == null || v.trim().isEmpty) ? msg : null;

  return _showTransportForm(
    context,
    title: existing == null ? 'نئی گاڑی' : 'گاڑی میں ترمیم',
    icon: Icons.directions_bus_outlined,
    build: () => _TransportFormShell(
      formKey: formKey,
      fields: [
        M360TextField(
          label: 'نمبر پلیٹ',
          hint: 'مثلاً LHR-1234',
          controller: plate,
          validator: (v) => need(v, 'نمبر پلیٹ درج کرنا ضروری ہے'),
        ),
        const SizedBox(height: 12),
        M360TextField(
          label: 'گاڑی کی قسم',
          hint: 'مثلاً بس، وین، کوسٹر',
          controller: type,
          validator: (v) => need(v, 'قسم درج کرنا ضروری ہے'),
        ),
        const SizedBox(height: 12),
        M360TextField(
          label: 'گنجائش (نشستیں)',
          controller: capacity,
          keyboardType: TextInputType.number,
          validator: (v) =>
              (v == null || v.trim().isEmpty || int.tryParse(v.trim()) == null)
                  ? 'درست عدد درج کریں'
                  : null,
        ),
        const SizedBox(height: 12),
        M360TextField(
          label: 'ماڈل سال (اختیاری)',
          controller: modelYear,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        M360TextField(
          label: 'نوٹ (اختیاری)',
          controller: notes,
          maxLines: 2,
        ),
      ],
      onSave: () async {
        final tenantId = ref.read(currentTenantIdProvider);
        if (tenantId == null) return false;
        return ref.read(transportProvider.notifier).saveVehicle(
              TransportVehicle(
                id: existing?.id ?? _uuid.v4(),
                tenantId: tenantId,
                plateNumber: plate.text.trim(),
                vehicleType: type.text.trim(),
                capacity: int.tryParse(capacity.text.trim()) ?? 0,
                modelYear: modelYear.text.trim().isEmpty
                    ? null
                    : modelYear.text.trim(),
                notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
              ),
            );
      },
      readError: () => ref.read(transportProvider).error,
    ),
  ).whenComplete(() {
    plate.dispose();
    type.dispose();
    capacity.dispose();
    modelYear.dispose();
    notes.dispose();
  });
}

// ─────────────────────────────────────────────
// Driver form
// ─────────────────────────────────────────────

/// Shows the create/edit driver dialog.
Future<void> showTransportDriverForm(
  BuildContext context,
  WidgetRef ref, {
  TransportDriver? existing,
}) {
  final name = TextEditingController(text: existing?.name ?? '');
  final phone = TextEditingController(text: existing?.phone ?? '');
  final license = TextEditingController(text: existing?.licenseNumber ?? '');
  final formKey = GlobalKey<FormState>();

  return _showTransportForm(
    context,
    title: existing == null ? 'نیا ڈرائیور' : 'ڈرائیور میں ترمیم',
    icon: Icons.person_outline,
    build: () => _TransportFormShell(
      formKey: formKey,
      fields: [
        M360TextField(
          label: 'ڈرائیور کا نام',
          controller: name,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'نام درج کرنا ضروری ہے' : null,
        ),
        const SizedBox(height: 12),
        M360TextField(
          label: 'فون نمبر (اختیاری)',
          controller: phone,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        M360TextField(
          label: 'لائسنس نمبر (اختیاری)',
          controller: license,
        ),
      ],
      onSave: () async {
        final tenantId = ref.read(currentTenantIdProvider);
        if (tenantId == null) return false;
        return ref.read(transportProvider.notifier).saveDriver(
              TransportDriver(
                id: existing?.id ?? _uuid.v4(),
                tenantId: tenantId,
                name: name.text.trim(),
                phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
                licenseNumber:
                    license.text.trim().isEmpty ? null : license.text.trim(),
              ),
            );
      },
      readError: () => ref.read(transportProvider).error,
    ),
  ).whenComplete(() {
    name.dispose();
    phone.dispose();
    license.dispose();
  });
}

// ─────────────────────────────────────────────
// Route form
// ─────────────────────────────────────────────

/// Shows the create/edit route dialog.
Future<void> showTransportRouteForm(
  BuildContext context,
  WidgetRef ref, {
  TransportRoute? existing,
}) {
  final name = TextEditingController(text: existing?.name ?? '');
  final start = TextEditingController(text: existing?.startPoint ?? '');
  final end = TextEditingController(text: existing?.endPoint ?? '');
  final formKey = GlobalKey<FormState>();

  return _showTransportForm(
    context,
    title: existing == null ? 'نیا راستہ' : 'راستے میں ترمیم',
    icon: Icons.route_outlined,
    build: () => _TransportFormShell(
      formKey: formKey,
      fields: [
        M360TextField(
          label: 'راستے کا نام',
          hint: 'مثلاً ماڈل ٹاؤن روٹ',
          controller: name,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'نام درج کرنا ضروری ہے' : null,
        ),
        const SizedBox(height: 12),
        M360TextField(
          label: 'آغاز (اختیاری)',
          controller: start,
        ),
        const SizedBox(height: 12),
        M360TextField(
          label: 'اختتام (اختیاری)',
          controller: end,
        ),
      ],
      onSave: () async {
        final tenantId = ref.read(currentTenantIdProvider);
        if (tenantId == null) return false;
        return ref.read(transportProvider.notifier).saveRoute(
              TransportRoute(
                id: existing?.id ?? _uuid.v4(),
                tenantId: tenantId,
                name: name.text.trim(),
                startPoint:
                    start.text.trim().isEmpty ? null : start.text.trim(),
                endPoint: end.text.trim().isEmpty ? null : end.text.trim(),
              ),
            );
      },
      readError: () => ref.read(transportProvider).error,
    ),
  ).whenComplete(() {
    name.dispose();
    start.dispose();
    end.dispose();
  });
}

// ─────────────────────────────────────────────
// Stop form
// ─────────────────────────────────────────────

/// Shows the create/edit stop dialog for a route.
Future<void> showTransportStopForm(
  BuildContext context,
  WidgetRef ref, {
  required String routeId,
  TransportStop? existing,
  int nextSequence = 0,
}) {
  final name = TextEditingController(text: existing?.name ?? '');
  final formKey = GlobalKey<FormState>();

  return _showTransportForm(
    context,
    title: existing == null ? 'نیا اسٹاپ' : 'اسٹاپ میں ترمیم',
    icon: Icons.location_on_outlined,
    build: () => _TransportFormShell(
      formKey: formKey,
      fields: [
        M360TextField(
          label: 'اسٹاپ کا نام',
          controller: name,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'نام درج کرنا ضروری ہے' : null,
        ),
      ],
      onSave: () async {
        final tenantId = ref.read(currentTenantIdProvider);
        if (tenantId == null) return false;
        return ref.read(transportProvider.notifier).saveStop(
              TransportStop(
                id: existing?.id ?? _uuid.v4(),
                tenantId: tenantId,
                routeId: routeId,
                name: name.text.trim(),
                sequence: existing?.sequence ?? nextSequence,
              ),
            );
      },
      readError: () => ref.read(transportProvider).error,
    ),
  ).whenComplete(name.dispose);
}

// ─────────────────────────────────────────────
// Assignment form
// ─────────────────────────────────────────────

/// Shows the create/edit assignment dialog (vehicle + driver + route).
Future<void> showTransportAssignmentForm(
  BuildContext context,
  WidgetRef ref, {
  required List<TransportVehicle> vehicles,
  required List<TransportDriver> drivers,
  required List<TransportRoute> routes,
  TransportAssignment? existing,
}) {
  return showM360Dialog<void>(
    context,
    title: existing == null ? 'نئی اسائنمنٹ' : 'اسائنمنٹ میں ترمیم',
    icon: Icons.assignment_outlined,
    content: _AssignmentForm(
      vehicles: vehicles,
      drivers: drivers,
      routes: routes,
      existing: existing,
    ),
  );
}

class _AssignmentForm extends ConsumerStatefulWidget {
  final List<TransportVehicle> vehicles;
  final List<TransportDriver> drivers;
  final List<TransportRoute> routes;
  final TransportAssignment? existing;

  const _AssignmentForm({
    required this.vehicles,
    required this.drivers,
    required this.routes,
    this.existing,
  });

  @override
  ConsumerState<_AssignmentForm> createState() => _AssignmentFormState();
}

class _AssignmentFormState extends ConsumerState<_AssignmentForm> {
  String? _vehicleId;
  String? _driverId;
  String? _routeId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _vehicleId = widget.existing?.vehicleId;
    _driverId = widget.existing?.driverId;
    _routeId = widget.existing?.routeId;
  }

  Future<void> _save() async {
    if (_vehicleId == null || _routeId == null) {
      setState(() => _error = 'براہ کرم گاڑی اور راستہ دونوں منتخب کریں۔');
      return;
    }
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) {
      setState(() => _error = 'براہ کرم پہلے لاگ اِن کریں۔');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await ref
        .read(transportProvider.notifier)
        .saveAssignment(TransportAssignment(
          id: widget.existing?.id ?? _uuid.v4(),
          tenantId: tenantId,
          vehicleId: _vehicleId!,
          routeId: _routeId!,
          driverId: _driverId,
        ));
    if (!mounted) return;
    if (ok) {
      showM360SnackBar(context, 'اسائنمنٹ محفوظ ہو گئی۔');
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = ref.read(transportProvider).error ??
            'محفوظ نہیں ہو سکی۔ دوبارہ کوشش کریں۔';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        M360Dropdown<String>(
          label: 'گاڑی',
          hint: widget.vehicles.isEmpty
              ? 'کوئی گاڑی درج نہیں'
              : 'گاڑی منتخب کریں',
          value: _vehicleId,
          items: [
            for (final v in widget.vehicles)
              M360DropdownItem(
                  value: v.id, label: '${v.plateNumber} — ${v.vehicleType}'),
          ],
          onChanged: (v) => setState(() => _vehicleId = v),
        ),
        const SizedBox(height: 12),
        M360Dropdown<String>(
          label: 'ڈرائیور (اختیاری)',
          hint: 'ڈرائیور منتخب کریں',
          value: _driverId,
          items: [
            for (final d in widget.drivers)
              M360DropdownItem(value: d.id, label: d.name),
          ],
          onChanged: (v) => setState(() => _driverId = v),
        ),
        const SizedBox(height: 12),
        M360Dropdown<String>(
          label: 'راستہ',
          hint: widget.routes.isEmpty
              ? 'کوئی راستہ درج نہیں'
              : 'راستہ منتخب کریں',
          value: _routeId,
          items: [
            for (final r in widget.routes)
              M360DropdownItem(value: r.id, label: r.name),
          ],
          onChanged: (v) => setState(() => _routeId = v),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textDirection: TextDirection.rtl,
            style: const TextStyle(color: Colors.red),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            M360TertiaryButton(
              label: 'منسوخ',
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            M360PrimaryButton(
              label: 'محفوظ کریں',
              isLoading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ],
    );
  }
}
