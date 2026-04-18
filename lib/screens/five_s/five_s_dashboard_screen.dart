import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:riqma_webapp/screens/five_s/five_s_form_screen.dart';
import 'package:riqma_webapp/screens/five_s/five_s_reports_screen.dart';

class FiveSDashboardScreen extends StatelessWidget {
  const FiveSDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '5S Management System',
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Section: Stats
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Total 5S Audits',
                    FirebaseFirestore.instance.collection('five_s_submissions').snapshots(),
                    (snapshot) => snapshot.docs.length.toString(),
                    Colors.blue,
                    Icons.assignment_turned_in_rounded,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    'Avg Score',
                    FirebaseFirestore.instance.collection('five_s_submissions').snapshots(),
                    (snapshot) {
                      if (snapshot.docs.isEmpty) {
                        return '0%';
                      }
                      double totalScore = 0;
                      for (final doc in snapshot.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        totalScore += (data['total_score'] as num? ?? 0).toDouble();
                      }
                      return '${(totalScore / snapshot.docs.length).toStringAsFixed(1)}%';
                    },
                    Colors.green,
                    Icons.score_rounded,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    'Pending Actions',
                    FirebaseFirestore.instance
                        .collection('five_s_submissions')
                        .where('status', isEqualTo: 'pending') // Assuming 'pending' status exists
                        .snapshots(),
                    (snapshot) => snapshot.docs.length.toString(),
                    Colors.orange,
                    Icons.pending_actions_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            
            // Middle Section: Navigation Buttons
            Text(
              'Actions',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1F36),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildActionCard(
                    context,
                    'Conduct New 5S Audit',
                    'Start a new audit checklist for a specific area.',
                    Icons.playlist_add_rounded,
                    Colors.blueAccent,
                    () => Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(builder: (context) => const FiveSFormScreen()),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _buildActionCard(
                    context,
                    '5S Audit History',
                    'View past audit reports and performance trends.',
                    Icons.history_rounded,
                    Colors.purpleAccent,
                    () => Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(builder: (context) => const FiveSReportsScreen()),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    Stream<QuerySnapshot> stream,
    String Function(QuerySnapshot) valueBuilder,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('Error');
              }
              if (!snapshot.hasData) {
                return const Text('...');
              }
              return Text(
                valueBuilder(snapshot.data!),
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1F36),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context,
    String title,
    String description,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 200,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color.withValues(alpha: 0.8)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
