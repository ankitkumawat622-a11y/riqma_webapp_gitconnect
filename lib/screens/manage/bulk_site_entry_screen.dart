import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Column width constants ────────────────────────────────────────────────────
const double _kSColIndex = 40.0;
const double _kSColName = 220.0;
const double _kSColState = 180.0;
const double _kSColDistrict = 180.0;
const double _kSColWarehouse = 160.0;
const double _kSColStatus = 120.0;
const double _kSColDelete = 44.0;
const double kBulkSiteRowHeight = 52.0;

// ─── Row Data Model ───────────────────────────────────────────────────────────

class BulkSiteRowData extends ChangeNotifier {
  String siteName;
  String? stateId;
  String? stateName;
  DocumentReference? stateRef;
  String district;
  String warehouseCode;

  BulkSiteRowData({
    this.siteName = '',
    this.stateId,
    this.stateName,
    this.stateRef,
    this.district = '',
    this.warehouseCode = '',
  });

  bool get isValid => siteName.trim().isNotEmpty && stateRef != null;

  void setSiteName(String v) {
    siteName = v;
    notifyListeners();
  }

  void setState2({
    required String id,
    required String name,
    required DocumentReference ref,
  }) {
    stateId = id;
    stateName = name;
    stateRef = ref;
    notifyListeners();
  }

  void clearState() {
    stateId = null;
    stateName = null;
    stateRef = null;
    notifyListeners();
  }

  void setDistrict(String v) {
    district = v;
    notifyListeners();
  }

  void setWarehouseCode(String v) {
    warehouseCode = v;
    notifyListeners();
  }

  Map<String, dynamic> toFirestore() => {
        'site_name': siteName.trim(),
        'state_ref': stateRef,
        'state_name': stateName ?? '',
        'district': district.trim(),
        'warehouse_code': warehouseCode.trim(),
        'created_at': FieldValue.serverTimestamp(),
        'bulk_entry': true,
      };
}

// ─── Controller ───────────────────────────────────────────────────────────────

class _BulkSiteController extends ChangeNotifier {
  final List<BulkSiteRowData> rows = [];
  Set<int> duplicateNameIndices = {};
  Set<int> firestoreDuplicateIndices = {};

  bool isSaving = false;
  String? errorMessage;
  int savedCount = 0;

  Set<String> existingSiteNames = {};

  _BulkSiteController() {
    for (int i = 0; i < 5; i++) {
      _addRowSilent();
    }
  }

  void _addRowSilent() {
    final row = BulkSiteRowData();
    row.addListener(_onRowChanged);
    rows.add(row);
  }

  void addRow() {
    _addRowSilent();
    _revalidate();
    notifyListeners();
  }

  void removeRow(int index) {
    if (index < 0 || index >= rows.length) return;
    rows[index].removeListener(_onRowChanged);
    rows[index].dispose();
    rows.removeAt(index);
    _revalidate();
    notifyListeners();
  }

  void _onRowChanged() {
    _revalidate();
    notifyListeners();
  }

  void updateExistingNames(Set<String> names) {
    existingSiteNames = names;
    _revalidate();
    notifyListeners();
  }

  void _revalidate() {
    duplicateNameIndices = {};
    firestoreDuplicateIndices = {};

    // Layer 1: within-batch
    final nameBuckets = <String, List<int>>{};
    for (int i = 0; i < rows.length; i++) {
      final t = rows[i].siteName.trim().toLowerCase();
      if (t.isNotEmpty) nameBuckets.putIfAbsent(t, () => []).add(i);
    }
    for (final e in nameBuckets.entries) {
      if (e.value.length > 1) duplicateNameIndices.addAll(e.value);
    }

    // Layer 2: Firestore
    for (int i = 0; i < rows.length; i++) {
      final t = rows[i].siteName.trim().toLowerCase();
      if (t.isNotEmpty && existingSiteNames.contains(t)) {
        firestoreDuplicateIndices.add(i);
      }
    }
  }

  List<String> validationMessages() {
    final msgs = <String>[];
    final named = rows.where((r) => r.siteName.trim().isNotEmpty).toList();
    if (named.isEmpty) msgs.add('No rows have a site name.');

    final noState = rows.where((r) => r.siteName.trim().isNotEmpty && r.stateRef == null).length;
    if (noState > 0) msgs.add('$noState row(s) are missing a State.');

    if (duplicateNameIndices.isNotEmpty) {
      msgs.add('${duplicateNameIndices.length} row(s) have duplicate names within this batch.');
    }
    if (firestoreDuplicateIndices.isNotEmpty) {
      msgs.add('${firestoreDuplicateIndices.length} row(s) already exist in the database.');
    }
    return msgs;
  }

