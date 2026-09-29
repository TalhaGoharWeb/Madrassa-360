/// دارالاقامہ فارم
/// Hostel create/edit dialogs + destructive confirmations (Phase 8).
///
/// All dialogs are built on the m360 component language ([M360Dialog],
/// [M360TextField], [M360Dropdown], [M360PrimaryButton]) and call the real
/// [HostelNotifier] write methods. With no backend the writes fail
/// honestly: the dialog keeps the entered data and shows the backend
/// error inline instead of closing with a fake success.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/design/m360.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/repositories/hostel_repository.dart';
import '../../../providers/hostel_provider.dart';
import '../../../providers/student_provider.dart';

const _uuid = Uuid();

String _bedStatusUr(HostelBedStatus s) => switch (s) {
      HostelBedStatus.available => 'خالی',
      HostelBedStatus.occupied => 'مصروف',
      HostelBedStatus.maintenance => 'مرمت میں',
    };

/// Destructive confirmation for hostel deletions (m360 destructive
/// pattern — red confirm, explicit warning, never silent).
///
/// Used by the widget test to assert the confirmation exists.
Future<bool> confirmHostelDelete(
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
// Building form
// ─────────────────────────────────────────────

/// Shows the create/edit building dialog.
Future<void> showHostelBuildingForm(
  BuildContext context, {
  HostelBuilding? existing,
}) {
  return showM360Dialog<void>(
    context,
    title: existing == null ? 'نئی عمارت' : 'عمارت میں ترمیم',
    icon: Icons.apartment_outlined,
    content: _BuildingForm(existing: existing),
  );
}

class _BuildingForm extends ConsumerStatefulWidget {
  final HostelBuilding? existing;

  const _BuildingForm({this.existing});

  @override
  ConsumerState<_BuildingForm> createState() => _BuildingFormState();
}

class _BuildingFormState extends ConsumerState<_BuildingForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _warden;
  late final TextEditingController _notes;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _warden = TextEditingController(text: widget.existing?.wardenName ?? '');
    _notes = TextEditingController(text: widget.existing?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _warden.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) {
      setState(() => _error = 'براہ کرم پہلے لاگ اِن کریں۔');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final building = HostelBuilding(
      id: widget.existing?.id ?? _uuid.v4(),
      tenantId: tenantId,
      name: _name.text.trim(),
      wardenName: _warden.text.trim().isEmpty ? null : _warden.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    final ok = await ref.read(hostelProvider.notifier).saveBuilding(building);
    if (!mounted) return;
    if (ok) {
      showM360SnackBar(context, 'عمارت محفوظ ہو گئی۔');
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = ref.read(hostelProvider).error ??
            'محفوظ نہیں ہو سکا۔ دوبارہ کوشش کریں۔';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          M360TextField(
            label: 'عمارت کا نام',
            hint: 'مثلاً دارالاقامہ بلاک اے',
            controller: _name,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'نام درج کرنا ضروری ہے'
                : null,
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'وارڈن کا نام (اختیاری)',
            controller: _warden,
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'نوٹ (اختیاری)',
            controller: _notes,
            maxLines: 2,
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
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Room form
// ─────────────────────────────────────────────

/// Shows the create/edit room dialog.
Future<void> showHostelRoomForm(
  BuildContext context, {
  required List<HostelBuilding> buildings,
  HostelRoom? existing,
  String? buildingId,
}) {
  return showM360Dialog<void>(
    context,
    title: existing == null ? 'نیا کمرہ' : 'کمرے میں ترمیم',
    icon: Icons.meeting_room_outlined,
    content: _RoomForm(
      buildings: buildings,
      existing: existing,
      buildingId: buildingId,
    ),
  );
}

class _RoomForm extends ConsumerStatefulWidget {
  final List<HostelBuilding> buildings;
  final HostelRoom? existing;
  final String? buildingId;

  const _RoomForm({
    required this.buildings,
    this.existing,
    this.buildingId,
  });

  @override
  ConsumerState<_RoomForm> createState() => _RoomFormState();
}

class _RoomFormState extends ConsumerState<_RoomForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _roomNo;
  late final TextEditingController _floor;
  late final TextEditingController _capacity;
  String? _buildingId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _roomNo = TextEditingController(text: widget.existing?.roomNo ?? '');
    _floor = TextEditingController(text: widget.existing?.floor ?? '');
    _capacity = TextEditingController(
        text: widget.existing == null ? '' : '${widget.existing!.capacity}');
    _buildingId = widget.existing?.buildingId ?? widget.buildingId;
  }

  @override
  void dispose() {
    _roomNo.dispose();
    _floor.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_buildingId == null) {
      setState(() => _error = 'براہ کرم عمارت منتخب کریں۔');
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
    final room = HostelRoom(
      id: widget.existing?.id ?? _uuid.v4(),
      tenantId: tenantId,
      buildingId: _buildingId!,
      roomNo: _roomNo.text.trim(),
      floor: _floor.text.trim().isEmpty ? null : _floor.text.trim(),
      capacity: int.tryParse(_capacity.text.trim()) ?? 0,
    );
    final ok = await ref.read(hostelProvider.notifier).saveRoom(room);
    if (!mounted) return;
    if (ok) {
      showM360SnackBar(context, 'کمرہ محفوظ ہو گیا۔');
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = ref.read(hostelProvider).error ??
            'محفوظ نہیں ہو سکا۔ دوبارہ کوشش کریں۔';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          M360Dropdown<String>(
            label: 'عمارت',
            hint: 'عمارت منتخب کریں',
            value: _buildingId,
            items: [
              for (final b in widget.buildings)
                M360DropdownItem(value: b.id, label: b.name),
            ],
            onChanged: (v) => setState(() => _buildingId = v),
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'کمرہ نمبر',
            hint: 'مثلاً 101',
            controller: _roomNo,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'کمرہ نمبر درج کرنا ضروری ہے'
                : null,
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'منزل (اختیاری)',
            controller: _floor,
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'گنجائش (بستروں کی تعداد)',
            controller: _capacity,
            keyboardType: TextInputType.number,
            validator: (v) => (v == null ||
                    v.trim().isEmpty ||
                    int.tryParse(v.trim()) == null)
                ? 'درست عدد درج کریں'
                : null,
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
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Bed form
// ─────────────────────────────────────────────

/// Shows the create/edit bed dialog.
Future<void> showHostelBedForm(
  BuildContext context, {
  required List<HostelRoom> rooms,
  HostelBed? existing,
  String? roomId,
}) {
  return showM360Dialog<void>(
    context,
    title: existing == null ? 'نیا بستر' : 'بستر میں ترمیم',
    icon: Icons.bed_outlined,
    content: _BedForm(
      rooms: rooms,
      existing: existing,
      roomId: roomId,
    ),
  );
}

class _BedForm extends ConsumerStatefulWidget {
  final List<HostelRoom> rooms;
  final HostelBed? existing;
  final String? roomId;

  const _BedForm({
    required this.rooms,
    this.existing,
    this.roomId,
  });

  @override
  ConsumerState<_BedForm> createState() => _BedFormState();
}

class _BedFormState extends ConsumerState<_BedForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _bedNo;
  String? _roomId;
  HostelBedStatus _status = HostelBedStatus.available;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bedNo = TextEditingController(text: widget.existing?.bedNo ?? '');
    _roomId = widget.existing?.roomId ?? widget.roomId;
    _status = widget.existing?.status ?? HostelBedStatus.available;
  }

  @override
  void dispose() {
    _bedNo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_roomId == null) {
      setState(() => _error = 'براہ کرم کمرہ منتخب کریں۔');
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
    final bed = HostelBed(
      id: widget.existing?.id ?? _uuid.v4(),
      tenantId: tenantId,
      roomId: _roomId!,
      bedNo: _bedNo.text.trim(),
      status: _status,
    );
    final ok = await ref.read(hostelProvider.notifier).saveBed(bed);
    if (!mounted) return;
    if (ok) {
      showM360SnackBar(context, 'بستر محفوظ ہو گیا۔');
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = ref.read(hostelProvider).error ??
            'محفوظ نہیں ہو سکا۔ دوبارہ کوشش کریں۔';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          M360Dropdown<String>(
            label: 'کمرہ',
            hint: 'کمرہ منتخب کریں',
            value: _roomId,
            items: [
              for (final r in widget.rooms)
                M360DropdownItem(value: r.id, label: 'کمرہ ${r.roomNo}'),
            ],
            onChanged: (v) => setState(() => _roomId = v),
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'بستر نمبر',
            hint: 'مثلاً بستر 1',
            controller: _bedNo,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'بستر نمبر درج کرنا ضروری ہے'
                : null,
          ),
          const SizedBox(height: 12),
          M360Dropdown<HostelBedStatus>(
            label: 'حالت',
            value: _status,
            items: [
              for (final s in HostelBedStatus.values)
                M360DropdownItem(value: s, label: _bedStatusUr(s)),
            ],
            onChanged: (v) =>
                setState(() => _status = v ?? HostelBedStatus.available),
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
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Allocation form
// ─────────────────────────────────────────────

/// Shows the allocate-bed dialog (uses REAL student rows from
/// [allStudentsProvider] — never invented names).
Future<void> showHostelAllocationForm(
  BuildContext context, {
  required List<HostelBed> beds,
}) {
  return showM360Dialog<void>(
    context,
    title: 'بستر الاٹ کریں',
    icon: Icons.hotel_outlined,
    content: _AllocationForm(beds: beds),
  );
}

class _AllocationForm extends ConsumerStatefulWidget {
  final List<HostelBed> beds;

  const _AllocationForm({required this.beds});

  @override
  ConsumerState<_AllocationForm> createState() => _AllocationFormState();
}

class _AllocationFormState extends ConsumerState<_AllocationForm> {
  String? _studentId;
  String? _bedId;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_studentId == null || _bedId == null) {
      setState(() => _error = 'براہ کرم طالب علم اور بستر دونوں منتخب کریں۔');
      return;
    }
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) {
      setState(() => _error = 'براہ کرم پہلے لاگ اِن کریں۔');
      return;
    }
    final students = ref.read(allStudentsProvider).valueOrNull ?? [];
    final student = students.where((s) => s.id == _studentId).firstOrNull;
    setState(() {
      _saving = true;
      _error = null;
    });
    final allocation = HostelAllocation(
      id: _uuid.v4(),
      tenantId: tenantId,
      bedId: _bedId!,
      studentId: _studentId!,
      studentName: student?.name ?? '',
      fromDate: DateTime.now(),
    );
    final ok = await ref.read(hostelProvider.notifier).allocate(allocation);
    if (!mounted) return;
    if (ok) {
      showM360SnackBar(context, 'بستر الاٹ ہو گیا۔');
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = ref.read(hostelProvider).error ??
            'الاٹ نہیں ہو سکا۔ دوبارہ کوشش کریں۔';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(allStudentsProvider);
    final availableBeds = widget.beds
        .where((b) => b.status == HostelBedStatus.available)
        .toList(growable: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        studentsAsync.when(
          data: (students) => M360Dropdown<String>(
            label: 'طالب علم',
            hint: students.isEmpty
                ? 'کوئی طالب علم نہیں ملا'
                : 'طالب علم منتخب کریں',
            value: _studentId,
            items: [
              for (final s in students)
                M360DropdownItem(value: s.id, label: s.name),
            ],
            onChanged: (v) => setState(() => _studentId = v),
          ),
          loading: () => const M360LoadingState(itemCount: 1),
          error: (_, __) => const Text(
            'طلبہ کی فہرست لوڈ نہیں ہو سکی۔',
            textDirection: TextDirection.rtl,
          ),
        ),
        const SizedBox(height: 12),
        M360Dropdown<String>(
          label: 'بستر',
          hint: availableBeds.isEmpty
              ? 'کوئی خالی بستر نہیں'
              : 'خالی بستر منتخب کریں',
          value: _bedId,
          items: [
            for (final b in availableBeds)
              M360DropdownItem(value: b.id, label: 'بستر ${b.bedNo}'),
          ],
          onChanged: (v) => setState(() => _bedId = v),
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
              label: 'الاٹ کریں',
              isLoading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ],
    );
  }
}
