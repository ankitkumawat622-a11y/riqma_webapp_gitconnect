import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:riqma_webapp/widgets/modern_searchable_dropdown.dart';
import 'package:url_launcher/url_launcher.dart';

class TrainingMaterialsTab extends StatefulWidget {
  const TrainingMaterialsTab({super.key});

  @override
  State<TrainingMaterialsTab> createState() => _TrainingMaterialsTabState();
}

class _TrainingMaterialsTabState extends State<TrainingMaterialsTab> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddMaterialDialog,
        backgroundColor: const Color(0xFF1A1F36),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          'Add Material',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('training_materials')
            .orderBy('uploadedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open_rounded, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No training materials yet',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 400,
              childAspectRatio: 1.5,
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
            ),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              return _buildMaterialCard(data);
            },
          );
        },
      ),
    );
  }

  Widget _buildMaterialCard(Map<String, dynamic> data) {
    final type = data['type'] ?? 'Other';
    final IconData icon;
    final Color color;

    switch (type) {
      case 'Video':
        icon = Icons.play_circle_outline_rounded;
        color = Colors.red;
        break;
      case 'PDF':
        icon = Icons.picture_as_pdf_rounded;
        color = Colors.orange;
        break;
      default:
        icon = Icons.description_rounded;
        color = Colors.blue;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: InkWell(
        onTap: () async {
          final String? url = data['link']?.toString();
          if (url != null && await canLaunchUrl(Uri.parse(url))) {
            await launchUrl(Uri.parse(url));
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not launch URL')),
              );
            }
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const Spacer(),
                  Text(
                    type.toString(),
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                (data['title'] ?? 'Untitled').toString(),
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1F36),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  (data['description'] ?? '').toString(),
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(
                    data['uploadedAt'] != null
                        ? DateFormat('MMM d, yyyy').format((data['uploadedAt'] as Timestamp).toDate())
                        : 'Unknown date',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddMaterialDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final linkController = TextEditingController();
    String selectedType = 'Video';

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Add Training Material', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: linkController,
                  decoration: InputDecoration(
                    labelText: 'Link (URL)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                ModernSearchableDropdown(
                  label: 'Type',
                  value: selectedType,
                  items: const {
                    'Video': 'Video',
                    'PDF': 'PDF',
                    'Other': 'Other'
                  },
                  color: Colors.indigo,
                  icon: Icons.type_specimen_rounded,
                  onChanged: (value) => setState(() => selectedType = value!),
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
                if (titleController.text.isEmpty || linkController.text.isEmpty) {
                  return;
                }

                try {
                  await FirebaseFirestore.instance.collection('training_materials').add({
                    'title': titleController.text,
                    'description': descriptionController.text,
                    'link': linkController.text,
                    'type': selectedType,
                    'uploadedAt': FieldValue.serverTimestamp(),
                  });
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1F36),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Add Material', style: GoogleFonts.outfit(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
