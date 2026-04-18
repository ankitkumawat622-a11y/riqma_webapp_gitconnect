import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pluto_grid/pluto_grid.dart';

class TurbineModelsView extends StatefulWidget {
  const TurbineModelsView({super.key});

  @override
  State<TurbineModelsView> createState() => _TurbineModelsViewState();
}

class _TurbineModelsViewState extends State<TurbineModelsView> {
  List<PlutoRow> rows = [];
  bool isLoading = true;
  StreamSubscription<QuerySnapshot>? _dataSubscription;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<PlutoColumn> columns = [
    PlutoColumn(title: 'Model Name', field: 'name', type: PlutoColumnType.text(), width: 200),
    PlutoColumn(title: 'Make', field: 'make', type: PlutoColumnType.text(), width: 150),
    PlutoColumn(title: 'Rating', field: 'rating', type: PlutoColumnType.text(), width: 100),
    PlutoColumn(title: 'Site Name', field: 'site_name', type: PlutoColumnType.text(), width: 250),
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
                final state = rendererContext.stateManager.gridFocusNode.context?.findAncestorStateOfType<_TurbineModelsViewState>();
                state?._editItem(rendererContext.row.cells['id']?.value?.toString());
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 20),
              onPressed: () {
                final state = rendererContext.stateManager.gridFocusNode.context?.findAncestorStateOfType<_TurbineModelsViewState>();
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
    _setupDataStream();
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _setupDataStream() {
    _dataSubscription = FirebaseFirestore.instance
        .collection('turbinemodel')
        .snapshots()
        .listen((snapshot) {
      final newRows = snapshot.docs.map((doc) {
        final data = doc.data();
        
        // Handle both new list format and legacy single string format
        String siteNamesDisplay = 'Unknown Site';
        if (data.containsKey('site_names') && data['site_names'] is List) {
          final List<dynamic> names = data['site_names'] as List<dynamic>;
          siteNamesDisplay = names.join(', ');
        } else if (data.containsKey('site_name')) {
          siteNamesDisplay = data['site_name'].toString();
        }

        return PlutoRow(
          cells: {
            'name': PlutoCell(value: (data.containsKey('turbine_model') ? data['turbine_model'] : (data.containsKey('name') ? data['name'] : 'Unknown')).toString()),
            'make': PlutoCell(value: (data.containsKey('turbine_make') ? data['turbine_make'] : 'N/A').toString()),
            'rating': PlutoCell(value: (data.containsKey('turbine_rating') ? data['turbine_rating'] : 'N/A').toString()),
            'site_name': PlutoCell(value: siteNamesDisplay),
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

  Future<void> _showMultiSelect(BuildContext context, List<QueryDocumentSnapshot> sites, List<String> selectedSiteIds, void Function(List<String>) onConfirm) async {
    final List<String> tempSelectedIds = List.from(selectedSiteIds);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Select Sites', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              content: SingleChildScrollView(
                child: ListBody(
                  children: sites.map((site) {
                    final data = site.data() as Map<String, dynamic>;
                    final siteName = data['site_name']?.toString() ?? (data['name']?.toString() ?? 'Unknown Site');
                    final isSelected = tempSelectedIds.contains(site.id);
                    
                    return CheckboxListTile(
                      value: isSelected,
                      title: Text(siteName),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (bool? checked) {
                        setState(() {
                          if (checked == true) {
                            tempSelectedIds.add(site.id);
                          } else {
                            tempSelectedIds.remove(site.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    onConfirm(tempSelectedIds);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _addItem() {
    final nameController = TextEditingController();
    final makeController = TextEditingController();
    final ratingController = TextEditingController();
    List<String> selectedSiteIds = [];
    List<String> selectedSiteNames = [];

    unawaited(showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Turbine Model', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Model Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: makeController,
                decoration: const InputDecoration(labelText: 'Turbine Make', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ratingController,
                decoration: const InputDecoration(labelText: 'Turbine Rating', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('sites').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}');
                  }
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }

                  final sites = snapshot.data!.docs;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sites', style: GoogleFonts.outfit(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          await _showMultiSelect(context, sites, selectedSiteIds, (newIds) {
                            setDialogState(() {
                              selectedSiteIds = newIds;
                              selectedSiteNames = newIds.map((id) {
                                final doc = sites.firstWhere((s) => s.id == id);
                                final data = doc.data() as Map<String, dynamic>;
                                return data['site_name']?.toString() ?? (data['name']?.toString() ?? 'Unknown Site');
                              }).toList();
                            });
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  selectedSiteNames.isEmpty ? 'Select Sites' : selectedSiteNames.join(', '),
                                  style: TextStyle(color: selectedSiteNames.isEmpty ? Colors.grey[600] : Colors.black),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down),
                            ],
                          ),
                        ),
                      ),
                    ],
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
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a model name')));
                return;
              }
              // It's okay to have no sites selected, but usually we want at least one. 
              // Allowing empty for flexibility, or we can enforce it.
              
              try {
                await FirebaseFirestore.instance.collection('turbinemodel').add({
                  'turbine_model': nameController.text.trim(),
                  'name': nameController.text.trim(),
                  'turbine_make': makeController.text.trim(),
                  'turbine_rating': ratingController.text.trim(),
                  'site_ids': selectedSiteIds.map((id) => FirebaseFirestore.instance.doc('/sites/$id')).toList(),
                  'site_names': selectedSiteNames,
                  'created_at': FieldValue.serverTimestamp(),
                });
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Model added')));
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
    ));
  }

  Future<void> _editItem(String? docId) async {
    if (docId == null) {
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('turbinemodel').doc(docId).get();
      if (!doc.exists || !mounted) {
        return;
      }

      final data = doc.data()!;
      final nameController = TextEditingController(text: (data.containsKey('turbine_model') ? data['turbine_model'] : (data.containsKey('name') ? data['name'] : '')).toString());
      final makeController = TextEditingController(text: (data.containsKey('turbine_make') ? data['turbine_make'] : '').toString());
      final ratingController = TextEditingController(text: (data.containsKey('turbine_rating') ? data['turbine_rating'] : '').toString());
      
      List<String> selectedSiteIds = [];
      List<String> selectedSiteNames = [];

      // Load existing sites (handle both new list [Refs or Strings] and legacy single ref)
      if (data.containsKey('site_ids') && data['site_ids'] is List) {
        final List<dynamic> rawIds = data['site_ids'] as List<dynamic>;
        selectedSiteIds = rawIds.map((e) => e is DocumentReference ? e.id : e.toString()).toList();
        if (data.containsKey('site_names') && data['site_names'] is List) {
          selectedSiteNames = List<String>.from(data['site_names'] as Iterable<dynamic>);
        }
      } else if (data.containsKey('site_ref')) {
        // Legacy support
        final DocumentReference? ref = data['site_ref'] as DocumentReference?;
        if (ref != null) {
          selectedSiteIds.add(ref.id);
          if (data.containsKey('site_name')) {
            selectedSiteNames.add(data['site_name'].toString());
          }
        }
      }

      if (!mounted) {
        return;
      }

      unawaited(showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Edit Turbine Model', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          content: StatefulBuilder(
            builder: (context, setDialogState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Model Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: makeController,
                  decoration: const InputDecoration(labelText: 'Turbine Make', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ratingController,
                  decoration: const InputDecoration(labelText: 'Turbine Rating', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('sites').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }
                    final sites = snapshot.data!.docs;
                    
                    // Refresh names if needed (e.g. if we only had IDs)
                    // But for simplicity, we rely on what we loaded or what user selects.
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sites', style: GoogleFonts.outfit(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () async {
                            await _showMultiSelect(context, sites, selectedSiteIds, (newIds) {
                              setDialogState(() {
                                selectedSiteIds = newIds;
                                selectedSiteNames = newIds.map((id) {
                                  final doc = sites.firstWhere((s) => s.id == id);
                                  final data = doc.data() as Map<String, dynamic>;
                                  return data['site_name']?.toString() ?? (data['name']?.toString() ?? 'Unknown Site');
                                }).toList();
                              });
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    selectedSiteNames.isEmpty ? 'Select Sites' : selectedSiteNames.join(', '),
                                    style: TextStyle(color: selectedSiteNames.isEmpty ? Colors.grey[600] : Colors.black),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                        ),
                      ],
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
                if (nameController.text.trim().isEmpty) {
                  return;
                }
                try {
                  await FirebaseFirestore.instance.collection('turbinemodel').doc(docId).update({
                    'turbine_model': nameController.text.trim(),
                    'name': nameController.text.trim(),
                    'turbine_make': makeController.text.trim(),
                    'turbine_rating': ratingController.text.trim(),
                    'site_ids': selectedSiteIds.map((id) => FirebaseFirestore.instance.doc('/sites/$id')).toList(),
                    'site_names': selectedSiteNames,
                  });
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Model updated')));
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
        title: Text('Delete Turbine Model', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        content: const Text('Are you sure? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await FirebaseFirestore.instance.collection('turbinemodel').doc(docId).delete();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Model deleted')));
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
    var filteredRows = rows;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filteredRows = rows.where((r) {
        final name = r.cells['name']?.value?.toString().toLowerCase() ?? '';
        final make = r.cells['make']?.value?.toString().toLowerCase() ?? '';
        final rating = r.cells['rating']?.value?.toString().toLowerCase() ?? '';
        final sites = r.cells['site_name']?.value?.toString().toLowerCase() ?? '';
        return name.contains(q) || make.contains(q) || rating.contains(q) || sites.contains(q);
      }).toList();
    }

    final modelsList = filteredRows.map((r) => {
      'id': r.cells['id']?.value ?? '',
      'name': r.cells['name']?.value ?? 'Unknown',
      'make': r.cells['make']?.value ?? 'N/A',
      'rating': r.cells['rating']?.value ?? 'N/A',
      'site_name': r.cells['site_name']?.value ?? 'N/A',
    }).toList();

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
                      Text('${modelsList.length} Models', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => setState(() => _isSearching = true),
                        icon: Icon(Icons.search_rounded, color: Colors.grey.shade600, size: 20),
                        tooltip: 'Search models',
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
                            hintText: 'Search models...',
                            hintStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade400),
                            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF6B5B95)),
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
                  label: const Text('Add Model'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B5B95),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 1))),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('MODEL NAME', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                Expanded(flex: 1, child: Text('MAKE', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                Expanded(flex: 1, child: Text('RATING', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                Expanded(flex: 2, child: Text('SITES', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                SizedBox(width: 100, child: Text('ACTIONS', textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : modelsList.isEmpty
                    ? Center(child: Text('No models found', style: GoogleFonts.outfit(color: Colors.grey.shade500)))
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: modelsList.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (context, index) {
                          final model = modelsList[index];
                          final name = model['name'] as String;
                          final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            child: Row(
                              children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(color: const Color(0xFF6B5B95).withValues(alpha: 0.1), shape: BoxShape.circle),
                                  child: Center(child: Text(initial, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF6B5B95)))),
                                ),
                                const SizedBox(width: 16),
                                Expanded(flex: 2, child: Text(name, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF1A1F36)))),
                                Expanded(flex: 1, child: Text(model['make'] as String, style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade600))),
                                Expanded(flex: 1, child: Text(model['rating'] as String, style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade600))),
                                Expanded(
                                  flex: 2,
                                  child: Text(model['site_name'] as String, style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
                                ),
                                SizedBox(
                                  width: 100,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 36, height: 36,
                                        decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                                        child: IconButton(padding: EdgeInsets.zero, icon: Icon(Icons.edit_outlined, size: 18, color: Colors.grey.shade600), onPressed: () => _editItem(model['id']?.toString())),
                                      ),
                                      const SizedBox(width: 8),
                                      // Delete Button
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          shape: BoxShape.circle,
                                        ),
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          icon: Icon(Icons.delete_outlined, size: 18, color: Colors.red.shade400),
                                          onPressed: () => _deleteItem(model['id']?.toString()),
                                        ),
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
