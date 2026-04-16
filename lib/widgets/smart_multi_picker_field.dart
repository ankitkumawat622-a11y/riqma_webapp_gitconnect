import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SmartMultiPickerField extends StatefulWidget {
  final String label;
  final List<String> selectedValues;
  final Map<String, String> items; // Key: ID/Value, Value: Display Name
  final void Function(List<String> values) onChanged;
  final bool enabled;

  const SmartMultiPickerField({
    super.key,
    required this.label,
    required this.selectedValues,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<SmartMultiPickerField> createState() => _SmartMultiPickerFieldState();
}

class _SmartMultiPickerFieldState extends State<SmartMultiPickerField> {
  late TextEditingController _displayController;

  @override
  void initState() {
    super.initState();
    _updateDisplayController();
  }

  void _updateDisplayController() {
    if (widget.selectedValues.isEmpty) {
      _displayController = TextEditingController(text: '');
    } else {
      final names = widget.selectedValues
          .map((val) => widget.items[val] ?? val)
          .join(', ');
      _displayController = TextEditingController(text: names);
    }
  }

  @override
  void didUpdateWidget(SmartMultiPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedValues != oldWidget.selectedValues ||
        widget.items != oldWidget.items) {
      if (widget.selectedValues.isEmpty) {
        _displayController.text = '';
      } else {
        final names = widget.selectedValues
            .map((val) => widget.items[val] ?? val)
            .join(', ');
        _displayController.text = names;
      }
    }
  }

  @override
  void dispose() {
    _displayController.dispose();
    super.dispose();
  }

  void _showSelectionDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _MultiSelectionDialog(
        title: widget.label,
        items: widget.items,
        initialValues: widget.selectedValues,
        onSelected: (List<String> values) {
          widget.onChanged(values);
          if (values.isEmpty) {
            _displayController.text = '';
          } else {
            _displayController.text =
                values.map((val) => widget.items[val] ?? val).join(', ');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: widget.enabled ? () => _showSelectionDialog(context) : null,
          child: AbsorbPointer(
            child: TextFormField(
              controller: _displayController,
              enabled: widget.enabled,
              decoration: InputDecoration(
                labelText: widget.label,
                labelStyle: GoogleFonts.outfit(),
                hintText: 'Tap to select models',
                hintStyle: GoogleFonts.outfit(color: Colors.grey[400]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[200]!),
                ),
                suffixIcon: Icon(Icons.keyboard_arrow_down_rounded,
                    color: widget.enabled ? Colors.grey[600] : Colors.grey[300]),
                filled: true,
                fillColor: widget.enabled ? Colors.white : Colors.grey[100],
              ),
              style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: widget.enabled ? Colors.black : Colors.grey[600])
                  .copyWith(overflow: TextOverflow.ellipsis),
              maxLines: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class _MultiSelectionDialog extends StatefulWidget {
  final String title;
  final Map<String, String> items;
  final List<String> initialValues;
  final void Function(List<String> values) onSelected;

  const _MultiSelectionDialog({
    required this.title,
    required this.items,
    required this.initialValues,
    required this.onSelected,
  });

  @override
  State<_MultiSelectionDialog> createState() => _MultiSelectionDialogState();
}

class _MultiSelectionDialogState extends State<_MultiSelectionDialog> {
  late List<MapEntry<String, String>> _filteredItems;
  late List<String> _selectedValues;

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items.entries.toList();
    _selectedValues = List.from(widget.initialValues);
  }

  void _filterItems(String query) {
    setState(() {
      _filteredItems = widget.items.entries
          .where((entry) =>
              entry.value.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  void _toggleSelection(String key) {
    setState(() {
      if (_selectedValues.contains(key)) {
        _selectedValues.remove(key);
      } else {
        _selectedValues.add(key);
      }
    });
  }

  void _selectAll() {
    setState(() {
      final allFilteredKeys = _filteredItems.map((e) => e.key).toList();
      _selectedValues.addAll(allFilteredKeys);
      _selectedValues = _selectedValues.toSet().toList(); // Remove duplicates
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedValues.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.title,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1F36),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  color: Colors.grey[600],
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: GoogleFonts.outfit(color: Colors.grey[400], fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[400], size: 20),
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: GoogleFonts.outfit(fontSize: 14),
              onChanged: _filterItems,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _selectAll,
                  child: Text('Select All', style: GoogleFonts.outfit()),
                ),
                TextButton(
                  onPressed: _clearSelection,
                  child: Text('Clear', style: GoogleFonts.outfit(color: Colors.red)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _filteredItems.isEmpty
                  ? Center(
                      child: Text(
                        'No results found',
                        style: GoogleFonts.outfit(color: Colors.grey[500]),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredItems.length,
                      itemBuilder: (context, index) {
                        final entry = _filteredItems[index];
                        final isSelected = _selectedValues.contains(entry.key);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          child: Material(
                            color: isSelected
                                ? const Color(0xFFE3F2FD)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _toggleSelection(entry.key),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        entry.value,
                                        style: GoogleFonts.outfit(
                                          fontSize: 14,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                          color: isSelected
                                              ? const Color(0xFF0277BD)
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      isSelected
                                          ? Icons.check_box_rounded
                                          : Icons.check_box_outline_blank_rounded,
                                      color: isSelected
                                          ? const Color(0xFF0277BD)
                                          : Colors.grey[400],
                                      size: 24,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1F36),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  widget.onSelected(_selectedValues);
                  Navigator.pop(context);
                },
                child: Text('Done (${_selectedValues.length})', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
