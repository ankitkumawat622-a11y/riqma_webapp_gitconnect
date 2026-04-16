import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:riqma_webapp/widgets/smart_multi_picker_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Data Model
// ---------------------------------------------------------------------------

class MainCategory {
  final String id;
  final String name;
  final int sortOrder;
  final int totalQuestions;
  final List<String> targetModels; // List of turbinemodel document IDs
  final bool isAllModels;
  final String? modelName; // Legacy fallback string
  final DocumentReference? turbinemodelRef; // Legacy fallback ref

  MainCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.totalQuestions,
    required this.targetModels,
    required this.isAllModels,
    this.modelName,
    this.turbinemodelRef,
  });

  factory MainCategory.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    List<String> models = [];
    try {
      if (data['target_models'] is List) {
        models = List<String>.from(
            (data['target_models'] as List).map((e) => e.toString()));
      } else if (data['model_name'] != null &&
          (data['model_name'] as String).isNotEmpty) {
        // Legacy: single model_name — best-effort: we don't have the ID here
        // so we leave targetModels empty and rely on model_name for display.
      }
    } catch (_) {}

    bool allModels = false;
    try {
      allModels = data['is_all_models'] == true;
    } catch (_) {}

    return MainCategory(
      id: doc.id,
      name: (data['name'] ?? 'Unknown').toString(),
      sortOrder: (data['sort_order'] as int?) ?? 0,
      totalQuestions: (data['total_questions'] as int?) ?? 0,
      targetModels: models,
      isAllModels: allModels,
      modelName: data['model_name']?.toString(),
      turbinemodelRef: data['turbinemodel_ref'] as DocumentReference?,
    );
  }

  /// Returns a human-readable model label for display in the list.
  String modelDisplayLabel(Map<String, String> idToName) {
    if (isAllModels) return 'All Models';
    if (targetModels.isNotEmpty) {
      final names =
          targetModels.map((id) => idToName[id] ?? id).join(', ');
      return names;
    }
    // Legacy fallback
    return modelName ?? 'N/A';
  }
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class MainCategoriesView extends StatefulWidget {
  const MainCategoriesView({super.key});

  @override
  State<MainCategoriesView> createState() => _MainCategoriesViewState();
}

class _MainCategoriesViewState extends State<MainCategoriesView> {
  // Filter state: stores the turbinemodel document ID, or 'All'
  String _selectedModelId = 'All';

