import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ─── Rich Span Model ──────────────────────────────────────────────────────────

class RichSpan {
  String text;
  bool bold;
  bool italic;
  double fontSize;
  int colorArgb; // e.g. 0xFF1A1F36

  RichSpan({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.fontSize = 14.0,
    this.colorArgb = 0xFF1A1F36,
  });

  RichSpan copyWith({
    String? text,
    bool? bold,
    bool? italic,
    double? fontSize,
    int? colorArgb,
  }) {
    return RichSpan(
      text: text ?? this.text,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      fontSize: fontSize ?? this.fontSize,
      colorArgb: colorArgb ?? this.colorArgb,
    );
  }

  /// Serialize to an inline-styled HTML <span> (or plain text if no formatting).
  String toHtml() {
    if (text.isEmpty) return '';
    final styles = <String>[];
    if (bold) styles.add('font-weight:bold');
    if (italic) styles.add('font-style:italic');
    if (fontSize != 14.0) styles.add('font-size:${fontSize.round()}px');
    if (colorArgb != 0xFF1A1F36) {
      final hex = '#${(colorArgb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
      styles.add('color:$hex');
    }
    final escaped = _escapeHtml(text);
    if (styles.isEmpty) return escaped;
    return '<span style="${styles.join(';')}">$escaped</span>';
  }

  static String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static RichSpan plain(String text) => RichSpan(text: text);
}

/// Concatenate spans into an HTML string.
String spansToHtml(List<RichSpan> spans) =>
    spans.isEmpty ? '' : spans.map((s) => s.toHtml()).join('');

/// Concatenate spans to plain text.
String spansToPlain(List<RichSpan> spans) =>
    spans.map((s) => s.text).join('');

// ─── Row Data Model ───────────────────────────────────────────────────────────

class BulkTaskRowData extends ChangeNotifier {
  List<RichSpan> titleSpans;
  List<RichSpan> descSpans;

  String? subCategoryId;
  String? subCategoryName;
  DocumentReference? subCategoryRef;
  DocumentReference? mainCategoryRef;

  String? referenceId;
  String? referenceName;
  DocumentReference? referenceRef;

  int sortOrder;

  BulkTaskRowData({
    List<RichSpan>? titleSpans,
    List<RichSpan>? descSpans,
    this.subCategoryId,
    this.subCategoryName,
    this.subCategoryRef,
    this.mainCategoryRef,
    this.referenceId,
    this.referenceName,
    this.referenceRef,
    this.sortOrder = 0,
  })  : titleSpans = titleSpans ?? [],
        descSpans = descSpans ?? [];

  String get titlePlain => spansToPlain(titleSpans);
  String get descPlain => spansToPlain(descSpans);
  String get titleHtml => spansToHtml(titleSpans);
  String get descHtml => spansToHtml(descSpans);

  void setTitleSpans(List<RichSpan> spans) {
    titleSpans = List.from(spans);
    notifyListeners();
  }

  void setDescSpans(List<RichSpan> spans) {
    descSpans = List.from(spans);
    notifyListeners();
  }

  void setSubCategory({
    required String id,
    required String name,
    required DocumentReference ref,
    DocumentReference? mainCatRef,
  }) {
    subCategoryId = id;
    subCategoryName = name;
    subCategoryRef = ref;
    mainCategoryRef = mainCatRef;
    notifyListeners();
  }

  void clearSubCategory() {
    subCategoryId = null;
    subCategoryName = null;
    subCategoryRef = null;
    mainCategoryRef = null;
    notifyListeners();
  }

  void setReference({
    required String id,
    required String name,
    required DocumentReference ref,
  }) {
    referenceId = id;
    referenceName = name;
    referenceRef = ref;
    notifyListeners();
  }

  void clearReference() {
    referenceId = null;
    referenceName = null;
    referenceRef = null;
    notifyListeners();
  }

  void setSortOrder(int order) {
    sortOrder = order;
    notifyListeners();
  }

  /// Copy SubCategory fields from [source].
  void copySubCategoryFrom(BulkTaskRowData source) {
    subCategoryId = source.subCategoryId;
    subCategoryName = source.subCategoryName;
    subCategoryRef = source.subCategoryRef;
    mainCategoryRef = source.mainCategoryRef;
    notifyListeners();
  }

