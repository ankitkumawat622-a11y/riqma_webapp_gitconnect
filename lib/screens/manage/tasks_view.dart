import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:riqma_webapp/screens/manage/bulk_task_entry_screen.dart';
import 'package:riqma_webapp/widgets/modern_searchable_dropdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Rich Text Formatting State ─────────────────────────────────────────────
class _TextStyle {
  Color color;
  double fontSize;
  String fontFamily;
  bool bold;
  bool italic;

  _TextStyle({
    this.color = const Color(0xFF1A1F36),
    this.fontSize = 14,
    this.fontFamily = 'Outfit',
    this.bold = false,
    this.italic = false,
  });

  TextStyle toFlutter() {
    final base = fontFamily == 'Outfit'
        ? GoogleFonts.outfit
        : fontFamily == 'Roboto'
            ? GoogleFonts.roboto
            : fontFamily == 'Inter'
                ? GoogleFonts.inter
                : fontFamily == 'Lato'
                    ? GoogleFonts.lato
                    : fontFamily == 'Montserrat'
                        ? GoogleFonts.montserrat
                        : fontFamily == 'Poppins'
                            ? GoogleFonts.poppins
                            : GoogleFonts.outfit;
    return base(
      color: color,
      fontSize: fontSize,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    );
  }
}


