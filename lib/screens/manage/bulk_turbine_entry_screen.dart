import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Column width constants ────────────────────────────────────────────────────
const double _kTColIndex = 40.0;
const double _kTColName = 220.0;
const double _kTColSite = 200.0;
const double _kTColModel = 200.0;
const double _kTColStatus = 120.0;
const double _kTColDelete = 44.0;
const double kBulkTurbineRowHeight = 52.0;

// ─── Row Data Model ───────────────────────────────────────────────────────────

class BulkTurbineRowData extends ChangeNotifier {
  String turbineName;
  String? siteId;
  String? siteName;
  DocumentReference? siteRef;
  String? modelId;
  String? modelName;
  DocumentReference? modelRef;

  BulkTurbineRowData({
    this.turbineName = '',
    this.siteId,
    this.siteName,
    this.siteRef,
    this.modelId,
    this.modelName,
    this.modelRef,
  });

  bool get isValid =>
      turbineName.trim().isNotEmpty && siteRef != null && modelRef != null;

  void setTurbineName(String v) {
    turbineName = v;
    notifyListeners();
  }

  void setSite({
    required String id,
    required String name,
    required DocumentReference ref,
  }) {
    siteId = id;
    siteName = name;
    siteRef = ref;
    notifyListeners();
  }

  void clearSite() {
    siteId = null;
    siteName = null;
    siteRef = null;
    notifyListeners();
  }

  void setModel({
    required String id,
    required String name,
    required DocumentReference ref,
  }) {
    modelId = id;
    modelName = name;
    modelRef = ref;
    notifyListeners();
  }

  void clearModel() {
    modelId = null;
    modelName = null;
    modelRef = null;
    notifyListeners();
  }

  Map<String, dynamic> toFirestore() => {
        'turbine_name': turbineName.trim(),
        'name': turbineName.trim(),
        'site_ref': siteRef,
        'site_name': siteName ?? '',
        'turbinemodel_ref': modelRef,
        'model_name': modelName ?? '',
        'created_at': FieldValue.serverTimestamp(),
        'bulk_entry': true,
      };
}

// ─── Controller ───────────────────────────────────────────────────────────────

class _BulkTurbineController extends ChangeNotifier {
  final List<BulkTurbineRowData> rows = [];
  Set<int> duplicateNameIndices = {};
  Set<int> firestoreDuplicateIndices = {};

  bool isSaving = false;
  String? errorMessage;
  int savedCount = 0;

  Set<String> existingTurbineNames = {};

  _BulkTurbineController() {
    for (int i = 0; i < 5; i++) {
      _addRowSilent();
    }
  }

  void _addRowSilent() {
    final row = BulkTurbineRowData();
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
    existingTurbineNames = names;
    _revalidate();
    notifyListeners();
  }

  // ── Layer 1 + Layer 2 duplicate detection ─────────────────────────────────

  void _revalidate() {
    duplicateNameIndices = {};
    firestoreDuplicateIndices = {};

    // Layer 1: within-batch
    final nameBuckets = <String, List<int>>{};
    for (int i = 0; i < rows.length; i++) {
      final t = rows[i].turbineName.trim().toLowerCase();
      if (t.isNotEmpty) nameBuckets.putIfAbsent(t, () => []).add(i);
    }
    for (final e in nameBuckets.entries) {
      if (e.value.length > 1) duplicateNameIndices.addAll(e.value);
    }

    // Layer 2: against Firestore
    for (int i = 0; i < rows.length; i++) {
      final t = rows[i].turbineName.trim().toLowerCase();
      if (t.isNotEmpty && existingTurbineNames.contains(t)) {
        firestoreDuplicateIndices.add(i);
      }
    }
  }

  List<String> validationMessages() {
    final msgs = <String>[];
    final named = rows.where((r) => r.turbineName.trim().isNotEmpty).toList();
    if (named.isEmpty) msgs.add('No rows have a turbine name.');

    final noSite = rows
        .where((r) => r.turbineName.trim().isNotEmpty && r.siteRef == null)
        .length;
    if (noSite > 0) msgs.add('$noSite row(s) are missing a Site.');

    final noModel = rows
        .where((r) => r.turbineName.trim().isNotEmpty && r.modelRef == null)
        .length;
    if (noModel > 0) msgs.add('$noModel row(s) are missing a Model.');

    if (duplicateNameIndices.isNotEmpty) {
      msgs.add(
          '${duplicateNameIndices.length} row(s) have duplicate names within this batch.');
    }
    if (firestoreDuplicateIndices.isNotEmpty) {
      msgs.add(
          '${firestoreDuplicateIndices.length} row(s) already exist in the database.');
    }
    return msgs;
  }

