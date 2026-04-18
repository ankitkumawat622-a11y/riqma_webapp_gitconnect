import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pluto_grid/pluto_grid.dart';

class ReferenceManagementScreen extends StatefulWidget {
  const ReferenceManagementScreen({super.key});

  @override
  State<ReferenceManagementScreen> createState() => _ReferenceManagementScreenState();
}

class _ReferenceManagementScreenState extends State<ReferenceManagementScreen> {
  List<PlutoRow> rows = [];
  bool isLoading = true;
  StreamSubscription<QuerySnapshot>? _dataSubscription;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<PlutoColumn> columns = [
    PlutoColumn(
      title: 'Reference Name',
      field: 'name',
      type: PlutoColumnType.text(),
      width: 200,
    ),
    PlutoColumn(
      title: 'Code',
      field: 'code',
      type: PlutoColumnType.text(),
      width: 150,
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
                final state = rendererContext.stateManager.gridFocusNode.context
                    ?.findAncestorStateOfType<_ReferenceManagementScreenState>();
                state?._editItem(rendererContext.row.cells['id']?.value?.toString());
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 20),
              onPressed: () {
                final state = rendererContext.stateManager.gridFocusNode.context
                    ?.findAncestorStateOfType<_ReferenceManagementScreenState>();
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
        .collection('references')
        .snapshots()
        .listen((snapshot) {
      final newRows = snapshot.docs.map((doc) {
        final data = doc.data();
        return PlutoRow(
          cells: {
            'name': PlutoCell(value: (data['name'] ?? 'Unknown').toString()),
            'code': PlutoCell(value: (data['code'] ?? '').toString()),
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

  void _addItem() {
    final nameController = TextEditingController();
    final codeController = TextEditingController();

    unawaited(showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Reference', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Reference Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(labelText: 'Code (Optional)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a name'), backgroundColor: Colors.orange));
                return;
              }
              try {
                await FirebaseFirestore.instance.collection('references').add({
                  'name': nameController.text.trim(),
                  'code': codeController.text.trim(),
                  'created_at': FieldValue.serverTimestamp(),
                });
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Reference added successfully!'),
                    backgroundColor: Colors.green,
                  ));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Error adding reference: $e'),
                    backgroundColor: Colors.red,
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

  Future<void> _editItem(String? docId) async {
    if (docId == null) {
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('references').doc(docId).get();
      if (!doc.exists || !mounted) {
        return;
      }

      final data = doc.data()!;
      final nameController = TextEditingController(text: (data['name'] ?? '').toString());
      final codeController = TextEditingController(text: (data['code'] ?? '').toString());

      if (!mounted) {
        return;
      }

      unawaited(showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Edit Reference', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Reference Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(labelText: 'Code (Optional)', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  return;
                }
                try {
                  await FirebaseFirestore.instance.collection('references').doc(docId).update({
                    'name': nameController.text.trim(),
                    'code': codeController.text.trim(),
                  });
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reference updated')));
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
        title: Text('Delete Reference', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        content: const Text('Are you sure? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await FirebaseFirestore.instance.collection('references').doc(docId).delete();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reference deleted')));
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
        final code = r.cells['code']?.value?.toString().toLowerCase() ?? '';
        return name.contains(q) || code.contains(q);
      }).toList();
    }

    final refsList = filteredRows.map((r) => {
      'id': r.cells['id']?.value ?? '',
      'name': r.cells['name']?.value ?? 'Unknown',
      'code': r.cells['code']?.value ?? 'N/A',
    }).toList();

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FD),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Premium Header ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1F36).withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.bookmarks_rounded, color: Color(0xFF1A1F36), size: 22),
                    ),
                    const SizedBox(width: 16),
                    if (!_isSearching) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('References', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700, color: const Color(0xFF1A1F36))),
                          Text('${refsList.length} items strictly managed', style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w400)),
                        ],
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: () => setState(() => _isSearching = true),
                        icon: Icon(Icons.search_rounded, color: Colors.grey.shade600, size: 22),
                        tooltip: 'Search references',
                        splashRadius: 22,
                      ),
                    ] else ...[
                      SizedBox(
                        width: 300,
                        height: 42,
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          style: GoogleFonts.outfit(fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'Search by name or code...',
                            hintStyle: GoogleFonts.outfit(fontSize: 15, color: Colors.grey.shade400),
                            prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF1A1F36)),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () {
                                setState(() {
                                  _isSearching = false;
                                  _searchController.clear();
                                  _searchQuery = '';
                                });
                              },
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            fillColor: Colors.grey.shade100,
                            filled: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (value) => setState(() => _searchQuery = value),
                        ),
                      ),
                    ],
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text('Create Reference', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1F36),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),

          // ── Modern Grid Layout ──────────────────────────────────────────────
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A1F36)))
                : refsList.isEmpty
                    ? _buildEmptyState()
                    : GridView.builder(
                        padding: const EdgeInsets.all(24),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 350,
                          mainAxisExtent: 180,
                          crossAxisSpacing: 24,
                          mainAxisSpacing: 24,
                        ),
                        itemCount: refsList.length,
                        itemBuilder: (context, index) {
                          final ref = refsList[index];
                          return _buildModernRefCard(ref);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(_searchQuery.isEmpty ? 'No references yet' : 'No matching references', 
            style: GoogleFonts.outfit(fontSize: 18, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
          if (_searchQuery.isNotEmpty) 
            TextButton(
              onPressed: () => setState(() { _isSearching = false; _searchController.clear(); _searchQuery = ''; }),
              child: const Text('Clear search'),
            ),
        ],
      ),
    );
  }

  Widget _buildModernRefCard(Map<String, dynamic> ref) {
    final name = ref['name'] as String;
    final code = (ref['code']?.toString().isEmpty ?? true) ? 'NO CODE' : ref['code'].toString();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFF0F0F0)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _editItem(ref['id']?.toString()),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1A1F36), Color(0xFF434D7B)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(initial, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                    Row(
                      children: [
                        _CardActionButton(
                          icon: Icons.edit_outlined,
                          color: Colors.blue.shade600,
                          onPressed: () => _editItem(ref['id']?.toString()),
                        ),
                        const SizedBox(width: 8),
                        _CardActionButton(
                          icon: Icons.delete_outline_rounded,
                          color: Colors.red.shade400,
                          onPressed: () => _deleteItem(ref['id']?.toString()),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  name,
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF1A1F36)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EAF6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    code,
                    style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF3F51B5), letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _CardActionButton({required this.icon, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 16, color: color),
        onPressed: onPressed,
      ),
    );
  }
}
