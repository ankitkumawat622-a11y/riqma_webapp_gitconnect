import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:riqma_webapp/screens/activity_log_screen.dart';
import 'package:riqma_webapp/screens/auditor_dashboard.dart';
import 'package:riqma_webapp/screens/dashboard/analytics_section.dart';
import 'package:riqma_webapp/screens/five_s/five_s_dashboard_screen.dart';
import 'package:riqma_webapp/screens/kaizen/kaizen_training_dashboard.dart';
import 'package:riqma_webapp/screens/reports/final_reports_screen.dart';
import 'package:riqma_webapp/widgets/glass_dialog_wrapper.dart';
import 'package:riqma_webapp/widgets/selection_step_card.dart';

class AuditorMainDashboardScreen extends StatefulWidget {
  const AuditorMainDashboardScreen({super.key});

  @override
  State<AuditorMainDashboardScreen> createState() => _AuditorMainDashboardScreenState();
}

class _AuditorMainDashboardScreenState extends State<AuditorMainDashboardScreen> {
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;
  String? get _currentUserEmail => FirebaseAuth.instance.currentUser?.email;

  /// Maps auditor email to display name
  String _getAuditorName(String? email) {
    if (email == null || email.isEmpty) {
      return 'Auditor';
    }
    
    // Email to Name mapping
    const Map<String, String> emailNameMap = {
      '2164@renom.com': 'Ankit Kumawat',
      '0722@renom.com': 'Shankar Game',
    };
    
    // Check if email exists in map
    if (emailNameMap.containsKey(email.toLowerCase())) {
      return emailNameMap[email.toLowerCase()]!;
    }
    
    // Fallback: Return username part (before @)
    final atIndex = email.indexOf('@');
    if (atIndex > 0) {
      return email.substring(0, atIndex);
    }
    return email;
  }

