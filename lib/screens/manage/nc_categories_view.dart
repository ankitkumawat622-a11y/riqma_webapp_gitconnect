import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Admin view for managing NC Categories stored in audit_configs/nc_categories.
/// Each item: { "name": "Quality of Workmanship", "is_workman_penalty": true }
class NCCategoriesView extends StatefulWidget {
  const NCCategoriesView({super.key});

  @override
  State<NCCategoriesView> createState() => _NCCategoriesViewState();
}

class _NCCategoriesViewState extends State<NCCategoriesView> {
  final _firestore = FirebaseFirestore.instance;
  static const _docPath = 'audit_configs/nc_categories';
  bool _isLoading = false;

  /// Shows dialog to add or edit an NC category.
  Future<void> _showCategoryDialog({Map<String, dynamic>? existing}) async {
    final nameController = TextEditingController(text: existing?['name']?.toString() ?? '');
    bool isWorkman = existing?['is_workman_penalty'] == true;
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.report_problem_outlined, color: Colors.indigo[700]),
              const SizedBox(width: 8),
              Text(
                existing == null ? 'Add NC Category' : 'Edit NC Category',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Category Name',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  style: GoogleFonts.outfit(),
                  validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Switch(
                      value: isWorkman,
                      onChanged: (v) => setDialogState(() => isWorkman = v),
                    activeThumbColor: Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Workmanship Penalty', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                          Text(
                            'When ON, NCs in this category contribute to the Workmanship penalty score.',
                            style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(context);
                final messenger = ScaffoldMessenger.of(context);
                setState(() => _isLoading = true);
                try {
                  final docRef = _firestore.doc(_docPath);
                  final snap = await docRef.get();
                  final List<dynamic> items = List<dynamic>.from((snap.data()?['items'] as List<dynamic>?) ?? []);

                  final newItem = {
                    'name': nameController.text.trim(),
                    'is_workman_penalty': isWorkman,
                  };

                  if (existing != null) {
                    // Replace existing entry by name
                    final idx = items.indexWhere((e) => (e as Map)['name'] == existing['name']);
                    if (idx >= 0) items[idx] = newItem;
                  } else {
                    items.add(newItem);
                  }

                  await docRef.set({'items': items}, SetOptions(merge: true));
                  if (mounted) {
                    messenger.showSnackBar(const SnackBar(content: Text('Category saved')));
                  }
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo[700],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCategory(Map<String, dynamic> item, List<dynamic> currentItems) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Category', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          'Delete "${item['name']}"? This cannot be undone.',
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: GoogleFonts.outfit())),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isLoading = true);
    try {
      final updatedItems = List<dynamic>.from(currentItems)
        ..removeWhere((e) => (e as Map)['name'] == item['name']);
      await _firestore.doc(_docPath).set({'items': updatedItems}, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                Icon(Icons.report_problem_outlined, color: Colors.indigo[700]),
                const SizedBox(width: 8),
                Text('NC Categories', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => _showCategoryDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('Add Category', style: GoogleFonts.outfit()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(color: Colors.indigo),
          // Info banner
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Categories with "Workmanship Penalty" enabled will contribute to the Workmanship Assessment Score in Excel reports.',
                    style: GoogleFonts.outfit(fontSize: 12, color: Colors.blue[800]),
                  ),
                ),
              ],
            ),
          ),
          // List
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: _firestore.doc(_docPath).snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = List<Map<String, dynamic>>.from(
                  ((snap.data?.data() as Map<String, dynamic>?)?['items'] as List<dynamic>? ?? [])
                      .map((e) => Map<String, dynamic>.from(e as Map)),
                );
                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.category_outlined, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 8),
                        Text('No categories yet. Add one above.',
                            style: GoogleFonts.outfit(color: Colors.grey[500])),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final item = items[i];
                    final isWorkman = item['is_workman_penalty'] == true;
                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isWorkman ? Colors.orange.shade50 : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.report_problem_outlined,
                            color: isWorkman ? Colors.orange[700] : Colors.blue[700],
                            size: 20,
                          ),
                        ),
                        title: Text(item['name']?.toString() ?? '', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                        subtitle: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isWorkman ? Colors.orange.shade100 : Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isWorkman ? 'Workmanship Penalty' : 'Standard',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  color: isWorkman ? Colors.orange[800] : Colors.blue[800],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => _showCategoryDialog(existing: item),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              color: Colors.grey[600],
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              onPressed: () => _deleteCategory(item, items),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              color: Colors.red[400],
                              tooltip: 'Delete',
                            ),
                          ],
                        ),
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
}
