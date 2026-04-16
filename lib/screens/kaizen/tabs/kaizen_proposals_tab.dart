import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class KaizenProposalsTab extends StatefulWidget {
  const KaizenProposalsTab({super.key});

  @override
  State<KaizenProposalsTab> createState() => _KaizenProposalsTabState();
}

class _KaizenProposalsTabState extends State<KaizenProposalsTab> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('kaizen_submissions')
            .orderBy('date', descending: true)
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
                  Icon(Icons.lightbulb_outline_rounded, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No Kaizen proposals yet',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(Colors.grey[50]),
                  dataRowMinHeight: 60,
                  dataRowMaxHeight: 80,
                  columns: [
                    DataColumn(label: Text('Date', style: GoogleFonts.outfit(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Auditor', style: GoogleFonts.outfit(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Title', style: GoogleFonts.outfit(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Status', style: GoogleFonts.outfit(fontWeight: FontWeight.bold))),
                  ],
                  rows: snapshot.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return DataRow(
                      onSelectChanged: (_) => _showProposalDetails(doc.id, data),
                      cells: [
                        DataCell(Text(
                          data['date'] != null
                              ? DateFormat('MMM d, yyyy').format((data['date'] as Timestamp).toDate())
                              : 'Unknown',
                          style: GoogleFonts.outfit(),
                        )),
                        DataCell(Text(
                          (data['auditorName'] ?? 'Unknown').toString(),
                          style: GoogleFonts.outfit(fontWeight: FontWeight.w500),
                        )),
                        DataCell(Text(
                          (data['title'] ?? 'Untitled').toString(),
                          style: GoogleFonts.outfit(),
                        )),
                        DataCell(_buildStatusBadge((data['status'] ?? 'Pending').toString())),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    Color textColor;
    switch (status.toLowerCase()) {
      case 'approved':
        color = Colors.green.withValues(alpha: 0.1);
        textColor = Colors.green;
        break;
      case 'rejected':
        color = Colors.red.withValues(alpha: 0.1);
        textColor = Colors.red;
        break;
      default:
        color = Colors.orange.withValues(alpha: 0.1);
        textColor = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: GoogleFonts.outfit(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  void _showProposalDetails(String docId, Map<String, dynamic> data) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 800,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Kaizen Proposal Details',
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A1F36),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailItem('Auditor', (data['auditorName'] ?? 'Unknown').toString()),
                        const SizedBox(height: 16),
                        _buildDetailItem('Title', (data['title'] ?? 'Untitled').toString()),
                        const SizedBox(height: 16),
                        _buildDetailItem('Benefits', (data['benefits'] ?? 'No benefits listed').toString()),
                      ],
                    ),
                  ),
                  const SizedBox(width: 32),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _buildPhotoCard('Before', data['beforePhotoUrl']?.toString())),
                        const SizedBox(width: 16),
                        Expanded(child: _buildPhotoCard('After', data['afterPhotoUrl']?.toString())),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              if (data['status'] == 'Pending' || data['status'] == null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => _updateStatus(docId, 'Rejected'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      ),
                      child: Text('Reject', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () => _updateStatus(docId, 'Approved'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      ),
                      child: Text('Approve', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 14,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 16,
            color: const Color(0xFF1A1F36),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoCard(String label, String? url) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          height: 150,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: url != null && url.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(url, fit: BoxFit.cover),
                )
              : Icon(Icons.image_not_supported_rounded, color: Colors.grey[400]),
        ),
      ],
    );
  }

  Future<void> _updateStatus(String docId, String status) async {
    try {
      await FirebaseFirestore.instance.collection('kaizen_submissions').doc(docId).update({
        'status': status,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating status: $e')),
        );
      }
    }
  }
}
