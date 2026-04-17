import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:riqma_webapp/widgets/modern_searchable_dropdown.dart';
import 'package:riqma_webapp/widgets/smart_multi_picker_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SubCategory {
  final String id;
  final String name;
  final DocumentReference? mainCategoryRef;
  final String? mainCategoryName;
  final int sortOrder;
  final List<String> targetModels;
  final String? parentCategoryId;

  SubCategory({
    required this.id,
    required this.name,
    this.mainCategoryRef,
    this.mainCategoryName,
    required this.sortOrder,
    required this.targetModels,
    this.parentCategoryId,
  });

  factory SubCategory.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    List<String> parsedModels = [];
    if (data.containsKey('target_models') && data['target_models'] is List) {
      parsedModels = (data['target_models'] as List).map((e) => e.toString()).toList();
    } else if (data.containsKey('model_name') && data['model_name'] != null) {
      parsedModels = [data['model_name'].toString()];
    }

    return SubCategory(
      id: doc.id,
      name: (data['name'] ?? 'Unknown').toString(),
      mainCategoryRef: data['main_categories_ref'] as DocumentReference?,
      mainCategoryName: data['main_category_name']?.toString(),
      sortOrder: (data['sort_order'] as int?) ?? 0,
      targetModels: parsedModels,
      parentCategoryId: data['parent_category_id']?.toString(),
    );
  }
}

class SubCategoriesView extends StatefulWidget {
  const SubCategoriesView({super.key});

  @override
  State<SubCategoriesView> createState() => _SubCategoriesViewState();
}

class _SubCategoriesViewState extends State<SubCategoriesView> {
  
