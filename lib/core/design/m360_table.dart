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
/// Optional built-ins: row selection ([selectable], [selectedIds],
/// [onSelectionChanged]) and client-side pagination ([pageSize],
/// [pageSizeOptions]).
///
/// Pure presentation: sorting, selection state (when uncontrolled), and
/// pagination are view-local; the caller owns the data. Bulk actions go
/// through [onSelectionChanged].

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
    this.rowId,
    this.selectable = false,
    this.selectedIds,
    this.onSelectionChanged,
    this.pageSize,
    this.pageSizeOptions = const [10, 25, 50],
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

  /// Stable identity for selection callbacks and pagination state.
  /// Defaults to the row itself (identity). Must be non-null per row.
  final Object? Function(T row)? rowId;

  /// Enables row selection UI. Defaults to false.
  final bool selectable;

  /// Controlled selected ids; when null the table keeps selection
  /// internally and still reports it via [onSelectionChanged].
  final Set<Object>? selectedIds;

  /// Fired with the current selected ids after every change.
  final ValueChanged<Set<Object>>? onSelectionChanged;

  /// Rows per page; null disables pagination. Defaults to null.
  final int? pageSize;

  /// Page-size options shown in the footer; defaults to [10, 25, 50].
  final List<int> pageSizeOptions;

  @override
  State<M360ResponsiveTable<T>> createState() => _M360ResponsiveTableState<T>();
}

class _M360ResponsiveTableState<T> extends State<M360ResponsiveTable<T>> {
  int? _sortColumnIndex;
  bool _sortAscending = true;
  int _pageIndex = 0;
  late int _effectivePageSize;
  Set<Object> _internalSelection = {};

  @override
  void initState() {
    super.initState();
    _effectivePageSize = widget.pageSize ?? widget.rows.length;
  }

