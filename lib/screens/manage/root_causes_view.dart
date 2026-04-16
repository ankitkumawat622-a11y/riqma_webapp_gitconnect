import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Admin view for managing Root Causes stored in audit_configs/root_causes.
/// Each item: { "id": "RC_001", "label": "Material Not available", "is_material": true }
class RootCausesView extends StatefulWidget {
  const RootCausesView({super.key});

  @override
  State<RootCausesView> createState() => _RootCausesViewState();
}

class _RootCausesViewState extends State<RootCausesView> {
  final _firestore = FirebaseFirestore.instance;
  static const _docPath = 'audit_configs/root_causes';
  bool _isLoading = false;

  Future<void> _showRootCauseDialog({Map<String, dynamic>? existing}) async {
    final idController = TextEditingController(text: existing?['id']?.toString() ?? '');
    final labelController = TextEditingController(text: existing?['label']?.toString() ?? '');
    bool isMaterial = existing?['is_material'] == true;
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.analytics_outlined, color: Colors.teal[700]),
            const SizedBox(width: 8),
            Text(
              existing == null ? 'Add Root Cause' : 'Edit Root Cause',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (existing == null)
                TextFormField(
                  controller: idController,
                  decoration: InputDecoration(
                    labelText: 'ID (e.g. RC_001)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  style: GoogleFonts.outfit(),
                  validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                ),
              if (existing == null) const SizedBox(height: 12),
              TextFormField(
                controller: labelController,
                decoration: InputDecoration(
                  labelText: 'Root Cause Label',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                style: GoogleFonts.outfit(),
                validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              StatefulBuilder(
                builder: (context, setCheckState) => CheckboxListTile(
                  title: Text('Is Material Related?', style: GoogleFonts.outfit(fontSize: 14)),
                  subtitle: Text('Enables PI Number & Date fields in Action Plan', style: GoogleFonts.outfit(fontSize: 11)),
                  value: isMaterial,
                  onChanged: (val) => setCheckState(() => isMaterial = val ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
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

                if (existing != null) {
                  final idx = items.indexWhere((e) => (e as Map)['id'] == existing['id']);
                  if (idx >= 0) {
                    items[idx] = {
                      'id': existing['id'], 
                      'label': labelController.text.trim(),
                      'is_material': isMaterial,
                    };
                  }
                } else {
                  items.add({
                    'id': idController.text.trim(), 
                    'label': labelController.text.trim(),
                    'is_material': isMaterial,
                  });
                }

                await docRef.set({'items': items}, SetOptions(merge: true));
                if (mounted) {
                  messenger.showSnackBar(const SnackBar(content: Text('Root Cause saved')));
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
              backgroundColor: Colors.teal[700],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRootCause(Map<String, dynamic> item, List<dynamic> currentItems) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Root Cause', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text('Delete "${item['label']}"? This cannot be undone.', style: GoogleFonts.outfit()),
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
        ..removeWhere((e) => (e as Map)['id'] == item['id']);
      await _firestore.doc(_docPath).set({'items': updatedItems}, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Root Cause deleted')));
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
                Icon(Icons.analytics_outlined, color: Colors.teal[700]),
                const SizedBox(width: 8),
                Text('Root Causes', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => _showRootCauseDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('Add Root Cause', style: GoogleFonts.outfit()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(color: Colors.teal),
          const SizedBox(height: 8),
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
                        Icon(Icons.analytics_outlined, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 8),
                        Text('No root causes yet. Add one above.',
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
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: GoogleFonts.outfit(color: Colors.teal[700], fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(item['label']?.toString() ?? '', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          'ID: ${item['id']?.toString() ?? '-'}',
                          style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey[500]),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item['is_material'] == true)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Icon(Icons.inventory_2_outlined, size: 16, color: Colors.orange[300]),
                              ),
                            IconButton(
                              onPressed: () => _showRootCauseDialog(existing: item),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              color: Colors.grey[600],
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              onPressed: () => _deleteRootCause(item, items),
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
