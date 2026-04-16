import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'bulk_grid_controller.dart';

// ─── Preset color palette ─────────────────────────────────────────────────────

const _kPresetColors = [
  Color(0xFF1A1F36), // Dark Navy (default)
  Color(0xFFE53935), // Red
  Color(0xFF1565C0), // Blue
  Color(0xFF2E7D32), // Green
  Color(0xFFE65100), // Orange
  Color(0xFF6A1B9A), // Purple
  Color(0xFF00695C), // Teal
  Color(0xFF616161), // Grey
];

const _kPresetFontSizes = [11.0, 12.0, 13.0, 14.0, 16.0, 18.0, 20.0];

const _kDefaultColor = Color(0xFF1A1F36);

// ─── BulkRichTextCell ─────────────────────────────────────────────────────────

class BulkRichTextCell extends StatelessWidget {
  final List<RichSpan> spans;
  final ValueChanged<List<RichSpan>> onChanged;
  final bool hasDuplicate;
  final String placeholder;
  final int maxLines;

  const BulkRichTextCell({
    super.key,
    required this.spans,
    required this.onChanged,
    this.hasDuplicate = false,
    this.placeholder = 'Click to edit…',
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = spans.isEmpty || spansToPlain(spans).trim().isEmpty;

    final borderColor = hasDuplicate
        ? Colors.red.shade400
        : Colors.grey.shade300;
    final bgColor = hasDuplicate
        ? Colors.red.shade50
        : Colors.white;

    return InkWell(
      onTap: () => _openEditor(context),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: isEmpty
            ? Text(
                placeholder,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: Colors.grey.shade400,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
              )
            : _buildRichPreview(spans, maxLines: maxLines),
      ),
    );
  }

  Widget _buildRichPreview(List<RichSpan> spans, {int maxLines = 2}) {
    return Text.rich(
      TextSpan(
        children: spans.map((s) {
          return TextSpan(
            text: s.text,
            style: TextStyle(
              fontWeight: s.bold ? FontWeight.bold : FontWeight.normal,
              fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
              fontSize: s.fontSize,
              color: Color(s.colorArgb),
              fontFamily: GoogleFonts.outfit().fontFamily,
            ),
          );
        }).toList(),
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    final result = await showDialog<List<RichSpan>>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => _RichTextEditorDialog(
        initialSpans: spans,
        placeholder: placeholder,
      ),
    );
    if (result != null) {
      onChanged(result);
    }
  }
}

// ─── Rich Text Editor Dialog ──────────────────────────────────────────────────

class _RichTextEditorDialog extends StatefulWidget {
  final List<RichSpan> initialSpans;
  final String placeholder;

  const _RichTextEditorDialog({
    required this.initialSpans,
    required this.placeholder,
  });

  @override
  State<_RichTextEditorDialog> createState() => _RichTextEditorDialogState();
}

class _RichTextEditorDialogState extends State<_RichTextEditorDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Tab 0: Simple (single span, whole-cell formatting)
  late TextEditingController _simpleTextCtrl;
  bool _simpleBold = false;
  bool _simpleItalic = false;
  double _simpleFontSize = 14.0;
  Color _simpleColor = _kDefaultColor;

  // Tab 1: Advanced (multiple spans)
  late List<RichSpan> _advancedSpans;
  final TextEditingController _spanTextCtrl = TextEditingController();
  bool _spanBold = false;
  bool _spanItalic = false;
  double _spanFontSize = 14.0;
  Color _spanColor = _kDefaultColor;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _advancedSpans = List.from(widget.initialSpans);

    // Determine initial tab: single span → simple mode
    if (widget.initialSpans.length <= 1) {
      final s = widget.initialSpans.isEmpty ? null : widget.initialSpans.first;
      _simpleTextCtrl =
          TextEditingController(text: s?.text ?? '');
      _simpleBold = s?.bold ?? false;
      _simpleItalic = s?.italic ?? false;
      _simpleFontSize = s?.fontSize ?? 14.0;
      _simpleColor = s != null ? Color(s.colorArgb) : _kDefaultColor;
    } else {
      // Multiple spans → start on advanced tab
      final plain = spansToPlain(widget.initialSpans);
      _simpleTextCtrl = TextEditingController(text: plain);
      _tabController.index = 1;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _simpleTextCtrl.dispose();
    _spanTextCtrl.dispose();
    super.dispose();
  }

  List<RichSpan> _buildSimpleResult() {
    final text = _simpleTextCtrl.text;
    if (text.trim().isEmpty) return [];
    return [
      RichSpan(
        text: text,
        bold: _simpleBold,
        italic: _simpleItalic,
        fontSize: _simpleFontSize,
        colorArgb: _simpleColor.toARGB32(),
      ),
    ];
  }

