import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Fixed height of each grid row — used to calculate how many rows are
/// covered by a drag-fill gesture.
const double kBulkRowHeight = 58.0;

// ─── BulkDropdownCell ─────────────────────────────────────────────────────────

class BulkDropdownCell extends StatelessWidget {
  final String? selectedId;
  final String? selectedName;
  final Map<String, String> items; // id → display name
  final ValueChanged<String> onSelected;
  final VoidCallback? onCleared;

  /// Called when the drag-fill handle ends. [endRow] is the target last row.
  final void Function(int endRow)? onDragFill;
  final int rowIndex;
  final int totalRows;
  final bool hasError;
  final String placeholder;

  const BulkDropdownCell({
    super.key,
    required this.selectedId,
    required this.selectedName,
    required this.items,
    required this.onSelected,
    this.onCleared,
    this.onDragFill,
    required this.rowIndex,
    required this.totalRows,
    this.hasError = false,
    this.placeholder = 'Select…',
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = selectedId != null && selectedName != null;

    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => _showPicker(context),
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: hasError
                    ? Colors.red.shade50
                    : hasValue
                        ? Colors.indigo.shade50
                        : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasError
                      ? Colors.red.shade400
                      : hasValue
                          ? Colors.indigo.shade200
                          : Colors.grey.shade300,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hasValue ? selectedName! : placeholder,
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        color: hasValue
                            ? const Color(0xFF1A1F36)
                            : Colors.grey.shade400,
                        fontStyle: hasValue
                            ? FontStyle.normal
                            : FontStyle.italic,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  if (hasValue && onCleared != null)
                    GestureDetector(
                      onTap: onCleared,
                      child: Icon(Icons.close_rounded,
                          size: 14, color: Colors.grey.shade500),
                    )
                  else
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 16, color: Colors.grey.shade500),
                ],
              ),
            ),
          ),
        ),
        // ── Drag-fill handle ─────────────────────────────────────────────
        if (onDragFill != null)
          _DragFillHandle(
            rowIndex: rowIndex,
            totalRows: totalRows,
            onFill: onDragFill!,
          ),
      ],
    );
  }

  void _showPicker(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black45,
      builder: (ctx) => _DropdownPickerDialog(
        title: placeholder.replaceAll('…', ''),
        items: items,
        initialId: selectedId,
        onSelected: (id) {
          onSelected(id);
          Navigator.pop(ctx);
        },
      ),
    );
  }
}

// ─── Dropdown Picker Dialog ───────────────────────────────────────────────────

class _DropdownPickerDialog extends StatefulWidget {
  final String title;
  final Map<String, String> items;
  final String? initialId;
  final ValueChanged<String> onSelected;

  const _DropdownPickerDialog({
    required this.title,
    required this.items,
    this.initialId,
    required this.onSelected,
  });

  @override
  State<_DropdownPickerDialog> createState() => _DropdownPickerDialogState();
}

class _DropdownPickerDialogState extends State<_DropdownPickerDialog> {
  late List<MapEntry<String, String>> _filtered;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = widget.items.entries.toList();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.toLowerCase();
      setState(() {
        _filtered = widget.items.entries
            .where((e) => e.value.toLowerCase().contains(q))
            .toList();
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 380,
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.65),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.title,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1F36),
                  ),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.grey.shade600,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints()),
              ],
            ),
            const SizedBox(height: 12),
            // Search
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search…',
                hintStyle: GoogleFonts.outfit(
                    color: Colors.grey.shade400, fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded,
                    color: Colors.grey.shade400, size: 18),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
              ),
              style: GoogleFonts.outfit(fontSize: 13),
            ),
            const SizedBox(height: 12),
            // List
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text('No results',
                          style: GoogleFonts.outfit(
                              color: Colors.grey.shade400)),
                    )
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (ctx, i) {
                        final e = _filtered[i];
                        final isSelected = e.key == widget.initialId;
                        return Material(
                          color: isSelected
                              ? const Color(0xFFE3F2FD)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              e.value,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isSelected
                                    ? const Color(0xFF0277BD)
                                    : Colors.black87,
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle_rounded,
                                    color: Color(0xFF0277BD), size: 18)
                                : null,
                            onTap: () => widget.onSelected(e.key),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 0),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Drag Fill Handle ─────────────────────────────────────────────────────────

class _DragFillHandle extends StatefulWidget {
  final int rowIndex;
  final int totalRows;
  final void Function(int endRow) onFill;

  const _DragFillHandle({
    required this.rowIndex,
    required this.totalRows,
    required this.onFill,
  });

  @override
  State<_DragFillHandle> createState() => _DragFillHandleState();
}

class _DragFillHandleState extends State<_DragFillHandle> {
  bool _isDragging = false;
  double _startY = 0;
  int _previewEndRow = -1;

  int _computeEndRow(double currentY) {
    final delta = currentY - _startY;
    final extra = (delta / kBulkRowHeight).round();
    return (widget.rowIndex + extra)
        .clamp(widget.rowIndex, widget.totalRows - 1);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart: (d) {
        setState(() {
          _isDragging = true;
          _startY = d.globalPosition.dy;
          _previewEndRow = widget.rowIndex;
        });
      },
      onVerticalDragUpdate: (d) {
        setState(() {
          _previewEndRow = _computeEndRow(d.globalPosition.dy);
        });
      },
      onVerticalDragEnd: (_) {
        if (_previewEndRow > widget.rowIndex) {
          widget.onFill(_previewEndRow);
        }
        setState(() {
          _isDragging = false;
          _previewEndRow = -1;
        });
      },
      onVerticalDragCancel: () {
        setState(() {
          _isDragging = false;
          _previewEndRow = -1;
        });
      },
      child: Tooltip(
        message: _isDragging && _previewEndRow > widget.rowIndex
            ? 'Fill ${_previewEndRow - widget.rowIndex} row(s) ↓'
            : 'Drag to fill down',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(left: 4, top: 26),
          decoration: BoxDecoration(
            color: _isDragging
                ? Colors.blue.shade600
                : Colors.blue.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
          child: _isDragging && _previewEndRow > widget.rowIndex
              ? Tooltip(
                  message: '+${_previewEndRow - widget.rowIndex}',
                  child: const SizedBox.expand(),
                )
              : null,
        ),
      ),
    );
  }
}

// ─── BulkFillPreviewOverlay ───────────────────────────────────────────────────
// Thin stripe shown on rows that will be filled during a drag operation.

class BulkFillPreviewStripe extends StatelessWidget {
  const BulkFillPreviewStripe({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.08),
            border: Border.all(color: Colors.blue.shade200, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

// Export constant so the order cell can share it
const double kRowHeight = kBulkRowHeight;