class TasksView extends StatefulWidget {
  const TasksView({super.key});

  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView> {
  List<PlutoRow> rows = [];
  bool isLoading = true;
  StreamSubscription<QuerySnapshot>? _dataSubscription;
  StreamSubscription<QuerySnapshot>? _mainCatSubscription;
  StreamSubscription<QuerySnapshot>? _subCatSubscription;
  StreamSubscription<QuerySnapshot>? _refSubscription;
  
  // Filter State
  bool _isFiltersExpanded = false;
  String _selectedModel = 'All';
  String _selectedMainCategory = 'All';
  String _selectedSubCategory = 'All';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Relationship Maps
  Map<String, String> _subCatIdToMainCatId = {};
  Map<String, List<String>> _mainToModelsMap = {};
  Map<String, bool> _mainIsGlobalMap = {};
  Map<String, String> _subCatIdToName = {};
  Map<String, String> _mainCatIdToName = {};
  Map<String, String> _refIdToName = {};

  @override
  void initState() {
    super.initState();
    _loadSavedFilters();
    _setupDataStream();
  }

  Future<void> _loadSavedFilters() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedModel = prefs.getString('tasks_model_filter_id') ?? 'All';
      _selectedMainCategory = prefs.getString('tasks_main_category_filter_id') ?? 'All';
      _selectedSubCategory = prefs.getString('tasks_sub_category_filter_id') ?? 'All';
    });
  }

  Future<void> _updateModelFilter(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tasks_model_filter_id', modelId);
    // Reset dependent filters
    await prefs.setString('tasks_main_category_filter_id', 'All');
    await prefs.setString('tasks_sub_category_filter_id', 'All');
    setState(() {
      _selectedModel = modelId;
      _selectedMainCategory = 'All';
      _selectedSubCategory = 'All';
    });
  }

  Future<void> _updateMainCategoryFilter(String categoryId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tasks_main_category_filter_id', categoryId);
    // Reset dependent filter
    await prefs.setString('tasks_sub_category_filter_id', 'All');
    setState(() {
      _selectedMainCategory = categoryId;
      _selectedSubCategory = 'All';
    });
  }

  Future<void> _updateSubCategoryFilter(String subCategoryId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tasks_sub_category_filter_id', subCategoryId);
    setState(() {
      _selectedSubCategory = subCategoryId;
    });
  }

  @override
  void dispose() {
    _mainCatSubscription?.cancel();
    _subCatSubscription?.cancel();
    _refSubscription?.cancel();
    _dataSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _setupDataStream() {
    // 1. Fetch Main Categories (Support Dual-Stream: target_models OR is_all_models)
    _mainCatSubscription = FirebaseFirestore.instance.collection('main_categories').snapshots().listen((mainCatSnapshot) {
      final Map<String, List<String>> mainToModels = {};
      final Map<String, bool> mainIsGlobal = {};
      final Map<String, String> mainToName = {};
      
      for (final doc in mainCatSnapshot.docs) {
        final data = doc.data();
        mainToName[doc.id] = (data['name'] ?? 'Unknown').toString();
        mainIsGlobal[doc.id] = data['is_all_models'] == true;
        
        if (data['target_models'] is List) {
          mainToModels[doc.id] = List<String>.from(data['target_models'] as List);
        } else if (data['turbinemodel_ref'] is DocumentReference) {
          // Legacy Fallback
          mainToModels[doc.id] = [(data['turbinemodel_ref'] as DocumentReference).id];
        }
      }
      
      _mainToModelsMap = mainToModels;
      _mainIsGlobalMap = mainIsGlobal;
      _mainCatIdToName = mainToName;
      if (mounted) setState(() {});
    });

    // 2. Fetch Sub Categories (to map Sub -> Main)
    _subCatSubscription = FirebaseFirestore.instance.collection('sub_categories').snapshots().listen((subCatSnapshot) {
      final Map<String, String> subToMain = {};
      final Map<String, String> subToName = {};
      
      for (final doc in subCatSnapshot.docs) {
        final data = doc.data();
        subToName[doc.id] = (data['name'] ?? 'Unknown').toString();
        
        if (data['main_categories_ref'] is DocumentReference) {
          subToMain[doc.id] = (data['main_categories_ref'] as DocumentReference).id;
        }
      }
      
      _subCatIdToMainCatId = subToMain;
      _subCatIdToName = subToName;
      if (mounted) setState(() {});
    });

    // 2.5 Fetch References (Task 4: Live Reference Name Fallback)
    _refSubscription = FirebaseFirestore.instance.collection('references').snapshots().listen((refSnapshot) {
      final Map<String, String> refToName = {};
      for (final doc in refSnapshot.docs) {
        refToName[doc.id] = (doc.data()['name'] ?? 'Unknown').toString();
      }
      _refIdToName = refToName;
      if (mounted) setState(() {});
    });
      
    // 3. Listen to Tasks
    _dataSubscription = FirebaseFirestore.instance
        .collection('tasks')
        .snapshots()
        .listen((snapshot) {
      
      final newRows = snapshot.docs.map((doc) {
        final data = doc.data();

        // Fix #5/#10: Prefer live sub-category name from lookup map.
        // sub_category_name is a denormalised copy that becomes stale after renames.
        String? subCatId;
        if (data['sub_categories_ref'] is DocumentReference) {
           subCatId = (data['sub_categories_ref'] as DocumentReference).id;
        }
        // Live name takes priority; stored name is the fallback for unresolved IDs
        final liveSubCatName = subCatId != null ? _subCatIdToName[subCatId] : null;
        final subCatName = liveSubCatName ?? data['sub_category_name'] ?? 'N/A';
        
        // Resolve IDs for filtering

        // Try to resolve Main Cat Name from ID lookup if possible, fallback to nothing
        // We rely on the ID for filtering, but display uses the stored name or lookup
        // Ideally we display what's in the task or lookup fresh
        
        String mainCatNameDisplay = 'N/A';
        if (subCatId != null && _subCatIdToMainCatId.containsKey(subCatId)) {
           final mainCatId = _subCatIdToMainCatId[subCatId];
           if (mainCatId != null) {
              mainCatNameDisplay = _mainCatIdToName[mainCatId] ?? 'N/A';
           }
        }

        return PlutoRow(
          cells: {
            'title': PlutoCell(value: (data['title'] ?? 'Unknown').toString()),
            'description': PlutoCell(value: (data['description'] ?? '').toString()),
            'main_category': PlutoCell(value: mainCatNameDisplay),
            'sub_category': PlutoCell(value: subCatName.toString()),
            'sub_category_id': PlutoCell(value: subCatId ?? ''), // Hidden column for filtering
            'reference': PlutoCell(value: (data['ref_id'] != null ? _refIdToName[data['ref_id'].toString()] : null) ?? (data['referenceoftask'] ?? '').toString()),
            'sort_order': PlutoCell(value: data['sort_order'] ?? 0),
            'id': PlutoCell(value: doc.id),
            'actions': PlutoCell(value: ''),
          },
        );
      }).toList();

      if (mounted) {
        // Fix Task 2: Robust Numeric Sorting for Tasks
        newRows.sort((a, b) {
          final valA = a.cells['sort_order']?.value ?? 0;
          final valB = b.cells['sort_order']?.value ?? 0;
          final num orderA = valA is num ? valA : (num.tryParse(valA.toString()) ?? 0);
          final num orderB = valB is num ? valB : (num.tryParse(valB.toString()) ?? 0);
          return orderA.compareTo(orderB);
        });
        
        setState(() {rows = newRows; isLoading = false;});
      }
    }, onError: (Object error) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $error')));
      }
    });
  }

  Future<void> _addItem({String? activeFilterSubCatId, String? activeFilterModelId}) async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final sortOrderController = TextEditingController(text: '0');
    final titleStyle = _TextStyle();
    final descStyle = _TextStyle(fontSize: 13, color: Colors.grey.shade700);

    String? selectedModelId;
    String? selectedMainCategoryId;
    DocumentReference? selectedMainCategoryRef;
    String? selectedSubCategoryId;
    DocumentReference? selectedSubCategoryRef;
    String? selectedSubCategoryName;
    String? selectedReferenceId;
    DocumentReference? selectedReferenceRef;
    String? selectedReferenceName;
    bool isLoadingOrder = false;

    final prefs = await SharedPreferences.getInstance();
    final lastModelId = prefs.getString('last_task_model_id');

    Future<void> fetchNextTaskOrder(DocumentReference subCatRef, StateSetter setDialogState) async {
      setDialogState(() => isLoadingOrder = true);
      try {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('tasks')
            .where('sub_categories_ref', isEqualTo: subCatRef)
            .get();
        int maxOrder = -1;
        for (final doc in querySnapshot.docs) {
          final order = doc.data()['sort_order'];
          final orderInt = order is int ? order : int.tryParse(order.toString()) ?? 0;
          if (orderInt > maxOrder) maxOrder = orderInt;
        }
        sortOrderController.text = (maxOrder + 1).toString();
      } catch (e) {
        debugPrint('Error fetching next task order: $e');
        sortOrderController.text = '0';
      }
      setDialogState(() => isLoadingOrder = false);
    }

    if (!mounted) return;

    selectedModelId = activeFilterModelId;
    if (selectedModelId == null && lastModelId != null && _selectedModel == 'All') {
      selectedModelId = lastModelId;
    }
    if (activeFilterSubCatId != null) {
      selectedSubCategoryId = activeFilterSubCatId;
      selectedSubCategoryName = _subCatIdToName[activeFilterSubCatId];
    }

    await _showTaskFormDialog(
      isEdit: false,
      titleController: titleController,
      descriptionController: descriptionController,
      sortOrderController: sortOrderController,
      titleStyle: titleStyle,
      descStyle: descStyle,
      selectedModelIdGetter: () => selectedModelId,
      selectedModelIdSetter: (v) => selectedModelId = v,
      selectedMainCategoryIdGetter: () => selectedMainCategoryId,
      selectedMainCategoryIdSetter: (v) => selectedMainCategoryId = v,
      selectedMainCategoryRefSetter: (v) => selectedMainCategoryRef = v,
      selectedSubCategoryIdGetter: () => selectedSubCategoryId,
      selectedSubCategoryIdSetter: (v) => selectedSubCategoryId = v,
      selectedSubCategoryRefSetter: (v) => selectedSubCategoryRef = v,
      selectedSubCategoryNameSetter: (v) => selectedSubCategoryName = v,
      selectedReferenceIdGetter: () => selectedReferenceId,
      selectedReferenceIdSetter: (v) => selectedReferenceId = v,
      selectedReferenceRefSetter: (v) => selectedReferenceRef = v,
      selectedReferenceNameSetter: (v) => selectedReferenceName = v,
      isLoadingOrderGetter: () => isLoadingOrder,
      fetchNextTaskOrder: fetchNextTaskOrder,
      onSave: () async {
        if (titleController.text.trim().isEmpty || selectedSubCategoryRef == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select Model, Main Category, Sub Category and enter Title')),
          );
          return;
        }
        if (selectedModelId != null) await prefs.setString('last_task_model_id', selectedModelId!);
        await FirebaseFirestore.instance.collection('tasks').add({
          'title': titleController.text.trim(),
          'description': descriptionController.text.trim(),
          'referenceoftask': selectedReferenceName ?? '',
          'reference_ref': selectedReferenceRef,
          'sub_categories_ref': selectedSubCategoryRef,
          'sub_category_name': selectedSubCategoryName,
          'sort_order': int.tryParse(sortOrderController.text) ?? 0,
          'created_at': FieldValue.serverTimestamp(),
          'main_category_ref': selectedMainCategoryRef,
          'title_style': {
            'color': titleStyle.color.toARGB32(),
            'fontSize': titleStyle.fontSize,
            'fontFamily': titleStyle.fontFamily,
            'bold': titleStyle.bold,
            'italic': titleStyle.italic,
          },
          'desc_style': {
            'color': descStyle.color.toARGB32(),
            'fontSize': descStyle.fontSize,
            'fontFamily': descStyle.fontFamily,
            'bold': descStyle.bold,
            'italic': descStyle.italic,
          },
        });
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task added')));
        }
      },
    );
  }

  Future<void> _editItem(String? docId) async {
    if (docId == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('tasks').doc(docId).get();
      if (!doc.exists || !mounted) return;

      final data = doc.data()!;
      final titleController = TextEditingController(text: (data['title'] ?? '').toString());
      final descriptionController = TextEditingController(text: (data['description'] ?? '').toString());
      final sortOrderController = TextEditingController(text: (data['sort_order'] ?? 0).toString());

      // Restore saved styles
      final savedTitleStyle = data['title_style'] as Map<String, dynamic>?;
      final savedDescStyle = data['desc_style'] as Map<String, dynamic>?;
      final titleStyle = _TextStyle(
        color: savedTitleStyle != null ? Color(savedTitleStyle['color'] as int) : const Color(0xFF1A1F36),
        fontSize: savedTitleStyle != null ? (savedTitleStyle['fontSize'] as num).toDouble() : 14,
        fontFamily: savedTitleStyle?['fontFamily'] as String? ?? 'Outfit',
        bold: savedTitleStyle?['bold'] as bool? ?? false,
        italic: savedTitleStyle?['italic'] as bool? ?? false,
      );
      final descStyle = _TextStyle(
        color: savedDescStyle != null ? Color(savedDescStyle['color'] as int) : Colors.grey.shade700,
        fontSize: savedDescStyle != null ? (savedDescStyle['fontSize'] as num).toDouble() : 13,
        fontFamily: savedDescStyle?['fontFamily'] as String? ?? 'Outfit',
        bold: savedDescStyle?['bold'] as bool? ?? false,
        italic: savedDescStyle?['italic'] as bool? ?? false,
      );

      String? selectedSubCategoryId;
      DocumentReference? selectedSubCategoryRef = data['sub_categories_ref'] as DocumentReference?;
      String? selectedSubCategoryName = data['sub_category_name']?.toString();
      String? selectedReferenceId;
      DocumentReference? selectedReferenceRef = data['reference_ref'] as DocumentReference?;
      String? selectedReferenceName = data['referenceoftask']?.toString();

      if (selectedReferenceRef != null) {
        try {
          final refDoc = await selectedReferenceRef.get();
          if (refDoc.exists) {
            selectedReferenceId = refDoc.id;
            final refData = refDoc.data() as Map<String, dynamic>?;
            if (refData != null) selectedReferenceName = refData['name']?.toString();
          }
        } catch (e) { debugPrint('Error fetching reference: $e'); }
      }

      if (selectedSubCategoryRef != null) {
        try {
          final subCategoryDoc = await selectedSubCategoryRef.get();
          if (subCategoryDoc.exists) {
            selectedSubCategoryId = subCategoryDoc.id;
            final subCategoryData = subCategoryDoc.data() as Map<String, dynamic>?;
            if (subCategoryData != null) selectedSubCategoryName = subCategoryData['name']?.toString();
          }
        } catch (e) { debugPrint('Error fetching sub category: $e'); }
      }

      if (!mounted) return;

      await _showTaskFormDialog(
        isEdit: true,
        titleController: titleController,
        descriptionController: descriptionController,
        sortOrderController: sortOrderController,
        titleStyle: titleStyle,
        descStyle: descStyle,
        selectedSubCategoryIdGetter: () => selectedSubCategoryId,
        selectedSubCategoryIdSetter: (v) => selectedSubCategoryId = v,
        selectedSubCategoryRefSetter: (v) => selectedSubCategoryRef = v,
        selectedSubCategoryNameSetter: (v) => selectedSubCategoryName = v,
        selectedReferenceIdGetter: () => selectedReferenceId,
        selectedReferenceIdSetter: (v) => selectedReferenceId = v,
        selectedReferenceRefSetter: (v) => selectedReferenceRef = v,
        selectedReferenceNameSetter: (v) => selectedReferenceName = v,
        onSave: () async {
          if (titleController.text.trim().isEmpty || selectedSubCategoryRef == null) return;
          await FirebaseFirestore.instance.collection('tasks').doc(docId).update({
            'title': titleController.text.trim(),
            'description': descriptionController.text.trim(),
            'referenceoftask': selectedReferenceName ?? '',
            'reference_ref': selectedReferenceRef,
            'sub_categories_ref': selectedSubCategoryRef,
            'sub_category_name': selectedSubCategoryName,
            'sort_order': int.tryParse(sortOrderController.text) ?? 0,
            'title_style': {
              'color': titleStyle.color.toARGB32(),
              'fontSize': titleStyle.fontSize,
              'fontFamily': titleStyle.fontFamily,
              'bold': titleStyle.bold,
              'italic': titleStyle.italic,
            },
            'desc_style': {
              'color': descStyle.color.toARGB32(),
              'fontSize': descStyle.fontSize,
              'fontFamily': descStyle.fontFamily,
              'bold': descStyle.bold,
              'italic': descStyle.italic,
            },
          });
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task updated')));
          }
        },
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  /// Universal rich-text form dialog for both Add and Edit
  Future<void> _showTaskFormDialog({
    required bool isEdit,
    required TextEditingController titleController,
    required TextEditingController descriptionController,
    required TextEditingController sortOrderController,
    required _TextStyle titleStyle,
    required _TextStyle descStyle,
    // Add-mode only selectors
    String? Function()? selectedModelIdGetter,
    void Function(String?)? selectedModelIdSetter,
    String? Function()? selectedMainCategoryIdGetter,
    void Function(String?)? selectedMainCategoryIdSetter,
    void Function(DocumentReference?)? selectedMainCategoryRefSetter,
    // Shared selectors
    String? Function()? selectedSubCategoryIdGetter,
    void Function(String?)? selectedSubCategoryIdSetter,
    void Function(DocumentReference?)? selectedSubCategoryRefSetter,
    void Function(String?)? selectedSubCategoryNameSetter,
    String? Function()? selectedReferenceIdGetter,
    void Function(String?)? selectedReferenceIdSetter,
    void Function(DocumentReference?)? selectedReferenceRefSetter,
    void Function(String?)? selectedReferenceNameSetter,
    bool Function()? isLoadingOrderGetter,
    Future<void> Function(DocumentReference, StateSetter)? fetchNextTaskOrder,
    required Future<void> Function() onSave,
  }) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Container(
              width: 540,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 40, offset: const Offset(0, 12)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header ──────────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1A1F36), Color(0xFF2D3561)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isEdit ? Icons.edit_rounded : Icons.add_task_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isEdit ? 'Edit Task' : 'Add New Task',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () => Navigator.pop(ctx),
                          borderRadius: BorderRadius.circular(8),
                          child: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                        ),
                      ],
                    ),
                  ),

                  // ── Body ────────────────────────────────────────────────────
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Title field with toolbar ──────────────────────
                          const _SectionLabel(label: 'Title'),
                          _RichTextToolbar(
                            style: titleStyle,
                            onChanged: () => setDialogState(() {}),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: titleController,
                            style: titleStyle.toFlutter(),
                            decoration: InputDecoration(
                              hintText: 'Enter task title…',
                              hintStyle: GoogleFonts.outfit(color: Colors.grey.shade400),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF1A1F36), width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // ── Description field with toolbar ────────────────
                          const _SectionLabel(label: 'Description'),
                          _RichTextToolbar(
                            style: descStyle,
                            onChanged: () => setDialogState(() {}),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: descriptionController,
                            style: descStyle.toFlutter(),
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: 'Enter task description…',
                              hintStyle: GoogleFonts.outfit(color: Colors.grey.shade400),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF1A1F36), width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // ── Add-mode extra fields (Model/Main Cat) ────────
                          if (!isEdit) ...[
                            const _SectionLabel(label: 'Turbine Model'),
                            const SizedBox(height: 6),
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance.collection('turbinemodel').snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) return const LinearProgressIndicator();
                                final items = {
                                  for (final doc in snapshot.data!.docs)
                                    doc.id: (doc.data() as Map<String, dynamic>).containsKey('turbine_model')
                                        ? (doc.data() as Map<String, dynamic>)['turbine_model'].toString()
                                        : (doc.data() as Map<String, dynamic>)['name']?.toString() ?? 'Unknown',
                                };
                                return ModernSearchableDropdown(
                                  label: 'Turbine Model',
                                  items: items,
                                  value: selectedModelIdGetter?.call(),
                                  color: Colors.purple,
                                  icon: Icons.precision_manufacturing_rounded,
                                  onChanged: (val) {
                                    if (val == null) return;
                                    setDialogState(() {
                                      selectedModelIdSetter?.call(val);
                                      selectedMainCategoryIdSetter?.call(null);
                                      selectedMainCategoryRefSetter?.call(null);
                                      selectedSubCategoryIdSetter?.call(null);
                                      selectedSubCategoryNameSetter?.call(null);
                                      selectedSubCategoryRefSetter?.call(null);
                                    });
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            const _SectionLabel(label: 'Main Category'),
                            const SizedBox(height: 6),
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance.collection('main_categories').snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) return const SizedBox();
                                final docs = snapshot.data!.docs.where((d) {
                                  final dd = d.data() as Map<String, dynamic>;
                                  final modelId = selectedModelIdGetter?.call();
                                  if (modelId == null) return false;
                                  if (dd['turbinemodel_ref'] is DocumentReference) {
                                    return (dd['turbinemodel_ref'] as DocumentReference).id == modelId;
                                  }
                                  return false;
                                });
                                final items = {
                                  for (final doc in docs)
                                    doc.id: (doc.data() as Map<String, dynamic>)['name']?.toString() ?? 'Unknown',
                                };
                                return ModernSearchableDropdown(
                                  label: 'Main Category',
                                  items: items,
                                  value: selectedMainCategoryIdGetter?.call(),
                                  enabled: selectedModelIdGetter?.call() != null,
                                  color: Colors.indigo,
                                  icon: Icons.category_rounded,
                                  onChanged: (val) {
                                    if (val == null) return;
                                    final doc = docs.firstWhere((d) => d.id == val);
                                    setDialogState(() {
                                      selectedMainCategoryIdSetter?.call(val);
                                      selectedMainCategoryRefSetter?.call(doc.reference);
                                      selectedSubCategoryIdSetter?.call(null);
                                      selectedSubCategoryNameSetter?.call(null);
                                      selectedSubCategoryRefSetter?.call(null);
                                    });
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                          ],

                          // ── Sub Category ──────────────────────────────────
                          const _SectionLabel(label: 'Sub Category'),
                          const SizedBox(height: 6),
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance.collection('sub_categories').snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) return const SizedBox();
                              Iterable<QueryDocumentSnapshot> docs = snapshot.data!.docs;
                              if (!isEdit) {
                                docs = docs.where((d) {
                                  final dd = d.data() as Map<String, dynamic>;
                                  final mainId = selectedMainCategoryIdGetter?.call();
                                  if (mainId == null) return false;
                                  if (dd['main_categories_ref'] is DocumentReference) {
                                    return (dd['main_categories_ref'] as DocumentReference).id == mainId;
                                  }
                                  return false;
                                });
                              }
                              final items = {
                                for (final doc in docs)
                                  doc.id: (doc.data() as Map<String, dynamic>)['name']?.toString() ?? 'Unknown',
                              };
                              return ModernSearchableDropdown(
                                label: 'Sub Category',
                                items: items,
                                value: selectedSubCategoryIdGetter?.call(),
                                enabled: isEdit || selectedMainCategoryIdGetter?.call() != null,
                                color: Colors.blue,
                                icon: Icons.layers_rounded,
                                onChanged: (val) {
                                  if (val == null) return;
                                  final doc = docs.firstWhere((d) => d.id == val);
                                  setDialogState(() {
                                    selectedSubCategoryIdSetter?.call(val);
                                    selectedSubCategoryNameSetter?.call(
                                      (doc.data() as Map<String, dynamic>)['name']?.toString(),
                                    );
                                    selectedSubCategoryRefSetter?.call(doc.reference);
                                  });
                                  if (!isEdit) fetchNextTaskOrder?.call(doc.reference, setDialogState);
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 14),

                          // ── Reference ─────────────────────────────────────
                          const _SectionLabel(label: 'Reference'),
                          const SizedBox(height: 6),
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance.collection('references').snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) return const SizedBox();
                              final items = {
                                for (final doc in snapshot.data!.docs)
                                  doc.id: (doc.data() as Map<String, dynamic>)['name']?.toString() ?? 'Unknown',
                              };
                              return ModernSearchableDropdown(
                                label: 'Reference',
                                value: selectedReferenceIdGetter?.call(),
                                items: items,
                                color: Colors.amber,
                                icon: Icons.bookmark_rounded,
                                onChanged: (val) {
                                  final doc = snapshot.data!.docs.firstWhere((d) => d.id == val);
                                  setDialogState(() {
                                    selectedReferenceIdSetter?.call(val);
                                    selectedReferenceNameSetter?.call(
                                      (doc.data() as Map<String, dynamic>)['name']?.toString(),
                                    );
                                    selectedReferenceRefSetter?.call(doc.reference);
                                  });
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 14),

                          // ── Sort Order ────────────────────────────────────
                          const _SectionLabel(label: 'Sort Order'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: sortOrderController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: '0',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF1A1F36), width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              suffixIcon: (isLoadingOrderGetter?.call() ?? false)
                                  ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Footer actions ───────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border(top: BorderSide(color: Colors.grey.shade200)),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
                          child: Text('Cancel', style: GoogleFonts.outfit()),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () async {
                            try {
                              await onSave();
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
                              }
                            }
                          },
                          icon: Icon(isEdit ? Icons.save_rounded : Icons.add_rounded, size: 18),
                          label: Text(isEdit ? 'Update' : 'Add Task', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A1F36),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _deleteItem(String? docId) {
    if (docId == null) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Task', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        content: const Text('Are you sure? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await FirebaseFirestore.instance.collection('tasks').doc(docId).delete();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task deleted')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate filteredRows outside the Builder so it's available for the header count
    var filteredRows = rows.where((PlutoRow row) {
      final subCatId = row.cells['sub_category_id']?.value?.toString();
      // 1. Filter by SubCategory (ID)
      if (_selectedSubCategory != 'All') {
        return subCatId == _selectedSubCategory;
      }

      // 2. Filter by MainCategory (ID)
      if (_selectedMainCategory != 'All') {
        final mainCatId = subCatId != null ? _subCatIdToMainCatId[subCatId] : null;
        return mainCatId == _selectedMainCategory;
      }

      // 3. Filter by Model (ID)
      if (_selectedModel != 'All') {
        final mainCatId = subCatId != null ? _subCatIdToMainCatId[subCatId] : null;
        if (mainCatId == null) return false;
        final isGlobal = _mainIsGlobalMap[mainCatId] == true;
        final allowedModels = _mainToModelsMap[mainCatId] ?? [];
        return isGlobal || allowedModels.contains(_selectedModel);
      }
      return true;
    }).toList();

    // 4. Filter by Search Query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filteredRows = filteredRows.where((row) {
        final title = row.cells['title']?.value?.toString().toLowerCase() ?? '';
        final desc = row.cells['description']?.value?.toString().toLowerCase() ?? '';
        final mainCat = row.cells['main_category']?.value?.toString().toLowerCase() ?? '';
        final subCat = row.cells['sub_category']?.value?.toString().toLowerCase() ?? '';
        final ref = row.cells['reference']?.value?.toString().toLowerCase() ?? '';
        return title.contains(q) ||
            desc.contains(q) ||
            mainCat.contains(q) ||
            subCat.contains(q) ||
            ref.contains(q);
      }).toList();
    }

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded, color: Colors.grey.shade600, size: 20),
                    const SizedBox(width: 8),
                    if (!_isSearching) ...[
                      Text('Tasks (${filteredRows.length})', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => setState(() => _isSearching = true),
                        icon: Icon(Icons.search_rounded, color: Colors.grey.shade600, size: 20),
                        tooltip: 'Search tasks',
                        splashRadius: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ] else ...[
                      SizedBox(
                        width: 200,
                        height: 36,
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          style: GoogleFonts.outfit(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Search tasks...',
                            hintStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade400),
                            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF1A1F36)),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                setState(() {
                                  _isSearching = false;
                                  _searchController.clear();
                                  _searchQuery = '';
                                });
                              },
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                            fillColor: Colors.grey.shade100,
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 0),
                          ),
                          onChanged: (value) => setState(() => _searchQuery = value),
                        ),
                      ),
                    ],
                    const SizedBox(width: 16),
                    // Expand/Collapse Button
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _isFiltersExpanded = !_isFiltersExpanded;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              Text(
                                _isFiltersExpanded ? 'Hide Filters' : 'Show Filters',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  color: const Color(0xFF0277BD),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                _isFiltersExpanded 
                                    ? Icons.keyboard_arrow_up_rounded 
                                    : Icons.keyboard_arrow_down_rounded,
                                color: const Color(0xFF0277BD),
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // ── Bulk Entry Button ──────────────────────────────────
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const BulkTaskEntryScreen(),
                          fullscreenDialog: true,
                        ),
                      ),
                      icon: const Icon(Icons.table_rows_rounded, size: 16),
                      label: Text('Bulk Entry',
                          style: GoogleFonts.outfit(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1A1F36),
                        side: const BorderSide(color: Color(0xFF1A1F36)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // ── Single Add Task Button ──────────────────────────────
                    ElevatedButton.icon(
                      onPressed: () => _addItem(
                        activeFilterSubCatId:
                            _selectedSubCategory != 'All'
                                ? _selectedSubCategory
                                : null,
                        activeFilterModelId:
                            _selectedModel != 'All' ? _selectedModel : null,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Task'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1F36),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Turbine Model Filter
          if (_isFiltersExpanded) ...[
            _buildFilterRow(
              label: 'Model',
              stream: FirebaseFirestore.instance.collection('turbinemodel').snapshots(),
              selectedValue: _selectedModel,
              onSelected: _updateModelFilter,
              nameField: 'turbine_model', // or 'name' checked inside
              color: Colors.indigo,
            ),
            
            // Main Category Filter
            _buildFilterRow(
              label: 'Main Category',
              stream: FirebaseFirestore.instance.collection('main_categories').snapshots(),
              selectedValue: _selectedMainCategory,
              onSelected: _updateMainCategoryFilter,
              nameField: 'name',
              color: Colors.teal,
              parentFilterId: _selectedModel != 'All' ? _selectedModel : null,
              parentRefField: 'turbinemodel_ref',
            ),
            
            // Sub Category Filter
            _buildFilterRow(
              label: 'Sub Category',
              stream: FirebaseFirestore.instance.collection('sub_categories').snapshots(),
              selectedValue: _selectedSubCategory,
              onSelected: _updateSubCategoryFilter,
              nameField: 'name',
              color: Colors.orange,
              parentFilterId: _selectedMainCategory != 'All' ? _selectedMainCategory : null,
              parentRefField: 'main_categories_ref',
            ),
          ],
          
          // Column Headers
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 1))),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('TASK DETAILS', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                Expanded(flex: 2, child: Text('CATEGORY', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                Expanded(flex: 1, child: Text('REF', textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                SizedBox(width: 60, child: Text('ORDER', textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                SizedBox(width: 100, child: Text('ACTIONS', textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
              ],
            ),
          ),
          
        Expanded(
          child: Builder(
            builder: (context) {
              if (isLoading) return const Center(child: CircularProgressIndicator());

              if (filteredRows.isEmpty) {
                return const Center(child: Text('No tasks found for selected filters.'));
              }

                return ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: filteredRows.length,
                  separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
                  itemBuilder: (context, index) {
                    final row = filteredRows[index];
                    final id = row.cells['id']?.value;
                    final String title = (row.cells['title']?.value ?? 'Unknown').toString();
                    final String description = (row.cells['description']?.value ?? '').toString();
                    final String mainCat = (row.cells['main_category']?.value ?? 'N/A').toString();
                    final String subCat = (row.cells['sub_category']?.value ?? 'N/A').toString();
                    final String reference = (row.cells['reference']?.value ?? '').toString();
                    final sortOrder = row.cells['sort_order']?.value ?? 0;
                    final bool isNotEmpty = title.isNotEmpty;
                    final initial = isNotEmpty ? title[0].toUpperCase() : '?';

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(color: const Color(0xFF1A1F36).withValues(alpha: 0.1), shape: BoxShape.circle),
                                  child: Center(child: Text(initial, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF1A1F36)))),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(title, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF1A1F36))),
                                      if (description.isNotEmpty)
                                        Text(
                                          description,
                                          style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(mainCat, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.teal.shade700)),
                                Text(subCat, style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Center(
                              child: reference.toString().isNotEmpty
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                                      child: Text(reference, textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
                                    )
                                  : const SizedBox(),
                            ),
                          ),
                          SizedBox(
                            width: 60,
                            child: Center(
                              child: Text('$sortOrder', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade700)),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                                  child: IconButton(padding: EdgeInsets.zero, icon: Icon(Icons.edit_outlined, size: 18, color: Colors.grey.shade600), onPressed: () => _editItem(id?.toString())),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                                  child: IconButton(padding: EdgeInsets.zero, icon: Icon(Icons.delete_outlined, size: 18, color: Colors.red.shade400), onPressed: () => _deleteItem(id?.toString())),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow({
    required String label,
    required Stream<QuerySnapshot> stream,
    required String selectedValue,
    required void Function(String) onSelected,
    required String nameField,
    required MaterialColor color,
    String? parentFilterId,
    String? parentRefField,
  }) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: stream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox();
                }
                
                var items = snapshot.data!.docs;
                
                // Use IDs for logic
                // Filter by parent ref ID
                if (parentFilterId != null && parentRefField != null) {
                  items = items.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (data[parentRefField] is DocumentReference) {
                      return (data[parentRefField] as DocumentReference).id == parentFilterId;
                    }
                    return false;
                  }).toList();
                }
                
                return ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: const Text('All'),
                        selected: selectedValue == 'All',
                        selectedColor: color.shade100,
                        backgroundColor: Colors.grey.shade100,
                        labelStyle: GoogleFonts.outfit(fontSize: 12),
                        onSelected: (bool selected) {
                          if (selected) {
                            onSelected('All');
                          }
                        },
                      ),
                    ),
                    for (final doc in items)
                      Builder(
                        builder: (context) {
                          final data = doc.data() as Map<String, dynamic>;
                          final String name = (data[nameField] ?? (data['name'] ?? 'Unknown')).toString();
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(name),
                              selected: selectedValue == doc.id,
                              selectedColor: color.shade100,
                              backgroundColor: Colors.grey.shade100,
                              labelStyle: GoogleFonts.outfit(fontSize: 12),
                              onSelected: (bool selected) {
                                if (selected) {
                                  onSelected(doc.id);
                                }
                              },
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

}

// ─── Section Label ────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade600,
        letterSpacing: 0.4,
      ),
    );
  }
}

