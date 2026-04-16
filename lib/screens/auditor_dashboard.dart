import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'auditor_self_review_screen.dart';

class AuditorDashboardScreen extends StatelessWidget {
  final List<String>? statusFilter;
  
  const AuditorDashboardScreen({super.key, this.statusFilter});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    
    // Determine status filter for query
    final List<String> queryStatusFilter = statusFilter ?? ['pending_self_review', 'correction'];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Pending Review',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: Colors.white,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF57C00), Color(0xFFEF6C00)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Container(
        color: const Color(0xFFF7F9FC),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('audit_submissions')
                        .where('auditor_id', isEqualTo: currentUserId)
                        .where('status', whereIn: queryStatusFilter)
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: Color(0xFFF57C00)),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Error loading audits',
                                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.red[700]),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 48),
                                child: Text(
                                  snapshot.error.toString(),
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey[500]),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.check_circle_outline, size: 56, color: Colors.green[300]),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'No Pending Reviews',
                                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w600, color: const Color(0xFF1A1F36)),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'All audits have been reviewed!',
                                style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey[500]),
                              ),
                            ],
                          ),
                        );
                      }

                      return SingleChildScrollView(
                        child: SizedBox(
                          width: double.infinity,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              const Color(0xFF1A1F36),
                            ),
                            headingTextStyle: GoogleFonts.outfit(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.white,
                            ),
                            dataTextStyle: GoogleFonts.outfit(
                              fontSize: 14,
                              color: const Color(0xFF2D3447),
                            ),
                            dataRowColor: WidgetStateProperty.resolveWith<Color?>(
                              (Set<WidgetState> states) {
                                if (states.contains(WidgetState.hovered)) {
                                  return const Color(0xFFF0F7FF);
                                }
                                return null;
                              },
                            ),
                            columnSpacing: 32,
                            horizontalMargin: 28,
                            headingRowHeight: 52,
                            dataRowMinHeight: 56,
                            dataRowMaxHeight: 64,
                            dividerThickness: 0.5,
                            columns: const [
                              DataColumn(label: Text('Site Name')),
                              DataColumn(label: Text('Turbine Name')),
                              DataColumn(label: Text('Audit Date')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Action')),
                            ],
                            rows: snapshot.data!.docs.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final String siteName = (data['site'] ?? 'N/A').toString();
                              final String turbineName = (data['turbine'] ?? 'N/A').toString();
                              final dynamic auditDate = data['timestamp'];
                              final String status = (data['status'] ?? 'Unknown').toString();

                              String formattedDate = 'N/A';
                              if (auditDate != null) {
                                if (auditDate is Timestamp) {
                                  formattedDate = DateFormat('MMM dd, yyyy').format(auditDate.toDate());
                                } else if (auditDate is String) {
                                  formattedDate = auditDate;
                                }
                              }

                              // Status badge config
                              final bool isCorrection = status == 'correction';
                              final Color statusFg = isCorrection ? const Color(0xFFB91C1C) : const Color(0xFFC2410C);
                              final Color statusBg = isCorrection ? const Color(0xFFFEE2E2) : const Color(0xFFFFF7ED);
                              final String statusLabel = isCorrection ? 'CORRECTION' : status.replaceAll('_', ' ').toUpperCase();

                              return DataRow(
                                cells: [
                                  DataCell(Text(siteName, style: GoogleFonts.outfit(fontWeight: FontWeight.w500))),
                                  DataCell(Text(turbineName)),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.calendar_today_rounded, size: 13, color: Colors.grey[400]),
                                        const SizedBox(width: 6),
                                        Text(formattedDate),
                                      ],
                                    ),
                                  ),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: statusBg,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: statusFg.withValues(alpha: 0.2)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 6, height: 6,
                                            decoration: BoxDecoration(color: statusFg, shape: BoxShape.circle),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            statusLabel,
                                            style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600, color: statusFg),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (context) => AuditorSelfReviewScreen(
                                              documentId: doc.id,
                                              auditData: data,
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.visibility_outlined, size: 15),
                                      label: Text('Review', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF0D7377),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
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
            ),
          ],
        ),
      ),
    );
  }
}