  void _showAddPlanDialog(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    // Show loading while fetching user details
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    ));

    String? assignedState;
    String? assignedStateId;
    String? auditorName;
    
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        assignedState = data['assigned_state']?.toString();
        final role = data['role']?.toString();
        assignedStateId = data['assigned_state_id']?.toString();
        auditorName = _getAuditorName(user.email);

        // Safety recovery for state ID if it's missing in the user document
        if (assignedStateId == null && assignedState != null && assignedState.isNotEmpty) {
           try {
             final stateQ = await FirebaseFirestore.instance
                 .collection('states')
                 .where('state', isEqualTo: assignedState)
                 .limit(1)
                 .get();
             if (stateQ.docs.isNotEmpty) {
               assignedStateId = stateQ.docs.first.id;
             }
           } catch (e) {
             debugPrint('Error fetching state ID: $e');
           }
        }

        if (context.mounted) Navigator.pop(context); // Close loading

        // Bypass check if Manager/Admin
        final bool isAuditor = (role == 'auditor' || role == null);
        
        // Final fallback if assignedStateId is still null but we have a name (for newly assigned users)
        if (assignedStateId == null && assignedState != null && assignedState.isNotEmpty) {
           final statesSnap = await FirebaseFirestore.instance.collection('states').get();
           for (var doc in statesSnap.docs) {
             if ((doc.data())['state']?.toString() == assignedState) {
               assignedStateId = doc.id;
               break;
             }
           }
        }

        if (isAuditor && (assignedState == null || assignedState.isEmpty || assignedStateId == null)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You do not have an assigned state ID. Please contact admin to refresh your profile.')),
            );
          }
          return;
        }

        if (!context.mounted) return;

        // Show Form Dialog
        unawaited(showDialog<void>(
          context: context,
          builder: (context) => _PlanAuditDialog(
            auditorId: user.uid,
            auditorName: auditorName ?? 'Unknown Auditor',
            assignedState: assignedState ?? 'Admin',
            assignedStateId: assignedStateId,
            role: role,
          ),
        ));
        return;
      } else {
        if (context.mounted) Navigator.pop(context);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User profile not found.')));
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error fetching user profile: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auditorName = _getAuditorName(_currentUserEmail);
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1F36)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(
            height: 2,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0D7377), Color(0xFF3B82F6), Color(0xFFA855F7)],
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 30.0),
              child: Image.asset(
                'assets/images/riqma_logo.png',
                height: 68,
                fit: BoxFit.contain,
              ),
            ),
            const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0D7377), Color(0xFF3B82F6)],
                    ),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF0D7377).withValues(alpha: 0.3), blurRadius: 8),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white,
                    child: Text(
                      auditorName.isNotEmpty ? auditorName[0].toUpperCase() : 'A',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: const Color(0xFF0D7377),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  auditorName,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: const Color(0xFF1A1F36),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          _buildAppBarAction(
            icon: Icons.add_circle_outline_rounded,
            label: 'Plan Audit',
            color: const Color(0xFF0D7377),
            onPressed: () => _showAddPlanDialog(context),
          ),
          const SizedBox(width: 4),
          _buildAppBarIcon(Icons.cleaning_services_outlined, '5S Checklist', () {
            Navigator.push<void>(context, MaterialPageRoute<void>(builder: (context) => const FiveSDashboardScreen()));
          }),
          _buildAppBarIcon(Icons.lightbulb_outline, 'Kaizen', () {
            Navigator.push<void>(context, MaterialPageRoute<void>(builder: (context) => const KaizenTrainingDashboard(initialIndex: 1)));
          }),
          _buildAppBarIcon(Icons.school_outlined, 'Training', () {
            Navigator.push<void>(context, MaterialPageRoute<void>(builder: (context) => const KaizenTrainingDashboard(initialIndex: 0)));
          }),
          _buildAppBarIcon(Icons.widgets_outlined, 'Other Services', () {}),
          const SizedBox(width: 4),
          _buildAppBarIcon(Icons.history_rounded, 'Activity Log', () {
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  appBar: AppBar(
                    title: Text('My Activity', style: GoogleFonts.outfit(color: const Color(0xFF1A1F36), fontWeight: FontWeight.bold)),
                    backgroundColor: Colors.white,
                    elevation: 0,
                    scrolledUnderElevation: 1,
                    iconTheme: const IconThemeData(color: Color(0xFF1A1F36)),
                  ),
                  body: const ActivityLogScreen(),
                ),
              ),
            );
          }),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              icon: Icon(Icons.logout_rounded, color: Colors.grey[500]),
              tooltip: 'Logout',
              style: IconButton.styleFrom(
                backgroundColor: Colors.grey[100],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => FirebaseAuth.instance.signOut(),
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF7F9FC),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
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
              'My Analytics',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1F36),
              ),
            ),
            const SizedBox(height: 16),
            AnalyticsSection(auditorId: _currentUserId),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBarAction({required IconData icon, required String label, required Color color, required VoidCallback onPressed}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: color, size: 20),
        label: Text(label, style: GoogleFonts.outfit(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        style: TextButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildAppBarIcon(IconData icon, String tooltip, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        icon: Icon(icon, color: const Color(0xFF1A1F36), size: 22),
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final userId = _currentUserId;
    
    return Row(
      children: [
        Expanded(
          child: _buildMyPlannedCard(userId),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'My Completed',
            stream: FirebaseFirestore.instance
                .collection('audit_submissions')
                .where('auditor_id', isEqualTo: userId)
                .where('status', isEqualTo: 'approved')
                .snapshots(),
            countBuilder: (QuerySnapshot snapshot) => snapshot.docs.length.toString(),
            color: Colors.green,
            icon: Icons.check_circle_rounded,
            onTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (context) => FinalReportsScreen(auditorId: userId),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'Pending Reviews',
            stream: FirebaseFirestore.instance
                .collection('audit_submissions')
                .where('auditor_id', isEqualTo: userId)
                .where('status', isEqualTo: 'pending_self_review')
                .snapshots(),
            countBuilder: (QuerySnapshot snapshot) => snapshot.docs.length.toString(),
            color: Colors.orange,
            icon: Icons.pending_actions_rounded,
            onTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const AuditorDashboardScreen(statusFilter: ['pending_self_review'])),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'Corrections',
            stream: FirebaseFirestore.instance
                .collection('audit_submissions')
                .where('auditor_id', isEqualTo: userId)
                .where('status', isEqualTo: 'correction')
                .snapshots(),
            countBuilder: (QuerySnapshot snapshot) => snapshot.docs.length.toString(),
            color: Colors.red,
            icon: Icons.error_outline_rounded,
            onTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const AuditorDashboardScreen(statusFilter: ['correction'])),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMyPlannedCard(String? userId) {
    const Color color = Colors.blueAccent;
    const IconData icon = Icons.calendar_today_rounded;

    return _HoverScaleCard(
      onTap: () async {
        if (userId == null) return;
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
        if (!mounted) return;
        final userData = userDoc.data();
        final assignedState = userData?['assigned_state'] as String?;
        final role = userData?['role'] as String?;
        final bool isAuditor = (role == 'auditor' || role == null);

        if (assignedState != null && assignedState.isNotEmpty) {
          unawaited(Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (context) => AuditorMyPlansScreen(auditorId: userId, assignedState: assignedState),
            ),
          ));
        } else if (!isAuditor) {
           // Manager/Admin without state can see all (fallback to "Admin" or similar if needed by destination screen)
           unawaited(Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (context) => AuditorMyPlansScreen(auditorId: userId, assignedState: 'Admin'),
            ),
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No assigned state found for this user.')),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 3,
              width: 40,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.4)]),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(icon, color: color, size: 20),
                ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.arrow_forward_rounded, color: Colors.grey[400], size: 16),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<DocumentSnapshot>(
              future: userId != null
                  ? FirebaseFirestore.instance.collection('users').doc(userId).get()
                  : null,
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return Text('...', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold));
                }
                if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                  return Text('0', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: const Color(0xFF1A1F36)));
                }
                final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                final assignedState = userData?['assigned_state'] as String?;
                final role = userData?['role'] as String?;
                final bool isAuditor = (role == 'auditor' || role == null);

                if (isAuditor && (assignedState == null || assignedState.isEmpty)) {
                  return Text('0', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: const Color(0xFF1A1F36)));
                }

                Query query = FirebaseFirestore.instance.collection('planning_data');
                // Only filter by state if auditor OR if a specific state is assigned to manager
                if (assignedState != null && assignedState != 'Admin') {
                  query = query.where('state', isEqualTo: assignedState);
                }
                
                return StreamBuilder<QuerySnapshot>(
                  stream: query.where('status', isEqualTo: 'approved').snapshots(),
                  builder: (context, planningSnapshot) {
                    if (planningSnapshot.connectionState == ConnectionState.waiting) {
                      return Text('...', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold));
                    }
                    if (!planningSnapshot.hasData || planningSnapshot.data!.docs.isEmpty) {
                      return Text('0', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: const Color(0xFF1A1F36)));
                    }
                    int totalTurbines = 0;
                    for (var doc in planningSnapshot.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final turbines = data['number_of_turbines'];
                      if (turbines is int) {
                        totalTurbines += turbines;
                      } else if (turbines is String) {
                        totalTurbines += int.tryParse(turbines) ?? 0;
                      }
                    }
                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: totalTurbines.toDouble()),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOutCubic,
                      builder: (context, val, _) => Text(
                        val.toInt().toString(),
                        style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: const Color(0xFF1A1F36)),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 4),
            Text(
              'My Planned',
              style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey[500], fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
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
    return _HoverScaleCard(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Accent stripe
            Container(
              height: 3,
              width: 40,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.4)]),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                if (onTap != null)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.arrow_forward_rounded, color: Colors.grey[400], size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Text('Error');
                if (!snapshot.hasData) return Text('...', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold));
                final value = countBuilder(snapshot.data!);
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: double.tryParse(value) ?? 0),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (context, val, _) => Text(
                    val.toInt().toString(),
                    style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: const Color(0xFF1A1F36)),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey[500], fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsRow() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                'My Audits',
                'View all pending and correction audits',
                Icons.assignment_rounded,
                Colors.indigo,
                onTap: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(builder: (context) => const AuditorDashboardScreen(statusFilter: <String>['pending_self_review', 'correction'])),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildActionCard(
                'My Reports',
                'View your approved audit reports',
                Icons.description_rounded,
                Colors.purple,
                onTap: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => FinalReportsScreen(auditorId: _currentUserId),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard(
    String title,
    String description,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return _HoverScaleCard(
      onTap: onTap,
      child: Container(
        height: 140,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color.withValues(alpha: 0.7)],
            stops: const [0.0, 1.0],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: GoogleFonts.outfit(fontSize: 12, color: Colors.white.withValues(alpha: 0.9)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withValues(alpha: 0.6), size: 18),
          ],
        ),
      ),
    );
  }
}

