import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:riqma_webapp/widgets/bulk_grid/bulk_dropdown_cell.dart';
import 'package:riqma_webapp/widgets/bulk_grid/bulk_grid_controller.dart';
import 'package:riqma_webapp/widgets/bulk_grid/bulk_order_cell.dart';
import 'package:riqma_webapp/widgets/bulk_grid/bulk_rich_text_cell.dart';
import 'package:riqma_webapp/widgets/modern_searchable_dropdown.dart';

// ─── Column width constants ───────────────────────────────────────────────────
const double _kColTitle = 240.0;
const double _kColDesc = 240.0;
const double _kColSubCat = 180.0;
const double _kColRef = 160.0;
const double _kColOrder = 90.0;
const double _kColDelete = 44.0;
const double _kColIndex = 40.0;

// ─── BulkTaskEntryScreen ──────────────────────────────────────────────────────

class BulkTaskEntryScreen extends StatefulWidget {
  const BulkTaskEntryScreen({super.key});

  @override
  State<BulkTaskEntryScreen> createState() => _BulkTaskEntryScreenState();
}

class _BulkTaskEntryScreenState extends State<BulkTaskEntryScreen> {
  late final BulkGridController _controller;
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

  // ── Firestore lookup maps ──────────────────────────────────────────────────
  // Models
  Map<String, String> _modelMap = {}; // id → display name
  Set<String> _selectedModelIds = {};

  // Main Categories (filtered by model)
  List<QueryDocumentSnapshot> _mainCatDocs = [];
  Map<String, String> _mainCatMap = {}; // id → name
  String? _selectedMainCatId;

  // Sub Categories (filtered by main cat)
  List<QueryDocumentSnapshot> _subCatDocs = [];
  Map<String, String> _subCatMap = {}; // id → name

  // References
  Map<String, String> _refMap = {}; // id → name
  Map<String, DocumentReference> _refRefMap = {}; // id → DocumentReference

  // Sub cat lookup for paste: name → {id, name, ref, mainRef}
  Map<String, Map<String, dynamic>> _subCatByName = {};
  Map<String, Map<String, dynamic>> _refByName = {};

  // Loading/sub-cat-ref lookup
  Map<String, DocumentReference> _subCatRefMap = {};
  Map<String, DocumentReference?> _subCatMainRefMap = {};

  // Firestore stream subs
  StreamSubscription<QuerySnapshot>? _modelSub;
  StreamSubscription<QuerySnapshot>? _mainCatSub;
  StreamSubscription<QuerySnapshot>? _subCatSub;
  StreamSubscription<QuerySnapshot>? _refSub;

  bool _isLoadingLookups = true;

  @override
  void initState() {
    super.initState();
    _controller = BulkGridController();
    _setupStreams();
  }

  @override
  void dispose() {
    _controller.dispose();
    _hScroll.dispose();
    _vScroll.dispose();
    _modelSub?.cancel();
    _mainCatSub?.cancel();
    _subCatSub?.cancel();
    _refSub?.cancel();
    super.dispose();
  }

  // ── Stream Setup ──────────────────────────────────────────────────────────

  void _setupStreams() {
    // Models
    _modelSub = FirebaseFirestore.instance
        .collection('turbinemodel')
        .snapshots()
        .listen((snap) {
      final map = <String, String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = data['turbine_model']?.toString() ??
            data['name']?.toString() ??
            'Unknown';
        map[doc.id] = name;
      }
      if (mounted) setState(() => _modelMap = map);
    });

    // Main Categories
    _mainCatSub = FirebaseFirestore.instance
        .collection('main_categories')
        .snapshots()
        .listen((snap) {
      if (mounted) {
        setState(() {
          _mainCatDocs = snap.docs;
          _refreshMainCatMap();
        });
      }
    });

    // Sub Categories
    _subCatSub = FirebaseFirestore.instance
        .collection('sub_categories')
        .snapshots()
        .listen((snap) {
      if (mounted) {
        setState(() {
          _subCatDocs = snap.docs;
          _refreshSubCatMap();
          _isLoadingLookups = false;
        });
      }
    });