  bool get hasBlockingErrors =>
      duplicateNameIndices.isNotEmpty || firestoreDuplicateIndices.isNotEmpty;

  // ── TSV Paste ── Column order: Site Name | State Name | District | Warehouse Code

  Future<int> pasteFromClipboard({
    required Map<String, Map<String, dynamic>> stateByName,
  }) async {
    ClipboardData? data;
    try {
      data = await Clipboard.getData('text/plain');
    } catch (e) {
      debugPrint('Clipboard error: $e');
      return 0;
    }

    if (data?.text == null || data!.text!.trim().isEmpty) return 0;

    final lines = data.text!
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) return 0;

    while (rows.length < lines.length) {
      _addRowSilent();
    }

    int filled = 0;
    for (int i = 0; i < lines.length; i++) {
      final cols = lines[i].split('\t');
      final row = rows[i];

      // Col 0 → Site Name
      if (cols.isNotEmpty && cols[0].trim().isNotEmpty) {
        row.siteName = cols[0].trim();
        filled++;
      }

      // Col 1 → State Name (fuzzy lookup)
      if (cols.length > 1 && cols[1].trim().isNotEmpty) {
        final key = cols[1].trim().toLowerCase();
        final match = stateByName[key];
        if (match != null) {
          row.stateId = match['id'] as String?;
          row.stateName = match['name'] as String?;
          row.stateRef = match['ref'] as DocumentReference?;
        }
      }

      // Col 2 → District
      if (cols.length > 2) {
        row.district = cols[2].trim();
      }

      // Col 3 → Warehouse Code
      if (cols.length > 3) {
        row.warehouseCode = cols[3].trim();
      }

      row.notifyListeners();
    }

    _revalidate();
    notifyListeners();
    return filled;
  }

  // ── WriteBatch Save ─────────────────────────────────────────────────────────

  Future<bool> saveAll() async {
    if (isSaving) return false;

    final validRows = rows.where((r) => r.isValid).toList();
    if (validRows.isEmpty) {
      errorMessage = 'No valid rows. Each row needs a Site Name and State.';
      notifyListeners();
      return false;
    }
    if (hasBlockingErrors) {
      errorMessage = 'Fix duplicate errors before saving.';
      notifyListeners();
      return false;
    }

    isSaving = true;
    errorMessage = null;
    notifyListeners();

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final row in validRows) {
        final ref = FirebaseFirestore.instance.collection('sites').doc();
        batch.set(ref, row.toFirestore());
      }
      await batch.commit();
      savedCount = validRows.length;
      isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      isSaving = false;
      errorMessage = 'Save failed: $e';
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    for (final row in rows) {
      row.removeListener(_onRowChanged);
      row.dispose();
    }
    super.dispose();
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class BulkSiteEntryScreen extends StatefulWidget {
  const BulkSiteEntryScreen({super.key});

  @override
  State<BulkSiteEntryScreen> createState() => _BulkSiteEntryScreenState();
}

class _BulkSiteEntryScreenState extends State<BulkSiteEntryScreen> {
  late final _BulkSiteController _controller;
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

  // Lookup maps
  Map<String, String> _stateMap = {};
  Map<String, Map<String, dynamic>> _stateByName = {};

  bool _isLoadingLookups = true;

  StreamSubscription<QuerySnapshot>? _stateSub;
  StreamSubscription<QuerySnapshot>? _siteSub;

  @override
  void initState() {
    super.initState();
    _controller = _BulkSiteController();
    _setupStreams();
  }

  @override
  void dispose() {
    _controller.dispose();
    _hScroll.dispose();
    _vScroll.dispose();
    _stateSub?.cancel();
    _siteSub?.cancel();
    super.dispose();
  }

  void _setupStreams() {
    // States lookup
    _stateSub = FirebaseFirestore.instance
        .collection('states')
        .snapshots()
        .listen((snap) {
      final stateMap = <String, String>{};
      final stateByName = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = data['state']?.toString() ??
            data['name']?.toString() ??
            'Unknown';
        stateMap[doc.id] = name;
        stateByName[name.toLowerCase()] = {
          'id': doc.id,
          'name': name,
          'ref': doc.reference,
        };
      }
      if (mounted) {
        setState(() {
          _stateMap = stateMap;
          _stateByName = stateByName;
          _isLoadingLookups = false;
        });
      }
    });

