import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:riqma_webapp/screens/manage/bulk_site_entry_screen.dart';
import 'package:riqma_webapp/widgets/modern_searchable_dropdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SitesView extends StatefulWidget {
  const SitesView({super.key});

  @override
  State<SitesView> createState() => _SitesViewState();
}

class _SitesViewState extends State<SitesView> {
  List<PlutoRow> rows = [];
  bool isLoading = true;
  StreamSubscription<QuerySnapshot>? _dataSubscription;
  
  // Filter & Search State
  String _selectedState = 'All';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<PlutoColumn> columns = [
    PlutoColumn(
      title: 'Site Name',
      field: 'name',
      type: PlutoColumnType.text(),
      width: 200,
    ),
    PlutoColumn(
      title: 'State',
      field: 'state',
      type: PlutoColumnType.text(),
      width: 150,
    ),
    PlutoColumn(
      title: 'Zone',
      field: 'zone',
      type: PlutoColumnType.text(),
      width: 120,
    ),
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
                final state = rendererContext.stateManager.gridFocusNode.context?.findAncestorStateOfType<_SitesViewState>();
                state?._editItem(rendererContext.row.cells['id']?.value?.toString());
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 20),
              onPressed: () {
                final state = rendererContext.stateManager.gridFocusNode.context?.findAncestorStateOfType<_SitesViewState>();
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
    _setupDataStream();
  }

