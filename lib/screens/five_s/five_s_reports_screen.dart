import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class FiveSReportsScreen extends StatelessWidget {
  const FiveSReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '5S Audit History',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1F36),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1F36)),
      ),
      backgroundColor: const Color(0xFFF7F9FC),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('five_s_submissions')
                .orderBy('timestamp', descending: true)
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
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_toggle_off_rounded, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                          'No audit history found',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF7F9FC)),
                    headingTextStyle: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A1F36),
                    ),
                    dataTextStyle: GoogleFonts.outfit(color: const Color(0xFF1A1F36)),
                    columns: const [
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Area / Zone')),
                      DataColumn(label: Text('Score')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: snapshot.data!.docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final timestamp = data['timestamp'] as Timestamp?;
                      final dateStr = timestamp != null
                          ? DateFormat('MMM dd, yyyy').format(timestamp.toDate())
                          : 'N/A';
                      final score = data['total_score'] ?? 0;
                      final maxScore = data['max_score'] ?? 1; // Avoid div by zero
                      final percentage = ((score / maxScore) * 100).toStringAsFixed(1);

                      return DataRow(
                        cells: [
                          DataCell(Text(dateStr)),
                          DataCell(Text((data['area'] ?? 'Unknown').toString())),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getScoreColor(double.parse(percentage.toString())).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$score / $maxScore ($percentage%)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _getScoreColor(double.parse(percentage.toString())),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                (data['status'] ?? 'Completed').toString().toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            IconButton(
                              icon: const Icon(Icons.visibility_rounded, color: Colors.blue),
                              onPressed: () {
                                // TODO: Implement detailed view
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Detailed view coming soon')),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Color _getScoreColor(double percentage) {
    if (percentage >= 80) {
      return Colors.green;
    }
    if (percentage >= 50) {
      return Colors.orange;
    }
    return Colors.red;
  }
}
