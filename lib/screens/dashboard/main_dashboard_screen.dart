import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:riqma_webapp/screens/dashboard/analytics_section.dart';
import 'package:riqma_webapp/screens/dashboard/approved_plans_dashboard.dart';
import 'package:riqma_webapp/screens/five_s/five_s_dashboard_screen.dart';
import 'package:riqma_webapp/screens/kaizen/kaizen_training_dashboard.dart';
import 'package:riqma_webapp/screens/reports/final_reports_screen.dart';

class MainDashboardScreen extends StatefulWidget {
  final void Function(int index, String? statusFilter)? onNavigateToTab;

  const MainDashboardScreen({super.key, this.onNavigateToTab});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overview',
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A1F36),
            ),
          ),
          const SizedBox(height: 24),
          _buildStatsRow(),
          const SizedBox(height: 32),
          Text(
            'Quick Actions',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A1F36),
            ),
          ),
          const SizedBox(height: 16),
          _buildQuickActionsRow(),
          const SizedBox(height: 32),
          Text(
            'Analytics',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A1F36),
            ),
          ),
          const SizedBox(height: 16),
          _buildAnalyticsPlaceholder(),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            title: 'Total Planned SQA',
            stream: FirebaseFirestore.instance
                .collection('planning_data')
                .where('status', isEqualTo: 'approved')
                .snapshots(),
            countBuilder: (snapshot) => snapshot.docs.length.toString(),
            color: Colors.blueAccent,
            icon: Icons.calendar_today_rounded,
            onTap: () => _showApprovedPlansDashboard(context),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            title: 'Total SQA Completed',
            stream: FirebaseFirestore.instance
                .collection('audit_submissions')
                .where('status', isEqualTo: 'approved')
                .snapshots(),
            countBuilder: (snapshot) => snapshot.docs.length.toString(),
            color: Colors.green,
            icon: Icons.check_circle_outline_rounded,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            title: 'Pending Review',
            stream: FirebaseFirestore.instance
                .collection('audit_submissions')
                .where('status',
                    whereIn: ['pending', 'pending_manager_approval', 'pending_2', 'pending_3', 'pending_4', 'correction']).snapshots(),
            countBuilder: (snapshot) => snapshot.docs.length.toString(),
            color: Colors.orange,
            icon: Icons.pending_actions_rounded,
            onTap: () {
              widget.onNavigateToTab?.call(1, 'pending_group');
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            title: 'Final Reports',
            stream: FirebaseFirestore.instance
                .collection('audit_submissions')
                .where('status', isEqualTo: 'approved')
                .snapshots(),
            countBuilder: (snapshot) => snapshot.docs.length.toString(),
            color: Colors.purple,
            icon: Icons.assignment_turned_in_rounded,
            onTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const FinalReportsScreen()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required Stream<QuerySnapshot> stream,
    required String Function(QuerySnapshot) countBuilder,
    required Color color,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                if (onTap != null)
                  Icon(Icons.arrow_forward_rounded, color: Colors.grey[400], size: 20),
              ],
            ),
            const SizedBox(height: 24),
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
                  countBuilder(snapshot.data!),
                  style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1F36),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildActionCard(
            'Kaizen & Training',
            Icons.model_training_rounded,
            Colors.blue,
            onTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const KaizenTrainingDashboard()),
              );
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildActionCard(
            '5S Audit',
            Icons.cleaning_services_rounded,
            Colors.orange,
            onTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const FiveSDashboardScreen()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard(String title, IconData icon, Color color, {VoidCallback? onTap, bool isComingSoon = false}) {
    return InkWell(
      onTap: onTap ?? () {
        if (isComingSoon) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$title Coming Soon!', style: GoogleFonts.outfit()),
              backgroundColor: const Color(0xFF1A1F36),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (onTap != null) {
          onTap();
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 120,
        padding: const EdgeInsets.all(24),
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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsPlaceholder() {
    return const AnalyticsSection();
  }

  void _showApprovedPlansDashboard(BuildContext context) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (context) => const ApprovedPlansDashboard()),
    );
  }
}
