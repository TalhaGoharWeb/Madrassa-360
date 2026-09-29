import 'package:flutter/material.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'design_tokens.dart';

/// مدرسہ 360 — اسٹیٹس چِپ
/// The single canonical status chip. Use [M360StatusChip] (or its semantic
/// factories) for every entity status — table cells, detail headers, list
/// tiles — never ad-hoc colored containers.

/// Canonical entity statuses with fixed color + Urdu label.
enum M360Status {
  /// فعال / Active (green).
  active,

  /// غیر فعال / Inactive (grey).
  inactive,

  /// زیر التوا / Pending (amber).
  pending,

  /// مکمل / Completed (teal).
  complete,

  /// منسوخ / Cancelled (red).
  cancelled,

  /// واجب الادا / Due (orange).
  due,

  /// ادا شدہ / Paid (green).
  paid,

  /// میعاد ختم / Expired (grey).
  expired,

  /// مسودہ / Draft (grey).
  draft,
}

/// Attendance statuses with fixed color + Urdu label.
enum M360AttendanceStatus {
  /// حاضر (green).
  present,

  /// غیر حاضر (red).
  absent,

  /// رخصت (amber).
  leave,

  /// دیر سے (orange).
  late,

  /// چھٹی کا دن (grey).
  holiday,
}

/// Fee/payment statuses with fixed color + Urdu label.
enum M360FeeStatus {
  /// ادا شدہ (green).
  paid,

  /// جزوی ادا شدہ (amber).
  partial,

  /// واجب الادا (orange).
  due,

  /// بقایا (red).
  overdue,

  /// معاف (grey).
  waived,
}

/// Canonical status chip: fixed color + Urdu label per status.
class M360StatusChip extends StatelessWidget {
  /// Creates a chip for a canonical [M360Status].
  const M360StatusChip({super.key, required this.status})
      : _attendance = null,
        _fee = null,
        _kind = _Kind.status;

  /// Creates a chip for an attendance status.
  const M360StatusChip.attendance({
    super.key,
    required M360AttendanceStatus attendance,
  })  : status = null,
        _attendance = attendance,
        _fee = null,
        _kind = _Kind.attendance;

  /// Creates a chip for a fee status.
  const M360StatusChip.fee({super.key, required M360FeeStatus fee})
      : status = null,
        _attendance = null,
        _fee = fee,
        _kind = _Kind.fee;

  /// Canonical entity status (non-attendance/fee constructor).
  final M360Status? status;
  final M360AttendanceStatus? _attendance;
  final M360FeeStatus? _fee;
  final _Kind _kind;

  _ChipSpec _spec() {
    switch (_kind) {
      case _Kind.attendance:
        switch (_attendance!) {
          case M360AttendanceStatus.present:
            return _ChipSpec('حاضر', AppColors.success);
          case M360AttendanceStatus.absent:
            return _ChipSpec('غیر حاضر', AppColors.error);
          case M360AttendanceStatus.leave:
            return _ChipSpec('رخصت', AppColors.warning);
          case M360AttendanceStatus.late:
            return _ChipSpec('دیر سے', AppColors.accent);
          case M360AttendanceStatus.holiday:
            return _ChipSpec('چھٹی', AppColors.textSecondary);
        }
      case _Kind.fee:
        switch (_fee!) {
          case M360FeeStatus.paid:
            return _ChipSpec('ادا شدہ', AppColors.success);
          case M360FeeStatus.partial:
            return _ChipSpec('جزوی', AppColors.warning);
          case M360FeeStatus.due:
            return _ChipSpec('واجب الادا', AppColors.accent);
          case M360FeeStatus.overdue:
            return _ChipSpec('بقایا', AppColors.error);
          case M360FeeStatus.waived:
            return _ChipSpec('معاف', AppColors.textSecondary);
        }
      case _Kind.status:
        switch (status!) {
          case M360Status.active:
            return _ChipSpec('فعال', AppColors.success);
          case M360Status.inactive:
            return _ChipSpec('غیر فعال', AppColors.textSecondary);
          case M360Status.pending:
            return _ChipSpec('زیر التوا', AppColors.warning);
          case M360Status.complete:
            return _ChipSpec('مکمل', AppColors.primary);
          case M360Status.cancelled:
            return _ChipSpec('منسوخ', AppColors.error);
          case M360Status.due:
            return _ChipSpec('واجب الادا', AppColors.accent);
          case M360Status.paid:
            return _ChipSpec('ادا شدہ', AppColors.success);
          case M360Status.expired:
            return _ChipSpec('میعاد ختم', AppColors.textSecondary);
          case M360Status.draft:
            return _ChipSpec('مسودہ', AppColors.textSecondary);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec();
    // The tinted background is near-white, so the raw status color as text
    // fails contrast (amber ~2.1:1, orange ~2.4:1). Darken the foreground
    // toward the same hue for a readable label; the tint + Urdu label keep
    // the status recognizable. Not color-alone: the text label carries the
    // meaning, and the semantics label announces it as a status.
    final foreground = _darken(spec.color);
    return Semantics(
      label: 'حالت: ${spec.label}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 28),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(
          horizontal: M360Spacing.sm,
          vertical: M360Spacing.xxs,
        ),
        decoration: BoxDecoration(
          color: spec.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(M360Radius.pill),
        ),
        child: Text(
          spec.label,
          textDirection: TextDirection.rtl,
          style: AppTypography.labelSmall.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Darkens [color] toward the same hue for an accessible text foreground
  /// on the chip's light tinted background.
  static Color _darken(Color color, [double amount = 0.32]) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }
}

enum _Kind { status, attendance, fee }

class _ChipSpec {
  const _ChipSpec(this.label, this.color);
  final String label;
  final Color color;
}