    // Existing site names for Layer 2 duplicate check
    _siteSub = FirebaseFirestore.instance
        .collection('sites')
        .snapshots()
        .listen((snap) {
      final names = snap.docs.map((d) {
        final data = d.data();
        return (data['site_name'] ?? data['name'] ?? '')
            .toString()
            .toLowerCase()
            .trim();
      }).where((s) => s.isNotEmpty).toSet();
      _controller.updateExistingNames(names);
    });
  }

  Future<void> _handlePaste() async {
    final count = await _controller.pasteFromClipboard(
      stateByName: _stateByName,
    );
    if (!mounted) return;
    _showSnack(
      count > 0
          ? 'Pasted $count row(s) from clipboard'
          : 'No TSV data found. Copy rows from Excel first.',
      count > 0 ? Colors.green.shade700 : Colors.orange.shade700,
    );
  }

  Future<void> _handleSave() async {
    final msgs = _controller.validationMessages();
    if (msgs.isNotEmpty) {
      final proceed = await _showErrorDialog(msgs);
      if (!proceed) return;
    }

    final success = await _controller.saveAll();
    if (!mounted) return;

    if (success) {
      _showSnack(
        '✓ Saved ${_controller.savedCount} site(s) to Firestore',
        Colors.green.shade700,
        action: SnackBarAction(
          label: 'Go Back',
          textColor: Colors.white,
          onPressed: () => Navigator.pop(context),
        ),
      );
    } else if (_controller.errorMessage != null) {
      _showSnack(_controller.errorMessage!, Colors.red.shade700);
    }
  }

  void _showSnack(String msg, Color color, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.outfit()),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 4),
      action: action,
    ));
  }

  Future<bool> _showErrorDialog(List<String> messages) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    style:
                        GoogleFonts.outfit(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 10),
                for (final msg in messages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.circle, size: 6, color: Colors.red.shade400),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(msg, style: GoogleFonts.outfit(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Rows already in the database or with duplicates cannot be saved.',
                  style: GoogleFonts.outfit(
                      color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Fix First',
                    style: GoogleFonts.outfit(color: Colors.grey.shade600)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1F36),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('Save Valid Rows',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ) ??
        false;
  }

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
            _buildInfoBanner(),
            _buildColumnHeaders(),
            Expanded(child: _buildGrid()),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0277BD),
      foregroundColor: Colors.white,
      elevation: 2,
      shadowColor: Colors.black26,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.pop(context),
        tooltip: 'Back to Sites',
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.location_on_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bulk Site Entry',
                    style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Colors.white)),
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context2, _) => Text(
                    '${_controller.rows.length} rows  •  '
                    '${_controller.rows.where((r) => r.isValid).length} ready to save',
                    style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.8)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
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
        ListenableBuilder(
          listenable: _controller,
          builder: (context2, _) {
            final saving = _controller.isSaving;
            return ElevatedButton.icon(
              onPressed: saving ? null : _handleSave,
              icon: saving
                  ? const SizedBox(
                      width: 16, height: 16,
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

  Widget _buildInfoBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
        spacing: 20,
        runSpacing: 8,
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
                child: const Icon(Icons.info_outline_rounded,
                    size: 16, color: Color(0xFF0277BD)),
              ),
              const SizedBox(width: 10),
              Text(
                'Excel column order:  Site Name  |  State Name  |  District  |  Warehouse Code',
                style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1F36)),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SLegendDot(color: Colors.red.shade400, label: 'In-batch duplicate'),
              const SizedBox(width: 12),
              _SLegendDot(color: Colors.orange.shade600, label: 'Already in database'),
              const SizedBox(width: 12),
              _SLegendDot(color: Colors.green.shade600, label: 'Valid row'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildColumnHeaders() {
    const headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: Color(0xFF8A94A6),
    );

    Widget header(String label, double width, {bool required = false}) {
      return SizedBox(
        width: width,
        child: Row(
          children: [
            Text(label.toUpperCase(), style: headerStyle),
            if (required)
              Text(' *', style: headerStyle.copyWith(color: Colors.red.shade400)),
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
            const SizedBox(width: _kSColIndex),
            header('Site Name', _kSColName, required: true),
            const SizedBox(width: 8),
            header('State', _kSColState, required: true),
            const SizedBox(width: 8),
            header('District', _kSColDistrict),
            const SizedBox(width: 8),
            header('Warehouse Code', _kSColWarehouse),
            const SizedBox(width: 8),
            header('Status', _kSColStatus),
            const SizedBox(width: _kSColDelete),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    if (_isLoadingLookups) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF0277BD)),
            SizedBox(height: 16),
            Text('Loading lookup data…'),
          ],
        ),
      );
    }

    return Scrollbar(
      controller: _vScroll,
      child: SingleChildScrollView(
        controller: _vScroll,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context2, _) {
            return Column(
              children: [
                for (int i = 0; i < _controller.rows.length; i++)
                  _BulkSiteRow(
                    key: ValueKey(i),
                    rowIndex: i,
                    row: _controller.rows[i],
                    controller: _controller,
                    stateMap: _stateMap,
                    stateByName: _stateByName,
                    hScrollController: _hScroll,
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  child: InkWell(
                    onTap: _controller.addRow,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded,
                              color: Colors.grey.shade500, size: 18),
                          const SizedBox(width: 6),
                          Text('Add Row',
                              style: GoogleFonts.outfit(
                                  color: Colors.grey.shade500, fontSize: 13)),
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
    );
  }
}

// ─── Single Row Widget ────────────────────────────────────────────────────────

class _BulkSiteRow extends StatelessWidget {
  final int rowIndex;
  final BulkSiteRowData row;
  final _BulkSiteController controller;
  final Map<String, String> stateMap;
  final Map<String, Map<String, dynamic>> stateByName;
  final ScrollController hScrollController;

  const _BulkSiteRow({
    super.key,
    required this.rowIndex,
    required this.row,
    required this.controller,
    required this.stateMap,
    required this.stateByName,
    required this.hScrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: row,
      builder: (context2, _) {
        final isDupBatch = controller.duplicateNameIndices.contains(rowIndex);
        final isDupFirestore = controller.firestoreDuplicateIndices.contains(rowIndex);
        final isValid = row.isValid;
        final isEven = rowIndex % 2 == 0;

        Color? rowTint;
        if (isDupFirestore) rowTint = Colors.orange.shade50;
        if (isDupBatch) rowTint = Colors.red.shade50;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: kBulkSiteRowHeight,
          color: rowTint ?? (isEven ? Colors.white : const Color(0xFFFAFBFD)),
          child: Stack(
            children: [
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Divider(height: 1, color: Colors.grey.shade200, thickness: 1),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: hScrollController,
                physics: const NeverScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Index
                      SizedBox(
                        width: _kSColIndex,
                        child: Center(
                          child: Text(
                            '${rowIndex + 1}',
                            style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: Colors.grey.shade400,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),

                      // Site Name
                      SizedBox(
                        width: _kSColName,
                        child: _SPlainTextField(
                          value: row.siteName,
                          placeholder: 'Site name…',
                          hasDuplicate: isDupBatch || isDupFirestore,
                          accentColor: const Color(0xFF0277BD),
                          onChanged: row.setSiteName,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // State
                      SizedBox(
                        width: _kSColState,
                        child: _SInlineDropdown(
                          selectedId: row.stateId,
                          selectedName: row.stateName,
                          items: stateMap,
                          placeholder: 'Select state…',
                          accentColor: const Color(0xFF0277BD),
                          onSelected: (id) {
                            final found = stateByName.values
                                .where((m) => m['id'] == id)
                                .firstOrNull;
                            if (found != null) {
                              row.setState2(
                                id: found['id'] as String,
                                name: found['name'] as String,
                                ref: found['ref'] as DocumentReference,
                              );
                            }
                          },
                          onCleared: row.clearState,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // District
                      SizedBox(
                        width: _kSColDistrict,
                        child: _SPlainTextField(
                          value: row.district,
                          placeholder: 'District…',
                          hasDuplicate: false,
                          accentColor: const Color(0xFF0277BD),
                          onChanged: row.setDistrict,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Warehouse Code
                      SizedBox(
                        width: _kSColWarehouse,
                        child: _SPlainTextField(
                          value: row.warehouseCode,
                          placeholder: 'WH code…',
                          hasDuplicate: false,
                          accentColor: const Color(0xFF0277BD),
                          onChanged: row.setWarehouseCode,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Status
                      SizedBox(
                        width: _kSColStatus,
                        child: _SSitStatusBadge(
                          isDupBatch: isDupBatch,
                          isDupFirestore: isDupFirestore,
                          isValid: isValid,
                          siteName: row.siteName,
                        ),
                      ),

                      // Delete
                      SizedBox(
                        width: _kSColDelete,
                        child: Center(
                          child: Tooltip(
                            message: 'Delete row',
                            child: InkWell(
                              onTap: () => controller.removeRow(rowIndex),
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

// ─── Searchable Inline Dropdown ───────────────────────────────────────────────

class _SInlineDropdown extends StatelessWidget {
  final String? selectedId;
  final String? selectedName;
  final Map<String, String> items;
  final String placeholder;
  final Color accentColor;
  final ValueChanged<String> onSelected;
  final VoidCallback onCleared;

  const _SInlineDropdown({
    required this.selectedId,
    required this.selectedName,
    required this.items,
    required this.placeholder,
    required this.accentColor,
    required this.onSelected,
    required this.onCleared,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selectedId != null
                ? accentColor.withValues(alpha: 0.5)
                : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selectedName ?? placeholder,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: selectedName != null
                      ? const Color(0xFF1A1F36)
                      : Colors.grey.shade400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selectedId != null)
              GestureDetector(
                onTap: onCleared,
                child: Icon(Icons.close_rounded,
                    size: 14, color: Colors.grey.shade400),
              )
            else
              Icon(Icons.arrow_drop_down_rounded,
                  size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    final searchCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final query = searchCtrl.text.toLowerCase();
          final filtered = query.isEmpty
              ? items.entries.toList()
              : items.entries
                  .where((e) => e.value.toLowerCase().contains(query))
                  .toList();
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
            title: TextField(
              controller: searchCtrl,
              onChanged: (_) => setS(() {}),
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search…',
                hintStyle: GoogleFonts.outfit(color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
            content: SizedBox(
              width: 300,
              height: 300,
              child: filtered.isEmpty
                  ? Center(
                      child: Text('No matches',
                          style: GoogleFonts.outfit(color: Colors.grey.shade500)),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final e = filtered[i];
                        return ListTile(
                          selected: e.key == selectedId,
                          selectedColor: accentColor,
                          title: Text(e.value,
                              style: GoogleFonts.outfit(fontSize: 14)),
                          onTap: () {
                            onSelected(e.key);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Plain Text Field ─────────────────────────────────────────────────────────

class _SPlainTextField extends StatefulWidget {
  final String value;
  final String placeholder;
  final bool hasDuplicate;
  final Color accentColor;
  final ValueChanged<String> onChanged;

  const _SPlainTextField({
    required this.value,
    required this.placeholder,
    required this.hasDuplicate,
    required this.accentColor,
    required this.onChanged,
  });

  @override
  State<_SPlainTextField> createState() => _SPlainTextFieldState();
}

class _SPlainTextFieldState extends State<_SPlainTextField> {
  late TextEditingController _ctrl;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_SPlainTextField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_focused) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: TextField(
        controller: _ctrl,
        onChanged: widget.onChanged,
        style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF1A1F36)),
        decoration: InputDecoration(
          hintText: widget.placeholder,
          hintStyle: GoogleFonts.outfit(
              fontSize: 13, color: Colors.grey.shade400),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: widget.hasDuplicate
                  ? Colors.red.shade400
                  : Colors.grey.shade300,
              width: widget.hasDuplicate ? 1.5 : 1.0,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: widget.hasDuplicate
                  ? Colors.red.shade400
                  : widget.accentColor,
              width: 1.5,
            ),
          ),
          filled: true,
          fillColor:
              widget.hasDuplicate ? Colors.red.shade50 : Colors.white,
        ),
      ),
    );
  }
}

// ─── Status Badge ─────────────────────────────────────────────────────────────

class _SSitStatusBadge extends StatelessWidget {
  final bool isDupBatch;
  final bool isDupFirestore;
  final bool isValid;
  final String siteName;

  const _SSitStatusBadge({
    required this.isDupBatch,
    required this.isDupFirestore,
    required this.isValid,
    required this.siteName,
  });

  @override
  Widget build(BuildContext context) {
    if (siteName.trim().isEmpty) return const SizedBox();

    late Color bgColor;
    late Color fgColor;
    late String label;
    late IconData icon;

    if (isDupBatch) {
      bgColor = Colors.red.shade50;
      fgColor = Colors.red.shade700;
      label = 'Duplicate';
      icon = Icons.content_copy_rounded;
    } else if (isDupFirestore) {
      bgColor = Colors.orange.shade50;
      fgColor = Colors.orange.shade700;
      label = 'Exists in DB';
      icon = Icons.cloud_off_rounded;
    } else if (isValid) {
      bgColor = Colors.green.shade50;
      fgColor = Colors.green.shade700;
      label = 'Ready';
      icon = Icons.check_circle_outline_rounded;
    } else {
      bgColor = Colors.grey.shade100;
      fgColor = Colors.grey.shade600;
      label = 'Incomplete';
      icon = Icons.pending_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fgColor),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.outfit(
                  fontSize: 11, fontWeight: FontWeight.w600, color: fgColor)),
        ],
      ),
    );
  }
}

// ─── Legend Dot ───────────────────────────────────────────────────────────────

class _SLegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _SLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style:
                GoogleFonts.outfit(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }
}
