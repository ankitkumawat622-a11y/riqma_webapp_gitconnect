import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'bulk_dropdown_cell.dart' show kBulkRowHeight;

// ─── BulkOrderCell ────────────────────────────────────────────────────────────

class BulkOrderCell extends StatefulWidget {
  final int value;
  final bool isDuplicate;
  final ValueChanged<int> onChanged;
  final void Function(int endRow)? onDragFill;
  final int rowIndex;
  final int totalRows;

  const BulkOrderCell({
    super.key,
    required this.value,
    required this.isDuplicate,
    required this.onChanged,
    this.onDragFill,
    required this.rowIndex,
    required this.totalRows,
  });

  @override
  State<BulkOrderCell> createState() => _BulkOrderCellState();
}

class _BulkOrderCellState extends State<BulkOrderCell> {
  late TextEditingController _ctrl;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(BulkOrderCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update controller if the value changed externally (not from
    // the user typing in this cell).
    if (oldWidget.value != widget.value && !_hasFocus) {
      _ctrl.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onSubmit(String val) {
    final parsed = int.tryParse(val);
    if (parsed != null) widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final isDup = widget.isDuplicate;

    return Row(
      children: [
        Expanded(
          child: Focus(
            onFocusChange: (hasFocus) {
              setState(() => _hasFocus = hasFocus);
              if (!hasFocus) _onSubmit(_ctrl.text);
            },
            child: TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDup ? Colors.red.shade600 : const Color(0xFF1A1F36),
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDup
                        ? Colors.red.shade400
                        : Colors.grey.shade300,
                    width: isDup ? 1.5 : 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDup
                        ? Colors.red.shade500
                        : const Color(0xFF1A1F36),
                    width: 1.5,
                  ),
                ),
                filled: true,
                fillColor: isDup ? Colors.red.shade50 : Colors.white,
                // Subtle duplicate warning icon
                suffixIcon: isDup
                    ? Tooltip(
                        message: 'Duplicate order number',
                        child: Icon(Icons.warning_amber_rounded,
                            size: 14,
                            color: Colors.red.shade400),
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(
                    minWidth: 22, maxWidth: 22),
              ),
              onSubmitted: _onSubmit,
              onChanged: (val) {
                final parsed = int.tryParse(val);
                if (parsed != null) widget.onChanged(parsed);
              },
            ),
          ),
        ),
        // ── Drag-fill handle ─────────────────────────────────────────────
        if (widget.onDragFill != null)
          _OrderDragHandle(
            rowIndex: widget.rowIndex,
            totalRows: widget.totalRows,
            baseValue: widget.value,
            onFill: widget.onDragFill!,
          ),
      ],
    );
  }
}

// ─── Order Drag Handle ────────────────────────────────────────────────────────

class _OrderDragHandle extends StatefulWidget {
  final int rowIndex;
  final int totalRows;
  final int baseValue;
  final void Function(int endRow) onFill;

  const _OrderDragHandle({
    required this.rowIndex,
    required this.totalRows,
    required this.baseValue,
    required this.onFill,
  });

  @override
  State<_OrderDragHandle> createState() => _OrderDragHandleState();
}

class _OrderDragHandleState extends State<_OrderDragHandle> {
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
    final fillCount =
        _isDragging && _previewEndRow > widget.rowIndex
            ? _previewEndRow - widget.rowIndex
            : 0;

    return GestureDetector(
      onVerticalDragStart: (d) {
        setState(() {
          _isDragging = true;
          _startY = d.globalPosition.dy;
          _previewEndRow = widget.rowIndex;
        });
      },
      onVerticalDragUpdate: (d) {
        setState(
          () => _previewEndRow = _computeEndRow(d.globalPosition.dy),
        );
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
        message: fillCount > 0
            ? 'Auto-fill: ${widget.baseValue + 1}…${widget.baseValue + fillCount}'
            : 'Drag to auto-increment order',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(left: 4, top: 22),
              decoration: BoxDecoration(
                color: _isDragging
                    ? Colors.deepOrange.shade500
                    : Colors.deepOrange.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Preview badge
            if (fillCount > 0)
              Positioned(
                left: -12,
                top: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.shade600,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '+$fillCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