  /// Copy Reference fields from [source].
  void copyReferenceFrom(BulkTaskRowData source) {
    referenceId = source.referenceId;
    referenceName = source.referenceName;
    referenceRef = source.referenceRef;
    notifyListeners();
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': titlePlain,
      'title_html': titleHtml,
      'description': descPlain,
      'description_html': descHtml,
      'sub_categories_ref': subCategoryRef,
      'sub_category_name': subCategoryName ?? '',
      'main_category_ref': mainCategoryRef,
      'reference_ref': referenceRef,
      'referenceoftask': referenceName ?? '',
      'sort_order': sortOrder,
      'created_at': FieldValue.serverTimestamp(),
      'bulk_entry': true,
    };
  }

  bool get isValid => titlePlain.trim().isNotEmpty && subCategoryRef != null;
}

// ─── Grid Controller ──────────────────────────────────────────────────────────

class BulkGridController extends ChangeNotifier {
  final List<BulkTaskRowData> rows = [];
  final Set<int> duplicateOrderIndices = {};
  final Set<int> duplicateTitleIndices = {};
  final Set<int> duplicateDescIndices = {};

  bool isSaving = false;
  String? errorMessage;
  int savedCount = 0;

  BulkGridController() {
    for (int i = 0; i < 5; i++) {
      _addRowSilent(sortOrder: i + 1);
    }
  }

  // ── Row Management ─────────────────────────────────────────────────────────

  void _addRowSilent({int? sortOrder}) {
    final row = BulkTaskRowData(sortOrder: sortOrder ?? rows.length + 1);
    row.addListener(_onRowChanged);
    rows.add(row);
  }

  void addRow() {
    _addRowSilent(sortOrder: rows.length + 1);
    _revalidate();
    notifyListeners();
  }

  void insertRowAfter(int index) {
    final row = BulkTaskRowData(sortOrder: rows.length + 1);
    row.addListener(_onRowChanged);
    rows.insert(index + 1, row);
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

  // ── Duplicate Detection ────────────────────────────────────────────────────

  void _revalidate() {
    duplicateOrderIndices.clear();
    duplicateTitleIndices.clear();
    duplicateDescIndices.clear();

    // Orders
    final orderBuckets = <int, List<int>>{};
    for (int i = 0; i < rows.length; i++) {
      orderBuckets.putIfAbsent(rows[i].sortOrder, () => []).add(i);
    }
    for (final entry in orderBuckets.entries) {
      if (entry.value.length > 1) duplicateOrderIndices.addAll(entry.value);
    }

    // Titles
    final titleBuckets = <String, List<int>>{};
    for (int i = 0; i < rows.length; i++) {
      final t = rows[i].titlePlain.trim();
      if (t.isNotEmpty) titleBuckets.putIfAbsent(t, () => []).add(i);
    }
    for (final entry in titleBuckets.entries) {
      if (entry.value.length > 1) duplicateTitleIndices.addAll(entry.value);
    }

    // Descriptions
    final descBuckets = <String, List<int>>{};
    for (int i = 0; i < rows.length; i++) {
      final d = rows[i].descPlain.trim();
      if (d.isNotEmpty) descBuckets.putIfAbsent(d, () => []).add(i);
    }
    for (final entry in descBuckets.entries) {
      if (entry.value.length > 1) duplicateDescIndices.addAll(entry.value);
    }
  }

  // ── Drag-to-Fill ──────────────────────────────────────────────────────────

  /// Fill rows from [startRow+1] to [endRow] (inclusive) with data from [startRow].
  /// For 'sort_order', auto-increments. For other fields, straight copy.
  void dragFill({
    required int startRow,
    required int endRow,
    required String field,
  }) {
    if (startRow < 0 || startRow >= rows.length) return;
    final end = endRow.clamp(0, rows.length - 1);
    if (end <= startRow) return;

    final source = rows[startRow];
    for (int i = startRow + 1; i <= end; i++) {
      final target = rows[i];
      switch (field) {
        case 'sub_category':
          target.copySubCategoryFrom(source);
          break;
        case 'reference':
          target.copyReferenceFrom(source);
          break;
        case 'sort_order':
          target.sortOrder = source.sortOrder + (i - startRow);
          target.notifyListeners();
          break;
      }
    }
    _revalidate();
    notifyListeners();
  }

  // ── Clipboard Paste ───────────────────────────────────────────────────────

  /// Parses a TSV string (from Excel copy) into row data.
  /// Column mapping: 0=Title, 1=Description, 2=SubCat name (fuzzy), 3=Ref name, 4=Order
  Future<int> pasteFromClipboard({
    Map<String, Map<String, dynamic>>? subCatByName,
    Map<String, Map<String, dynamic>>? refByName,
  }) async {
    ClipboardData? data;
    try {
      data = await Clipboard.getData('text/plain');
    } catch (e) {
      debugPrint('Clipboard read error: $e');
      return 0;
    }

    if (data?.text == null || data!.text!.trim().isEmpty) return 0;

    final lines = data.text!
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) return 0;

    // Ensure we have enough rows
    while (rows.length < lines.length) {
      _addRowSilent(sortOrder: rows.length + 1);
    }

    int filled = 0;
    for (int i = 0; i < lines.length; i++) {
      final cols = lines[i].split('\t');
      final row = rows[i];

      // Col 0 → Title
      if (cols.isNotEmpty && cols[0].trim().isNotEmpty) {
        row.titleSpans = [RichSpan.plain(cols[0].trim())];
        filled++;
      }
      // Col 1 → Description
      if (cols.length > 1 && cols[1].trim().isNotEmpty) {
        row.descSpans = [RichSpan.plain(cols[1].trim())];
      }
      // Col 2 → Sub Category (fuzzy name match)
      if (cols.length > 2 && subCatByName != null) {
        final name = cols[2].trim().toLowerCase();
        final match = subCatByName.entries
            .firstWhere(
              (e) => e.key.toLowerCase() == name,
              orElse: () => const MapEntry('', {}),
            )
            .value;
        if (match.isNotEmpty) {
          row.subCategoryId = match['id'] as String?;
          row.subCategoryName = match['name'] as String?;
          row.subCategoryRef = match['ref'] as DocumentReference?;
          row.mainCategoryRef = match['mainRef'] as DocumentReference?;
        }
      }
      // Col 3 → Reference (fuzzy name match)
      if (cols.length > 3 && refByName != null) {
        final name = cols[3].trim().toLowerCase();
        final match = refByName.entries
            .firstWhere(
              (e) => e.key.toLowerCase() == name,
              orElse: () => const MapEntry('', {}),
            )
            .value;
        if (match.isNotEmpty) {
          row.referenceId = match['id'] as String?;
          row.referenceName = match['name'] as String?;
          row.referenceRef = match['ref'] as DocumentReference?;
        }
      }
      // Col 4 → Sort Order
      if (cols.length > 4) {
        row.sortOrder = int.tryParse(cols[4].trim()) ?? (i + 1);
      } else {
        row.sortOrder = i + 1;
      }

      row.notifyListeners();
    }

    _revalidate();
    notifyListeners();
    return filled;
  }

