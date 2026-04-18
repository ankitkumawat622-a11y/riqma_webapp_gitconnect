import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:riqma_webapp/screens/manage/bulk_turbine_entry_screen.dart';
import 'package:riqma_webapp/widgets/modern_searchable_dropdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TurbinesView extends StatefulWidget {
  const TurbinesView({super.key});

  @override
  State<TurbinesView> createState() => _TurbinesViewState();
}

class _TurbinesViewState extends State<TurbinesView> {
  // Filter & Search State
  String _selectedSite = 'All';
  String _selectedState = 'All';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Map<String, String> _siteToStateMap = {};
  bool _filterNewOnly = false;
  
  // Data State
  StreamSubscription<QuerySnapshot>? _dataSubscription;
  List<PlutoRow> rows = [];
  bool isLoading = true;

  final List<PlutoColumn> columns = [
    PlutoColumn(title: 'Turbine Name', field: 'name', type: PlutoColumnType.text(), width: 180),
    PlutoColumn(title: 'Site', field: 'site', type: PlutoColumnType.text(), width: 150),
    PlutoColumn(title: 'Model', field: 'model', type: PlutoColumnType.text(), width: 150),
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
              icon: const Icon(Icons.edit_rounded, color: Colors.blueAccent, size: 20),
              onPressed: () {
                final state = rendererContext.stateManager.gridFocusNode.context?.findAncestorStateOfType<_TurbinesViewState>();
                state?._editItem(rendererContext.row.cells['id']?.value?.toString());
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 20),
              onPressed: () {
                final state = rendererContext.stateManager.gridFocusNode.context?.findAncestorStateOfType<_TurbinesViewState>();
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
    _fetchSiteStateMapping();
    _setupDataStream();
  }

  Future<void> _fetchSiteStateMapping() async {
    final sitesSnapshot = await FirebaseFirestore.instance.collection('sites').get();
    final Map<String, String> mapping = {};
    for (final doc in sitesSnapshot.docs) {
      final data = doc.data();
      final siteName = (data['site_name'] ?? data['name'] ?? '').toString();
      final stateName = (data['state_name'] ?? 'Unknown').toString();
      if (siteName.isNotEmpty) {
        mapping[siteName] = stateName;
      }
    }
    if (mounted) setState(() => _siteToStateMap = mapping);
  }

  Future<void> _loadSavedFilter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedSite = prefs.getString('turbines_site_filter') ?? 'All';
    });
  }

  Future<void> _updateFilter(String site) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('turbines_site_filter', site);
    setState(() {
      _selectedSite = site;
    });
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _setupDataStream() {
    _dataSubscription = FirebaseFirestore.instance
        .collection('turbinename')
        .snapshots()
        .listen((snapshot) {
      final newRows = snapshot.docs.map((doc) {
        final data = doc.data();
        return PlutoRow(
          cells: {
            'name': PlutoCell(value: (data.containsKey('turbine_name') ? data['turbine_name'] : (data.containsKey('name') ? data['name'] : 'Unknown')).toString()),
            'site': PlutoCell(value: (data.containsKey('site_name') ? data['site_name'] : 'N/A').toString()),
            'model': PlutoCell(value: (data.containsKey('model_name') ? data['model_name'] : 'N/A').toString()),
            'wtg_category': PlutoCell(value: (data['wtg_category'] == 'old' ? 'existing' : (data['wtg_category'] ?? 'existing')).toString()),
            'actions': PlutoCell(value: ''),
            'id': PlutoCell(value: doc.id),
          },
        );
      }).toList();

      if (mounted) setState(() {rows = newRows; isLoading = false;});
    }, onError: (Object error) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $error')));
      }
    });
  }

  void _addItem() {
    final nameController = TextEditingController();
    String? selectedSiteId, selectedModelId;
    DocumentReference? selectedSiteRef, selectedModelRef;
    String? selectedSiteName, selectedModelName;

    unawaited(showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add Turbine', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Turbine Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('sites').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }
                  final sites = snapshot.data!.docs;
                  final Map<String, String> siteMap = {
                    for (final doc in sites)
                      doc.id: (doc.data() as Map<String, dynamic>).containsKey('site_name') 
                          ? (doc.data() as Map<String, dynamic>)['site_name'].toString() 
                          : ((doc.data() as Map<String, dynamic>).containsKey('name') 
                              ? (doc.data() as Map<String, dynamic>)['name'].toString() 
                              : 'Unknown')
                  };

                  return ModernSearchableDropdown(
                    label: 'Site',
                    items: siteMap,
                    value: selectedSiteId,
                    color: Colors.teal,
                    icon: Icons.location_on_rounded,
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selectedSiteId = value;
                        final doc = sites.firstWhere((d) => d.id == value);
                        final data = doc.data() as Map<String, dynamic>;
                        selectedSiteName = (data.containsKey('site_name') ? data['site_name'] : (data.containsKey('name') ? data['name'] : 'Unknown')).toString();
                        selectedSiteRef = doc.reference;
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('turbinemodel').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }
                  final models = snapshot.data!.docs;
                    final Map<String, String> modelMap = {
                      for (final doc in models)
                        doc.id: (doc.data() as Map<String, dynamic>).containsKey('turbine_model') 
                            ? (doc.data() as Map<String, dynamic>)['turbine_model'].toString() 
                            : ((doc.data() as Map<String, dynamic>).containsKey('name') 
                                ? (doc.data() as Map<String, dynamic>)['name'].toString() 
                                : 'Unknown')
                    };

                    return ModernSearchableDropdown(
                      label: 'Model',
                      items: modelMap,
                      value: selectedModelId,
                      color: Colors.indigo,
                      icon: Icons.precision_manufacturing_rounded,
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          selectedModelId = value;
                          final doc = models.firstWhere((d) => d.id == value);
                          final data = doc.data() as Map<String, dynamic>;
                          selectedModelName = (data.containsKey('turbine_model') ? data['turbine_model'] : (data.containsKey('name') ? data['name'] : 'Unknown')).toString();
                          selectedModelRef = doc.reference;
                        });
                      },
                    );
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty || selectedSiteRef == null || selectedModelRef == null) {
                  return;
                }
                try {
                  await FirebaseFirestore.instance.collection('turbinename').add({
                    'turbine_name': nameController.text.trim(),
                    'name': nameController.text.trim(),
                    'site_ref': selectedSiteRef,
                    'site_name': selectedSiteName,
                    'turbinemodel_ref': selectedModelRef,
                    'model_name': selectedModelName,
                    'created_at': FieldValue.serverTimestamp(),
                  });
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turbine added')));
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
        ),
      ),
    ));
  }

  Future<void> _editItem(String? docId) async {
    if (docId == null) {
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('turbinename').doc(docId).get();
      if (!doc.exists || !mounted) {
        return;
      }

      final data = doc.data()!;
      final nameController = TextEditingController(text: (data['turbine_name'] ?? (data['name'] ?? '')).toString());
      String? selectedSiteId, selectedModelId;
      DocumentReference? selectedSiteRef = data['site_ref'] as DocumentReference?, selectedModelRef = data['turbinemodel_ref'] as DocumentReference?;
      String? selectedSiteName = data['site_name']?.toString(), selectedModelName = data['model_name']?.toString();

      if (selectedSiteRef != null) {
        try {
          final siteDoc = await selectedSiteRef.get();
          if (siteDoc.exists) {
            selectedSiteId = siteDoc.id;
            final siteData = siteDoc.data() as Map<String, dynamic>?;
            if (siteData != null) {
              selectedSiteName = (siteData['site_name'] ?? (siteData['name'] ?? 'Unknown')).toString();
            }
          }
        } catch (e) {
          // ignore: empty_catches
        }
      }

      if (selectedModelRef != null) {
        try {
          final modelDoc = await selectedModelRef.get();
          if (modelDoc.exists) {
            selectedModelId = modelDoc.id;
            final modelData = modelDoc.data() as Map<String, dynamic>?;
            if (modelData != null) {
              selectedModelName = (modelData['turbine_model'] ?? (modelData['name'] ?? 'Unknown')).toString();
            }
          }
        } catch (e) {
          // ignore: empty_catches
        }
      }

      if (!mounted) {
        return;
      }

      unawaited(showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Edit Turbine', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Turbine Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('sites').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }
                    final sites = snapshot.data!.docs;
                    final Map<String, String> siteMap = {
                      for (final doc in sites)
                        doc.id: (doc.data() as Map<String, dynamic>).containsKey('site_name') 
                            ? (doc.data() as Map<String, dynamic>)['site_name'].toString() 
                            : ((doc.data() as Map<String, dynamic>).containsKey('name') 
                                ? (doc.data() as Map<String, dynamic>)['name'].toString() 
                                : 'Unknown')
                    };

                    return ModernSearchableDropdown(
                      label: 'Site',
                      items: siteMap,
                      value: selectedSiteId,
                      color: Colors.teal,
                      icon: Icons.location_on_rounded,
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          selectedSiteId = value;
                          final doc = sites.firstWhere((d) => d.id == value);
                          final data = doc.data() as Map<String, dynamic>;
                          selectedSiteName = (data['site_name'] ?? (data['name'] ?? 'Unknown')).toString();
                          selectedSiteRef = doc.reference;
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('turbinemodel').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }
                    final models = snapshot.data!.docs;
                    final Map<String, String> modelMap = {
                      for (final doc in models)
                        doc.id: (doc.data() as Map<String, dynamic>).containsKey('turbine_model') 
                            ? (doc.data() as Map<String, dynamic>)['turbine_model'].toString() 
                            : ((doc.data() as Map<String, dynamic>).containsKey('name') 
                                ? (doc.data() as Map<String, dynamic>)['name'].toString() 
                                : 'Unknown')
                    };

                    return ModernSearchableDropdown(
                      label: 'Model',
                      items: modelMap,
                      value: selectedModelId,
                      color: Colors.indigo,
                      icon: Icons.precision_manufacturing_rounded,
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          selectedModelId = value;
                          final doc = models.firstWhere((d) => d.id == value);
                          final data = doc.data() as Map<String, dynamic>;
                          selectedModelName = (data['turbine_model'] ?? (data['name'] ?? 'Unknown')).toString();
                          selectedModelRef = doc.reference;
                        });
                      },
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty || selectedSiteRef == null || selectedModelRef == null) {
                    return;
                  }
                  try {
                    await FirebaseFirestore.instance.collection('turbinename').doc(docId).update({
                      'turbine_name': nameController.text.trim(),
                      'name': nameController.text.trim(),
                      'site_ref': selectedSiteRef,
                      'site_name': selectedSiteName,
                      'turbinemodel_ref': selectedModelRef,
                      'model_name': selectedModelName,
                    });
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turbine updated')));
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
        ),
      ));
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
        title: Text('Delete Turbine', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        content: const Text('Are you sure? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await FirebaseFirestore.instance.collection('turbinename').doc(docId).delete();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turbine deleted')));
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
    ));
  }

  Future<void> _updateWTGCategory(String docId, String category) async {
    try {
      await FirebaseFirestore.instance.collection('turbinename').doc(docId).update({
        'wtg_category': category,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _masterToggleWTGCategory(bool isNew, List<Map<String, dynamic>> visibleTurbines) async {
    final String category = isNew ? 'new' : 'existing';
    final batch = FirebaseFirestore.instance.batch();
    
    for (final t in visibleTurbines) {
      final docRef = FirebaseFirestore.instance.collection('turbinename').doc(t['id']?.toString());
      batch.update(docRef, {'wtg_category': category});
    }
    
    try {
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('All turbines updated to $category')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter and Search rows
    var filteredRows = rows;
    
    // 1. State Filter
    if (_selectedState != 'All') {
      filteredRows = filteredRows.where((PlutoRow r) {
        final siteName = r.cells['site']?.value?.toString() ?? '';
        return _siteToStateMap[siteName] == _selectedState;
      }).toList();
    }
    
    // 2. Site Filter
    if (_selectedSite != 'All') {
      filteredRows = filteredRows.where((PlutoRow r) => r.cells['site']?.value == _selectedSite).toList();
    }

    // 3. Search Filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filteredRows = filteredRows.where((PlutoRow r) {
        final name = r.cells['name']?.value?.toString().toLowerCase() ?? '';
        final site = r.cells['site']?.value?.toString().toLowerCase() ?? '';
        final model = r.cells['model']?.value?.toString().toLowerCase() ?? '';
        return name.contains(q) || site.contains(q) || model.contains(q);
      }).toList();
    }

    // 4. WTG Category Filter
    if (_filterNewOnly) {
      filteredRows = filteredRows.where((PlutoRow r) => r.cells['wtg_category']?.value.toString() == 'new').toList();
    }
    
    final turbinesList = filteredRows.map((PlutoRow r) => {
      'id': r.cells['id']?.value ?? '',
      'name': r.cells['name']?.value ?? 'Unknown',
      'model': r.cells['model']?.value ?? 'N/A',
      'site': r.cells['site']?.value ?? 'N/A',
      'wtg_category': r.cells['wtg_category']?.value == 'old' ? 'existing' : (r.cells['wtg_category']?.value ?? 'existing'),
    }).toList();

    final int newTurbineCount = rows.where((r) => r.cells['wtg_category']?.value == 'new').length;

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
                      Text('${turbinesList.length} Turbines', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => setState(() => _isSearching = true),
                        icon: Icon(Icons.search_rounded, color: Colors.grey.shade600, size: 20),
                        tooltip: 'Search turbines',
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
                            hintText: 'Search turbines...',
                            hintStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade400),
                            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF00897B)),
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
                Row(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _filterNewOnly = !_filterNewOnly),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _filterNewOnly ? Colors.orange.shade50 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _filterNewOnly ? Colors.orange.shade200 : Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.new_releases_rounded, size: 16, color: _filterNewOnly ? Colors.orange : Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Text(
                              '$newTurbineCount New',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _filterNewOnly ? Colors.orange.shade800 : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const BulkTurbineEntryScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.table_rows_rounded, size: 16),
                      label: const Text('Bulk Add'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF00897B)),
                        foregroundColor: const Color(0xFF00897B),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _addItem,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Turbine'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Horizontal State Filter Bar
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('states').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();
                final states = snapshot.data!.docs;
                return ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('All States'),
                        selected: _selectedState == 'All',
                        selectedColor: Colors.teal.shade50,
                        backgroundColor: Colors.grey.shade100,
                        onSelected: (bool selected) {
                          if (selected) {
                            setState(() {
                              _selectedState = 'All';
                              _selectedSite = 'All'; // Reset site filter when state changes
                            });
                          }
                        },
                      ),
                    ),
                    for (final doc in states) Builder(builder: (context) {
                      final data = doc.data() as Map<String, dynamic>;
                      final name = (data['state'] ?? data['name'] ?? 'Unknown').toString();
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(name),
                          selected: _selectedState == name,
                          selectedColor: Colors.teal.shade50,
                          backgroundColor: Colors.grey.shade100,
                          onSelected: (bool selected) {
                            if (selected) {
                              setState(() {
                                _selectedState = name;
                                _selectedSite = 'All'; // Reset site filter when state changes
                              });
                            }
                          },
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('sites').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox();
                }
                var sites = snapshot.data!.docs;
                if (_selectedState != 'All') {
                  sites = sites.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return (data['state_name'] ?? 'Unknown') == _selectedState;
                  }).toList();
                }
                return ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('All Sites'),
                        selected: _selectedSite == 'All',
                        selectedColor: Colors.teal.shade100,
                        backgroundColor: Colors.grey.shade100,
                        onSelected: (bool selected) {
                          if (selected) {
                            _updateFilter('All');
                          }
                        },
                      ),
                    ),
                    for (final doc in sites)
                      Builder(
                        builder: (context) {
                          final data = doc.data() as Map<String, dynamic>;
                          final name = (data['site_name'] ?? data['name'] ?? 'Unknown').toString();
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(name.toString()),
                              selected: _selectedSite == name.toString(),
                              selectedColor: Colors.teal.shade100,
                              backgroundColor: Colors.grey.shade100,
                              onSelected: (bool selected) {
                                if (selected) {
                                  _updateFilter(name);
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
          
          // Column Headers
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 1))),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('TURBINE NAME', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                Expanded(flex: 2, child: Text('MODEL', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                Expanded(flex: 3, child: Text('SITE', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                SizedBox(
                  width: 120,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('CATEGORY', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                      const SizedBox(width: 4),
                      Transform.scale(
                        scale: 0.6,
                        child: Switch(
                          value: turbinesList.isNotEmpty && turbinesList.every((t) => t['wtg_category'] == 'new'),
                          onChanged: (val) => _masterToggleWTGCategory(val, turbinesList),
                          activeThumbColor: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 100, child: Text('ACTIONS', textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
              ],
            ),
          ),
          
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : turbinesList.isEmpty
                    ? Center(child: Text('No turbines found for this site.', style: GoogleFonts.outfit(color: Colors.grey.shade500)))
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: turbinesList.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (context, index) {
                          final turbine = turbinesList[index];
                          final name = turbine['name'] as String;
                          final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            child: Row(
                              children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(color: const Color(0xFF00897B).withValues(alpha: 0.1), shape: BoxShape.circle),
                                  child: Center(child: Text(initial, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF00897B)))),
                                ),
                                const SizedBox(width: 16),
                                 Expanded(flex: 2, child: Text(name, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF1A1F36)))),
                                 Expanded(flex: 2, child: Text(turbine['model']?.toString() ?? 'N/A', style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade600))),
                                 Expanded(
                                   flex: 3,
                                   child: Row(
                                     children: [
                                       Icon(Icons.location_on_outlined, size: 16, color: Colors.grey.shade500),
                                       const SizedBox(width: 4),
                                       Flexible(child: Text(turbine['site']?.toString() ?? 'N/A', style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                                     ],
                                   ),
                                 ),
                                SizedBox(
                                  width: 120,
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          (turbine['wtg_category'] == 'old' ? 'EXISTING' : (turbine['wtg_category'] ?? 'EXISTING')).toString().toUpperCase(),
                                          style: GoogleFonts.outfit(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: turbine['wtg_category'] == 'new' ? Colors.orange : Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Transform.scale(
                                          scale: 0.7,
                                          child: Switch(
                                            value: turbine['wtg_category'] == 'new',
                                            onChanged: (val) => _updateWTGCategory(turbine['id']?.toString() ?? '', val ? 'new' : 'existing'),
                                            activeThumbColor: Colors.orange,
                                          ),
                                        ),
                                      ],
                                    ),
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
                                         child: IconButton(padding: EdgeInsets.zero, icon: Icon(Icons.edit_outlined, size: 18, color: Colors.grey.shade600), onPressed: () => _editItem(turbine['id']?.toString())),
                                       ),
                                       const SizedBox(width: 8),
                                       Container(
                                         width: 36, height: 36,
                                         decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                                         child: IconButton(padding: EdgeInsets.zero, icon: Icon(Icons.delete_outlined, size: 18, color: Colors.red.shade400), onPressed: () => _deleteItem(turbine['id']?.toString())),
                                       ),
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
  }
}
