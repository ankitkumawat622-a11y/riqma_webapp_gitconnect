import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ModernSearchableDropdown extends StatefulWidget {
  final String label;
  final String? value;
  final Map<String, String> items;
  final MaterialColor color;
  final IconData icon;
  final void Function(String? value) onChanged;
  final String? hint;

  const ModernSearchableDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.color,
    required this.icon,
    required this.onChanged,
    this.hint,
    this.enabled = true,
    this.showLabel = true,
    this.compact = false,
  });

  final bool enabled;
  final bool showLabel;
  final bool compact;

  @override
  State<ModernSearchableDropdown> createState() => _ModernSearchableDropdownState();
}

class _ModernSearchableDropdownState extends State<ModernSearchableDropdown> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final displayValue = widget.value != null ? widget.items[widget.value] : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.enabled ? () {
          showDialog<void>(
            context: context,
            builder: (context) => _SearchableDialog(
              title: widget.label,
              items: widget.items,
              selectedValue: widget.value,
              color: widget.color,
              onSelected: widget.onChanged,
            ),
          );
        } : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 8 : 16, 
            vertical: widget.compact ? 6 : 12,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(widget.compact ? 8 : 16),
            border: Border.all(
              color: !widget.enabled 
                  ? Colors.grey.shade100 
                  : (_isHovering ? widget.color.shade300 : Colors.grey.shade200),
              width: (widget.enabled && _isHovering) ? 1.5 : 1,
            ),
            boxShadow: [
              if (widget.enabled)
                BoxShadow(
                  color: widget.color.withValues(alpha: _isHovering ? 0.15 : 0.05),
                  blurRadius: _isHovering ? 12 : 4,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Opacity(
            opacity: widget.enabled ? 1.0 : 0.5,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(widget.compact ? 4 : 8),
                  decoration: BoxDecoration(
                    color: widget.color.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(widget.icon, color: widget.color.shade700, size: widget.compact ? 14 : 18),
                ),
                SizedBox(width: widget.compact ? 8 : 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.showLabel && !widget.compact) ...[
                        Text(
                          widget.label,
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Text(
                        displayValue ?? widget.hint ?? 'Select ${widget.label}',
                        style: GoogleFonts.outfit(
                          fontSize: widget.compact ? 12 : 14,
                          color: displayValue != null ? const Color(0xFF1A1F36) : Colors.grey[500],
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: _isHovering ? widget.color.shade400 : Colors.grey[400],
                  size: widget.compact ? 16 : 20,
                ),
              ],
            ),
          ),
        ),
    ),
  );
  }
}

class _SearchableDialog extends StatefulWidget {
  final String title;
  final Map<String, String> items;
  final String? selectedValue;
  final MaterialColor color;
  final void Function(String? value) onSelected;

  const _SearchableDialog({
    required this.title,
    required this.items,
    this.selectedValue,
    required this.color,
    required this.onSelected,
  });

  @override
  State<_SearchableDialog> createState() => _SearchableDialogState();
}

class _SearchableDialogState extends State<_SearchableDialog> {
  late List<MapEntry<String, String>> _filteredItems;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items.entries.toList();
  }

  void _filterItems(String query) {
    setState(() {
      _filteredItems = widget.items.entries
          .where((entry) => entry.value.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      elevation: 0,
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        decoration: BoxDecoration(
           borderRadius: BorderRadius.circular(20),
           color: Colors.white,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select ${widget.title}',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1F36),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  color: Colors.grey[400],
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: GoogleFonts.outfit(color: Colors.grey[400]),
                prefixIcon: Icon(Icons.search_rounded, color: widget.color.shade400),
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: GoogleFonts.outfit(),
              onChanged: _filterItems,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredItems.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    final isSelected = widget.selectedValue == null;
                    return _buildItemTile(null, 'All ${widget.title}s', isSelected);
                  }
                  
                  final entry = _filteredItems[index - 1];
                  final isSelected = widget.selectedValue == entry.key;
                  return _buildItemTile(entry.key, entry.value, isSelected);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildItemTile(String? key, String label, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          widget.onSelected(key);
          Navigator.pop(context);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? widget.color.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
               color: isSelected ? widget.color.shade200 : Colors.grey.shade100,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? widget.color.shade800 : Colors.grey[800],
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: widget.color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