  // Filter State (IDs)
  String _selectedMainCategoryId = 'All';
  String _selectedModelId = 'All';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  
  // NOTE: PlutoGrid columns are defined but not currently used in the main build method (custom list view).
  final List<PlutoColumn> columns = [
    PlutoColumn(title: 'Name', field: 'name', type: PlutoColumnType.text(), width: 200),
    PlutoColumn(title: 'Main Category', field: 'main_category', type: PlutoColumnType.text(), width: 180),
    PlutoColumn(title: 'Turbine Model', field: 'model', type: PlutoColumnType.text(), width: 150),
    PlutoColumn(title: 'Sort Order', field: 'sort_order', type: PlutoColumnType.number(), width: 100),
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
              icon: const Icon(Icons.copy_rounded, color: Colors.green, size: 20),
              onPressed: () async {
                final state = rendererContext.stateManager.gridFocusNode.context?.findAncestorStateOfType<_SubCategoriesViewState>();
                final id = rendererContext.row.cells['id']?.value?.toString();
                if (id == null) return;
                final doc = await FirebaseFirestore.instance.collection('sub_categories').doc(id).get();
                if (doc.exists) {
                   state?._addItem(cloneData: SubCategory.fromSnapshot(doc));
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit_rounded, color: Colors.blueAccent, size: 20),
              onPressed: () {
                final state = rendererContext.stateManager.gridFocusNode.context?.findAncestorStateOfType<_SubCategoriesViewState>();
                state?._editItem(rendererContext.row.cells['id']?.value?.toString());
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 20),
              onPressed: () {
                final state = rendererContext.stateManager.gridFocusNode.context?.findAncestorStateOfType<_SubCategoriesViewState>();
                state?._deleteItem(rendererContext.row.cells['id']?.value?.toString());
              },
            ),
          ],
        );
      },
    ),
    PlutoColumn(title: 'ID', field: 'id', type: PlutoColumnType.text(), hide: true),
  ];



  @override
  void initState() {
    super.initState();
    _loadSavedFilter();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedFilter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedMainCategoryId = prefs.getString('sub_category_filter_id') ?? 'All';
      _selectedModelId = prefs.getString('sub_category_model_filter_id') ?? 'All';
    });
  }

  Future<void> _updateCategoryFilter(String categoryId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sub_category_filter_id', categoryId);
    setState(() {
      _selectedMainCategoryId = categoryId;
    });
  }

  Future<void> _updateModelFilter(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sub_category_model_filter_id', modelId);
    setState(() {
      _selectedModelId = modelId;
      if (modelId != 'All') {
         _selectedMainCategoryId = 'All'; 
         prefs.setString('sub_category_filter_id', 'All');
      }
    });
  }

  void _addItem({SubCategory? cloneData}) async {
    final nameController = TextEditingController(text: cloneData?.name ?? '');
    final sortOrderController = TextEditingController(text: cloneData?.sortOrder.toString() ?? '0');
    
    String? selectedCategoryId = cloneData?.mainCategoryRef?.id;
    DocumentReference? selectedCategoryRef = cloneData?.mainCategoryRef;
    String? selectedCategoryName = cloneData?.mainCategoryName;
    List<String> selectedModelIds = cloneData?.targetModels ?? [];
    
    bool isLoadingOrder = false;

    // Load last selected main category and model from SharedPreferences
    final prefs = await SharedPreferences.getInstance();

    // Function to fetch and set next sort order
    Future<void> fetchNextOrder(DocumentReference? mainCatRef, StateSetter setDialogState) async {
      if (mainCatRef == null) {
          setDialogState(() => isLoadingOrder = false);
          return;
      }
      setDialogState(() => isLoadingOrder = true);
      try {
        // Fetch all sub-categories for this main category (no orderBy to avoid index requirement)
        final querySnapshot = await FirebaseFirestore.instance
            .collection('sub_categories')
            .where('main_categories_ref', isEqualTo: mainCatRef)
            .get();
        
        int maxOrder = -1;
        for (final doc in querySnapshot.docs) {
          final order = doc.data()['sort_order'];
          final orderInt = order is int ? order : int.tryParse(order.toString()) ?? 0;
          if (orderInt > maxOrder) {
            maxOrder = orderInt;
          }
        }
        sortOrderController.text = (maxOrder + 1).toString();
      } catch (e) {
        debugPrint('Error fetching next order: $e');
        sortOrderController.text = '0';
      }
      setDialogState(() => isLoadingOrder = false);
    }

    if (!mounted) return;

    unawaited(showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Add Sub Category', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    // 1. Turbine Model Stream
                    // 1. Main Category Stream
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance.collection('main_categories').snapshots(),
                      builder: (context, categorySnapshot) {
                        if (!categorySnapshot.hasData) return const LinearProgressIndicator();
                        
                        final allCategories = categorySnapshot.data!.docs;
                        final Map<String, String> categoryMap = {
                          for (var doc in allCategories)
                            doc.id: doc.data()['name']?.toString() ?? 'Unknown'
                        };

                        return Column(
                          children: [
                            ModernSearchableDropdown(
                              label: 'Main Category',
                              items: categoryMap,
                              value: selectedCategoryId,
                              color: Colors.indigo,
                              icon: Icons.category_rounded,
                              onChanged: (value) {
                                if (value == null) return;
                                final doc = allCategories.firstWhere((d) => d.id == value);
                                final data = doc.data();
                                setDialogState(() {
                                  selectedCategoryId = value;
                                  selectedCategoryName = data['name']?.toString();
                                  selectedCategoryRef = doc.reference;
                                });
                                fetchNextOrder(doc.reference, setDialogState);
                              },
                            ),
                            const SizedBox(height: 16),
                            // 2. Turbine Models Multi-Select Stream
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance.collection('turbinemodel').snapshots(),
                              builder: (context, modelSnapshot) {
                                if (!modelSnapshot.hasData) return const SizedBox();
                                
                                final modelDocs = modelSnapshot.data!.docs;
                                final Map<String, String> modelMap = {
                                  for (var doc in modelDocs)
                                    doc.id: (doc.data() as Map<String, dynamic>).containsKey('turbine_model') 
                                        ? (doc.data() as Map<String, dynamic>)['turbine_model'].toString() 
                                        : ((doc.data() as Map<String, dynamic>).containsKey('name') 
                                            ? (doc.data() as Map<String, dynamic>)['name'].toString() 
                                            : 'Unknown')
                                };

                                return SmartMultiPickerField(
                                  label: 'Turbine Models (Target)',
                                  items: modelMap,
                                  selectedValues: selectedModelIds,
                                  onChanged: (values) {
                                    setDialogState(() {
                                      selectedModelIds = values;
                                    });
                                  },
                                );
                              }
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: sortOrderController,
                      decoration: InputDecoration(
                        labelText: 'Sort Order',
                        border: const OutlineInputBorder(),
                        suffixIcon: isLoadingOrder
                            ? const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : null,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty || selectedCategoryRef == null || selectedCategoryId == null) {
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
                     return;
                  }
                  try {
                    // Save selections
                    if (selectedModelIds.isNotEmpty) await prefs.setString('last_turbine_model_id', selectedModelIds.first);
                    if (selectedCategoryId != null) await prefs.setString('last_main_cat_id', selectedCategoryId!);

                    await FirebaseFirestore.instance.collection('sub_categories').add({
                      'name': nameController.text.trim(),
                      'main_categories_ref': selectedCategoryRef,
                      'main_category_name': selectedCategoryName,
                      'target_models': selectedModelIds,
                      'is_all_models': false,
                      'sort_order': int.tryParse(sortOrderController.text) ?? 0,
                      'created_at': FieldValue.serverTimestamp(),
                    });
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sub Category added')));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      )));
  }

  void _editItem(String? docId) async {
    if (docId == null) {
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('sub_categories').doc(docId).get();
      if (!doc.exists || !mounted) {
        return;
      }

      final data = doc.data()!;
      final nameController = TextEditingController(text: (data['name'] ?? '').toString());
      final sortOrderController = TextEditingController(text: (data['sort_order'] ?? 0).toString());
      
      String? selectedCategoryId;
      DocumentReference? selectedCategoryRef = data['main_categories_ref'] as DocumentReference?;
      String? selectedCategoryName = data['main_category_name']?.toString();
      
      List<String> selectedModelIds = [];
      if (data.containsKey('target_models') && data['target_models'] is List) {
        selectedModelIds = (data['target_models'] as List).map((e) => e.toString()).toList();
      } else if (data.containsKey('model_name') && data['model_name'] != null) {
        selectedModelIds = [data['model_name'].toString()];
      }

      if (selectedCategoryRef != null) {
        selectedCategoryId = selectedCategoryRef.id;
      }

      if (!mounted) {
        return;
      }

      unawaited(showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Edit Sub Category', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
            content: SizedBox(
               width: 400,
               child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    // 1. Main Category Stream
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance.collection('main_categories').snapshots(),
                      builder: (context, categorySnapshot) {
                        if (!categorySnapshot.hasData) return const LinearProgressIndicator();
                        
                        final allCategories = categorySnapshot.data!.docs;
                        final Map<String, String> categoryMap = {
                          for (var doc in allCategories)
                            doc.id: doc.data()['name']?.toString() ?? 'Unknown'
                        };

                        return Column(
                          children: [
                            ModernSearchableDropdown(
                              label: 'Main Category',
                              items: categoryMap,
                              value: selectedCategoryId,
                              color: Colors.indigo,
                              icon: Icons.category_rounded,
                              onChanged: (value) {
                                if (value == null) return;
                                final doc = allCategories.firstWhere((d) => d.id == value);
                                final data = doc.data();
                                setDialogState(() {
                                  selectedCategoryId = value;
                                  selectedCategoryName = data['name']?.toString();
                                  selectedCategoryRef = doc.reference;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            // 2. Turbine Models Multi-Select Stream
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance.collection('turbinemodel').snapshots(),
                              builder: (context, modelSnapshot) {
                                if (!modelSnapshot.hasData) return const SizedBox();
                                
                                final modelDocs = modelSnapshot.data!.docs;
                                final Map<String, String> modelMap = {
                                  for (var doc in modelDocs)
                                    doc.id: (doc.data() as Map<String, dynamic>).containsKey('turbine_model') 
                                        ? (doc.data() as Map<String, dynamic>)['turbine_model'].toString() 
                                        : ((doc.data() as Map<String, dynamic>).containsKey('name') 
                                            ? (doc.data() as Map<String, dynamic>)['name'].toString() 
                                            : 'Unknown')
                                };

                                return SmartMultiPickerField(
                                  label: 'Turbine Models (Target)',
                                  items: modelMap,
                                  selectedValues: selectedModelIds,
                                  onChanged: (values) {
                                    setDialogState(() {
                                      selectedModelIds = values;
                                    });
                                  },
                                );
                              }
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: sortOrderController,
                      decoration: const InputDecoration(labelText: 'Sort Order', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty || selectedCategoryRef == null) {
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
                     return;
                  }
                  try {
                    await FirebaseFirestore.instance.collection('sub_categories').doc(docId).update({
                      'name': nameController.text.trim(),
                      'main_categories_ref': selectedCategoryRef,
                      'main_category_name': selectedCategoryName,
                      'parent_category_id': selectedCategoryRef?.id,
                      'target_models': selectedModelIds,
                      'sort_order': int.tryParse(sortOrderController.text) ?? 0,
                    });
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sub Category updated')));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                child: const Text('Update'),
              ),
            ],
          ),
        )));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _deleteItem(String? docId) {
    if (docId == null) {
      return;
    }
    unawaited(showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Sub Category', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        content: const Text('Are you sure? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await FirebaseFirestore.instance.collection('sub_categories').doc(docId).delete();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sub Category deleted')));
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
      )));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('turbinemodel').snapshots(),
      builder: (context, modelSnapshot) {
        if (!modelSnapshot.hasData) return const Center(child: CircularProgressIndicator());

        final modelMap = {
          for (var doc in modelSnapshot.data!.docs)
            doc.id: (doc.data().containsKey('turbine_model') 
                ? doc.data()['turbine_model'] 
                : (doc.data().containsKey('name') ? doc.data()['name'] : 'Unknown')).toString()
        };

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('main_categories').snapshots(),
          builder: (context, mainCatSnapshot) {
        if (!mainCatSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final mainCatMap = {
          for (var doc in mainCatSnapshot.data!.docs)
            doc.id: doc.data()
        };

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('sub_categories').orderBy('sort_order').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final allDocs = snapshot.data!.docs;
            List<SubCategory> subCategories = allDocs.map((d) => SubCategory.fromSnapshot(d)).toList();
            
            // Apply Filtering Logic
            final filteredSubCategories = subCategories.where((subCat) {
               String? mainCatId;
               Map<String, dynamic>? mainCatData;
               if (subCat.mainCategoryRef != null) {
                  mainCatId = subCat.mainCategoryRef!.id;
                  mainCatData = mainCatMap[mainCatId];
               }
               
               String? modelId;
               if (mainCatData != null && mainCatData['turbinemodel_ref'] is DocumentReference) {
                  modelId = (mainCatData['turbinemodel_ref'] as DocumentReference).id;
               }
               
               if (_selectedModelId != 'All') {
                  if (!subCat.targetModels.contains(_selectedModelId)) {
                    if (modelId != _selectedModelId) return false;
                  }
               }
               
               if (_selectedMainCategoryId != 'All') {
                  if (mainCatId != _selectedMainCategoryId) return false;
               }
               
               if (_searchQuery.isNotEmpty) {
                  final q = _searchQuery.toLowerCase();
                  if (!subCat.name.toLowerCase().contains(q) && 
                      !(subCat.mainCategoryName?.toLowerCase().contains(q) ?? false)) {
                    return false;
                  }
               }
               
               return true;
            }).toList();

            final filteredCount = filteredSubCategories.length;

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 4))],
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
                    Icon(Icons.list_alt_rounded, color: Colors.grey.shade600, size: 20),
                    const SizedBox(width: 8),
                    if (!_isSearching) ...[
                      Text('Sub Categories ($filteredCount)', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => setState(() => _isSearching = true),
                        icon: Icon(Icons.search_rounded, color: Colors.grey.shade600, size: 20),
                        tooltip: 'Search sub categories',
                        splashRadius: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ] else ...[
                      SizedBox(
                        width: 250,
                        height: 36,
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          style: GoogleFonts.outfit(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Search sub categories...',
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
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Sub Category'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1F36),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          
          // Filters Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                // Model Filter
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final Map<String, String> items = {
                        'All': 'All Models',
                        ...modelMap
                      };

                      return ModernSearchableDropdown(
                        label: 'Filter by Model',
                        value: items.containsKey(_selectedModelId) ? _selectedModelId : 'All',
                        items: items,
                        color: Colors.purple,
                        icon: Icons.precision_manufacturing_rounded,
                        onChanged: (val) {
                          if (val != null) _updateModelFilter(val);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // Main Category Filter
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance.collection('main_categories').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox();
                      var categories = snapshot.data!.docs;
                      
                      if (_selectedModelId != 'All') {
                         categories = categories.where((doc) {
                            final data = doc.data();
                             if (data['turbinemodel_ref'] is DocumentReference) {
                               return (data['turbinemodel_ref'] as DocumentReference).id == _selectedModelId;
                             }
                             return false; 
                         }).toList();
                      }

                      final Map<String, String> items = {
                        'All': 'All Categories',
                        for (var doc in categories)
                          doc.id: (doc.data()['name'] ?? 'Unknown').toString()
                      };

                      return ModernSearchableDropdown(
                        label: 'Filter by Category',
                        value: items.containsKey(_selectedMainCategoryId) ? _selectedMainCategoryId : 'All',
                        items: items,
                        color: Colors.indigo,
                        icon: Icons.category_rounded,
                        onChanged: (val) {
                          if (val != null) _updateCategoryFilter(val);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          
          // Column Headers
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 1))),
            child: Row(
              children: <Widget>[
                Expanded(flex: 2, child: Text('NAME', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                Expanded(flex: 2, child: Text('MAIN CATEGORY', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                Expanded(flex: 2, child: Text('MODEL', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))), 
                SizedBox(width: 80, child: Text('ORDER', textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                SizedBox(width: 100, child: Text('ACTIONS', textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
              ],
            ),
          ),

          Expanded(
            child: filteredSubCategories.isEmpty
                ? Center(child: Text('No sub categories found', style: GoogleFonts.outfit(color: Colors.grey.shade500)))
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: filteredSubCategories.length,
                    separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, index) {
                      final subCat = filteredSubCategories[index];
                      // Use _mainCatMap to resolve site names for display
                      String modelNamesDisplay = 'All Models';
                      if (subCat.targetModels.isNotEmpty) {
                         modelNamesDisplay = subCat.targetModels.map((id) => modelMap[id] ?? id).join(', ');
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Row(
                          children: [
                            Expanded(flex: 2, child: Text(subCat.name, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF1A1F36)))),
                            Expanded(flex: 2, child: Text(subCat.mainCategoryName ?? 'Unknown', style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade600))),
                            Expanded(flex: 2, child: Text(modelNamesDisplay, style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                            SizedBox(width: 80, child: Text(subCat.sortOrder.toString(), textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade600))),
                            SizedBox(
                              width: 100,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.green), onPressed: () => _addItem(cloneData: subCat)),
                                  IconButton(icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.blueAccent), onPressed: () => _editItem(subCat.id)),
                                  IconButton(icon: const Icon(Icons.delete_rounded, size: 18, color: Colors.redAccent), onPressed: () => _deleteItem(subCat.id)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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
);
}
}
