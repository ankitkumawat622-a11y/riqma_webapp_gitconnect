import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:riqma_webapp/widgets/modern_searchable_dropdown.dart';

class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Filter States
  String? _selectedMonth;
  String? _selectedState;
  String? _selectedSite;
  String? _selectedStatus; // New Status Filter

  final List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _approvePlan(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('planning_data')
          .doc(docId)
          .update({'status': 'approved'});
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan Approved Successfully')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error approving plan: $e')),
      );
    }
  }

  Future<void> _rejectPlan(String docId) async {
    // Show Confirmation Dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reject Plan?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to reject this plan? This action cannot be undone.',
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), // Cancel
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true), // Confirm
            child: Text('Reject', style: GoogleFonts.outfit(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('planning_data').doc(docId).delete();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan rejected successfully')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error rejecting plan: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Uses MainLayout background
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('planning_data')
            .orderBy('planned_date', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data!.docs;

          // Process data for filters
          final Set<String> uniqueStates = {};
          final Set<String> uniqueSites = {};

          for (final doc in allDocs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['state'] != null) {
              uniqueStates.add(data['state'].toString());
            }
            // Only add sites if they match selected state (or if no state selected)
            if (_selectedState == null || 
                _selectedState == 'All States' || 
                data['state'] == _selectedState) {
               if (data['site_name'] != null) {
                 uniqueSites.add(data['site_name'].toString());
               }
            }
          }

          final List<String> statesList = ['All States', ...uniqueStates]..sort();

          final List<String> sitesList = ['All Sites', ...uniqueSites]..sort();

          // Filter Logic
          final filteredDocs = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            
            // Search Query
            final siteName = (data['site_name'] ?? '').toString().toLowerCase();
            final turbineId = (data['turbine_id'] ?? '').toString().toLowerCase();
            if (!siteName.contains(_searchQuery) && !turbineId.contains(_searchQuery)) {
              return false;
            }

            // Month Filter
            if (_selectedMonth != null && _selectedMonth != 'All Months') {
              final timestamp = data['planned_date'] as Timestamp?;
              if (timestamp != null) {
                final date = timestamp.toDate();
                final monthName = DateFormat('MMMM').format(date);
                if (monthName != _selectedMonth) {
                  return false;
                }
              }
            }

            // State Filter
            if (_selectedState != null && _selectedState != 'All States') {
              if (data['state'] != _selectedState) {
                return false;
              }
            }

            // Site Filter
            if (_selectedSite != null && _selectedSite != 'All Sites') {
              if (data['site_name'] != _selectedSite) {
                return false;
              }
            }

            // Status Filter
            if (_selectedStatus != null && _selectedStatus != 'All Statuses') {
              final status = (data['status'] ?? 'planned').toString();
              String displayStatus;
              if (status == 'pending_approval') {
                displayStatus = 'Pending Approval';
              } else if (status == 'approved') {
                displayStatus = 'Approved';
              } else if (status == 'completed') {
                displayStatus = 'Completed';
              } else {
                displayStatus = 'Others';
              }

              if (displayStatus != _selectedStatus) {
                return false;
              }
            }

            return true;
          }).toList();

          // Custom Sorting: Pending Approval -> Approved -> Completed -> Others
          filteredDocs.sort((a, b) {
            final dataA = a.data() as Map<String, dynamic>;
            final dataB = b.data() as Map<String, dynamic>;
            
            final statusA = (dataA['status'] ?? 'planned').toString();
            final statusB = (dataB['status'] ?? 'planned').toString();

            int getPriority(String status) {
              if (status == 'pending_approval') {
                return 0;
              }
              if (status == 'approved') {
                return 1;
              }
              if (status == 'completed') {
                return 2;
              }
              return 3;
            }

            return getPriority(statusA).compareTo(getPriority(statusB));
          });

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Combined Filter and Search Row
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  children: [
                    // Month Filter
                    Expanded(
                      flex: 2,
                      child: ModernSearchableDropdown(
                        label: 'Month',
                        value: _selectedMonth != 'All Months' ? _selectedMonth : null, // Handle 'All' logic
                        items: {
                          'All Months': 'All Months',
                          for (final m in _months) m: m,
                        },
                        color: Colors.blue,
                        icon: Icons.calendar_today_rounded,
                        onChanged: (val) => setState(() => _selectedMonth = val),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // State Filter
                    Expanded(
                      flex: 2,
                      child: ModernSearchableDropdown(
                        label: 'State',
                        value: _selectedState != 'All States' ? _selectedState : null,
                        items: {
                          for (final s in statesList) s: s,
                        },
                        color: Colors.orange,
                        icon: Icons.map_rounded,
                        onChanged: (val) {
                          setState(() {
                             _selectedState = val;
                             _selectedSite = null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Site Filter
                    Expanded(
                      flex: 2,
                      child: ModernSearchableDropdown(
                        label: 'Site',
                        value: _selectedSite != 'All Sites' ? _selectedSite : null,
                        items: {
                           for (final s in sitesList) s: s,
                        },
                        color: Colors.green,
                        icon: Icons.location_on_rounded,
                        onChanged: (val) => setState(() => _selectedSite = val),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Status Filter
                    Expanded(
                      flex: 2,
                      child: ModernSearchableDropdown(
                         label: 'Status',
                         value: _selectedStatus != 'All Statuses' ? _selectedStatus : null,
                         items: const {
                           'All Statuses': 'All Statuses',
                           'Pending Approval': 'Pending Approval',
                           'Approved': 'Approved',
                           'Completed': 'Completed'
                         },
                         color: Colors.purple,
                         icon: Icons.task_alt_rounded,
                         onChanged: (val) => setState(() => _selectedStatus = val),
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Search Bar (Right Side)
                    Expanded(
                      flex: 3,
                      child: Container(
                        height: 48, // Match dropdown height roughly
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardTheme.color,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.light ? 0.03 : 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value.toLowerCase();
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search plans...',
                            hintStyle: GoogleFonts.outfit(color: Colors.grey[400]),
                            prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[400]),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                          style: GoogleFonts.outfit(color: Theme.of(context).textTheme.bodyLarge?.color),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              // Planning List
              Expanded(
                child: filteredDocs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.event_busy_rounded, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              'No plans found matching filters',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                color: Theme.of(context).textTheme.bodySmall?.color,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 400,
                          mainAxisExtent: 240, // Increased height for approve button space
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                        ),
                        itemCount: filteredDocs.length,
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          return _buildPlanCard(doc.id, data);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }



  Widget _buildPlanCard(String docId, Map<String, dynamic> data) {
    final timestamp = data['planned_date'] as Timestamp?;
    final dateStr = timestamp != null
        ? DateFormat('dd MMM yyyy').format(timestamp.toDate())
        : 'No Date';
    
    final auditors = (data['auditors'] as List<dynamic>?)?.join(', ') ?? 'No Auditors';
    final status = data['status'] ?? 'planned';

    // Logic to determine the Main Display Title
    String displayTitle;
    final turbines = data['turbines']; // Check for list of turbines
    final singleId = data['turbine_id'] ?? data['turbineId']; // Check for single ID
    if (singleId != null && singleId.toString().isNotEmpty) {
      // Case 1: Specific Turbine ID exists
      displayTitle = singleId.toString();
    } else if (turbines != null && (turbines is List) && turbines.isNotEmpty) {
      // Case 2: List of turbines exists
      if (turbines.length == 1) {
        displayTitle = turbines[0].toString(); // Show the single ID
      } else {
        displayTitle = '${turbines.length} Turbines'; // Show count
      }
    } else {
      // Case 3 (Fallback): No specific ID found (Generic Plan)
      // Construct a title from Site and Model: e.g., "Kukru - G97"
      final String site = (data['site_name'] ?? data['site'] ?? 'Unknown Site').toString();
      final String model = (data['turbine_model'] ?? data['model'] ?? '').toString();
      displayTitle = model.isNotEmpty ? '$site / $model' : site;
    }

    Color statusColor;
    Color statusBgColor;
    String statusText;
    bool showActionBtns = false; // Renamed from showApproveBtn

    if (status == 'pending_approval') {
      statusColor = Colors.orange;
      statusBgColor = Colors.orange.withValues(alpha: 0.1);
      statusText = 'Pending Approval';
      showActionBtns = true;
    } else if (status == 'approved') {
      statusColor = Colors.blue;
      statusBgColor = Colors.blue.withValues(alpha: 0.1);
      statusText = 'Approved';
    } else if (status == 'completed') {
      statusColor = Colors.green;
      statusBgColor = Colors.green.withValues(alpha: 0.1);
      statusText = 'Completed';
    } else {
      statusColor = Colors.grey;
      statusBgColor = Colors.grey.withValues(alpha: 0.1);
      statusText = status.toString().toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.light ? 0.04 : 0.2),
            blurRadius: 15,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (data['site_name'] ?? 'Unknown Site').toString(),
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      (data['turbine_model'] ?? 'Unknown Model').toString(),
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.grey[400],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusText,
                  style: GoogleFonts.outfit(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            displayTitle,
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          const Spacer(),
          if (showActionBtns) ...[
            SizedBox(
              width: double.infinity,
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _approvePlan(docId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: Text(
                        'Approve',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: IconButton(
                      onPressed: () => _rejectPlan(docId),
                      icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                      tooltip: 'Reject Plan',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.calendar_today_rounded, size: 16, color: Colors.grey[400]),
              const SizedBox(width: 8),
              Text(
                dateStr,
                style: GoogleFonts.outfit(
                  color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.people_alt_rounded, size: 16, color: Colors.grey[400]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  auditors,
                  style: GoogleFonts.outfit(
                    color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