  // PlutoGrid column definitions (kept for potential future use)
  final List<PlutoColumn> columns = [
    PlutoColumn(
        title: 'Name',
        field: 'name',
        type: PlutoColumnType.text(),
        width: 200),
    PlutoColumn(
        title: 'Turbine Model',
        field: 'model',
        type: PlutoColumnType.text(),
        width: 200),
    PlutoColumn(
        title: 'Sort Order',
        field: 'sort_order',
        type: PlutoColumnType.number(),
        width: 100),
    PlutoColumn(
        title: 'Total Questions',
        field: 'total_questions',
        type: PlutoColumnType.number(),
        width: 120),
    PlutoColumn(
      title: 'Actions',
      field: 'actions',
      type: PlutoColumnType.text(),
      width: 150,
      enableSorting: false,
      enableFilterMenuItem: false,
      renderer: (rendererContext) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_rounded,
                  color: Colors.blueAccent, size: 20),
              onPressed: () {
                final state = rendererContext
                    .stateManager.gridFocusNode.context
                    ?.findAncestorStateOfType<_MainCategoriesViewState>();
                state?._editItem(
                    rendererContext.row.cells['id']?.value?.toString());
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded,
                  color: Colors.redAccent, size: 20),
              onPressed: () {
                final state = rendererContext
                    .stateManager.gridFocusNode.context
                    ?.findAncestorStateOfType<_MainCategoriesViewState>();
                state?._deleteItem(
                    rendererContext.row.cells['id']?.value?.toString());
              },
            ),
          ],
        );
      },
    ),
    PlutoColumn(
        title: 'ID',
        field: 'id',
        type: PlutoColumnType.text(),
        hide: true),
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedFilter();
  }

  Future<void> _loadSavedFilter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedModelId =
          prefs.getString('main_categories_model_filter_id') ?? 'All';
    });
  }

  Future<void> _updateFilter(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('main_categories_model_filter_id', modelId);
    setState(() {
      _selectedModelId = modelId;
    });
  }

  // ---------------------------------------------------------------------------
  // Add Dialog
  // ---------------------------------------------------------------------------

  void _addItem() async {
    final nameController = TextEditingController();
    final sortOrderController = TextEditingController(text: '0');
    final totalQuestionsController = TextEditingController(text: '0');
    List<String> selectedModelIds = [];
    bool isAllModels = false;

    final prefs = await SharedPreferences.getInstance();
    final lastModelId = prefs.getString('last_main_cat_model_id');

    if (!mounted) return;

    unawaited(showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Add Main Category',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),

                    // ── Model Selector ───────────────────────────────────
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('turbinemodel')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const LinearProgressIndicator();
                        }
                        final modelDocs = snapshot.data!.docs;
                        final Map<String, String> modelMap = {
                          for (var doc in modelDocs)
                            doc.id: _modelName(
                                doc.data() as Map<String, dynamic>),
                        };

                        // Pre-select last used model on first open
                        if (selectedModelIds.isEmpty &&
                            !isAllModels &&
                            lastModelId != null &&
                            modelMap.containsKey(lastModelId)) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            setDialogState(
                                () => selectedModelIds = [lastModelId]);
                          });
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // "All Models" toggle
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('Apply to All Models',
                                  style: GoogleFonts.outfit(fontSize: 14)),
                              value: isAllModels,
                              activeThumbColor: const Color(0xFF1A1F36),
                              onChanged: (val) => setDialogState(() {
                                isAllModels = val;
                                if (val) { selectedModelIds = []; }
                              }),
                            ),
                            const SizedBox(height: 8),
                            SmartMultiPickerField(
                              label: 'Turbine Models (Target)',
                              items: modelMap,
                              selectedValues: selectedModelIds,
                              enabled: !isAllModels,
                              onChanged: (values) {
                                setDialogState(
                                    () => selectedModelIds = values);
                              },
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 16),
                    TextField(
                      controller: sortOrderController,
                      decoration: const InputDecoration(
                        labelText: 'Sort Order',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: totalQuestionsController,
                      decoration: const InputDecoration(
                          labelText: 'Total Questions',
                          border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Please enter a name')));
                    return;
                  }
                  if (!isAllModels && selectedModelIds.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Please select at least one model or enable "All Models"')));
                    return;
                  }
                  try {
                    if (selectedModelIds.isNotEmpty) {
                      await prefs.setString(
                          'last_main_cat_model_id', selectedModelIds.first);
                    }

                    // Build legacy model_name fallback from first selected
                    // We need the model name string — fetch from Firestore snapshot
                    // (held in StreamBuilder scope). We resolve via a quick get().
                    String legacyModelName =
                        isAllModels ? 'All Models' : '';
                    DocumentReference? legacyRef;

                    if (!isAllModels && selectedModelIds.isNotEmpty) {
                      try {
                        final modelDoc = await FirebaseFirestore.instance
                            .collection('turbinemodel')
                            .doc(selectedModelIds.first)
                            .get();
                        if (modelDoc.exists) {
                          final md =
                              modelDoc.data() as Map<String, dynamic>;
                          legacyModelName = _modelName(md);
                          legacyRef = modelDoc.reference;
                        }
                      } catch (_) {}
                    }

                    await FirebaseFirestore.instance
                        .collection('main_categories')
                        .add({
                      'name': nameController.text.trim(),
                      'target_models': isAllModels ? <String>[] : selectedModelIds,
                      'is_all_models': isAllModels,
                      // Backward-compat legacy fields:
                      'model_name': legacyModelName,
                      'turbinemodel_ref': legacyRef,
                      'sort_order':
                          int.tryParse(sortOrderController.text) ?? 0,
                      'total_questions':
                          int.tryParse(totalQuestionsController.text) ?? 0,
                      'created_at': FieldValue.serverTimestamp(),
                    });

                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Category added')));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    ));
  }

  // ---------------------------------------------------------------------------
  // Edit Dialog
  // ---------------------------------------------------------------------------

  void _editItem(String? docId) async {
    if (docId == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('main_categories')
          .doc(docId)
          .get();
      if (!doc.exists || !mounted) return;

      final cat = MainCategory.fromSnapshot(doc);

      final nameController = TextEditingController(text: cat.name);
      final sortOrderController =
          TextEditingController(text: cat.sortOrder.toString());
      final totalQuestionsController =
          TextEditingController(text: cat.totalQuestions.toString());
      List<String> selectedModelIds = List.from(cat.targetModels);
      bool isAllModels = cat.isAllModels;

      if (!mounted) return;

      unawaited(showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Edit Main Category',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),

                    // ── Model Selector ─────────────────────────────────
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('turbinemodel')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const LinearProgressIndicator();
                        }
                        final modelDocs = snapshot.data!.docs;
                        final Map<String, String> modelMap = {
                          for (var d in modelDocs)
                            d.id: _modelName(
                                d.data() as Map<String, dynamic>),
                        };

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('Apply to All Models',
                                  style: GoogleFonts.outfit(fontSize: 14)),
                              value: isAllModels,
                              activeThumbColor: const Color(0xFF1A1F36),
                              onChanged: (val) => setDialogState(() {
                                isAllModels = val;
                                if (val) { selectedModelIds = []; }
                              }),
                            ),
                            const SizedBox(height: 8),
                            SmartMultiPickerField(
                              label: 'Turbine Models (Target)',
                              items: modelMap,
                              selectedValues: selectedModelIds,
                              enabled: !isAllModels,
                              onChanged: (values) {
                                setDialogState(
                                    () => selectedModelIds = values);
                              },
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 16),
                    TextField(
                      controller: sortOrderController,
                      decoration: const InputDecoration(
                          labelText: 'Sort Order',
                          border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: totalQuestionsController,
                      decoration: const InputDecoration(
                          labelText: 'Total Questions',
                          border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) return;
                  if (!isAllModels && selectedModelIds.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Please select at least one model or enable "All Models"')));
                    return;
                  }
                  try {
                    String legacyModelName =
                        isAllModels ? 'All Models' : '';
                    DocumentReference? legacyRef;

                    if (!isAllModels && selectedModelIds.isNotEmpty) {
                      try {
                        final modelDoc = await FirebaseFirestore.instance
                            .collection('turbinemodel')
                            .doc(selectedModelIds.first)
                            .get();
                        if (modelDoc.exists) {
                          final md =
                              modelDoc.data() as Map<String, dynamic>;
                          legacyModelName = _modelName(md);
                          legacyRef = modelDoc.reference;
                        }
                      } catch (_) {}
                    }

                    await FirebaseFirestore.instance
                        .collection('main_categories')
                        .doc(docId)
                        .update({
                      'name': nameController.text.trim(),
                      'target_models': isAllModels ? [] : selectedModelIds,
                      'is_all_models': isAllModels,
                      'model_name': legacyModelName,
                      'turbinemodel_ref': legacyRef,
                      'sort_order':
                          int.tryParse(sortOrderController.text) ?? 0,
                      'total_questions':
                          int.tryParse(totalQuestionsController.text) ?? 0,
                    });
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Category updated')));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                child: const Text('Update'),
              ),
            ],
          ),
        ),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Delete Dialog
  // ---------------------------------------------------------------------------

  void _deleteItem(String? docId) {
    if (docId == null) return;
    unawaited(showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Main Category',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        content: const Text('Are you sure? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .collection('main_categories')
                    .doc(docId)
                    .delete();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Category deleted')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    ));
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _modelName(Map<String, dynamic> data) {
    if (data.containsKey('turbine_model') && data['turbine_model'] != null) {
      return data['turbine_model'].toString();
    }
    if (data.containsKey('name') && data['name'] != null) {
      return data['name'].toString();
    }
    return 'Unknown';
  }

  /// Matches a [MainCategory] against the active filter (by turbinemodel doc ID).
  bool _matchesFilter(MainCategory cat) {
    if (_selectedModelId == 'All') return true;
    // New schema: is_all_models or target_models contains
    if (cat.isAllModels) return true;
    if (cat.targetModels.contains(_selectedModelId)) return true;
    // Legacy fallback: turbinemodel_ref ID match
    if (cat.turbinemodelRef != null &&
        cat.turbinemodelRef!.id == _selectedModelId) {
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
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
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.list_alt_rounded,
                        color: Colors.grey.shade600, size: 20),
                    const SizedBox(width: 8),
                    Text('Main Categories',
                        style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Category'),
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
          ),

          // ── Filter Chip Bar ──────────────────────────────────────────
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('turbinemodel')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();
                final models = snapshot.data!.docs;
                return ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('All Models'),
                        selected: _selectedModelId == 'All',
                        selectedColor: Colors.indigo.shade100,
                        backgroundColor: Colors.grey.shade100,
                        onSelected: (selected) {
                          if (selected) _updateFilter('All');
                        },
                      ),
                    ),
                    for (final doc in models)
                      Builder(builder: (context) {
                        final data = doc.data() as Map<String, dynamic>;
                        final name = _modelName(data);
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(name),
                            selected: _selectedModelId == doc.id,
                            selectedColor: Colors.indigo.shade100,
                            backgroundColor: Colors.grey.shade100,
                            onSelected: (selected) {
                              if (selected) _updateFilter(doc.id);
                            },
                          ),
                        );
                      }),
                  ],
                );
              },
            ),
          ),

          // ── Column Headers ───────────────────────────────────────────
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: Colors.grey.shade200, width: 1))),
            child: Row(
              children: [
                Expanded(
                    flex: 2,
                    child: Text('NAME',
                        style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.5))),
                Expanded(
                    flex: 3,
                    child: Text('MODEL(S)',
                        style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.5))),
                SizedBox(
                    width: 80,
                    child: Text('ORDER',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.5))),
                SizedBox(
                    width: 100,
                    child: Text('ACTIONS',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.5))),
              ],
            ),
          ),

          // ── List ────────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // Outer stream: model lookup map
              stream: FirebaseFirestore.instance
                  .collection('turbinemodel')
                  .snapshots(),
              builder: (context, modelSnapshot) {
                // Build id → name lookup
                final Map<String, String> idToName = {};
                if (modelSnapshot.hasData) {
                  for (final doc in modelSnapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    idToName[doc.id] = _modelName(data);
                  }
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('main_categories')
                      .orderBy('sort_order')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                          child: Text('Error: ${snapshot.error}'));
                    }

                    final allDocs = snapshot.data?.docs ?? [];
                    final categories = allDocs
                        .map((d) => MainCategory.fromSnapshot(d))
                        .where(_matchesFilter)
                        .toList();

                    if (categories.isEmpty) {
                      return const Center(
                          child: Text(
                              'No categories found for this model.'));
                    }

                    return ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: categories.length,
                      separatorBuilder: (context, index) =>
                          Divider(height: 1, color: Colors.grey.shade200),
                      itemBuilder: (context, index) {
                        final cat = categories[index];
                        final label = cat.modelDisplayLabel(idToName);
                        final initial = cat.name.isNotEmpty
                            ? cat.name[0].toUpperCase()
                            : '?';

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                    color: const Color(0xFF1A1F36)
                                        .withValues(alpha: 0.1),
                                    shape: BoxShape.circle),
                                child: Center(
                                    child: Text(initial,
                                        style: GoogleFonts.outfit(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                const Color(0xFF1A1F36)))),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                  flex: 2,
                                  child: Text(cat.name,
                                      style: GoogleFonts.outfit(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color:
                                              const Color(0xFF1A1F36)))),
                              // ── Model Display ──
                              Expanded(
                                flex: 3,
                                child: _buildModelChip(cat, label),
                              ),
                              SizedBox(
                                width: 80,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius:
                                            BorderRadius.circular(4)),
                                    child: Text('${cat.sortOrder}',
                                        style: GoogleFonts.outfit(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade700)),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 100,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          shape: BoxShape.circle),
                                      child: IconButton(
                                          padding: EdgeInsets.zero,
                                          icon: Icon(Icons.edit_outlined,
                                              size: 18,
                                              color: Colors.grey.shade600),
                                          onPressed: () =>
                                              _editItem(cat.id)),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          shape: BoxShape.circle),
                                      child: IconButton(
                                          padding: EdgeInsets.zero,
                                          icon: Icon(Icons.delete_outlined,
                                              size: 18,
                                              color: Colors.red.shade400),
                                          onPressed: () =>
                                              _deleteItem(cat.id)),
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Renders the model cell: a teal "All Models" chip, a set of model chips,
  /// or a plain text fallback for legacy documents.
  Widget _buildModelChip(MainCategory cat, String label) {
    if (cat.isAllModels) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.teal.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.teal.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.all_inclusive_rounded,
                size: 14, color: Colors.teal.shade700),
            const SizedBox(width: 4),
            Text('All Models',
                style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.teal.shade700)),
          ],
        ),
      );
    }

    if (cat.targetModels.isNotEmpty) {
      return Text(
        label,
        style: GoogleFonts.outfit(
            fontSize: 13,
            color: Colors.indigo.shade600,
            fontWeight: FontWeight.w500),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      );
    }

    // Legacy fallback
    return Text(label,
        style:
            GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade600),
        overflow: TextOverflow.ellipsis);
  }
}