// ─── Rich Text Toolbar ────────────────────────────────────────────────────────
class _RichTextToolbar extends StatefulWidget {
  final _TextStyle style;
  final VoidCallback onChanged;
  const _RichTextToolbar({required this.style, required this.onChanged});

  @override
  State<_RichTextToolbar> createState() => _RichTextToolbarState();
}

class _RichTextToolbarState extends State<_RichTextToolbar> {
  static const _colors = [
    Color(0xFF1A1F36), // Charcoal
    Color(0xFF0D47A1), // Deep Blue
    Color(0xFF1B5E20), // Deep Green
    Color(0xFFB71C1C), // Deep Red
    Color(0xFF4A148C), // Deep Purple
    Color(0xFFE65100), // Deep Orange
    Color(0xFF006064), // Teal
    Color(0xFF212121), // Dark grey
    Color(0xFF558B2F), // Olive
    Color(0xFF880E4F), // Pink
  ];

  static const _fontSizes = [10.0, 11.0, 12.0, 13.0, 14.0, 16.0, 18.0, 20.0, 24.0];

  static const _fonts = [
    'Outfit', 'Roboto', 'Inter', 'Lato', 'Montserrat', 'Poppins',
  ];

  bool _showColorPicker = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.style;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              // Bold
              _ToolBtn(
                icon: Icons.format_bold_rounded,
                active: s.bold,
                tooltip: 'Bold',
                onTap: () { setState(() { s.bold = !s.bold; }); widget.onChanged(); },
              ),
              // Italic
              _ToolBtn(
                icon: Icons.format_italic_rounded,
                active: s.italic,
                tooltip: 'Italic',
                onTap: () { setState(() { s.italic = !s.italic; }); widget.onChanged(); },
              ),
              const _Divider(),
              // Font size dropdown
              SizedBox(
                width: 120,
                child: ModernSearchableDropdown(
                  label: 'Size',
                  value: _fontSizes.contains(s.fontSize) ? s.fontSize.toString() : '14.0',
                  items: {for (final fs in _fontSizes) fs.toString(): '${fs.toInt()}px'},
                  color: Colors.grey,
                  icon: Icons.format_size_rounded,
                  onChanged: (v) {
                    if (v != null) { 
                      setState(() { s.fontSize = double.tryParse(v) ?? 14.0; }); 
                      widget.onChanged(); 
                    }
                  },
                ),
              ),
              const _Divider(),
              // Font family dropdown
              SizedBox(
                width: 140,
                child: ModernSearchableDropdown(
                  label: 'Font',
                  value: _fonts.contains(s.fontFamily) ? s.fontFamily : 'Outfit',
                  items: {for (final f in _fonts) f: f},
                  color: Colors.grey,
                  icon: Icons.font_download_rounded,
                  onChanged: (v) {
                    if (v != null) { 
                      setState(() { s.fontFamily = v; }); 
                      widget.onChanged(); 
                    }
                  },
                ),
              ),
              const _Divider(),
              // Color swatch button
              Tooltip(
                message: 'Text Color',
                child: GestureDetector(
                  onTap: () => setState(() => _showColorPicker = !_showColorPicker),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade400, width: 1.5),
                    ),
                    child: const Icon(Icons.colorize_rounded, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Color picker panel
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _showColorPicker
              ? Container(
                  key: const ValueKey('cp'),
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _colors.map((c) {
                      final selected = s.color == c;
                      return GestureDetector(
                        onTap: () {
                          setState(() { s.color = c; _showColorPicker = false; });
                          widget.onChanged();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? Colors.white : Colors.transparent,
                              width: 2,
                            ),
                            boxShadow: selected ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 6, spreadRadius: 1)] : [],
                          ),
                          child: selected ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
                        ),
                      );
                    }).toList(),
                  ),
                )
              : const SizedBox(key: ValueKey('no-cp')),
        ),
      ],
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;
  const _ToolBtn({required this.icon, required this.active, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF1A1F36) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 18, color: active ? Colors.white : Colors.grey.shade700),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.grey.shade300,
    );
  }
}


