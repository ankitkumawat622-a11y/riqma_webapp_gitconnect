import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:riqma_webapp/widgets/modern_searchable_dropdown.dart';

class StatesView extends StatefulWidget {
  const StatesView({super.key});

  @override
  State<StatesView> createState() => _StatesViewState();
}

class _StatesViewState extends State<StatesView> {
  List<PlutoRow> rows = [];
  bool isLoading = true;
  StreamSubscription<QuerySnapshot>? _dataSubscription;

  final List<PlutoColumn> columns = [
    PlutoColumn(
      title: 'State Name',
      field: 'name',
      type: PlutoColumnType.text(),
      width: 250,
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
                final state = rendererContext.stateManager.gridFocusNode.context?.findAncestorStateOfType<_StatesViewState>();
                state?._editItem(rendererContext.row.cells['id']?.value?.toString());
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 20),
              onPressed: () {
                final state = rendererContext.stateManager.gridFocusNode.context?.findAncestorStateOfType<_StatesViewState>();
                state?._deleteItem(rendererContext.row.cells['id']?.value?.toString());
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
      hide: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _setupDataStream();
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    super.dispose();
  }

  void _setupDataStream() {
    _dataSubscription = FirebaseFirestore.instance
        .collection('states')
        .snapshots()
        .listen((snapshot) {
      final newRows = snapshot.docs.map((doc) {
        final data = doc.data();
        return PlutoRow(
          cells: {
            'name': PlutoCell(value: (data.containsKey('state') ? data['state'] : (data.containsKey('name') ? data['name'] : 'Unknown')).toString()),
            'zone': PlutoCell(value: (data['zone'] ?? '-').toString()),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $error')),
        );
      }
    });
  }

  void _addItem() {
    final nameController = TextEditingController();
    final zoneController = TextEditingController();

    unawaited(showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add State', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'State Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ModernSearchableDropdown(
              label: 'Zone',
              items: {
                for (var z in ['North', 'South', 'East', 'West', 'Central', 'North-East'])
                  z: z
              },
              value: zoneController.text.trim().isEmpty ? null : zoneController.text.trim(),
              color: Colors.green,
              icon: Icons.map_rounded,
              onChanged: (val) {
                zoneController.text = val ?? '';
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                return;
              }

              try {
                await FirebaseFirestore.instance.collection('states').add({
                  'state': nameController.text.trim(),
                  'zone': zoneController.text.trim(),
                  'created_at': FieldValue.serverTimestamp(),
                });
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('State added successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
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
      final doc = await FirebaseFirestore.instance.collection('states').doc(docId).get();
      if (!doc.exists) {
        return;
      }

      final data = doc.data()!;
      final nameController = TextEditingController(text: (data.containsKey('state') ? data['state'] : (data.containsKey('name') ? data['name'] : '')).toString());
      final zoneController = TextEditingController(text: (data['zone'] ?? '').toString());

      if (!mounted) {
        return;
      }

      unawaited(showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Edit State', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'State Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              ModernSearchableDropdown(
                label: 'Zone',
                items: {
                  for (var z in ['North', 'South', 'East', 'West', 'Central', 'North-East'])
                    z: z
                },
                value: zoneController.text.trim().isEmpty ? null : zoneController.text.trim(),
                color: Colors.green,
                icon: Icons.map_rounded,
                onChanged: (val) {
                  zoneController.text = val ?? '';
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  return;
                }

                try {
                  await FirebaseFirestore.instance.collection('states').doc(docId).update({
                    'state': nameController.text.trim(),
                    'zone': zoneController.text.trim(),
                  });
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('State updated successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
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
        title: Text('Delete State', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        content: const Text('Are you sure you want to delete this state? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await FirebaseFirestore.instance.collection('states').doc(docId).delete();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('State deleted successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
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
    // Extract data from PlutoRows for our custom list
    final statesList = rows.map((r) => {
      'id': r.cells['id']?.value ?? '',
      'name': r.cells['name']?.value ?? 'Unknown',
      'zone': r.cells['zone']?.value ?? '-',
    }).toList();

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with count and Add button
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.list_alt_rounded, color: Colors.grey.shade600, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '${statesList.length} States',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add State'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          
          // Column Headers
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'STATE NAME',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'ZONE',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Text(
                    'ACTIONS',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Data List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : statesList.isEmpty
                    ? Center(
                        child: Text(
                          'No states found',
                          style: GoogleFonts.outfit(color: Colors.grey.shade500),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: statesList.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          color: Colors.grey.shade200,
                        ),
                        itemBuilder: (context, index) {
                          final state = statesList[index];
                          final name = state['name']?.toString() ?? 'N/A';
                          final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                          
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            child: Row(
                              children: [
                                // Avatar with Initial
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      initial,
                                      style: GoogleFonts.outfit(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF2E7D32),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                
                                // State Name
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    name,
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFF1A1F36),
                                    ),
                                  ),
                                ),
                                
                                // Zone Name
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    state['zone'] as String,
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFF1A1F36),
                                    ),
                                  ),
                                ),
                                
                                // Action Buttons
                                SizedBox(
                                  width: 100,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Edit Button
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          shape: BoxShape.circle,
                                        ),
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          icon: Icon(Icons.edit_outlined, size: 18, color: Colors.grey.shade600),
                                           onPressed: () => _editItem(state['id']?.toString()),
                                        ),
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
                                           onPressed: () => _deleteItem(state['id']?.toString()),
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