  void _addAdvancedSpan() {
    final text = _spanTextCtrl.text;
    if (text.trim().isEmpty) return;
    setState(() {
      _advancedSpans.add(RichSpan(
        text: text,
        bold: _spanBold,
        italic: _spanItalic,
        fontSize: _spanFontSize,
        colorArgb: _spanColor.toARGB32(),
      ));
      _spanTextCtrl.clear();
    });
  }

  void _removeAdvancedSpan(int index) {
    setState(() => _advancedSpans.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Container(
        width: 600,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A1F36), Color(0xFF2D3561)],
                ),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.format_color_text_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Rich Text Editor',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // ── Tabs ─────────────────────────────────────────────────────────
            Container(
              color: const Color(0xFFF8F9FA),
              child: TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF1A1F36),
                unselectedLabelColor: Colors.grey.shade500,
                indicatorColor: const Color(0xFF1A1F36),
                labelStyle: GoogleFonts.outfit(
                    fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle:
                    GoogleFonts.outfit(fontSize: 13),
                tabs: const [
                  Tab(text: 'Simple (Single Style)'),
                  Tab(text: 'Advanced (Multi Span)'),
                ],
              ),
            ),

            // ── Tab Body ─────────────────────────────────────────────────────
            SizedBox(
              height: 360,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSimpleTab(),
                  _buildAdvancedTab(),
                ],
              ),
            ),

            // ── Footer ───────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(
                    top: BorderSide(color: Colors.grey.shade200)),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade600),
                    child: Text('Cancel', style: GoogleFonts.outfit()),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      final result =
                          _tabController.index == 0
                              ? _buildSimpleResult()
                              : List<RichSpan>.from(_advancedSpans);
                      Navigator.pop(context, result);
                    },
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text('Apply',
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1F36),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Simple Tab ─────────────────────────────────────────────────────────────

  Widget _buildSimpleTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FormatToolbar(
            bold: _simpleBold,
            italic: _simpleItalic,
            fontSize: _simpleFontSize,
            color: _simpleColor,
            onBoldChanged: (v) => setState(() => _simpleBold = v),
            onItalicChanged: (v) => setState(() => _simpleItalic = v),
            onFontSizeChanged: (v) => setState(() => _simpleFontSize = v),
            onColorChanged: (v) => setState(() => _simpleColor = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _simpleTextCtrl,
            autofocus: true,
            maxLines: 5,
            style: TextStyle(
              fontWeight:
                  _simpleBold ? FontWeight.bold : FontWeight.normal,
              fontStyle:
                  _simpleItalic ? FontStyle.italic : FontStyle.normal,
              fontSize: _simpleFontSize,
              color: _simpleColor,
              fontFamily: GoogleFonts.outfit().fontFamily,
            ),
            decoration: InputDecoration(
              hintText: widget.placeholder,
              hintStyle: GoogleFonts.outfit(
                  color: Colors.grey.shade400, fontSize: 13),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                    color: Color(0xFF1A1F36), width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 12),
          // Live preview
          if (_simpleTextCtrl.text.isNotEmpty)
            _PreviewCard(spans: _buildSimpleResult()),
        ],
      ),
    );
  }

  // ── Advanced (Multi-Span) Tab ──────────────────────────────────────────────

  Widget _buildAdvancedTab() {
    return Column(
      children: [
        // Add span section
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFFF8F9FA),
          child: Column(
            children: [
              _FormatToolbar(
                bold: _spanBold,
                italic: _spanItalic,
                fontSize: _spanFontSize,
                color: _spanColor,
                onBoldChanged: (v) => setState(() => _spanBold = v),
                onItalicChanged: (v) => setState(() => _spanItalic = v),
                onFontSizeChanged: (v) =>
                    setState(() => _spanFontSize = v),
                onColorChanged: (v) => setState(() => _spanColor = v),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _spanTextCtrl,
                      style: TextStyle(
                        fontWeight: _spanBold
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontStyle: _spanItalic
                            ? FontStyle.italic
                            : FontStyle.normal,
                        fontSize: _spanFontSize,
                        color: _spanColor,
                        fontFamily: GoogleFonts.outfit().fontFamily,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Type a word or phrase…',
                        hintStyle: GoogleFonts.outfit(
                            color: Colors.grey.shade400, fontSize: 13),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addAdvancedSpan(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _addAdvancedSpan,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text('Add',
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1F36),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Spans list + preview
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_advancedSpans.isNotEmpty) ...[
                  _PreviewCard(spans: _advancedSpans),
                  const SizedBox(height: 12),
                  Text('Spans (${_advancedSpans.length}):',
                      style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600)),
                  const SizedBox(height: 6),
                ],
                for (int i = 0; i < _advancedSpans.length; i++)
                  _SpanListTile(
                    span: _advancedSpans[i],
                    onDelete: () => _removeAdvancedSpan(i),
                  ),
                if (_advancedSpans.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Add spans using the fields above.\nEach span can have its own style.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                            color: Colors.grey.shade400, fontSize: 13),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Format Toolbar ───────────────────────────────────────────────────────────

class _FormatToolbar extends StatelessWidget {
  final bool bold;
  final bool italic;
  final double fontSize;
  final Color color;
  final ValueChanged<bool> onBoldChanged;
  final ValueChanged<bool> onItalicChanged;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<Color> onColorChanged;

  const _FormatToolbar({
    required this.bold,
    required this.italic,
    required this.fontSize,
    required this.color,
    required this.onBoldChanged,
    required this.onItalicChanged,
    required this.onFontSizeChanged,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        // Bold
        _ToolbarChip(
          label: 'B',
          active: bold,
          textStyle: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 13),
          onTap: () => onBoldChanged(!bold),
        ),
        // Italic
        _ToolbarChip(
          label: 'I',
          active: italic,
          textStyle:
              const TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
          onTap: () => onItalicChanged(!italic),
        ),
        // Font size picker
        Container(
          height: 32,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SizeButton(
                icon: Icons.remove_rounded,
                onTap: () {
                  final idx = _kPresetFontSizes.indexOf(fontSize);
                  if (idx > 0) onFontSizeChanged(_kPresetFontSizes[idx - 1]);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('${fontSize.round()}px',
                    style:
                        GoogleFonts.outfit(fontSize: 12, color: Colors.black87)),
              ),
              _SizeButton(
                icon: Icons.add_rounded,
                onTap: () {
                  final idx = _kPresetFontSizes.indexOf(fontSize);
                  if (idx < _kPresetFontSizes.length - 1) {
                    onFontSizeChanged(_kPresetFontSizes[idx + 1]);
                  }
                },
              ),
            ],
          ),
        ),
        // Color dots
        for (final c in _kPresetColors)
          GestureDetector(
            onTap: () => onColorChanged(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: color == c
                      ? Colors.blueAccent
                      : Colors.grey.shade300,
                  width: color == c ? 2.5 : 1,
                ),
                boxShadow: color == c
                    ? [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 4)]
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class _ToolbarChip extends StatelessWidget {
  final String label;
  final bool active;
  final TextStyle? textStyle;
  final VoidCallback onTap;

  const _ToolbarChip({
    required this.label,
    required this.active,
    this.textStyle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1A1F36) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? const Color(0xFF1A1F36)
                : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: (textStyle ?? const TextStyle(fontSize: 13)).copyWith(
            color: active ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}

class _SizeButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SizeButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 28,
        height: 32,
        child: Icon(icon, size: 14, color: Colors.grey.shade700),
      ),
    );
  }
}

// ─── Preview Card ─────────────────────────────────────────────────────────────

class _PreviewCard extends StatelessWidget {
  final List<RichSpan> spans;

  const _PreviewCard({required this.spans});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Preview:',
              style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: Colors.indigo.shade400,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: spans.map((s) {
                return TextSpan(
                  text: s.text,
                  style: TextStyle(
                    fontWeight:
                        s.bold ? FontWeight.bold : FontWeight.normal,
                    fontStyle:
                        s.italic ? FontStyle.italic : FontStyle.normal,
                    fontSize: s.fontSize,
                    color: Color(s.colorArgb),
                    fontFamily: GoogleFonts.outfit().fontFamily,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Span List Tile ───────────────────────────────────────────────────────────

class _SpanListTile extends StatelessWidget {
  final RichSpan span;
  final VoidCallback onDelete;

  const _SpanListTile({required this.span, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final tagParts = <String>[];
    if (span.bold) tagParts.add('Bold');
    if (span.italic) tagParts.add('Italic');
    if (span.fontSize != 14.0) tagParts.add('${span.fontSize.round()}px');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Color(span.colorArgb),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              '"${span.text}"',
              style: TextStyle(
                fontWeight: span.bold ? FontWeight.bold : FontWeight.normal,
                fontStyle:
                    span.italic ? FontStyle.italic : FontStyle.normal,
                fontSize: 13,
                color: Color(span.colorArgb),
                fontFamily: GoogleFonts.outfit().fontFamily,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (tagParts.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(tagParts.join(', '),
                  style: GoogleFonts.outfit(
                      fontSize: 10, color: Colors.grey.shade600)),
            ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onDelete,
            borderRadius: BorderRadius.circular(4),
            child: Icon(Icons.close_rounded,
                size: 16, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