    // References
    _refSub = FirebaseFirestore.instance
        .collection('references')
        .snapshots()
        .listen((snap) {
      final refMap = <String, String>{};
      final refRefMap = <String, DocumentReference>{};
      final byName = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = data['name']?.toString() ?? 'Unknown';
        refMap[doc.id] = name;
        refRefMap[doc.id] = doc.reference;
        byName[name] = {
          'id': doc.id,
          'name': name,
          'ref': doc.reference,
        };
      }
      if (mounted) {
        setState(() {
          _refMap = refMap;
          _refRefMap = refRefMap;
          _refByName = byName;
        });
      }
    });
  }

  void _refreshMainCatMap() {
    final filtered = _selectedModelIds.isEmpty
        ? _mainCatDocs
        : _mainCatDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            // Multi-model support
            if (data['is_all_models'] == true) return true;
            if (data['target_models'] is List) {
              final targets = (data['target_models'] as List).cast<String>();
              return targets.any((t) => _selectedModelIds.contains(t));
            }
            // Legacy single ref
            if (data['turbinemodel_ref'] is DocumentReference) {
              return _selectedModelIds
                  .contains((data['turbinemodel_ref'] as DocumentReference).id);
            }
            return false;
          }).toList();

    _mainCatMap = {
      for (final doc in filtered)
        doc.id: (doc.data() as Map<String, dynamic>)['name']?.toString() ??
            'Unknown',
    };

    // Reset if no longer valid
    if (_selectedMainCatId != null &&
        !_mainCatMap.containsKey(_selectedMainCatId)) {
      _selectedMainCatId = null;
      _refreshSubCatMap();
    }
  }

  void _refreshSubCatMap() {
    final filtered = _selectedMainCatId == null
        ? _subCatDocs
        : _subCatDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['main_categories_ref'] is DocumentReference) {
              return (data['main_categories_ref'] as DocumentReference).id ==
                  _selectedMainCatId;
            }
            return false;
          }).toList();

    _subCatMap = {};
    _subCatRefMap = {};
    _subCatMainRefMap = {};
    _subCatByName = {};

    for (final doc in filtered) {
      final data = doc.data() as Map<String, dynamic>;
      final name = data['name']?.toString() ?? 'Unknown';
      _subCatMap[doc.id] = name;
      _subCatRefMap[doc.id] = doc.reference;
      _subCatMainRefMap[doc.id] =
          data['main_categories_ref'] as DocumentReference?;
      _subCatByName[name] = {
        'id': doc.id,
        'name': name,
        'ref': doc.reference,
        'mainRef': data['main_categories_ref'] as DocumentReference?,
      };
    }
  }

  // ── Header Selector Callbacks ─────────────────────────────────────────────

  void _onModelsChanged(Set<String> ids) {
    setState(() {
      _selectedModelIds = ids;
      _selectedMainCatId = null;
      _refreshMainCatMap();
      _refreshSubCatMap();
    });
  }

  void _onMainCatSelected(String? id) {
    setState(() {
      _selectedMainCatId = id;
      _refreshSubCatMap();
    });
  }

  // ── Paste Handler ─────────────────────────────────────────────────────────

  Future<void> _handlePaste() async {
    final count = await _controller.pasteFromClipboard(
      subCatByName: _subCatByName,
      refByName: _refByName,
    );
    if (!mounted) return;
    if (count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pasted $count row(s) from clipboard',
              style: GoogleFonts.outfit()),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'No TSV data found. Copy rows from Excel first.',
              style: GoogleFonts.outfit()),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  // ── Save Handler ──────────────────────────────────────────────────────────

  Future<void> _handleSave() async {
    // Pre-save validation UI
    final msgs = _controller.validationMessages();
    if (msgs.isNotEmpty) {
      final proceed = await _showErrorDialog(msgs);
      if (!proceed) return;
    }

    final success = await _controller.saveAll();
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ Saved ${_controller.savedCount} task(s) to Firestore',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Go Back',
            textColor: Colors.white,
            onPressed: () => Navigator.pop(context),
          ),
        ),
      );
    } else if (_controller.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_controller.errorMessage!,
              style: GoogleFonts.outfit()),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<bool> _showErrorDialog(List<String> messages) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.orange.shade600, size: 22),
                const SizedBox(width: 8),
                Text('Validation Issues',
                    style: GoogleFonts.outfit(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('The following issues were found:',
                    style: GoogleFonts.outfit(
                        color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 10),
                for (final msg in messages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.circle,
                            size: 6, color: Colors.red.shade400),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(msg,
                                style: GoogleFonts.outfit(fontSize: 13))),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Rows without a Title or Sub Category will be skipped. '
                  'Duplicate errors must be fixed before saving.',
                  style: GoogleFonts.outfit(
                      color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Fix First',
                      style: GoogleFonts.outfit(color: Colors.grey.shade600))),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1F36),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('Save Anyway',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── Field App Integration Sheet ───────────────────────────────────────────

  // void _showFieldAppGuide() {
  //   showModalBottomSheet<void>(
  //     context: context,
  //     isScrollControlled: true,
  //     backgroundColor: Colors.transparent,
  //     builder: (ctx) => const _FieldAppGuideSheet(),
  //   );
  // }

  Future<void> _showMultiModelPicker() async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => _MultiModelPickerDialog(
        availableModels: _modelMap,
        initialSelection: _selectedModelIds,
      ),
    );
    if (result != null) {
      _onModelsChanged(result);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyV &&
            HardwareKeyboard.instance.isControlPressed) {
          _handlePaste();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: _buildAppBar(),
        body: Column(
          children: [
            // ── Global selectors header ──────────────────────────────────
            _buildHeaderSelectors(),
            // ── Column headers ───────────────────────────────────────────
            _buildColumnHeaders(),
            // ── Rows ─────────────────────────────────────────────────────
            Expanded(child: _buildGrid()),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0277BD), // Premium RIQMA Blue
      foregroundColor: Colors.white,
      elevation: 2,
      shadowColor: Colors.black26,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.pop(context),
        tooltip: 'Back to Tasks',
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.table_rows_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bulk Task Entry',
                    style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Colors.white)),
                ListenableBuilder(
                  listenable: _controller,
                  builder: (_, child) => Text(
                    '${_controller.rows.length} rows   •   '
                    '${_controller.rows.where((r) => r.isValid).length} ready to save',
                    style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.8)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Paste button
        OutlinedButton.icon(
          onPressed: _handlePaste,
          icon: const Icon(Icons.content_paste_rounded,
              size: 16, color: Colors.white),
          label: Text('Paste Data',
              style: GoogleFonts.outfit(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(width: 8),
        // Add Row
        OutlinedButton.icon(
          onPressed: () {
            _controller.addRow();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_vScroll.hasClients) {
                _vScroll.animateTo(
                  _vScroll.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            });
          },
          icon: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
          label: Text('Add Row',
              style: GoogleFonts.outfit(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            backgroundColor: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        const SizedBox(width: 8),
        // Save All
        ListenableBuilder(
          listenable: _controller,
          builder: (_, child) {
            final saving = _controller.isSaving;
            return ElevatedButton.icon(
              onPressed: saving ? null : _handleSave,
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_rounded,
                      size: 18, color: Color(0xFF0277BD)),
              label: Text(saving ? 'Saving…' : 'Save To Database',
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: saving ? Colors.white : const Color(0xFF0277BD))),
              style: ElevatedButton.styleFrom(
                backgroundColor: saving ? Colors.grey.shade600 : Colors.white,
                foregroundColor: const Color(0xFF0277BD),
                elevation: 1,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            );
          },
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  // ── Header Selectors ──────────────────────────────────────────────────────

  Widget _buildHeaderSelectors() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0277BD).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        spacing: 16,
        runSpacing: 12,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0277BD).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.filter_list_rounded,
                        size: 16, color: Color(0xFF0277BD)),
                  ),
                  const SizedBox(width: 10),
                  Text('Global Filter',
                      style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: const Color(0xFF1A1F36))),
                ],
              ),
              const SizedBox(width: 4),
              // Model
              _HeaderMultiSelect(
                label: 'Turbine Models',
                selectedNames: _selectedModelIds.length == _modelMap.length && _modelMap.isNotEmpty
                    ? ['All Models']
                    : _selectedModelIds.map((id) => _modelMap[id] ?? id).toList(),
                onTap: _showMultiModelPicker,
                width: 220,
              ),
              // Main Category
              SizedBox(
                width: 220,
                child: _HeaderDropdown(
                  label: 'Main Category',
                  selectedId: _selectedMainCatId,
                  items: _mainCatMap,
                  onChanged: _onMainCatSelected,
                  enabled: _selectedModelIds.isNotEmpty,
                  width: 220,
                ),
              ),
            ],
          ),
          // Legend
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LegendDot(color: Colors.red.shade400, label: 'Duplicate'),
        const SizedBox(width: 12),
        _LegendDot(color: Colors.blue.shade300, label: 'Drag-fill handle'),
        const SizedBox(width: 12),
        _LegendDot(color: Colors.deepOrange.shade300, label: 'Order fill'),
      ],
    );
  }

  // ── Column Headers Row ────────────────────────────────────────────────────

  Widget _buildColumnHeaders() {
    const headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: Color(0xFF8A94A6),
    );

    Widget header(String label, double width,
        {bool required = false}) {
      return SizedBox(
        width: width,
        child: Row(
          children: [
            Text(label.toUpperCase(), style: headerStyle),
            if (required)
              Text(' *',
                  style: headerStyle.copyWith(color: Colors.red.shade400)),
          ],
        ),
      );
    }

    return Container(
      height: 38,
      color: const Color(0xFFF0F2F8),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _hScroll,
        child: Row(
          children: [
            const SizedBox(width: _kColIndex),
            header('Title', _kColTitle, required: true),
            const SizedBox(width: 8),
            header('Description', _kColDesc),
            const SizedBox(width: 8),
            header('Sub Category', _kColSubCat, required: true),
            const SizedBox(width: 8),
            header('Reference', _kColRef),
            const SizedBox(width: 8),
            header('Order', _kColOrder),
            const SizedBox(width: _kColDelete),
          ],
        ),
      ),
    );
  }

  // ── Grid ──────────────────────────────────────────────────────────────────

  Widget _buildGrid() {
    if (_isLoadingLookups) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF1A1F36)),
            SizedBox(height: 16),
            Text('Loading data…'),
          ],
        ),
      );
    }

    return Scrollbar(
      controller: _vScroll,
      child: SingleChildScrollView(
        controller: _vScroll,
        child: NotificationListener<ScrollNotification>(
          // Sync the horizontal scroll between header and grid
          onNotification: (n) => false,
          child: ListenableBuilder(
            listenable: _controller,
            builder: (_, child) {
              return Column(
                children: [
                  for (int i = 0; i < _controller.rows.length; i++)
                    _BulkTaskRow(
                      key: ValueKey(i),
                      rowIndex: i,
                      row: _controller.rows[i],
                      controller: _controller,
                      subCatMap: _subCatMap,
                      subCatRefMap: _subCatRefMap,
                      subCatMainRefMap: _subCatMainRefMap,
                      refMap: _refMap,
                      refRefMap: _refRefMap,
                      hScrollController: _hScroll,
                    ),
                  // Bottom "Add Row" affordance
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 8),
                    child: InkWell(
                      onTap: _controller.addRow,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.grey.shade300,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_rounded,
                                color: Colors.grey.shade500, size: 18),
                            const SizedBox(width: 6),
                            Text('Add Row',
                                style: GoogleFonts.outfit(
                                    color: Colors.grey.shade500,
                                    fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── Single Row Widget ────────────────────────────────────────────────────────

class _BulkTaskRow extends StatelessWidget {
  final int rowIndex;
  final BulkTaskRowData row;
  final BulkGridController controller;
  final Map<String, String> subCatMap;
  final Map<String, DocumentReference> subCatRefMap;
  final Map<String, DocumentReference?> subCatMainRefMap;
  final Map<String, String> refMap;
  final Map<String, DocumentReference> refRefMap;
  final ScrollController hScrollController;

  const _BulkTaskRow({
    super.key,
    required this.rowIndex,
    required this.row,
    required this.controller,
    required this.subCatMap,
    required this.subCatRefMap,
    required this.subCatMainRefMap,
    required this.refMap,
    required this.refRefMap,
    required this.hScrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: row,
      builder: (_, child) {
        final isDupOrder =
            controller.duplicateOrderIndices.contains(rowIndex);
        final isDupTitle =
            controller.duplicateTitleIndices.contains(rowIndex);
        final isDupDesc =
            controller.duplicateDescIndices.contains(rowIndex);

        final isEven = rowIndex % 2 == 0;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: kBulkRowHeight,
          color: isEven ? Colors.white : const Color(0xFFFAFBFD),
          child: Stack(
            children: [
              // Row separator
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Divider(
                    height: 1, color: Colors.grey.shade200, thickness: 1),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: hScrollController,
                physics: const NeverScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── Row Index ────────────────────────────────────────
                      SizedBox(
                        width: _kColIndex,
                        child: Center(
                          child: Text(
                            '${rowIndex + 1}',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: Colors.grey.shade400,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),

                      // ── Title (rich text) ─────────────────────────────────
                      SizedBox(
                        width: _kColTitle,
                        child: BulkRichTextCell(
                          spans: row.titleSpans,
                          hasDuplicate: isDupTitle,
                          placeholder: 'Task title…',
                          onChanged: row.setTitleSpans,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // ── Description (rich text) ───────────────────────────
                      SizedBox(
                        width: _kColDesc,
                        child: BulkRichTextCell(
                          spans: row.descSpans,
                          hasDuplicate: isDupDesc,
                          placeholder: 'Description…',
                          maxLines: 2,
                          onChanged: row.setDescSpans,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // ── Sub Category ─────────────────────────────────────
                      SizedBox(
                        width: _kColSubCat,
                        child: BulkDropdownCell(
                          selectedId: row.subCategoryId,
                          selectedName: row.subCategoryName,
                          items: subCatMap,
                          rowIndex: rowIndex,
                          totalRows: controller.rows.length,
                          placeholder: 'Sub Category…',
                          onSelected: (id) {
                            row.setSubCategory(
                              id: id,
                              name: subCatMap[id] ?? id,
                              ref: subCatRefMap[id]!,
                              mainCatRef: subCatMainRefMap[id],
                            );
                          },
                          onCleared: row.clearSubCategory,
                          onDragFill: (endRow) {
                            controller.dragFill(
                              startRow: rowIndex,
                              endRow: endRow,
                              field: 'sub_category',
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),

                      // ── Reference ─────────────────────────────────────────
                      SizedBox(
                        width: _kColRef,
                        child: BulkDropdownCell(
                          selectedId: row.referenceId,
                          selectedName: row.referenceName,
                          items: refMap,
                          rowIndex: rowIndex,
                          totalRows: controller.rows.length,
                          placeholder: 'Reference…',
                          onSelected: (id) {
                            row.setReference(
                              id: id,
                              name: refMap[id] ?? id,
                              ref: refRefMap[id]!,
                            );
                          },
                          onCleared: row.clearReference,
                          onDragFill: (endRow) {
                            controller.dragFill(
                              startRow: rowIndex,
                              endRow: endRow,
                              field: 'reference',
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),

                      // ── Order ─────────────────────────────────────────────
                      SizedBox(
                        width: _kColOrder,
                        child: BulkOrderCell(
                          value: row.sortOrder,
                          isDuplicate: isDupOrder,
                          rowIndex: rowIndex,
                          totalRows: controller.rows.length,
                          onChanged: row.setSortOrder,
                          onDragFill: (endRow) {
                            controller.dragFill(
                              startRow: rowIndex,
                              endRow: endRow,
                              field: 'sort_order',
                            );
                          },
                        ),
                      ),

                      // ── Delete ────────────────────────────────────────────
                      SizedBox(
                        width: _kColDelete,
                        child: Center(
                          child: Tooltip(
                            message: 'Delete row',
                            child: InkWell(
                              onTap: () =>
                                  controller.removeRow(rowIndex),
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Header Dropdown ──────────────────────────────────────────────────────────

class _HeaderDropdown extends StatelessWidget {
  final String label;
  final String? selectedId;
  final Map<String, String> items;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final double width;

  const _HeaderDropdown({
    required this.label,
    required this.selectedId,
    required this.items,
    required this.onChanged,
    this.enabled = true,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return ModernSearchableDropdown(
      label: label,
      value: selectedId,
      items: items,
      color: Colors.blue,
      icon: Icons.list_alt_rounded,
      onChanged: enabled ? onChanged : (val) {},
    );
  }
}

// ─── Legend Dot ───────────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: GoogleFonts.outfit(
                fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }
}


// ─── Header Multi Select Button ──────────────────────────────────────────────


class _HeaderMultiSelect extends StatelessWidget {
  final String label;
  final List<String> selectedNames;
  final VoidCallback onTap;
  final double width;

  const _HeaderMultiSelect({
    required this.label,
    required this.selectedNames,
    required this.onTap,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    String text;
    if (selectedNames.isEmpty) {
      text = '— Select —';
    } else if (selectedNames.length == 1 && selectedNames.first == 'All Models') {
      text = 'All Models';
    } else if (selectedNames.length <= 2) {
      text = selectedNames.join(', ');
    } else {
      text = '${selectedNames.length} Selected';
    }

    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      text,
                      style: GoogleFonts.outfit(
                          fontSize: 12.5,
                          color: selectedNames.isNotEmpty ? const Color(0xFF1A1F36) : Colors.grey.shade400,
                          fontWeight: selectedNames.isNotEmpty ? FontWeight.w600 : FontWeight.normal),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 16, color: Colors.grey.shade500),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Multi Model Picker Dialog ────────────────────────────────────────────────

class _MultiModelPickerDialog extends StatefulWidget {
  final Map<String, String> availableModels;
  final Set<String> initialSelection;

  const _MultiModelPickerDialog({
    required this.availableModels,
    required this.initialSelection,
  });

  @override
  State<_MultiModelPickerDialog> createState() => _MultiModelPickerDialogState();
}

class _MultiModelPickerDialogState extends State<_MultiModelPickerDialog> {
  late Set<String> _selected;
  String _search = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initialSelection);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleAll(bool selectAll) {
    setState(() {
      if (selectAll) {
        _selected = Set.from(widget.availableModels.keys);
      } else {
        _selected.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.availableModels.entries
        .where((e) => e.value.toLowerCase().contains(_search.toLowerCase()))
        .toList();

    final isAllSelected = _selected.length == widget.availableModels.length && 
                         widget.availableModels.isNotEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Select Turbine Models',
                    style: GoogleFonts.outfit(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Search
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search models…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
              style: GoogleFonts.outfit(fontSize: 14),
            ),
            const SizedBox(height: 16),
            // Select All Toggle
            Row(
              children: [
                Checkbox(
                  value: isAllSelected,
                  onChanged: (v) => _toggleAll(v ?? false),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                Text('Select All', 
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
                const Spacer(),
                Text('${_selected.length}/${widget.availableModels.length} Selected',
                    style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
            const Divider(),
            // List
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final modelId = filtered[i].key;
                  final modelName = filtered[i].value;
                  final isSelected = _selected.contains(modelId);

                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(modelId);
                        } else {
                          _selected.remove(modelId);
                        }
                      });
                    },
                    title: Text(modelName, style: GoogleFonts.outfit(fontSize: 14)),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey.shade600)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1F36),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: Text('Apply', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
