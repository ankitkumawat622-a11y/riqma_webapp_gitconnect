import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OthersConfigView extends StatefulWidget {
  const OthersConfigView({super.key});

  @override
  State<OthersConfigView> createState() => _OthersConfigViewState();
}

class _OthersConfigViewState extends State<OthersConfigView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;

  Future<void> _addItem(String docId, List<dynamic> currentItems) async {
    final TextEditingController idController = TextEditingController();
    final TextEditingController labelController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add New Option', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: idController,
                decoration: const InputDecoration(labelText: 'ID (Unique Keyword)', border: OutlineInputBorder()),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Required';
                  if (currentItems.any((item) => item['id'] == val)) return 'ID already exists';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: labelController,
                decoration: const InputDecoration(labelText: 'Display Label', border: OutlineInputBorder()),
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
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
              if (formKey.currentState!.validate()) {
                final newItem = {
                  'id': idController.text.trim(),
                  'label': labelController.text.trim(),
                };
                
                setState(() => _isLoading = true);
                Navigator.pop(context);

                try {
                  await _firestore.collection('audit_configs').doc(docId).set({
                    'items': FieldValue.arrayUnion([newItem]),
                  }, SetOptions(merge: true));
                } catch (e) {
                  _showError('Failed to add item: $e');
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _editItemLabel(String docId, List<dynamic> currentItems, Map<String, dynamic> itemToEdit) async {
    final TextEditingController labelController = TextEditingController(text: itemToEdit['label']?.toString() ?? '');
    
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Label', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${itemToEdit['id']}', style: GoogleFonts.outfit(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: labelController,
              decoration: const InputDecoration(labelText: 'Display Label', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newLabel = labelController.text.trim();
              if (newLabel.isEmpty || newLabel == itemToEdit['label']) {
                Navigator.pop(context);
                return;
              }

              setState(() => _isLoading = true);
              Navigator.pop(context);

              try {
                // To update an object in array, we remove the old and add the new
                final docRef = _firestore.collection('audit_configs').doc(docId);
                
                await _firestore.runTransaction((transaction) async {
                  final snap = await transaction.get(docRef);
                  if (snap.exists) {
                    final data = snap.data();
                    final List<dynamic> items = List<dynamic>.from((data?['items'] as List<dynamic>?) ?? []);
                    final index = items.indexWhere((i) => i['id'] == itemToEdit['id']);
                    if (index != -1) {
                      items[index]['label'] = newLabel;
                      transaction.update(docRef, {'items': items});
                    }
                  }
                });
              } catch (e) {
                _showError('Failed to edit item: $e');
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteItem(String docId, Map<String, dynamic> itemToDelete) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Item', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.red)),
        content: Text('Are you sure you want to delete "${itemToDelete['label']}"?\n\nWarning: Removing this may affect drop-down rendering in active audits.', style: GoogleFonts.outfit()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await _firestore.collection('audit_configs').doc(docId).update({
          'items': FieldValue.arrayRemove([itemToDelete]),
        });
      } catch (e) {
        _showError('Failed to delete item: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    }
  }

  Widget _buildSection(String title, String docId, String icon) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                ElevatedButton.icon(
                  onPressed: () async {
                    final snap = await _firestore.collection('audit_configs').doc(docId).get();
                    final items = snap.exists ? (snap.data()?['items'] as List<dynamic>? ?? <dynamic>[]) : <dynamic>[];
                    unawaited(_addItem(docId, items));
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add New'),
                  style: ElevatedButton.styleFrom(elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                )
              ],
            ),
            const Divider(height: 32),
            Expanded(
              child: StreamBuilder<DocumentSnapshot>(
                stream: _firestore.collection('audit_configs').doc(docId).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return const Center(child: Text('Error loading config'));
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  
                  final data = snapshot.data?.data() as Map<String, dynamic>?;
                  final List<dynamic> items = List<dynamic>.from(data?['items'] as List<dynamic>? ?? []);
                  
                  if (items.isEmpty) {
                     return const Center(child: Text('No items defined yet.'));
                  }

                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, i) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index] as Map<String, dynamic>;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade50,
                          child: Text(icon, style: const TextStyle(fontSize: 18)),
                        ),
                        title: Text(item['label']?.toString() ?? 'No Label', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                        subtitle: Text('ID: ${item['id']}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                              onPressed: () => _editItemLabel(docId, items, item),
                              tooltip: 'Edit Label',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _deleteItem(docId, item),
                              tooltip: 'Delete',
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSection('Maintenance Types', 'maintenance_types', '🔧'),
              const SizedBox(width: 24),
              _buildSection('Assessment Stages', 'assessment_stages', '⏱️'),
            ],
          ),
        ),
        if (_isLoading)
          Container(
            color: Colors.white.withValues(alpha: 0.5),
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