  Future<void> _loadSavedFilter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedState = prefs.getString('sites_state_filter') ?? 'All';
    });
  }

  Future<void> _updateFilter(String state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sites_state_filter', state);
    setState(() {
      _selectedState = state;
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
        .collection('sites')
        .snapshots()
        .listen((snapshot) {
      final newRows = snapshot.docs.map((doc) {
        final data = doc.data();
        return PlutoRow(
          cells: {
            'name': PlutoCell(value: (data.containsKey('site_name') ? data['site_name'] : (data.containsKey('name') ? data['name'] : 'Unknown Site')).toString()),
            'state': PlutoCell(value: (data.containsKey('state_name') ? data['state_name'] : 'Unknown State').toString()),
            'district': PlutoCell(value: (data.containsKey('district') ? data['district'] : '-').toString()),
            'warehouse_code': PlutoCell(value: (data.containsKey('warehouse_code') ? data['warehouse_code'] : '-').toString()),
            'zone': PlutoCell(value: (data.containsKey('zone') ? data['zone'] : 'Unassigned').toString()),
            'actions': PlutoCell(value: ''),
            'id': PlutoCell(value: doc.id),
          },
        );
      }).toList();

      if (mounted) {
        setState(() {
          rows = newRows;
          isLoading = false;
        });
      }
    }, onError: (Object error) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $error')));
      }
    });
  }

  Future<void> _addItem() async {
    final nameController = TextEditingController();
    final districtController = TextEditingController();
    final warehouseCodeController = TextEditingController();
    String? selectedZone;
    final List<String> zoneList = ['North', 'South', 'East', 'West', 'Central', 'North-East'];
    String? selectedStateId;
    String? selectedStateName;
    DocumentReference? selectedStateRef;

    final prefs = await SharedPreferences.getInstance();
    final savedStateId = prefs.getString('last_selected_state_id');

    // Optimization: Pre-set if we can, but we must validate against the list later
    if (savedStateId != null) {
      selectedStateId = savedStateId;
      // We can't set Name/Ref yet without the list
    }

    if (!mounted) {
      return;
    }

    unawaited(showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Site', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Site Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: districtController,
                decoration: const InputDecoration(labelText: 'District Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: warehouseCodeController,
                decoration: const InputDecoration(labelText: 'Warehouse Code', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              ModernSearchableDropdown(
                label: 'Zone',
                items: {for (var z in zoneList) z: z},
                value: selectedZone,
                color: Colors.blue,
                icon: Icons.map_rounded,
                onChanged: (value) => setDialogState(() => selectedZone = value),
              ),
              const SizedBox(height: 16),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('states').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}');
                  }
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }

                  final states = snapshot.data!.docs;
                  
                  // Validate selectedStateId matches an existing item
                  if (selectedStateId != null && !states.any((doc) => doc.id == selectedStateId)) {
                    selectedStateId = null; 
                  }
                  
                  // If we have a selectedStateId but no Name/Ref (loaded from prefs), find and set them
                  if (selectedStateId != null && selectedStateRef == null) {
                     try {
                        final doc = states.firstWhere((d) => d.id == selectedStateId);
                        final data = doc.data() as Map<String, dynamic>;
                        selectedStateName = data['state']?.toString() ?? 'Unknown';
                        selectedStateRef = doc.reference;
                     } catch (e) {
                        // Should be caught by the validations above, but just in case
                        selectedStateId = null;
                     }
                  }

                  final Map<String, String> stateMap = {
                    for (var doc in states) 
                      doc.id: (doc.data() as Map<String, dynamic>)['state']?.toString() ?? 'Unknown State'
                  };

                  return ModernSearchableDropdown(
                    label: 'State',
                    items: stateMap,
                    value: selectedStateId,
                    color: Colors.indigo,
                    icon: Icons.location_on_rounded,
                    onChanged: (value) async {
                      if (value == null) return;
                      await prefs.setString('last_selected_state_id', value);
                      setDialogState(() {
                        selectedStateId = value;
                        final doc = states.firstWhere((d) => d.id == value);
                        final data = doc.data() as Map<String, dynamic>;
                        selectedStateName = data['state']?.toString() ?? 'Unknown';
                        selectedStateRef = doc.reference;
                      });
                    },
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty || selectedStateRef == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields'), backgroundColor: Colors.orange));
                return;
              }
              try {

                await FirebaseFirestore.instance.collection('sites').add({
                  'site_name': nameController.text.trim(),
                  'state_ref': selectedStateRef,
                  'state_name': selectedStateName,
                  'district': districtController.text.trim(),
                  'warehouse_code': warehouseCodeController.text.trim(),
                  'zone': selectedZone ?? 'Unassigned',
                  'created_at': FieldValue.serverTimestamp(),
                });

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Site "${nameController.text.trim()}" added successfully!'),
                    backgroundColor: Colors.green,
                  ));
                }
              } catch (e) {

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Error adding site: $e'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 5),
                  ));
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ));
  }


  void _editItem(String? docId) async {
    if (docId == null) {
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('sites').doc(docId).get();
      if (!doc.exists || !mounted) {
        return;
      }

      final data = doc.data()!;
      final nameController = TextEditingController(text: (data.containsKey('site_name') ? data['site_name'] : (data.containsKey('name') ? data['name'] : '')).toString());
      final districtController = TextEditingController(text: (data.containsKey('district') ? data['district'] : '').toString());
      final warehouseCodeController = TextEditingController(text: (data.containsKey('warehouse_code') ? data['warehouse_code'] : '').toString());
      String? selectedZone = data['zone']?.toString();
      final List<String> zoneList = ['North', 'South', 'East', 'West', 'Central', 'North-East'];
      if (selectedZone != null && !zoneList.contains(selectedZone)) selectedZone = null;

      String? selectedStateId;
      String? selectedStateName;
      DocumentReference? selectedStateRef = data['state_ref'] as DocumentReference?;

      if (selectedStateRef != null) {
        try {
          final stateDoc = await selectedStateRef.get();
          if (stateDoc.exists) {
            selectedStateId = stateDoc.id;
            final stateData = stateDoc.data() as Map<String, dynamic>?;
            if (stateData != null) {
              selectedStateName = (stateData.containsKey('state') ? stateData['state'] : (stateData.containsKey('name') ? stateData['name'] : 'Unknown')).toString();
            }
          }
        } catch (e) {
          // Handle error
        }
      }

      if (!mounted) {
        return;
      }

      unawaited(showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Edit Site', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          content: StatefulBuilder(
            builder: (context, setDialogState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Site Name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: districtController,
                    decoration: const InputDecoration(labelText: 'District Name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: warehouseCodeController,
                    decoration: const InputDecoration(labelText: 'Warehouse Code', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  ModernSearchableDropdown(
                    label: 'Zone',
                    items: {for (var z in zoneList) z: z},
                    value: selectedZone,
                    color: Colors.blue,
                    icon: Icons.map_rounded,
                    onChanged: (value) => setDialogState(() => selectedZone = value),
                  ),
                  const SizedBox(height: 16),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('states').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }
                    final states = snapshot.data!.docs;
                    final Map<String, String> stateMap = {
                      for (var doc in states) 
                        doc.id: (doc.data() as Map<String, dynamic>).containsKey('state') 
                            ? (doc.data() as Map<String, dynamic>)['state'].toString() 
                            : ((doc.data() as Map<String, dynamic>).containsKey('name') 
                                ? (doc.data() as Map<String, dynamic>)['name'].toString() 
                                : 'Unknown')
                    };

                    return ModernSearchableDropdown(
                      label: 'State',
                      items: stateMap,
                      value: selectedStateId,
                      color: Colors.indigo,
                      icon: Icons.location_on_rounded,
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          selectedStateId = value;
                          final doc = states.firstWhere((d) => d.id == value);
                          final data = doc.data() as Map<String, dynamic>;
                          selectedStateName = (data.containsKey('state') ? data['state'] : (data.containsKey('name') ? data['name'] : 'Unknown')).toString();
                          selectedStateRef = doc.reference;
                        });
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty || selectedStateRef == null) {
                  return;
                }
                try {
                  await FirebaseFirestore.instance.collection('sites').doc(docId).update({
                    'site_name': nameController.text.trim(),
                    'state_ref': selectedStateRef,
                    'state_name': selectedStateName,
                    'district': districtController.text.trim(),
                    'warehouse_code': warehouseCodeController.text.trim(),
                    'zone': selectedZone ?? 'Unassigned',
                  });
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Site updated')));
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
        title: Text('Delete Site', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        content: const Text('Are you sure? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await FirebaseFirestore.instance.collection('sites').doc(docId).delete();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Site deleted')));
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

  @override
  Widget build(BuildContext context) {
    // Filter and Search rows
    var filteredRows = _selectedState == 'All'
        ? rows
        : rows.where((r) => r.cells['state']?.value == _selectedState).toList();
    
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filteredRows = filteredRows.where((r) {
        final name = r.cells['name']?.value?.toString().toLowerCase() ?? '';
        final state = r.cells['state']?.value?.toString().toLowerCase() ?? '';
        final district = r.cells['district']?.value?.toString().toLowerCase() ?? '';
        final warehouse = r.cells['warehouse_code']?.value?.toString().toLowerCase() ?? '';
        final zone = r.cells['zone']?.value?.toString().toLowerCase() ?? '';
        return name.contains(q) || state.contains(q) || district.contains(q) || warehouse.contains(q) || zone.contains(q);
      }).toList();
    }

    final sitesList = filteredRows.map((r) => {
      'id': r.cells['id']?.value ?? '',
      'name': r.cells['name']?.value ?? 'Unknown',
      'state': r.cells['state']?.value ?? 'N/A',
      'district': r.cells['district']?.value ?? '-',
      'warehouse_code': r.cells['warehouse_code']?.value ?? '-',
    }).toList();

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 4)),
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
                    Icon(Icons.list_alt_rounded, color: Colors.grey.shade600, size: 20),
                    const SizedBox(width: 8),
                    if (!_isSearching) ...[
                      Text('${sitesList.length} Sites', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => setState(() => _isSearching = true),
                        icon: Icon(Icons.search_rounded, color: Colors.grey.shade600, size: 20),
                        tooltip: 'Search sites',
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
                            hintText: 'Search sites...',
                            hintStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade400),
                            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF0277BD)),
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
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const BulkSiteEntryScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.table_rows_rounded, size: 16),
                      label: const Text('Bulk Add'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF0277BD)),
                        foregroundColor: const Color(0xFF0277BD),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _addItem,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Site'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0277BD),
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
                if (!snapshot.hasData) {
                  return const SizedBox();
                }
                final states = snapshot.data!.docs;
                return ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('All States'),
                        selected: _selectedState == 'All',
                        selectedColor: const Color(0xFF0277BD).withValues(alpha: 0.2),
                        backgroundColor: Colors.grey.shade100,
                        labelStyle: GoogleFonts.outfit(
                          color: _selectedState == 'All' ? const Color(0xFF0277BD) : Colors.black87,
                          fontWeight: _selectedState == 'All' ? FontWeight.w600 : FontWeight.normal,
                        ),
                        side: BorderSide.none,
                        onSelected: (bool selected) {
                          if (selected) {
                            _updateFilter('All');
                          }
                        },
                      ),
                    ),
                    for (final doc in states)
                      Builder(
                        builder: (context) {
                          final data = doc.data() as Map<String, dynamic>;
                          final name = data['state']?.toString() ?? data['name']?.toString() ?? 'Unknown';
                          final isSelected = _selectedState == name;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(name),
                              selected: isSelected,
                              selectedColor: const Color(0xFF0277BD).withValues(alpha: 0.2),
                              backgroundColor: Colors.grey.shade100,
                              labelStyle: GoogleFonts.outfit(
                                color: isSelected ? const Color(0xFF0277BD) : Colors.black87,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              ),
                              side: BorderSide.none,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 1))),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('SITE NAME', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                Expanded(flex: 2, child: Text('DISTRICT', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                Expanded(flex: 2, child: Text('WAREHOUSE', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                Expanded(flex: 1, child: Text('ZONE', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                Expanded(flex: 2, child: Text('STATE', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                SizedBox(width: 100, child: Text('ACTIONS', textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : sitesList.isEmpty
                    ? Center(child: Text('No sites found for this state', style: GoogleFonts.outfit(color: Colors.grey.shade500)))
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: sitesList.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (context, index) {
                          final site = sitesList[index];
                          final name = site['name'] as String;
                          final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            child: Row(
                              children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(color: const Color(0xFF0277BD).withValues(alpha: 0.1), shape: BoxShape.circle),
                                  child: Center(child: Text(initial, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF0277BD)))),
                                ),
                                const SizedBox(width: 16),
                                Expanded(flex: 2, child: Text(name, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF1A1F36)))),
                                Expanded(flex: 2, child: Text(site['district'] as String, style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade600))),
                                Expanded(flex: 2, child: Text(site['warehouse_code'] as String, style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade600))),
                                Expanded(flex: 1, child: Text(site['zone']?.toString() ?? '-', style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade600))),
                                Expanded(
                                  flex: 2,
                                  child: Row(
                                    children: [
                                      Icon(Icons.location_on_outlined, size: 16, color: Colors.grey.shade500),
                                      const SizedBox(width: 4),
                                       Flexible(child: Text(site['state']?.toString() ?? 'N/A', style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade600))),
                                    ],
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
                                         child: IconButton(padding: EdgeInsets.zero, icon: Icon(Icons.edit_outlined, size: 18, color: Colors.grey.shade600), onPressed: () => _editItem(site['id']?.toString())),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        width: 36, height: 36,
                                        decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                                         child: IconButton(padding: EdgeInsets.zero, icon: Icon(Icons.delete_outlined, size: 18, color: Colors.red.shade400), onPressed: () => _deleteItem(site['id']?.toString())),
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