class _PlanAuditDialog extends StatefulWidget {
  final String auditorId;
  final String auditorName;
  final String assignedState;
  final String? assignedStateId;
  final String? role;
  final String? planId; // For editing
  final Map<String, dynamic>? initialData; // For editing

  const _PlanAuditDialog({
    required this.auditorId,
    required this.auditorName,
    required this.assignedState,
    this.assignedStateId,
    this.role,
    this.planId,
    this.initialData,
  });

  @override
  State<_PlanAuditDialog> createState() => _PlanAuditDialogState();
}

class _PlanAuditDialogState extends State<_PlanAuditDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedState;
  String? _selectedStateId;
  String? _selectedSite;
  String? _selectedSiteId;
  String? _assignedStateId; // Local state for State ID
  DateTime? _selectedDate;
  String? _selectedModel;
  String? _selectedModelId;
  
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _availableModels = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  bool _loadingModels = false;
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    
    final bool isAuditor = (widget.role == 'auditor' || widget.role == null);

    if (widget.initialData != null) {
      _selectedSite = widget.initialData!['site_name']?.toString();
      // Try to recover IDs if they were stored (for editing older records they might be missing refs)
      // Getting IDs from refs requires parsing or storing them.
      // For now, if editing, we might need to rely on re-selection if IDs are missing.
      // Or we check if 'site_ref' exists:
      if (widget.initialData!['site_ref'] is DocumentReference) {
        _selectedSiteId = (widget.initialData!['site_ref'] as DocumentReference).id;
      }
      
      if (widget.initialData!['state_ref'] is DocumentReference) {
        _assignedStateId = (widget.initialData!['state_ref'] as DocumentReference).id;
        _selectedStateId = _assignedStateId;
        _selectedState = widget.initialData!['state']?.toString();
      }

      final plannedDate = widget.initialData!['planned_date'];
      if (plannedDate != null && plannedDate is Timestamp) {
        _selectedDate = plannedDate.toDate();
      }
      
      _selectedModel = widget.initialData!['turbine_model']?.toString();
      if (widget.initialData!['turbinemodel_ref'] is DocumentReference) {
        _selectedModelId = (widget.initialData!['turbinemodel_ref'] as DocumentReference).id;
      }
    } else {
      // New Plan
      if (isAuditor && widget.assignedStateId != null) {
        _selectedStateId = widget.assignedStateId;
        _selectedState = widget.assignedState;
        _assignedStateId = widget.assignedStateId;
      }
    }
    
    // Initial fetch if we have a site ID
    if (_selectedSiteId != null) {
      _fetchModelsForSite(_selectedSiteId!);
    }
    
    // If not found in initialData (or if new), use widget param
    _assignedStateId ??= widget.assignedStateId;
  }
  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _fetchModelsForSite(String siteId) async {
    setState(() => _loadingModels = true);
    try {
      final QuerySnapshot<Map<String, dynamic>> query = await FirebaseFirestore.instance
          .collection('turbinemodel')
          .where('site_ids', arrayContainsAny: [
            siteId,
            FirebaseFirestore.instance.doc('/sites/$siteId')
          ])
          .get();

      if (mounted) {
        setState(() {
          _availableModels = query.docs;
          // Sort models
          _availableModels.sort((a, b) {
            final n1 = a.data()['name'] ?? '';
            final n2 = b.data()['name'] ?? '';
            return n1.toString().compareTo(n2.toString());
          });

          // Auto-select if only one model
          if (_availableModels.length == 1) {
             final data = _availableModels.first.data();
             _selectedModel = data['name'] as String?;
             _selectedModelId = _availableModels.first.id;
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching models: $e');
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _submitPlan() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedSite == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a site')));
      return;
    }
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a date')));
      return;
    }

    setState(() => _isLoading = true);

    if (_selectedModel == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a model')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Ensure we have IDs.
      // If user didn't re-select value, but we have _selectedSite/Model from init,
      // we might not have ID if initData didn't have refs. 
      // Force user to re-select if ID is missing?
      if (_selectedSiteId == null || _selectedModelId == null) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please re-select Site and Model to ensure data validity.')));
         setState(() => _isLoading = false);
         return;
      }

      // SAFETY FIX: If ID is missing but we have a name, fetch the ID
      if (_assignedStateId == null && widget.assignedState.isNotEmpty) {
        try {
          var stateQuery = await FirebaseFirestore.instance
              .collection('states')
              .where('state', isEqualTo: widget.assignedState)
              .limit(1)
              .get();
          if (stateQuery.docs.isNotEmpty) {
            _assignedStateId = stateQuery.docs.first.id;
            debugPrint("✅ Recovered State ID: $_assignedStateId");
          }
        } catch (e) {
             debugPrint("⚠️ Failed to recover State ID: $e");
        }
      }

      if (!mounted) {
        return;
      }

      // 6. Identification of State ID (Required for filtering)
      if (_assignedStateId == null && _selectedStateId != null) {
        _assignedStateId = _selectedStateId;
      }

      if (_assignedStateId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: State reference missing. Please re-select.')));
        setState(() => _isLoading = false);
        return;
      }

      final docData = {
        // 1. Auditor details
        'auditor_id': widget.auditorId,
        'auditor_name': widget.auditorName,
        'auditors': [widget.auditorName],

        // 2. Dates
        'planned_date': Timestamp.fromDate(_selectedDate!),
        if (widget.planId == null) 'created_at': FieldValue.serverTimestamp(),

        // 3. Location & References (Standardized for Global Alignment)
        'site_name': _selectedSite,
        'site_id': _selectedSiteId,
        'site_ref': FirebaseFirestore.instance.doc('/sites/$_selectedSiteId'),
        'state': _selectedState ?? widget.assignedState,
        'state_id': _assignedStateId,
        'state_ref': FirebaseFirestore.instance.doc('/states/$_assignedStateId'),

        // 4. Turbine Details
        'turbine_model': _selectedModel,
        'turbine_model_id': _selectedModelId,
        'turbinemodel_ref': FirebaseFirestore.instance.doc('/turbinemodel/$_selectedModelId'),
        'number_of_turbines': 1,

        // 5. Status
        'status': 'pending_approval',
      };

      if (widget.planId != null) {
        await FirebaseFirestore.instance.collection('planning_data').doc(widget.planId).update(docData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Plan updated successfully!'), backgroundColor: Colors.green),
          );
        }
      } else {
        await FirebaseFirestore.instance.collection('planning_data').add(docData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Plan submitted for approval!'), backgroundColor: Colors.green),
          );
        }
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isAuditor = (widget.role == 'auditor' || widget.role == null);
    final bool isEditing = widget.planId != null;

    return GlassDialogWrapper(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(32),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D7377).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF0D7377), size: 24),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEditing ? 'Update Audit Plan' : 'Plan New Audit',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1B1F3B),
                        ),
                      ),
                      Text(
                        'Step through to schedule your next turbine audit',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: Colors.grey[400]),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[100],
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Step 1: State Selection
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('states').snapshots(),
                builder: (context, snapshot) {
                  final states = snapshot.data?.docs ?? [];
                  final Map<String, String> stateMap = {
                    for (var doc in states)
                      doc.id: (doc.data() as Map<String, dynamic>)['state']?.toString() ?? 'Unknown'
                  };

                  return SelectionStepCard(
                    title: 'STATE / REGION',
                    value: _selectedState,
                    icon: Icons.map_outlined,
                    accentColor: Colors.indigo,
                    isLocked: isAuditor,
                    onTap: () {
                      showDialog<void>(
                        context: context,
                        builder: (c) => _SearchDialog(
                          title: 'State',
                          items: stateMap,
                          selectedValue: _selectedStateId,
                          onSelected: (id) {
                            if (isAuditor) return; // double safety
                            setState(() {
                              _selectedStateId = id;
                              _selectedState = stateMap[id];
                              _assignedStateId = id;
                              _selectedSite = null;
                              _selectedSiteId = null;
                              _selectedModel = null;
                              _selectedModelId = null;
                              _availableModels = [];
                            });
                          },
                        ),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 16),

              // Step 2: Site Selection
              AnimatedOpacity(
                opacity: _selectedStateId == null ? 0.5 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: StreamBuilder<QuerySnapshot>(
                  stream: _selectedStateId == null 
                      ? const Stream.empty() 
                      : FirebaseFirestore.instance
                          .collection('sites')
                          .where('state_ref', isEqualTo: FirebaseFirestore.instance.doc('/states/$_selectedStateId'))
                          .snapshots(),
                  builder: (context, snapshot) {
                    final sites = snapshot.data?.docs ?? [];
                    final Map<String, String> siteMap = {
                      for (var doc in sites)
                        doc.id: (doc.data() as Map<String, dynamic>)['site_name']?.toString() ?? 
                               (doc.data() as Map<String, dynamic>)['name']?.toString() ?? 'Unknown'
                    };

                    return SelectionStepCard(
                      title: 'SITE LOCATION',
                      value: _selectedSite,
                      icon: Icons.location_on_outlined,
                      accentColor: const Color(0xFF0D7377),
                      onTap: _selectedStateId == null ? () {} : () {
                        showDialog<void>(
                          context: context,
                          builder: (c) => _SearchDialog(
                            title: 'Site',
                            items: siteMap,
                            selectedValue: _selectedSiteId,
                            onSelected: (id) {
                              setState(() {
                                _selectedSiteId = id;
                                _selectedSite = siteMap[id];
                                _selectedModel = null;
                                _selectedModelId = null;
                                _availableModels = [];
                                _fetchModelsForSite(id);
                              });
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Step 3: Turbine Model
              AnimatedOpacity(
                opacity: _selectedSiteId == null ? 0.5 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: SelectionStepCard(
                  title: 'TURBINE MODEL',
                  value: _selectedModel,
                  icon: Icons.settings_input_component_outlined,
                  accentColor: Colors.amber[700]!,
                  isLoading: _loadingModels,
                  onTap: _selectedSiteId == null ? () {} : () {
                    final Map<String, String> modelMap = {
                      for (var doc in _availableModels)
                        doc.id: doc.data()['name']?.toString() ?? 'Unknown'
                    };
                    showDialog<void>(
                      context: context,
                      builder: (c) => _SearchDialog(
                        title: 'Model',
                        items: modelMap,
                        selectedValue: _selectedModelId,
                        onSelected: (id) {
                          setState(() {
                            _selectedModelId = id;
                            _selectedModel = modelMap[id];
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Step 4: Date
              SelectionStepCard(
                title: 'PLANNED DATE',
                value: _selectedDate == null ? null : DateFormat('EEEE, dd MMM yyyy').format(_selectedDate!),
                icon: Icons.calendar_month_outlined,
                accentColor: Colors.deepPurple,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: Color(0xFF0D7377),
                            onPrimary: Colors.white,
                            onSurface: Color(0xFF1B1F3B),
                          ),
                          textButtonTheme: TextButtonThemeData(
                            style: TextButton.styleFrom(foregroundColor: const Color(0xFF0D7377)),
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null) setState(() => _selectedDate = picked);
                },
              ),
              const SizedBox(height: 40),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey[600], fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitPlan,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B1F3B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(isEditing ? 'Save Changes' : 'Confirm & Schedule', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
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
}

/// Specialized internal search dialog for the premium picker flow
class _SearchDialog extends StatefulWidget {
  final String title;
  final Map<String, String> items;
  final String? selectedValue;
  final void Function(String id) onSelected;

  const _SearchDialog({
    required this.title,
    required this.items,
    this.selectedValue,
    required this.onSelected,
  });

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  late List<MapEntry<String, String>> _filteredItems;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items.entries.toList();
    _filteredItems.sort((a, b) => a.value.compareTo(b.value));
  }

  void _onSearch(String val) {
    setState(() {
      _filteredItems = widget.items.entries
          .where((e) => e.value.toLowerCase().contains(val.toLowerCase()))
          .toList();
      _filteredItems.sort((a, b) => a.value.compareTo(b.value));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 400,
        height: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                Text('Select ${widget.title}', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              onChanged: _onSearch,
              style: GoogleFonts.outfit(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: GoogleFonts.outfit(fontSize: 14, color: Colors.grey[400]),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredItems.length,
                itemBuilder: (c, i) {
                  final item = _filteredItems[i];
                  final isSel = item.key == widget.selectedValue;
                  return ListTile(
                    title: Text(item.value, style: GoogleFonts.outfit(fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                    trailing: isSel ? const Icon(Icons.check_circle, color: Color(0xFF0D7377)) : null,
                    onTap: () {
                      widget.onSelected(item.key);
                      Navigator.pop(context);
                    },
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    selected: isSel,
                    selectedTileColor: const Color(0xFF0D7377).withValues(alpha: 0.05),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuditorMyPlansScreen extends StatelessWidget {
  final String auditorId;
  final String assignedState;

  const AuditorMyPlansScreen({
    super.key, 
    required this.auditorId,
    required this.assignedState,
  });

  void _deletePlan(BuildContext context, String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Plan?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete this plan? This action cannot be undone.',
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: GoogleFonts.outfit(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('planning_data').doc(docId).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Plan deleted successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting plan: $e')),
        );
      }
    }
  }

  void _showEditDialog(BuildContext context, String docId, Map<String, dynamic> data) {
    final state = data['state'] as String? ?? '';
    final auditorName = data['auditor_name'] as String? ?? 'Auditor';

    showDialog<void>(
      context: context,
      builder: (context) => _PlanAuditDialog(
        auditorId: auditorId,
        auditorName: auditorName,
        assignedState: state,
        planId: docId,
        initialData: data,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Plans', style: GoogleFonts.outfit(color: const Color(0xFF1A1F36), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1F36)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(
            height: 2,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0D7377), Color(0xFF3B82F6), Color(0xFFA855F7)],
              ),
            ),
          ),
        ),
      ),
      backgroundColor: const Color(0xFFF7F9FC),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('planning_data')
            .where('state', isEqualTo: assignedState)
            .where('status', isEqualTo: 'approved')
            .orderBy('planned_date', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: SelectableText('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.event_note_rounded, size: 48, color: Colors.grey[300]),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No plans found',
                    style: GoogleFonts.outfit(fontSize: 18, color: Colors.grey[500], fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              
              final status = data['status'] ?? 'planned';
              final isPending = status == 'pending_approval';

              final timestamp = data['planned_date'] as Timestamp?;
              final dateStr = timestamp != null
                  ? DateFormat('dd MMM yyyy').format(timestamp.toDate())
                  : 'No Date';

              Color statusColor;
              String statusText;

              if (status == 'pending_approval') {
                statusColor = Colors.orange;
                statusText = 'Pending Approval';
              } else if (status == 'approved') {
                statusColor = Colors.blue;
                statusText = 'Approved';
              } else if (status == 'completed') {
                statusColor = Colors.green;
                statusText = 'Completed';
              } else {
                statusColor = Colors.grey;
                statusText = status.toString().toUpperCase();
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade100),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Left accent bar
                    Container(
                      width: 4,
                      height: 100,
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6, height: 6,
                                        decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        statusText,
                                        style: GoogleFonts.outfit(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isPending)
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF0D7377)),
                                        onPressed: () => _showEditDialog(context, doc.id, data),
                                        tooltip: 'Edit',
                                        style: IconButton.styleFrom(
                                          backgroundColor: const Color(0xFF0D7377).withValues(alpha: 0.08),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: Icon(Icons.delete_outline, size: 18, color: Colors.red[400]),
                                        onPressed: () => _deletePlan(context, doc.id),
                                        tooltip: 'Delete',
                                        style: IconButton.styleFrom(
                                          backgroundColor: Colors.red.withValues(alpha: 0.08),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${data['site_name'] ?? 'Unknown Site'} / ${data['turbine_model'] ?? 'Unknown Model'}',
                              style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: const Color(0xFF1A1F36)),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(Icons.calendar_today_rounded, size: 13, color: Colors.grey[400]),
                                const SizedBox(width: 6),
                                Text(
                                  dateStr,
                                  style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey[500], fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Hover-scale card wrapper with smooth animation
class _HoverScaleCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _HoverScaleCard({required this.child, this.onTap});

  @override
  State<_HoverScaleCard> createState() => _HoverScaleCardState();
}

class _HoverScaleCardState extends State<_HoverScaleCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovering ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: _hovering
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 28, offset: const Offset(0, 10))]
                  : [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