  // ── Validation ────────────────────────────────────────────────────────────

  bool get hasErrors =>
      duplicateOrderIndices.isNotEmpty || duplicateTitleIndices.isNotEmpty;

  List<String> validationMessages() {
    final msgs = <String>[];
    final validRows =
        rows.where((r) => r.titlePlain.trim().isNotEmpty).toList();
    if (validRows.isEmpty) msgs.add('No rows have a title.');

    final noSubCat = rows
        .where((r) =>
            r.titlePlain.trim().isNotEmpty && r.subCategoryRef == null)
        .length;
    if (noSubCat > 0) {
      msgs.add('$noSubCat row(s) are missing a Sub Category.');
    }
    if (duplicateOrderIndices.isNotEmpty) {
      msgs.add('${duplicateOrderIndices.length} row(s) have duplicate Order numbers.');
    }
    if (duplicateTitleIndices.isNotEmpty) {
      msgs.add('${duplicateTitleIndices.length} row(s) have duplicate Titles.');
    }
    return msgs;
  }

  // ── Batch Save ────────────────────────────────────────────────────────────

  Future<bool> saveAll() async {
    if (isSaving) return false;

    final validRows =
        rows.where((r) => r.isValid).toList();

    if (validRows.isEmpty) {
      errorMessage =
          'No valid rows. Each row needs a Title and Sub Category.';
      notifyListeners();
      return false;
    }
    if (hasErrors) {
      errorMessage =
          'Fix duplicate errors (shown in red) before saving.';
      notifyListeners();
      return false;
    }

    isSaving = true;
    errorMessage = null;
    notifyListeners();

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final row in validRows) {
        final ref = FirebaseFirestore.instance.collection('tasks').doc();
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

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    for (final row in rows) {
      row.removeListener(_onRowChanged);
      row.dispose();
    }
    super.dispose();
  }
}