  bool get hasBlockingErrors =>
      duplicateNameIndices.isNotEmpty || firestoreDuplicateIndices.isNotEmpty;

  // ── TSV Paste ─── Column order: Turbine Name | Site Name | Model Name

  Future<int> pasteFromClipboard({
    required Map<String, Map<String, dynamic>> siteByName,
    required Map<String, Map<String, dynamic>> modelByName,
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

      // Col 0 → Turbine Name
      if (cols.isNotEmpty && cols[0].trim().isNotEmpty) {
        row.turbineName = cols[0].trim();
        filled++;
      }

      // Col 1 → Site Name (fuzzy lookup)
      if (cols.length > 1 && cols[1].trim().isNotEmpty) {
        final key = cols[1].trim().toLowerCase();
        final match = siteByName[key];
        if (match != null) {
          row.siteId = match['id'] as String?;
          row.siteName = match['name'] as String?;
          row.siteRef = match['ref'] as DocumentReference?;
        }
      }

      // Col 2 → Model Name (fuzzy lookup)
      if (cols.length > 2 && cols[2].trim().isNotEmpty) {
        final key = cols[2].trim().toLowerCase();
        final match = modelByName[key];
        if (match != null) {
          row.modelId = match['id'] as String?;
          row.modelName = match['name'] as String?;
          row.modelRef = match['ref'] as DocumentReference?;
        }
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
      errorMessage = 'No valid rows. Each row needs a Name, Site, and Model.';
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
        final ref = FirebaseFirestore.instance.collection('turbinename').doc();
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

class BulkTurbineEntryScreen extends StatefulWidget {
  const BulkTurbineEntryScreen({super.key});

  @override
  State<BulkTurbineEntryScreen> createState() => _BulkTurbineEntryScreenState();
}

class _BulkTurbineEntryScreenState extends State<BulkTurbineEntryScreen> {
  late final _BulkTurbineController _controller;
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

  // Lookup Maps (id→name for dropdowns, lower-name→data for paste)
  Map<String, String> _siteMap = {};
  Map<String, Map<String, dynamic>> _siteByName = {};

  Map<String, String> _modelMap = {};
  Map<String, Map<String, dynamic>> _modelByName = {};

  bool _isLoadingLookups = true;

  StreamSubscription<QuerySnapshot>? _siteSub;
  StreamSubscription<QuerySnapshot>? _modelSub;
  StreamSubscription<QuerySnapshot>? _turbineSub;

  @override
  void initState() {
    super.initState();
    _controller = _BulkTurbineController();
    _setupStreams();
  }

  @override
  void dispose() {
    _controller.dispose();
    _hScroll.dispose();
    _vScroll.dispose();
    _siteSub?.cancel();
    _modelSub?.cancel();
    _turbineSub?.cancel();
    super.dispose();
  }

  void _setupStreams() {
    // Sites lookup
    _siteSub = FirebaseFirestore.instance
        .collection('sites')
        .snapshots()
        .listen((snap) {
      final siteMap = <String, String>{};
      final siteByName = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = data['site_name']?.toString() ??
            data['name']?.toString() ??
            'Unknown';
        siteMap[doc.id] = name;
        siteByName[name.toLowerCase()] = {
          'id': doc.id,
          'name': name,
          'ref': doc.reference,
        };
      }
      if (mounted) setState(() { _siteMap = siteMap; _siteByName = siteByName; });
    });

    // Models lookup
    _modelSub = FirebaseFirestore.instance
        .collection('turbinemodel')
        .snapshots()
        .listen((snap) {
      final modelMap = <String, String>{};
      final modelByName = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = data['turbine_model']?.toString() ??
            data['name']?.toString() ??
            'Unknown';
        modelMap[doc.id] = name;
        modelByName[name.toLowerCase()] = {
          'id': doc.id,
          'name': name,
          'ref': doc.reference,
        };
      }
      if (mounted) {
        setState(() {
          _modelMap = modelMap;
          _modelByName = modelByName;
          _isLoadingLookups = false;
        });
      }
    });

    // Layer 2: existing turbine names
    _turbineSub = FirebaseFirestore.instance
        .collection('turbinename')
        .snapshots()
        .listen((snap) {
      final names = snap.docs
          .map((d) => (d.data()['turbine_name'] ?? d.data()['name'] ?? '')
              .toString()
              .toLowerCase()
              .trim())
          .where((s) => s.isNotEmpty)
          .toSet();
      _controller.updateExistingNames(names);
    });
  }

  Future<void> _handlePaste() async {
    final count = await _controller.pasteFromClipboard(
      siteByName: _siteByName,
      modelByName: _modelByName,
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
        '✓ Saved ${_controller.savedCount} turbine(s) to Firestore',
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
                    style: GoogleFonts.outfit(
                        color: Colors.grey.shade600, fontSize: 13)),
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
                            child: Text(msg,
                                style: GoogleFonts.outfit(fontSize: 13))),
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
                    style:
                        GoogleFonts.outfit(fontWeight: FontWeight.w600)),
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
      backgroundColor: const Color(0xFF00897B),
      foregroundColor: Colors.white,
      elevation: 2,
      shadowColor: Colors.black26,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.pop(context),
        tooltip: 'Back to Turbines',
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.wind_power_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bulk Turbine Entry',
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
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_rounded,
                      size: 18, color: Color(0xFF00897B)),
              label: Text(saving ? 'Saving…' : 'Save To Database',
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: saving ? Colors.white : const Color(0xFF00897B))),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    saving ? Colors.grey.shade600 : Colors.white,
                elevation: 1,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            color: const Color(0xFF00897B).withValues(alpha: 0.08),
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
                  color: const Color(0xFF00897B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.info_outline_rounded,
                    size: 16, color: Color(0xFF00897B)),
              ),
              const SizedBox(width: 10),
              Text(
                'Excel column order:  Turbine Name  |  Site Name  |  Model Name',
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
              _TLegendDot(
                  color: Colors.red.shade400, label: 'In-batch duplicate'),
              const SizedBox(width: 12),
              _TLegendDot(
                  color: Colors.orange.shade600,
                  label: 'Already in database'),
              const SizedBox(width: 12),
              _TLegendDot(
                  color: Colors.green.shade600, label: 'Valid row'),
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
            const SizedBox(width: _kTColIndex),
            header('Turbine Name', _kTColName, required: true),
            const SizedBox(width: 8),
            header('Site', _kTColSite, required: true),
            const SizedBox(width: 8),
            header('Model', _kTColModel, required: true),
            const SizedBox(width: 8),
            header('Status', _kTColStatus),
            const SizedBox(width: _kTColDelete),
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
            CircularProgressIndicator(color: Color(0xFF00897B)),
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
                  _BulkTurbineRow(
                    key: ValueKey(i),
                    rowIndex: i,
                    row: _controller.rows[i],
                    controller: _controller,
                    siteMap: _siteMap,
                    siteByName: _siteByName,
                    modelMap: _modelMap,
                    modelByName: _modelByName,
                    hScrollController: _hScroll,
                  ),
                // Bottom add affordance
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
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

class _BulkTurbineRow extends StatelessWidget {
  final int rowIndex;
  final BulkTurbineRowData row;
  final _BulkTurbineController controller;
  final Map<String, String> siteMap;
  final Map<String, Map<String, dynamic>> siteByName;
  final Map<String, String> modelMap;
  final Map<String, Map<String, dynamic>> modelByName;
  final ScrollController hScrollController;

  const _BulkTurbineRow({
    super.key,
    required this.rowIndex,
    required this.row,
    required this.controller,
    required this.siteMap,
    required this.siteByName,
    required this.modelMap,
    required this.modelByName,
    required this.hScrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: row,
      builder: (context2, _) {
        final isDupBatch = controller.duplicateNameIndices.contains(rowIndex);
        final isDupFirestore =
            controller.firestoreDuplicateIndices.contains(rowIndex);
        final isValid = row.isValid;
        final isEven = rowIndex % 2 == 0;

        Color? rowTint;
        if (isDupFirestore) rowTint = Colors.orange.shade50;
        if (isDupBatch) rowTint = Colors.red.shade50;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: kBulkTurbineRowHeight,
          color: rowTint ?? (isEven ? Colors.white : const Color(0xFFFAFBFD)),
          child: Stack(
            children: [
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Divider(
                    height: 1, color: Colors.grey.shade200, thickness: 1),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: hScrollController,
                physics: const NeverScrollableScrollPhysics(),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Index
                      SizedBox(
                        width: _kTColIndex,
                        child: Center(
                          child: Text('${rowIndex + 1}',
                              style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: Colors.grey.shade400,
                                  fontWeight: FontWeight.w500)),
                        ),
                      ),

                      // Turbine Name
                      SizedBox(
                        width: _kTColName,
                        child: _TPlainTextField(
                          value: row.turbineName,
                          placeholder: 'Turbine name…',
                          hasDuplicate: isDupBatch || isDupFirestore,
                          onChanged: row.setTurbineName,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Site
                      SizedBox(
                        width: _kTColSite,
                        child: _TInlineDropdown(
                          selectedId: row.siteId,
                          selectedName: row.siteName,
                          items: siteMap,
                          placeholder: 'Select site…',
                          accentColor: const Color(0xFF00897B),
                          onSelected: (id) {
                            final match = siteByName.values
                                .firstWhere(
                                  (m) => m['id'] == id,
                                  orElse: () => {},
                                );
                            if (match.isNotEmpty) {
                              row.setSite(
                                id: match['id'] as String,
                                name: match['name'] as String,
                                ref: match['ref'] as DocumentReference,
                              );
                            }
                          },
                          onCleared: row.clearSite,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Model
                      SizedBox(
                        width: _kTColModel,
                        child: _TInlineDropdown(
                          selectedId: row.modelId,
                          selectedName: row.modelName,
                          items: modelMap,
                          placeholder: 'Select model…',
                          accentColor: const Color(0xFF00897B),
                          onSelected: (id) {
                            final match = modelByName.values
                                .firstWhere(
                                  (m) => m['id'] == id,
                                  orElse: () => {},
                                );
                            if (match.isNotEmpty) {
                              row.setModel(
                                id: match['id'] as String,
                                name: match['name'] as String,
                                ref: match['ref'] as DocumentReference,
                              );
                            }
                          },
                          onCleared: row.clearModel,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Status
                      SizedBox(
                        width: _kTColStatus,
                        child: _TStatusBadge(
                          isDupBatch: isDupBatch,
                          isDupFirestore: isDupFirestore,
                          isValid: isValid,
                          turbineName: row.turbineName,
                        ),
                      ),

                      // Delete
                      SizedBox(
                        width: _kTColDelete,
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

class _TInlineDropdown extends StatelessWidget {
  final String? selectedId;
  final String? selectedName;
  final Map<String, String> items;
  final String placeholder;
  final Color accentColor;
  final ValueChanged<String> onSelected;
  final VoidCallback onCleared;

  const _TInlineDropdown({
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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
            title: TextField(
              controller: searchCtrl,
              onChanged: (_) => setS(() {}),
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search…',
                hintStyle:
                    GoogleFonts.outfit(color: Colors.grey.shade400),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
            content: SizedBox(
              width: 300,
              height: 350,
              child: filtered.isEmpty
                  ? Center(
                      child: Text('No matches',
                          style: GoogleFonts.outfit(
                              color: Colors.grey.shade500)),
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

class _TPlainTextField extends StatefulWidget {
  final String value;
  final String placeholder;
  final bool hasDuplicate;
  final ValueChanged<String> onChanged;

  const _TPlainTextField({
    required this.value,
    required this.placeholder,
    required this.hasDuplicate,
    required this.onChanged,
  });

  @override
  State<_TPlainTextField> createState() => _TPlainTextFieldState();
}

class _TPlainTextFieldState extends State<_TPlainTextField> {
  late TextEditingController _ctrl;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TPlainTextField old) {
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
        style:
            GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF1A1F36)),
        decoration: InputDecoration(
          hintText: widget.placeholder,
          hintStyle:
              GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade400),
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
                  : const Color(0xFF00897B),
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

class _TStatusBadge extends StatelessWidget {
  final bool isDupBatch;
  final bool isDupFirestore;
  final bool isValid;
  final String turbineName;

  const _TStatusBadge({
    required this.isDupBatch,
    required this.isDupFirestore,
    required this.isValid,
    required this.turbineName,
  });

  @override
  Widget build(BuildContext context) {
    if (turbineName.trim().isEmpty) return const SizedBox();

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
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: fgColor)),
        ],
      ),
    );
  }
}

// ─── Legend Dot ───────────────────────────────────────────────────────────────

class _TLegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _TLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: GoogleFonts.outfit(
                fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }
}