  @override
  void didUpdateWidget(M360ResponsiveTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageSize != widget.pageSize) {
      _effectivePageSize = widget.pageSize ?? widget.rows.length;
      _pageIndex = 0;
    }
    // Prune selection ids that no longer exist in the data.
    final ids = _allIds;
    _internalSelection = _internalSelection.intersection(ids);
  }

  /// Identity of a row; used as the selection key.
  Object _idOf(T row) {
    final id = widget.rowId != null ? widget.rowId!(row) : row;
    assert(id != null, 'M360ResponsiveTable: rowId must be non-null.');
    return id!;
  }

  Set<Object> get _allIds => widget.rows.map(_idOf).toSet();

  Set<Object> get _selection =>
      widget.selectedIds ?? _internalSelection;

  bool get _selectionControlled => widget.selectedIds != null;

  void _setSelection(Set<Object> next) {
    if (!_selectionControlled) {
      setState(() => _internalSelection = next);
    } else {
      setState(() {});
    }
    widget.onSelectionChanged?.call(Set<Object>.unmodifiable(next));
  }

  void _toggleRow(Object id, bool? selected) {
    final next = Set<Object>.of(_selection);
    if (selected == true) {
      next.add(id);
    } else {
      next.remove(id);
    }
    _setSelection(next);
  }

  void _toggleAll(bool? selected) {
    _setSelection(selected == true ? _allIds : <Object>{});
  }

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

  List<T> get _pagedRows {
    final rows = _sortedRows;
    if (widget.pageSize == null) return rows;
    final totalPages = _totalPages;
    if (totalPages == 0) return const [];
    final clamped = _pageIndex.clamp(0, totalPages - 1);
    final start = clamped * _effectivePageSize;
    final end = (start + _effectivePageSize).clamp(0, rows.length);
    return rows.sublist(start, end);
  }

  int get _totalPages {
    if (widget.pageSize == null || widget.rows.isEmpty) return 1;
    return (widget.rows.length / _effectivePageSize).ceil();
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  void _goToPage(int page) {
    setState(() {
      _pageIndex = page.clamp(0, _totalPages - 1);
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
        final body = constraints.maxWidth < M360Breakpoint.mobile
            ? _buildCardList()
            : _buildTable();
        if (widget.pageSize == null) return body;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            body,
            _buildPaginationFooter(),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // Wide layout: sortable DataTable.
  // ------------------------------------------------------------------

  Widget _buildTable() {
    final hasActions = widget.rowActions.isNotEmpty;
    final selection = _selection;
    final allIds = _allIds;
    final allSelected =
        allIds.isNotEmpty && selection.containsAll(allIds);
    final someSelected =
        selection.isNotEmpty && !allSelected;
    // DataTable reports column indexes including the selection column;
    // subtract it so sorting maps back onto [widget.columns].
    final sortOffset = widget.selectable ? 1 : 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          sortColumnIndex: _sortColumnIndex != null
              ? _sortColumnIndex! + (widget.selectable ? 1 : 0)
              : null,
          sortAscending: _sortAscending,
          headingTextStyle: AppTypography.labelNastaliq,
          dataTextStyle: AppTypography.bodyMedium,
          headingRowColor: WidgetStateProperty.all(AppColors.surface),
          dataRowMinHeight: 56,
          dataRowMaxHeight: 72,
          headingRowHeight: 56,
          columnSpacing: M360Spacing.lg,
          horizontalMargin: M360Spacing.md,
          dividerThickness: 1,
          columns: [
            if (widget.selectable)
              DataColumn(
                label: Checkbox(
                  tristate: true,
                  value: allSelected
                      ? true
                      : someSelected
                          ? null
                          : false,
                  onChanged: _toggleAll,
                ),
              ),
            for (int i = 0; i < widget.columns.length; i++)
              DataColumn(
                label: Text(
                  widget.columns[i].title,
                  textDirection: TextDirection.rtl,
                ),
                onSort: widget.columns[i].sortable
                    ? (index, ascending) => _onSort(
                          index - sortOffset,
                          ascending,
                        )
                    : null,              ),
            if (hasActions)
              const DataColumn(
                label: Text(
                  'کارروائی',
                  textDirection: TextDirection.rtl,
                ),
              ),
          ],
          rows: [
            for (final row in _pagedRows)
              DataRow(
                selected:
                    widget.selectable && selection.contains(_idOf(row)),
                onSelectChanged: widget.selectable
                    ? (selected) => _toggleRow(_idOf(row), selected)
                    : null,
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
    final rows = _pagedRows;
    final selection = _selection;
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(M360Spacing.md),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: M360Spacing.sm),
      itemBuilder: (context, index) {
        final row = rows[index];
        final id = _idOf(row);
        return M360Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.selectable)
                Row(
                  children: [
                    Checkbox(
                      value: selection.contains(id),
                      onChanged: (selected) =>
                          _toggleRow(id, selected),
                    ),
                    Expanded(
                      child: Text(
                        widget.columns.first.value(row),
                        textDirection: TextDirection.rtl,
                        style: AppTypography.labelNastaliq,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
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
                  alignment: AlignmentDirectional.centerEnd,
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

  // ------------------------------------------------------------------
  // Pagination footer.
  // ------------------------------------------------------------------

  Widget _buildPaginationFooter() {
    final totalPages = _totalPages;
    final page = _pageIndex.clamp(0, totalPages - 1);
    final start = page * _effectivePageSize + 1;
    final end =
        (start + _effectivePageSize - 1).clamp(0, widget.rows.length);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: M360Spacing.md,
        vertical: M360Spacing.sm,
      ),
      child: Row(
        children: [
          Text(
            '$start–$end از ${widget.rows.length}',
            textDirection: TextDirection.rtl,
            style: AppTypography.bodySmall,
          ),
          const Spacer(),
          DropdownButton<int>(
            value: _effectivePageSize,
            underline: const SizedBox.shrink(),
            items: [
              for (final option in widget.pageSizeOptions)
                DropdownMenuItem(
                  value: option,
                  child: Text(
                    '$option',
                    textDirection: TextDirection.ltr,
                    style: AppTypography.bodySmall,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _effectivePageSize = value;
                _pageIndex = 0;
              });
            },
          ),
          Text(
            ' فی صفحہ',
            textDirection: TextDirection.rtl,
            style: AppTypography.bodySmall,
          ),
          const SizedBox(width: M360Spacing.sm),
          IconButton(
            tooltip: 'پچھلا صفحہ',
            icon: const Icon(Icons.chevron_right),
            color: AppColors.textSecondary,
            onPressed: page > 0 ? () => _goToPage(page - 1) : null,
          ),
          Text(
            '${page + 1} / $totalPages',
            textDirection: TextDirection.ltr,
            style: AppTypography.bodySmall,
          ),
          IconButton(
            tooltip: 'اگلا صفحہ',
            icon: const Icon(Icons.chevron_left),
            color: AppColors.textSecondary,
            onPressed:
                page < totalPages - 1 ? () => _goToPage(page + 1) : null,
          ),
        ],
      ),
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
                  color:
                      action.danger ? AppColors.error : AppColors.textPrimary,
                ),
                const SizedBox(width: M360Spacing.xs),
                Text(
                  action.label,
                  textDirection: TextDirection.rtl,
                  style: AppTypography.labelNastaliq.copyWith(
                    fontSize: 15,
                    color:
                        action.danger ? AppColors.error : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
