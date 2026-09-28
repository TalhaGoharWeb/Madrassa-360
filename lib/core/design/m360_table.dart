import 'package:flutter/material.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'design_tokens.dart';
import 'm360_cards.dart';
import 'm360_states.dart';

/// مدرسہ 360 — ریسپانسیو ڈیٹا ٹیبل
/// Responsive data table with Urdu headers.
///
/// * Wide screens (>= [M360Breakpoint.mobile]): a real table with sortable
///   Urdu headers and a «کارروائی» actions column.
/// * Narrow screens: the same data auto-falls-back to a card list — one
///   [M360Card] per row, each column rendered as «title: value».
///
/// Pure presentation: sorting is view-local; the caller owns the data.

/// One table column.
class M360TableColumn<T> {
  /// Creates a table column.
  const M360TableColumn({
    required this.title,
    required this.value,
    this.cell,
    this.sortable = false,
    this.sortKey,
  }) : assert(
          !sortable || sortKey != null,
          'Sortable columns need a sortKey.',
        );

  /// Urdu header label, e.g. «نام».
  final String title;

  /// Plain-text value for the row (used by the card fallback and as the
  /// default cell content).
  final String Function(T row) value;

  /// Optional custom cell (e.g. an [M360Badge]); defaults to [value] as
  /// Naskh text.
  final Widget Function(T row)? cell;

  /// Whether the column shows a sort affordance.
  final bool sortable;

  /// Comparable key used for sorting; required when [sortable] is true.
  final Comparable Function(T row)? sortKey;
}

/// One row action shown in the «کارروائی» column.
class M360TableAction<T> {
  /// Creates a row action.
  const M360TableAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  /// Urdu action label, e.g. «ترمیم کریں».
  final String label;

  /// Action icon.
  final IconData icon;

  /// Handler receiving the row.
  final void Function(T row) onTap;

  /// Renders the label/icon in the error color.
  final bool danger;
}

/// Responsive table: desktop table ↔ mobile card list.
class M360ResponsiveTable<T> extends StatefulWidget {
  /// Creates a responsive table.
  const M360ResponsiveTable({
    super.key,
    required this.columns,
    required this.rows,
    this.rowActions = const [],
    this.emptyIcon = Icons.table_chart_outlined,
    this.emptyTitle = 'کوئی ریکارڈ نہیں ملا',
    this.emptyDescription =
        'اس فہرست میں دکھانے کے لیے کوئی ریکارڈ موجود نہیں ہے۔',
  });

  /// Column definitions (Urdu headers).
  final List<M360TableColumn<T>> columns;

  /// Row data.
  final List<T> rows;

  /// Actions per row, rendered in the «کارروائی» column.
  final List<M360TableAction<T>> rowActions;

  /// Empty-state icon.
  final IconData emptyIcon;

  /// Empty-state Urdu title.
  final String emptyTitle;

  /// Empty-state Urdu description.
  final String emptyDescription;

  @override
  State<M360ResponsiveTable<T>> createState() =>
      _M360ResponsiveTableState<T>();
}

class _M360ResponsiveTableState<T> extends State<M360ResponsiveTable<T>> {
  int? _sortColumnIndex;
  bool _sortAscending = true;

  List<T> get _sortedRows {
    final rows = List<T>.of(widget.rows);
    if (_sortColumnIndex != null) {
      final column = widget.columns[_sortColumnIndex!];
      final key = column.sortKey;
      if (key != null) {
        rows.sort((a, b) => _sortAscending
            ? Comparable.compare(key(a), key(b))
            : Comparable.compare(key(b), key(a)));
      }
    }
    return rows;
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return M360EmptyState(
        icon: widget.emptyIcon,
        title: widget.emptyTitle,
        description: widget.emptyDescription,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < M360Breakpoint.mobile) {
          return _buildCardList();
        }
        return _buildTable();
      },
    );
  }

  // ------------------------------------------------------------------
  // Wide layout: sortable DataTable.
  // ------------------------------------------------------------------

  Widget _buildTable() {
    final hasActions = widget.rowActions.isNotEmpty;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          sortColumnIndex: _sortColumnIndex,
          sortAscending: _sortAscending,
          headingTextStyle: AppTypography.labelNastaliq,
          dataTextStyle: AppTypography.bodyMedium,
          headingRowColor:
              WidgetStateProperty.all(AppColors.surface),
          dataRowMinHeight: 56,
          dataRowMaxHeight: 72,
          headingRowHeight: 56,
          columnSpacing: M360Spacing.lg,
          horizontalMargin: M360Spacing.md,
          dividerThickness: 1,
          columns: [
            for (int i = 0; i < widget.columns.length; i++)
              DataColumn(
                label: Text(
                  widget.columns[i].title,
                  textDirection: TextDirection.rtl,
                ),
                onSort: widget.columns[i].sortable
                    ? (index, ascending) => _onSort(index, ascending)
                    : null,
              ),
            if (hasActions)
              const DataColumn(
                label: Text(
                  'کارروائی',
                  textDirection: TextDirection.rtl,
                ),
              ),
          ],
          rows: [
            for (final row in _sortedRows)
              DataRow(
                cells: [
                  for (final column in widget.columns)
                    DataCell(
                      column.cell != null
                          ? column.cell!(row)
                          : Text(
                              column.value(row),
                              textDirection: TextDirection.rtl,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                  if (hasActions)
                    DataCell(_ActionsMenu<T>(
                      row: row,
                      actions: widget.rowActions,
                    )),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Narrow layout: card list.
  // ------------------------------------------------------------------

  Widget _buildCardList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(M360Spacing.md),
      itemCount: _sortedRows.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: M360Spacing.sm),
      itemBuilder: (context, index) {
        final row = _sortedRows[index];
        return M360Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final column in widget.columns) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        column.title,
                        textDirection: TextDirection.rtl,
                        style: AppTypography.labelSmall,
                      ),
                    ),
                    const SizedBox(width: M360Spacing.xs),
                    Expanded(
                      child: column.cell != null
                          ? column.cell!(row)
                          : Text(
                              column.value(row),
                              textDirection: TextDirection.rtl,
                              style: AppTypography.bodyMedium,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: M360Spacing.xs),
              ],
              if (widget.rowActions.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: _ActionsMenu<T>(
                    row: row,
                    actions: widget.rowActions,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Overflow menu hosting the row actions.
class _ActionsMenu<T> extends StatelessWidget {
  const _ActionsMenu({required this.row, required this.actions});

  final T row;
  final List<M360TableAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<M360TableAction<T>>(
      tooltip: 'کارروائی',
      icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
      onSelected: (action) => action.onTap(row),
      itemBuilder: (context) => [
        for (final action in actions)
          PopupMenuItem<M360TableAction<T>>(
            value: action,
            child: Row(
              children: [
                Icon(
                  action.icon,
                  size: 20,
                  color: action.danger
                      ? AppColors.error
                      : AppColors.textPrimary,
                ),
                const SizedBox(width: M360Spacing.xs),
                Text(
                  action.label,
                  textDirection: TextDirection.rtl,
                  style: AppTypography.labelNastaliq.copyWith(
                    fontSize: 15,
                    color: action.danger
                        ? AppColors.error
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
