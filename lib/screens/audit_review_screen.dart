import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:riqma_webapp/screens/audit/audit_summary_report_screen.dart';
import 'package:riqma_webapp/services/activity_log_service.dart';
import 'package:riqma_webapp/services/mis_service.dart';
import 'package:riqma_webapp/services/toast_service.dart';
import 'package:riqma_webapp/widgets/modern_searchable_dropdown.dart';

class AuditReviewScreen extends StatefulWidget {
  final String auditId;
  final Map<String, dynamic> auditData;
  final bool isReadOnly;

  const AuditReviewScreen({
    super.key,
    required this.auditId,
    required this.auditData,
    this.isReadOnly = false,
  });

  @override
  State<AuditReviewScreen> createState() => _AuditReviewScreenState();
}

class _AuditReviewScreenState extends State<AuditReviewScreen> {
  late Map<String, dynamic> localAuditData;


  // Selection & Filter Tracking
  int _selectedTaskIndex = 0;
  String _filterStatus = 'Not OK'; // 'all' | 'OK' | 'Not OK'
  List<AuditGroup> _processedGroups = []; // State for hierarchical data
  final Set<String> _collapsedCategories = {}; // tracks which main-cats are collapsed
  bool _isMetadataExpanded = true; // State for collapsible metadata

   // Dynamic Config (fetched from Firestore)
  List<Map<String, dynamic>> _ncCategories = [];
  List<Map<String, dynamic>> _rootCauses = [];
  final Map<String, String> _refIdToName = {};
  
  // Metadata Controllers (Read-Only)
  final TextEditingController _wtgRatingController = TextEditingController();
  final TextEditingController _wtgModelController = TextEditingController();
  final TextEditingController _turbineMakeController = TextEditingController(); // Added
  final TextEditingController _customerNameController = TextEditingController();
  
  // Fetched Data
  String _fetchedMake = '';
  String _fetchedRating = '';

  DateTime? _commissioningDate;
  DateTime? _dateOfTakeOver;
  DateTime? _planDateMaintenance;
  DateTime? _actualDateMaintenance;

  // Task Controllers
  final TextEditingController _managerCommentController = TextEditingController();

  // Master Remark State
  List<Map<String, dynamic>> _masterRemarks = [];
  bool _hasShownAutoRemarkPopup = false;

  // Maintenance Classification (matching Auditor features)
  String? _assessmentStage;
  String? _maintenanceType;
  
  // PM Team Data
  String _pmTeamLeader = '';
  List<String> _pmTeamMembers = [];
  
  // NC Recognition (Task 3)
  Map<String, String> _taskToNCId = {}; // Maps Task Key -> NC Doc ID

  @override
  void initState() {
    super.initState();
    localAuditData = Map<String, dynamic>.from(widget.auditData);
    if (localAuditData['audit_data'] != null) {
      localAuditData['audit_data'] = Map<String, dynamic>.from(
        localAuditData['audit_data'] as Map<String, dynamic>,
      );
    }

    // Initialize Metadata
    _wtgRatingController.text = (localAuditData['wtg_rating'] ?? '').toString();
    _customerNameController.text = (localAuditData['customer_name'] ?? '').toString();
    _wtgModelController.text = (localAuditData['turbine_model_name'] ?? localAuditData['wtg_model'] ?? widget.auditData['turbine_model_name'] ?? widget.auditData['turbine_model'] ?? widget.auditData['model'] ?? widget.auditData['wtg_model'] ?? '').toString();
    _turbineMakeController.text = (localAuditData['turbine_make'] ?? widget.auditData['turbine_make'] ?? '').toString();

    _fetchModelDetails(); // Auto-populate Make/Rating
    
    _commissioningDate = _parseDate(localAuditData['commissioning_date']);
    _dateOfTakeOver = _parseDate(localAuditData['date_of_take_over']);
    _planDateMaintenance = _parseDate(localAuditData['plan_date_of_maintenance']);
    _actualDateMaintenance = _parseDate(localAuditData['actual_date_of_maintenance']);

    // Initialize Maintenance Classification - properly handle null
    final assessmentVal = widget.auditData['assessment_stage'];
    _assessmentStage = (assessmentVal != null && assessmentVal.toString().isNotEmpty) 
        ? assessmentVal.toString() 
        : null;
    
    final maintenanceVal = widget.auditData['maintenance_type'];
    _maintenanceType = (maintenanceVal != null && maintenanceVal.toString().isNotEmpty) 
        ? maintenanceVal.toString() 
        : null;

    // Initialize PM Team data
    _pmTeamLeader = widget.auditData['pm_team_leader']?.toString() ?? '';
    localAuditData['pm_team_leader'] = _pmTeamLeader;
    final pmMembers = widget.auditData['pm_team_members'];
    _pmTeamMembers = (pmMembers is List) 
        ? List<String>.from(pmMembers.map((e) => e.toString())) 
        : <String>[];
    localAuditData['pm_team_members'] = _pmTeamMembers;

    localAuditData['pm_team_members'] = _pmTeamMembers;

    _processAuditData(); // Process groups initially
    _updateSelectedTaskControllers();
    _fetchAuditConfigs(); // Fetch dynamic NC categories
    _checkNCRecognition(); // Check for linked NCs

    _initializeMasterRemarks();

    // Log Audit Review Start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showAutomaticRemarkPopupIfNeeded();
      ActivityLogService.instance.log(
        actionType: ActivityActionType.auditStart,
        description: 'Manager started reviewing audit for ${widget.auditData['turbine_id'] ?? widget.auditData['turbine'] ?? 'Unknown Turbine'}',
        metadata: {
          'auditId': widget.auditId,
          'turbineId': widget.auditData['turbine_id'] ?? widget.auditData['turbine'],
        },
      );
    });
  }

  void _processAuditData() {
    final auditDataMap = localAuditData['audit_data'] as Map<String, dynamic>? ?? {};
    final entries = auditDataMap.entries.toList();
    // Sort numerically so Task 10 comes after Task 9 (not between 1 and 2)
    entries.sort((a, b) {
      final ia = int.tryParse(a.key);
      final ib = int.tryParse(b.key);
      if (ia != null && ib != null) return ia.compareTo(ib);
      return a.key.compareTo(b.key);
    });

    final Map<String, AuditGroup> groups = {};

    for (int i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final task = entry.value as Map<String, dynamic>;
        
        final mainCat = task['main_category_name']?.toString() ?? 'Other';
        final subCat = task['sub_category_name']?.toString() ?? 'General';
        final status = task['status']?.toString();
        final isCorrected = task['is_corrected'] == true;
        final isOk = status == 'OK' && !isCorrected;

        // Get or Create Main Group
        if (!groups.containsKey(mainCat)) {
            groups[mainCat] = AuditGroup(mainCat);
        }
        final mainGroup = groups[mainCat]!;

        // Get or Create Sub Group
        if (!mainGroup.subGroups.containsKey(subCat)) {
            mainGroup.subGroups[subCat] = AuditGroup(subCat);
        }
        final subGroup = mainGroup.subGroups[subCat]!;

        // Update Counts
        if (isOk) {
            mainGroup.okCount++;
            subGroup.okCount++;
        } else {
            mainGroup.notOkCount++;
            subGroup.notOkCount++;
        }

        // Add Task
        // Store original index to allow selection
        final Map<String, dynamic> taskData = Map.from(task);
        taskData['original_index'] = i; 
        taskData['key'] = entry.key;
        subGroup.tasks.add(taskData);
    }

    setState(() {
        _processedGroups = groups.values.toList();
    });
  }

  DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  @override
  void dispose() {
    _wtgRatingController.dispose();
    _wtgModelController.dispose();
    _turbineMakeController.dispose();
    _customerNameController.dispose();
    _managerCommentController.dispose();
    super.dispose();
  }

  void _initializeMasterRemarks() {
    final remarks = widget.auditData['master_remarks'];
    if (remarks is List) {
      _masterRemarks = List<Map<String, dynamic>>.from(remarks.map((e) => Map<String, dynamic>.from(e as Map)));
    }
  }

  Widget _buildStatusToggleButton({
    required String label,
    required bool isSelected,
    required MaterialColor activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.1) : Colors.transparent,
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? activeColor.shade700 : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }

  void _showAutomaticRemarkPopupIfNeeded() {
    if (_hasShownAutoRemarkPopup) return;

    final hasNewRemark = widget.auditData['manager_remark_seen'] == false;
    if (hasNewRemark && _masterRemarks.isNotEmpty) {
      final lastRemark = _masterRemarks.last;
      if (lastRemark['authorRole'] == 'auditor') {
        _hasShownAutoRemarkPopup = true;
        _showRemarkPopup(lastRemark);
        
        // Mark as seen in Firestore
        FirebaseFirestore.instance
            .collection('audit_submissions')
            .doc(widget.auditId)
            .update({'manager_remark_seen': true});
      }
    }
  }

  void _showRemarkPopup(Map<String, dynamic> remarkData) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 450,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.mark_chat_unread_rounded, color: Colors.blue.shade700, size: 32),
              ),
              const SizedBox(height: 20),
              Text(
                'Auditor Message',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1F36),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    widget.auditData['auditor_name']?.toString() ?? remarkData['authorName'].toString(),
                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[800]),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('dd/MM/yyyy HH:mm').format((remarkData['timestamp'] as Timestamp).toDate()),
                    style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  remarkData['remark'].toString(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    color: Colors.grey[800],
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1F36),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    'Understood',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMasterRemarkHistory() {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 550,
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.history_edu_rounded, color: Colors.teal.shade700, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Remark History',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A1F36),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(backgroundColor: Colors.grey.shade100),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: _masterRemarks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notes_rounded, size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text('No remarks yet', style: GoogleFonts.outfit(color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _masterRemarks.length,
                        itemBuilder: (context, index) {
                          final remark = _masterRemarks[(_masterRemarks.length - 1) - index];
                          final isManager = remark['authorRole'] == 'manager';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 20.0),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Column(
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: isManager ? Colors.blue.shade400 : Colors.orange.shade400,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 2),
                                          boxShadow: [
                                            BoxShadow(
                                              color: (isManager ? Colors.blue : Colors.orange).withValues(alpha: 0.3),
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: Container(
                                          width: 2,
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: isManager ? Colors.blue.shade50.withValues(alpha: 0.5) : Colors.orange.shade50.withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: isManager ? Colors.blue.shade100 : Colors.orange.shade100,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                           Row(
                                             mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                             children: [
                                               Text(
                                                 (isManager ? 'Manager' : (widget.auditData['auditor_name']?.toString() ?? remark['authorName'].toString())),
                                                 style: GoogleFonts.outfit(
                                                   fontWeight: FontWeight.bold,
                                                   fontSize: 13,
                                                   color: isManager ? Colors.blue.shade900 : Colors.orange.shade900,
                                                 ),
                                               ),
                                               Text(
                                                 DateFormat('dd/MM/yyyy HH:mm').format((remark['timestamp'] as Timestamp).toDate()),
                                                 style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey[500]),
                                               ),
                                             ],
                                           ),
                                          const SizedBox(height: 8),
                                          Text(
                                            remark['remark'].toString(),
                                            style: GoogleFonts.outfit(
                                              fontSize: 14,
                                              color: Colors.grey[800],
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateSelectedTaskControllers() {
    final tasks = _getSortedTasks();
    if (_selectedTaskIndex < tasks.length) {
      final item = tasks[_selectedTaskIndex].value as Map<String, dynamic>;
      _managerCommentController.text = (item['manager_comment'] ?? '').toString();
    }
  }

  void _selectTask(int index) {
    setState(() {
      _selectedTaskIndex = index;
      _updateSelectedTaskControllers();
    });
  }



  Future<void> _fetchAuditConfigs() async {
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('audit_configs').doc('nc_categories').get(),
        FirebaseFirestore.instance.collection('audit_configs').doc('root_causes').get(),
        FirebaseFirestore.instance.collection('references').get(),
      ]);
      final ncSnap = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final rcSnap = results[1] as DocumentSnapshot<Map<String, dynamic>>;
      final refSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;
      if (mounted) {
        setState(() {
          // Process References for fallback
          for (final doc in refSnap.docs) {
             _refIdToName[doc.id] = doc.data()['name']?.toString() ?? 'Unknown';
          }

          _ncCategories = ncSnap.exists
              ? List<Map<String, dynamic>>.from(
                  (ncSnap.data()?['items'] as List<dynamic>? ?? [])
                      .map((e) => Map<String, dynamic>.from(e as Map)))
              : [];
          _rootCauses = rcSnap.exists
              ? List<Map<String, dynamic>>.from(
                  (rcSnap.data()?['items'] as List<dynamic>? ?? [])
                      .map((e) => Map<String, dynamic>.from(e as Map)))
              : [];
        });
      }
    } catch (e) {
      debugPrint('Error fetching audit configs: $e');
    }
  }

  Future<void> _checkNCRecognition() async {
    try {
      final ncsSnapshot = await FirebaseFirestore.instance
          .collection('ncs')
          .where('audit_ref', isEqualTo: FirebaseFirestore.instance.doc('/audit_submissions/${widget.auditId}'))
          .get();
          
      final Map<String, String> taskToNC = {};
      for (final doc in ncsSnapshot.docs) {
        final taskKey = doc.data()['task_key']?.toString();
        if (taskKey != null) {
          taskToNC[taskKey] = doc.id;
        }
      }
      
      if (mounted) {
        setState(() {
          _taskToNCId = taskToNC;
        });
      }
    } catch (e) {
      debugPrint('Error recognizing NCs: $e');
    }
  }

  Future<void> _fetchModelDetails() async {
    // 1. Prefer the dedicated ID field
    String? modelId = widget.auditData['turbine_model_id']?.toString();

    // 2. Fall back to turbinemodel_ref DocumentReference (hardened link)
    if (modelId == null || modelId.isEmpty) {
      final ref = widget.auditData['turbinemodel_ref'];
      if (ref is DocumentReference) modelId = ref.id;
    }

    // 3. Last resort: legacy string field (may be a name, not an ID)
    if (modelId == null || modelId.isEmpty) {
      modelId = widget.auditData['turbine_model']?.toString();
    }

    if (modelId != null && modelId.isNotEmpty) {
      
      try {
        final doc = await FirebaseFirestore.instance
            .collection('turbinemodel')
            .doc(modelId)
            .get();
            
        if (doc.exists && mounted) {
           final data = doc.data();
           setState(() {
            _fetchedMake = (data?['turbine_make'] ?? '').toString();
            _fetchedRating = (data?['turbine_rating'] ?? '').toString(); // e.g. "2 MW"
            
            // Auto-fill controllers if they are empty
            if (_turbineMakeController.text.isEmpty) {
              _turbineMakeController.text = _fetchedMake;
              localAuditData['turbine_make'] = _fetchedMake;
            }
            if (_wtgRatingController.text.isEmpty) {
              _wtgRatingController.text = _fetchedRating;
              localAuditData['wtg_rating'] = _fetchedRating;
            }
          });
        }
      } catch (e) {
        debugPrint('Error fetching model details: $e');
      } finally {
      }
    }
  }

  List<MapEntry<String, dynamic>> _getSortedTasks() {
    final auditDataMap = localAuditData['audit_data'] as Map<String, dynamic>? ?? {};
    final entries = auditDataMap.entries.toList();
    // Numeric sort so task 10 comes after task 9
    entries.sort((a, b) {
      final ia = int.tryParse(a.key);
      final ib = int.tryParse(b.key);
      if (ia != null && ib != null) return ia.compareTo(ib);
      return a.key.compareTo(b.key);
    });
    return entries;
  }

  Future<void> _updateAuditStatus(String newStatus) async {
    try {
      if (newStatus == 'correction' || newStatus == 'rejected') {
        final remark = await _showRejectionRemarkDialog();
        if (remark == null || remark.isEmpty) return; // User cancelled or empty

        if (!mounted) return;
        unawaited(showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.white)),
        ));

        // Save any pending manager comment
        final tasks = _getSortedTasks();
        if (_selectedTaskIndex < tasks.length) {
          final taskKey = tasks[_selectedTaskIndex].key;
          localAuditData['audit_data'][taskKey]['manager_comment'] = _managerCommentController.text;
        }

        final user = FirebaseAuth.instance.currentUser;
        final newRemarkEntry = {
          'authorRole': 'manager',
          'remark': remark,
          'timestamp': FieldValue.serverTimestamp(),
          'authorName': user?.displayName ?? user?.email?.split('@')[0] ?? 'Manager',
        };

        await FirebaseFirestore.instance
            .collection('audit_submissions')
            .doc(widget.auditId)
            .update({
          'status': 'correction',
          'manager_reviewed_at': FieldValue.serverTimestamp(),
          'audit_data': localAuditData['audit_data'],
          'maintenance_type': _maintenanceType,
          'assessment_stage': _assessmentStage,
          'pm_team_leader': _pmTeamLeader,
          'pm_team_members': _pmTeamMembers,
          'master_remarks': FieldValue.arrayUnion([newRemarkEntry]),
        });
        
        // Mandatory Notification Add
        await FirebaseFirestore.instance.collection('notifications').add({
          'targetUserId': widget.auditData['auditor_id'] ?? widget.auditData['userId'],
          'title': 'Audit Correction Needed',
          'message': 'Audit for ${localAuditData['turbine_id'] ?? 'Turbine'} has been sent back: $remark',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'type': 'audit_correction',
          'auditId': widget.auditId,
        });

      } else {
        unawaited(showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.white)),
        ));

        await FirebaseFirestore.instance
            .collection('audit_submissions')
            .doc(widget.auditId)
            .update({
          'status': newStatus,
          'manager_reviewed_at': FieldValue.serverTimestamp(),
          'maintenance_type': _maintenanceType,
          'assessment_stage': _assessmentStage,
          'pm_team_leader': _pmTeamLeader,
          'pm_team_members': _pmTeamMembers,
        });

        // Trigger Automated MIS Sync (Flattened data for analysis & cross-platform tracking)
        if (newStatus == 'approved') {
          // Pass the updated localAuditData to ensure MIS has the latest values
          unawaited(MISService().syncAuditToMIS(widget.auditId, localAuditData));
        }
      }

      // Log Action
      final actionType = newStatus == 'approved' 
          ? ActivityActionType.reportApprove 
          : ActivityActionType.reportReject;
          
      await ActivityLogService.instance.log(
        actionType: actionType,
        description: newStatus == 'approved' 
            ? 'Approved audit report for ${localAuditData['turbine_id'] ?? localAuditData['turbine'] ?? 'Unknown'}'
            : 'Rejected audit report (correction needed) for ${localAuditData['turbine_id'] ?? localAuditData['turbine'] ?? 'Unknown'}',
        metadata: {
          'auditId': widget.auditId,
          'status': newStatus,
          'turbineId': localAuditData['turbine_id'] ?? localAuditData['turbine'],
        },
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      
      ToastService.success(newStatus == 'approved' ? 'Audit Approved Successfully' : 'Sent for Correction');
      Navigator.of(context).pop(); // Go back to dashboard
    } catch (e) {
      // Log Failure
      await ActivityLogService.instance.log(
        actionType: ActivityActionType.error,
        description: 'Error updating audit status: $e',
        metadata: {
          'auditId': widget.auditId,
          'targetStatus': newStatus,
          'error': e.toString(),
        },
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ToastService.error('Error updating audit: $e');
    }
  }

  void _navigateToSummary() {
    // 1. Prepare Master Data Map for the summary screen
    final Map<String, String> masterDataMap = {
      'turbine_make': _turbineMakeController.text,
      'turbine_model': _wtgModelController.text,
      'turbine_rating': _wtgRatingController.text,
      'district': (localAuditData['district'] ?? '').toString(),
      'warehouse_code': (localAuditData['warehouse_code'] ?? '').toString(),
      'zone': (localAuditData['zone'] ?? '').toString(),
    };

    // 2. Add any missing site/state info if not in localAuditData
    // (Usually fetched during initState or _fetchModelDetails)

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => AuditSummaryReportScreen(
          auditId: widget.auditId,
          auditData: localAuditData,
          masterData: masterDataMap,
        ),
      ),
    );
  }

  Future<String?> _showRejectionRemarkDialog() async {
    final TextEditingController remarkController = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Mandatory Master Remark', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Please provide a reason for sending this audit back for correction:', style: GoogleFonts.outfit(fontSize: 14)),
            const SizedBox(height: 16),
            TextField(
              controller: remarkController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Enter mandatory remark...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text('Cancel', style: GoogleFonts.outfit()),
          ),
          ElevatedButton(
            onPressed: () {
              if (remarkController.text.trim().length < 5) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Remark must be at least 5 characters', style: GoogleFonts.outfit())),
                );
                return;
              }
              Navigator.pop(context, remarkController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[600]),
            child: Text('Confirm Rejection', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveChanges() async {
    try {
        // Save current comment
        final tasks = _getSortedTasks();
        if (_selectedTaskIndex < tasks.length) {
            final taskKey = tasks[_selectedTaskIndex].key;
            localAuditData['audit_data'][taskKey]['manager_comment'] = _managerCommentController.text;
        }

        await FirebaseFirestore.instance
            .collection('audit_submissions')
            .doc(widget.auditId)
            .update({
            'audit_data': localAuditData['audit_data'],
            'maintenance_type': _maintenanceType,
            'assessment_stage': _assessmentStage,
            'pm_team_leader': _pmTeamLeader,
            'pm_team_members': _pmTeamMembers,
        });
        
        if (mounted) {
            ToastService.success('Changes saved');
        }
    } catch (e) {
        if (mounted) {
            ToastService.error('Error saving: $e');
        }
    }
  }

  void _showFullImage(String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4,
              child: Image.network(imageUrl, fit: BoxFit.contain),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows Maintenance Details dialog for selecting Type and Stage
  void _showMaintenanceDetailsDialog() {
    String? tempStageId = localAuditData['assessment_stage_id']?.toString();
    String? tempTypeId = localAuditData['maintenance_type_id']?.toString();
    String? tempStageLabel = _assessmentStage;
    String? tempTypeLabel = _maintenanceType;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.settings_applications, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Text('Maintenance Details', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              ],
            ),
            content: FutureBuilder<List<DocumentSnapshot>>(
              future: Future.wait([
                FirebaseFirestore.instance.collection('audit_configs').doc('assessment_stages').get(),
                FirebaseFirestore.instance.collection('audit_configs').doc('maintenance_types').get(),
              ]),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(width: 400, height: 200, child: Center(child: CircularProgressIndicator()));
                }
                
                List<dynamic> stagesRaw = [];
                List<dynamic> typesRaw = [];
                
                if (snapshot.hasData) {
                  final stageSnap = snapshot.data![0];
                  final typeSnap = snapshot.data![1];
                  if (stageSnap.exists && stageSnap.data() != null) {
                      stagesRaw = List<dynamic>.from(
                          (stageSnap.data() as Map<String, dynamic>)['items'] as List? ?? []);
                  }
                  if (typeSnap.exists && typeSnap.data() != null) {
                      typesRaw = List<dynamic>.from(
                          (typeSnap.data() as Map<String, dynamic>)['items'] as List? ?? []);
                  }
                }

                // Fallbacks
                if (stagesRaw.isEmpty) stagesRaw = [{'id': 'STAGE_AFTER', 'label': 'After maintenance'}, {'id': 'STAGE_BEFORE', 'label': 'Before maintenance'}, {'id': 'STAGE_DURING', 'label': 'During maintenance'}];
                if (typesRaw.isEmpty) typesRaw = [{'id': 'EYPM', 'label': 'Electrical Maintenance Yearly'}, {'id': 'MYPM', 'label': 'Mechanical Maintenance Yearly'}, {'id': 'HYPM', 'label': 'Half Yearly Maintenance'}, {'id': 'VYPM', 'label': 'Visual And Grease Maintenance'}];

                // Map legacy labels to IDs
                if (tempStageId == null && tempStageLabel != null && tempStageLabel!.isNotEmpty) {
                  final match = stagesRaw.firstWhere(
                      (s) => (s as Map)['label'] == tempStageLabel, orElse: () => null);
                  if (match != null) tempStageId = (match as Map)['id']?.toString();
                }
                if (tempTypeId == null && tempTypeLabel != null && tempTypeLabel!.isNotEmpty) {
                  final match = typesRaw.firstWhere(
                      (t) => (t as Map)['label'] == tempTypeLabel, orElse: () => null);
                  if (match != null) tempTypeId = (match as Map)['id']?.toString();
                }

                return SingleChildScrollView(
                  child: SizedBox(
                    width: 400,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ModernSearchableDropdown(
                          label: 'Type Of Maintenance',
                          value: tempTypeId,
                          items: {
                            for (final t in typesRaw) t['id'].toString(): t['label'].toString()
                          },
                          color: Colors.indigo,
                          icon: Icons.precision_manufacturing_rounded,
                          onChanged: (val) {
                            setDialogState(() {
                                tempTypeId = val;
                                final found = typesRaw.firstWhere(
                                    (t) => (t as Map)['id'] == val,
                                    orElse: () => <String, dynamic>{'label': val});
                                tempTypeLabel = (found as Map)['label']?.toString();
                              });
                          },
                        ),
                        const SizedBox(height: 20),
                        Text('Assessment Work Details', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 8),
                        ModernSearchableDropdown(
                          label: 'Assessment Work Details',
                          value: tempStageId,
                          items: {
                            for (final s in stagesRaw) s['id'].toString(): s['label'].toString()
                          },
                          color: Colors.blue,
                          icon: Icons.checklist_rtl_rounded,
                          onChanged: (val) {
                             setDialogState(() {
                                tempStageId = val;
                                final found = stagesRaw.firstWhere(
                                    (s) => (s as Map)['id'] == val,
                                    orElse: () => <String, dynamic>{'label': val});
                                tempStageLabel = (found as Map)['label']?.toString();
                              });
                          },
                        ),

                      ],
                    ),
                  ),
                );
              }
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.outfit())),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _maintenanceType = tempTypeLabel;
                    _assessmentStage = tempStageLabel;
                    localAuditData['maintenance_type'] = tempTypeLabel;
                    localAuditData['maintenance_type_id'] = tempTypeId;
                    localAuditData['assessment_stage'] = tempStageLabel;
                    localAuditData['assessment_stage_id'] = tempStageId;
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[700]),
                child: Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Shows PM Team Management dialog
  void _showPMTeamDialog() {
    final TextEditingController leaderController = TextEditingController(
      text: localAuditData['pm_team_leader']?.toString() ?? '',
    );
    
    List<String> members = <String>[];
    if (localAuditData['pm_team_members'] is List) {
      members = List<String>.from((localAuditData['pm_team_members'] as List).map((e) => e.toString()));
    }
    final TextEditingController newMemberController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.people_alt, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text('PM Team', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Team Leader
                  Text('Team Leader', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: leaderController,
                    decoration: InputDecoration(
                      hintText: 'Enter team leader name',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Team Members
                  Text('Team Members', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: newMemberController,
                          decoration: InputDecoration(
                            hintText: 'Add member name',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          if (newMemberController.text.isNotEmpty) {
                            setDialogState(() => members.add(newMemberController.text.trim()));
                            newMemberController.clear();
                          }
                        },
                        icon: Icon(Icons.add_circle, color: Colors.green[600]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...members.asMap().entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Chip(
                      label: Text(entry.value, style: GoogleFonts.outfit()),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () => setDialogState(() => members.removeAt(entry.key)),
                    ),
                  )),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.outfit())),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _pmTeamLeader = leaderController.text.trim();
                    _pmTeamMembers = List<String>.from(members);
                    localAuditData['pm_team_leader'] = _pmTeamLeader;
                    localAuditData['pm_team_members'] = _pmTeamMembers;
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700]),
                child: Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Shows NC Category classification dialog (dynamic from Firestore)
  void _showNCCategoryDialog(int index) {
    final List<MapEntry<String, dynamic>> tasks = _getSortedTasks();
    if (index < 0 || index >= tasks.length) {
      return;
    }
    
    final taskKey = tasks[index].key;
    final item = localAuditData['audit_data'][taskKey] as Map<String, dynamic>? ?? {};
    String? selectedCategory = item['nc_category']?.toString();

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.category, color: Colors.purple[700]),
                const SizedBox(width: 8),
                Text('NC Classification', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              ],
            ),
              content: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ModernSearchableDropdown(
                  label: 'NC Category',
                  value: selectedCategory,
                  items: {
                    for (final cat in _ncCategories) cat['name']?.toString() ?? '': cat['name']?.toString() ?? ''
                  },
                  color: Colors.purple,
                  icon: Icons.category_outlined,
                  onChanged: (val) => setDialogState(() => selectedCategory = val),
                ),
              ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.outfit())),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    localAuditData['audit_data'][taskKey]['nc_category'] = selectedCategory;
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple[700]),
                child: Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Shows Action Plan dialog for editing plan, dates, and root cause
  void _showActionPlanDialog(int index) {
    final List<MapEntry<String, dynamic>> tasks = _getSortedTasks();
    if (index < 0 || index >= tasks.length) {
      return;
    }
    
    final taskKey = tasks[index].key;
    final item = localAuditData['audit_data'][taskKey] as Map<String, dynamic>? ?? {};
    
    final actionPlanController = TextEditingController(text: item['action_plan']?.toString() ?? '');
    String? selectedRootCause = item['root_cause']?.toString();
    // Ensure saved value still exists in dynamic list; if not, keep it as a custom entry
    DateTime? targetDate = _parseDate(item['target_date']);
    DateTime? closingDate = _parseDate(item['closing_date']);

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Merge dynamic list with any pre-existing value not in the list
          final rootCauseItems = _rootCauses.map((rc) => rc['label']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
          
          if (selectedRootCause != null &&
              selectedRootCause!.isNotEmpty &&
              !rootCauseItems.contains(selectedRootCause)) {
            rootCauseItems.insert(0, selectedRootCause!);
          }

          String? selectedRefId = item['reference_id']?.toString();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.assignment, color: Colors.indigo[700]),
                const SizedBox(width: 8),
                Text('Action Plan', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Root Cause
                    Text('Root Cause', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    rootCauseItems.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text('Loading root causes...', style: GoogleFonts.outfit(color: Colors.grey)),
                            ),
                          )
                        : ModernSearchableDropdown(
                      label: 'Root Cause',
                      value: rootCauseItems.contains(selectedRootCause) ? selectedRootCause : null,
                      items: {for (final rc in rootCauseItems) rc: rc},
                      color: Colors.amber,
                      icon: Icons.psychology_rounded,
                      onChanged: (val) => setDialogState(() => selectedRootCause = val),
                    ),
                    const SizedBox(height: 16),
                    // Action Plan
                    Text('Plan of Action', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: actionPlanController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Enter action plan...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Dates Row
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Target Date', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: targetDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (picked != null) setDialogState(() => targetDate = picked);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey[300]!),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        targetDate != null ? DateFormat('dd/MM/yyyy').format(targetDate!) : 'Select date',
                                        style: GoogleFonts.outfit(color: targetDate != null ? Colors.black87 : Colors.grey),
                                      ),
                                      const Icon(Icons.calendar_today, size: 16),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Closing Date', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: closingDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (picked != null) setDialogState(() => closingDate = picked);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey[300]!),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        closingDate != null ? DateFormat('dd/MM/yyyy').format(closingDate!) : 'Select date',
                                        style: GoogleFonts.outfit(color: closingDate != null ? Colors.black87 : Colors.grey),
                                      ),
                                      const Icon(Icons.calendar_today, size: 16),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Reference Selection
                    Text('Reference Documentation', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    ModernSearchableDropdown(
                      label: 'Referance',
                      value: _refIdToName.containsKey(selectedRefId) ? selectedRefId : null,
                      items: _refIdToName,
                      color: Colors.blueGrey,
                      icon: Icons.menu_book_rounded,
                      onChanged: (val) => setDialogState(() => selectedRefId = val),
                    ),

                    // PI Section (Read-Only Display)
                    if (item['material_status'] != null && item['material_status'].toString().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text('Material / PI Details', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.indigo[700])),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.inventory, size: 16, color: Colors.indigo[700]),
                                const SizedBox(width: 8),
                                Text('Status: ${item['material_status']}', style: GoogleFonts.outfit(fontSize: 13, color: Colors.indigo[800])),
                              ],
                            ),
                            if (item['pi_number'] != null && item['pi_number'].toString().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(Icons.receipt_long, size: 16, color: Colors.indigo[700]),
                                  const SizedBox(width: 8),
                                  Text('PI Number: ${item['pi_number']}', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.indigo[800])),
                                ],
                              ),
                            ],
                            if (item['pi_date'] != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(Icons.calendar_month, size: 16, color: Colors.indigo[700]),
                                  const SizedBox(width: 8),
                                  Text(
                                    'PI Date: ${item['pi_date'] is Timestamp ? DateFormat('dd/MM/yyyy').format((item['pi_date'] as Timestamp).toDate()) : item['pi_date'].toString()}',
                                    style: GoogleFonts.outfit(fontSize: 13, color: Colors.indigo[800]),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.outfit())),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    localAuditData['audit_data'][taskKey]['action_plan'] = actionPlanController.text;
                    localAuditData['audit_data'][taskKey]['root_cause'] = selectedRootCause;
                    if (targetDate != null) {
                      localAuditData['audit_data'][taskKey]['target_date'] = Timestamp.fromDate(targetDate!);
                    }
                    if (closingDate != null) {
                      localAuditData['audit_data'][taskKey]['closing_date'] = Timestamp.fromDate(closingDate!);
                    }
                    localAuditData['audit_data'][taskKey]['reference_id'] = selectedRefId;
                    if (selectedRefId != null) {
                      localAuditData['audit_data'][taskKey]['reference_name'] = _refIdToName[selectedRefId];
                    }
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo[700]),
                child: Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final currentStatus = localAuditData['status']?.toString().toLowerCase() ?? 'submitted';
    final isApproved = currentStatus == 'approved';
    
    final tasks = _getSortedTasks();
    final siteName = localAuditData['site'] ?? 'Unknown Site';
    final turbineName = localAuditData['turbine'] ?? 'Unknown Turbine';
    final timestamp = localAuditData['timestamp'];
    String formattedDate = 'N/A';
    if (timestamp != null && timestamp is Timestamp) {
      formattedDate = DateFormat('dd/MM/yyyy').format(timestamp.toDate());
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveChanges,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFFF7F9FC),
          appBar: AppBar(
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D7377), Color(0xFF0A5C5E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            titleSpacing: 0,
            title: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.wind_power, size: 24),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Site Name: $siteName', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
                      Text(
                        '${_maintenanceType ?? 'Select Type'} | ${_assessmentStage ?? 'Select Stage'}',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: (_maintenanceType == null || _assessmentStage == null) ? Colors.red[200] : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 32),
                  _buildHeaderItem('Turbine Number', turbineName.toString()),
                  const SizedBox(width: 16),
                  _buildHeaderItem('Audit Date', formattedDate),
                ],
              ),
            ),
            actions: widget.isReadOnly ? null : [
              // Maintenance Classification Button
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Tooltip(
                  message: 'Maintenance Details',
                  child: IconButton(
                    onPressed: _showMaintenanceDetailsDialog,
                    icon: const Icon(Icons.settings_applications, size: 22),
                    style: IconButton.styleFrom(
                      backgroundColor: (_maintenanceType == null || _assessmentStage == null) 
                          ? Colors.red.withValues(alpha: 0.3) 
                          : Colors.white.withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Master Remark History Button
              if (_masterRemarks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Tooltip(
                    message: 'Master Remark History',
                    child: IconButton(
                      onPressed: _showMasterRemarkHistory,
                      icon: const Icon(Icons.history_edu, size: 22),
                      style: IconButton.styleFrom(
                        backgroundColor: (widget.auditData['manager_remark_seen'] == false)
                            ? Colors.orange.withValues(alpha: 0.6)
                            : Colors.white.withValues(alpha: 0.2),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              // PM Team Management Button
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Tooltip(
                  message: 'Manage PM Team',
                  child: IconButton(
                    onPressed: _showPMTeamDialog,
                    icon: const Icon(Icons.people_alt, size: 22),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Summary Preview Button
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Tooltip(
                  message: 'View Audit Summary',
                  child: ElevatedButton.icon(
                    onPressed: _navigateToSummary,
                    icon: const Icon(Icons.analytics_outlined, size: 16),
                    label: Text('Summary', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Correction Button
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ElevatedButton.icon(
                  onPressed: () => _updateAuditStatus('correction'),
                  icon: const Icon(Icons.reply_rounded, size: 16),
                  label: Text(
                    isApproved ? 'Re-open for Correction' : 'Send for Correction', 
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
              if (!isApproved) ...[
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
                  child: ElevatedButton.icon(
                    onPressed: () => _updateAuditStatus('approved'),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text('Approve', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ],
          ),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Panel (35%)
              Expanded(
                flex: 35,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFE0F7F6), Color(0xFFF0FDFA), Color(0xFFF7F9FC)],
                      stops: [0.0, 0.5, 1.0],
                    ),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildMetadataSection(),
                              const SizedBox(height: 32),
                              _buildStatsSection(tasks),
                              const SizedBox(height: 32),
                              _buildHierarchicalTaskList(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Right Panel (65%)
              Expanded(
                flex: 65,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Column(
                            children: [
                              if (tasks.isNotEmpty)
                                _buildTaskCard(tasks, _selectedTaskIndex),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderItem(String label, String value) {
    return Row(
      children: [
        Text(label, style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Text(value, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildMetadataSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.teal.shade100, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.shade900.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.precision_manufacturing_rounded, color: Colors.teal.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Basic Information',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade900,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => setState(() => _isMetadataExpanded = !_isMetadataExpanded),
                child: AnimatedRotation(
                  turns: _isMetadataExpanded ? 0.0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.teal.shade700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedCrossFade(
            firstChild: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildMetadataItem('Turbine Make', _turbineMakeController.text, Icons.factory_rounded)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildMetadataItem('WTG Model', _wtgModelController.text, Icons.model_training_rounded)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildMetadataItem('WTG Rating', _wtgRatingController.text, Icons.bolt_rounded)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildMetadataItem('Customer', _customerNameController.text, Icons.business_rounded)),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ModernSearchableDropdown(
                        label: 'Assessment Stage',
                        value: _assessmentStage,
                        items: const {
                          'Commissioning': 'Commissioning',
                          'Maintenance': 'Maintenance',
                          'Major Component': 'Major Component',
                          'RWP': 'RWP',
                        },
                        color: Colors.teal,
                        icon: Icons.assignment_turned_in_rounded,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _assessmentStage = val;
                              localAuditData['assessment_stage'] = val;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ModernSearchableDropdown(
                        label: 'Maintenance Type',
                        value: _maintenanceType,
                        items: const {
                          '500 Hr': '500 Hr',
                          'H-Yearly': 'H-Yearly',
                          'Yearly': 'Yearly',
                          '2-Yearly': '2-Yearly',
                          '3-Yearly': '3-Yearly',
                          '4-Yearly': '4-Yearly',
                          '5-Yearly': '5-Yearly',
                        },
                        color: Colors.teal,
                        icon: Icons.settings_suggest_rounded,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _maintenanceType = val;
                              localAuditData['maintenance_type'] = val;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildDateItem('Commissioning', _commissioningDate)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildDateItem('Take Over', _dateOfTakeOver)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildDateItem('Plan Maintenance', _planDateMaintenance)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildDateItem('Actual Maintenance', _actualDateMaintenance)),
                  ],
                ),
              ],
            ),
            secondChild: const SizedBox.shrink(),
            crossFadeState: _isMetadataExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade50),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: Colors.teal.shade300),
              const SizedBox(width: 4),
              Text(label, style: GoogleFonts.outfit(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value.isEmpty ? '---' : value,
            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade900),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDateItem(String label, DateTime? date) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.teal.shade50.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.teal.shade100.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 10, color: Colors.teal.shade700, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.calendar_today_rounded, size: 12, color: Colors.teal.shade400),
              const SizedBox(width: 6),
              Text(
                date != null ? DateFormat('dd MMM yyyy').format(date) : 'Not Set',
                style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.teal.shade900),
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildStatsSection(List<MapEntry<String, dynamic>> tasks) {
    int okCount = 0;
    int notOkCount = 0;
    for (final entry in tasks) {
      final status = entry.value['status']?.toString().toLowerCase() ?? '';
      final isCorrected = entry.value['is_corrected'] == true;
      if (status == 'ok' && !isCorrected) {
        okCount++;
      } else {
        notOkCount++;
      }
    }

    Widget statCard(String label, int count, Color countColor, String filterValue) {
      final isActive = _filterStatus == filterValue;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() {
            _filterStatus = isActive ? 'all' : filterValue;
          }),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isActive ? countColor.withValues(alpha: 0.12) : Colors.purple.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isActive ? countColor : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: GoogleFonts.outfit(color: Colors.black87, fontSize: 12)),
                    if (isActive)
                      Text('Filtering', style: GoogleFonts.outfit(fontSize: 9, color: countColor, fontWeight: FontWeight.w600)),
                  ],
                ),
                Row(
                  children: [
                    Text('$count', style: GoogleFonts.outfit(color: countColor, fontSize: 19, fontWeight: FontWeight.bold)),
                    if (isActive) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.close, size: 12, color: countColor),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        statCard('OK Points', okCount, Colors.green, 'OK'),
        const SizedBox(width: 16),
        statCard('Not OK', notOkCount, Colors.redAccent, 'Not OK'),
      ],
    );
  }

  // ─── Flat List Builder ─────────────────────────────────────────────────────

  List<dynamic> _buildFlatItems() {
    final List<dynamic> items = [];

    // Apply filter projection — never mutate _processedGroups
    final List<AuditGroup> displayGroups;
    if (_filterStatus == 'all') {
      displayGroups = _processedGroups;
    } else {
      final String filterLower = _filterStatus.toLowerCase();
      displayGroups = _processedGroups
          .map((mainGroup) {
            final newMain = AuditGroup(mainGroup.title);
            mainGroup.subGroups.forEach((k, subGroup) {
              final filteredTasks = subGroup.tasks
                  .where((t) {
                    final s = t['status']?.toString().toLowerCase() ?? '';
                    final ic = t['is_corrected'] == true;
                    if (filterLower == 'ok') return s == 'ok' && !ic;
                    if (filterLower == 'not ok') return s != 'ok' || ic;
                    return s == filterLower;
                  })
                  .toList();
              if (filteredTasks.isNotEmpty) {
                final newSub = AuditGroup(subGroup.title)
                  ..tasks.addAll(filteredTasks);
                newMain.subGroups[k] = newSub;
              }
            });
            return newMain;
          })
          .where((g) => g.subGroups.isNotEmpty)
          .toList();
    }

    for (final mainGroup in displayGroups) {
      final allTasks = mainGroup.subGroups.values.expand((sg) => sg.tasks).toList();
      final okCount = allTasks.where((t) {
        final s = t['status']?.toString().toLowerCase() ?? '';
        final ic = t['is_corrected'] == true;
        return s == 'ok' && !ic;
      }).length;
      final notOkCount = allTasks.length - okCount;

      items.add(_FlatCategoryHeader(
        title: mainGroup.title,
        okCount: okCount,
        notOkCount: notOkCount,
      ));

      // Skip children when this category is collapsed
      if (_collapsedCategories.contains(mainGroup.title)) continue;

      for (final subGroup in mainGroup.subGroups.values) {
        final ncCount = subGroup.tasks
            .where((t) => (t['status']?.toString().toLowerCase() ?? '') != 'ok')
            .length;
        items.add(_FlatSubCategoryHeader(title: subGroup.title, ncCount: ncCount));
        for (final task in subGroup.tasks) {
          items.add(task);
        }
      }
    }
    return items;
  }

  Widget _buildHierarchicalTaskList() {
    final flatItems = _buildFlatItems();

    if (flatItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text(
            _filterStatus == 'all' ? 'No tasks found.' : 'No "$_filterStatus" tasks.',
            style: GoogleFonts.outfit(color: Colors.grey[500], fontStyle: FontStyle.italic),
          ),
        ),
      );
    }

    final List<Widget> slivers = [];
    _FlatSubCategoryHeader? currentSubHeader;
    List<Map<String, dynamic>> currentTasks = [];

    void flushSubGroup() {
      if (currentSubHeader == null && currentTasks.isEmpty) return;
      if (currentSubHeader != null) {
        slivers.add(SliverToBoxAdapter(
          child: _SubCategoryHeaderWidget(header: currentSubHeader!),
        ));
      }
      if (currentTasks.isNotEmpty) {
        final tasks = List<Map<String, dynamic>>.from(currentTasks);
        slivers.add(SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _buildFlatTaskItem(tasks[i]),
            childCount: tasks.length,
          ),
        ));
      }
      currentSubHeader = null;
      currentTasks = [];
    }

    for (final item in flatItems) {
      if (item is _FlatCategoryHeader) {
        flushSubGroup();
        final catHeader = item;
        final isCollapsed = _collapsedCategories.contains(catHeader.title);
        slivers.add(SliverPersistentHeader(
          pinned: true,
          delegate: _CategoryStickyHeaderDelegate(
            header: catHeader,
            isCollapsed: isCollapsed,
            onToggle: () => setState(() {
              if (_collapsedCategories.contains(catHeader.title)) {
                _collapsedCategories.remove(catHeader.title);
              } else {
                _collapsedCategories.add(catHeader.title);
              }
            }),
          ),
        ));
      } else if (item is _FlatSubCategoryHeader) {
        flushSubGroup();
        currentSubHeader = item;
      } else {
        currentTasks.add(item as Map<String, dynamic>);
      }
    }
    flushSubGroup();

    final headerCount = flatItems.whereType<_FlatCategoryHeader>().length;
    final subHeaderCount = flatItems.whereType<_FlatSubCategoryHeader>().length;
    final taskCount = flatItems.whereType<Map<String, dynamic>>().length;
    final estimatedHeight =
        (headerCount * 52.0) + (subHeaderCount * 36.0) + (taskCount * 76.0);
    final listHeight = estimatedHeight.clamp(120.0, 1600.0);

    return SizedBox(
      height: listHeight,
      child: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: slivers,
      ),
    );
  }

  /// High-density task row — 4px NC strip, color-coded bg, truncated observation.
  Widget _buildFlatTaskItem(Map<String, dynamic> task) {
    final isCorrected = task['is_corrected'] == true;
    final isOk = (task['status']?.toString().toLowerCase() ?? '') == 'ok' && !isCorrected;
    final originalIndex = task['original_index'] as int;
    final isSelected = originalIndex == _selectedTaskIndex;
    final question = task['question']?.toString() ?? 'No Question';
    final observation = task['observation']?.toString() ?? '';
    final hasObs = observation.isNotEmpty;

    final Color bgColor = isSelected
        ? (isOk ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE))
        : (isOk ? const Color(0xFFF1FBF2) : const Color(0xFFFFF8F8));
    final Color stripColor = isOk ? Colors.transparent : const Color(0xFFE53935);
    final Color borderColor = isSelected
        ? (isOk ? const Color(0xFF43A047) : const Color(0xFFE53935))
        : Colors.transparent;

    return GestureDetector(
      onTap: () => _selectTask(originalIndex),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(
            left: BorderSide(color: stripColor, width: 4),
            bottom: BorderSide(color: Colors.grey.shade100, width: 1),
            top: isSelected ? BorderSide(color: borderColor, width: 0.5) : BorderSide.none,
            right: isSelected ? BorderSide(color: borderColor, width: 0.5) : BorderSide.none,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 12, top: 10, bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      question,
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: const Color(0xFF1A1F36),
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isOk ? const Color(0xFF43A047) : const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isOk ? 'OK' : 'NC',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (_taskToNCId.containsKey(task['key'])) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'NC Document Linked',
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                        child: const Icon(Icons.link, size: 10, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
              if (hasObs) ...[
                const SizedBox(height: 4),
                Text(
                  observation,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: isOk ? Colors.green.shade800 : Colors.red.shade800,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(List<MapEntry<String, dynamic>> tasks, int index) {
    if (index < 0 || index >= tasks.length) {
      return const SizedBox();
    }
    
    final entry = tasks[index];
    final taskKey = entry.key;
    final item = entry.value as Map<String, dynamic>? ?? {};
    final question = item['question'] ?? 'No Question';
    final status = item['status']?.toString().toLowerCase() ?? '';
    final isOk = status == 'ok';
    
    final subStatus = item['sub_status'] ?? '';
    final String? refId = item['reference_id']?.toString();
    final referenceName = _refIdToName[refId] ?? item['reference_name'] ?? item['referenceoftask'] ?? '';
    final observation = item['observation'] ?? '';
    
    final photosList = item['photos'] is List ? item['photos'] as List : <dynamic>[];
    final List<String> photos = photosList.map((e) => e.toString()).toList();

    // Dynamic color based on status
    final Color cardBackgroundColor;
    final Color cardBorderColor;
    if (status == 'ok') {
      cardBackgroundColor = Colors.green.shade50;
      cardBorderColor = Colors.green;
    } else if (status == 'not ok' || status == 'notok' || status == 'not_ok') {
      cardBackgroundColor = Colors.red.shade50;
      cardBorderColor = Colors.red;
    } else {
      cardBackgroundColor = Colors.white;
      cardBorderColor = Colors.grey.shade300;
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorderColor, width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1F36).withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#${index + 1}',
                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1A1F36)),
                  ),
                ),
                const SizedBox(width: 12),
                if (item['is_corrected'] == true) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.shade100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_fix_high_rounded, size: 14, color: Colors.green.shade700),
                        const SizedBox(width: 4),
                        Text('OSC', style: GoogleFonts.outfit(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                // Unified Control Group
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status Toggle
                    if (!widget.isReadOnly) 
                      Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            _buildStatusToggleButton(
                              label: 'OK', 
                              isSelected: status == 'ok', 
                              activeColor: Colors.green,
                              onTap: () {
                                setState(() => localAuditData['audit_data'][taskKey]['status'] = 'OK');
                                _processAuditData();
                              }
                            ),
                            Container(width: 1, color: Colors.grey.shade200),
                            _buildStatusToggleButton(
                              label: 'Not OK', 
                              isSelected: !isOk, 
                              activeColor: Colors.red,
                              onTap: () {
                                setState(() => localAuditData['audit_data'][taskKey]['status'] = 'Not OK');
                                _processAuditData();
                                if (localAuditData['audit_data'][taskKey]['nc_category'] == null ||
                                    localAuditData['audit_data'][taskKey]['nc_category'].toString().isEmpty) {
                                  _showNCCategoryDialog(index);
                                }
                              }
                            ),
                          ],
                        ),
                      )
                    else 
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isOk ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isOk ? Colors.green.shade100 : Colors.red.shade100),
                        ),
                        child: Text(
                          isOk ? 'OK' : 'Not OK',
                          style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: isOk ? Colors.green.shade700 : Colors.red.shade700),
                        ),
                      ),
                    
                    if (!isOk || item['is_corrected'] == true) ...[
                      const SizedBox(width: 8),
                      // Sub-Status / Criticality
                      SizedBox(
                        height: 36,
                        child: widget.isReadOnly
                          ? Builder(builder: (context) {
                                final s = subStatus.toString().toUpperCase();
                                Color bgColor = Colors.grey.shade50;
                                Color textColor = Colors.black87;
                                Color borderColor = Colors.grey.shade200;

                                if (s == 'CF') {
                                  bgColor = Colors.red.shade50;
                                  textColor = Colors.red.shade700;
                                  borderColor = Colors.red.shade100;
                                } else if (s == 'MCF') {
                                  bgColor = Colors.blue.shade50;
                                  textColor = Colors.blue.shade700;
                                  borderColor = Colors.blue.shade100;
                                }

                                return subStatus.toString().isNotEmpty 
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: bgColor,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: borderColor),
                                      ),
                                      child: Text(
                                        subStatus.toString(),
                                        style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: textColor),
                                      ),
                                    )
                                  : const SizedBox.shrink();
                              })
                            : Builder(builder: (context) {
                                final s = subStatus.toString().toUpperCase();

                                return ModernSearchableDropdown(
                                  label: 'Criticality',
                                  compact: true,
                                  showLabel: false,
                                  value: ['Aobs', 'MCF', 'CF'].contains(subStatus.toString()) ? subStatus.toString() : null,
                                  items: const {'Aobs': 'Aobs', 'MCF': 'MCF', 'CF': 'CF'},
                                  color: (s == 'CF' ? Colors.red : (s == 'MCF' ? Colors.blue : Colors.grey)),
                                  icon: Icons.crisis_alert_rounded,
                                  onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          localAuditData['audit_data'][taskKey]['sub_status'] = val;
                                          _processAuditData(); // Reactive update
                                        });
                                      }
                                  },
                                );
                              }),
                      ),
                    ],
                    
                    if (referenceName.toString().isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Center(
                          child: Text(
                            'Ref: $referenceName', 
                            style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600)
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // Content
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(question.toString(), style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 16),
                
                // Observation & Remark (Read-Only)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Observation', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[600])),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Text(observation.toString().isNotEmpty ? observation.toString() : '-', style: GoogleFonts.outfit(fontSize: 14)),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Manager Comment (Editable only when not read-only)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Manager Comment', style: GoogleFonts.outfit(fontSize: 12, color: Colors.blue[800], fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    widget.isReadOnly
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue[100]!),
                            ),
                            child: Text(
                              _managerCommentController.text.isNotEmpty ? _managerCommentController.text : '-',
                              style: GoogleFonts.outfit(fontSize: 14),
                            ),
                          )
                        : TextField(
                            controller: _managerCommentController,
                            decoration: InputDecoration(
                              hintText: 'Add a comment for the auditor...',
                              filled: true,
                              fillColor: Colors.blue[50],
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.blue[100]!)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.blue[100]!)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            maxLines: 2,
                            onChanged: (val) {
                              localAuditData['audit_data'][taskKey]['manager_comment'] = val;
                            },
                          ),
                  ],
                ),

                const SizedBox(height: 16),
                
                // Photos (View-Only)
                if (photos.isNotEmpty)
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: photos.length,
                      itemBuilder: (context, photoIndex) {
                        return InkWell(
                          onTap: () => _showFullImage(photos[photoIndex]),
                          child: Container(
                            width: 80,
                            margin: const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(photos[photoIndex], fit: BoxFit.cover),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  
                  if (item['nc_category'] != null && item['nc_category'].toString().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: item['nc_category'] == 'Quality of Workmanship' ? Colors.orange[50] :
                                         item['nc_category'] == 'RWP Point' ? Colors.blue[50] :
                                         Colors.purple[50],
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: item['nc_category'] == 'Quality of Workmanship' ? Colors.orange[200]! :
                                             item['nc_category'] == 'RWP Point' ? Colors.blue[200]! :
                                             Colors.purple[200]!
                                  ),
                              ),
                              child: Text(
                                  item['nc_category']?.toString() ?? '',
                                  style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: item['nc_category'] == 'Quality of Workmanship' ? Colors.orange[800] :
                                             item['nc_category'] == 'RWP Point' ? Colors.blue[800] :
                                             Colors.purple[800]
                                  ),
                              ),
                          ),
                          if (!widget.isReadOnly) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => _showNCCategoryDialog(index),
                              icon: Icon(Icons.edit, size: 16, color: Colors.purple[600]),
                              tooltip: 'Edit NC Category',
                              constraints: const BoxConstraints(minHeight: 28, minWidth: 28),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ],
                      ),
                  ],
                  
                  // NC Category Button (for Not OK tasks without category set)
                  if (!isOk && (item['nc_category'] == null || item['nc_category'].toString().isEmpty) && !widget.isReadOnly) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _showNCCategoryDialog(index),
                      icon: Icon(Icons.category, size: 16, color: Colors.purple[600]),
                      label: Text('Classify NC', style: GoogleFonts.outfit(fontSize: 12, color: Colors.purple[700])),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.purple[200]!),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                    ),
                  ],
                  
                  // Action Plan Summary Box (for Not OK tasks)
                  if (!isOk) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.indigo.shade50, Colors.blue.shade50],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.indigo.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.assignment, size: 18, color: Colors.indigo[700]),
                              const SizedBox(width: 8),
                              Text('Action Plan', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo[700])),
                              const Spacer(),
                              if (!widget.isReadOnly)
                                IconButton(
                                  onPressed: () => _showActionPlanDialog(index),
                                  icon: Icon(Icons.edit, size: 18, color: Colors.indigo[600]),
                                  tooltip: 'Edit Action Plan',
                                  constraints: const BoxConstraints(minHeight: 28, minWidth: 28),
                                  padding: EdgeInsets.zero,
                                ),
                            ],
                          ),
                          if (item['root_cause'] != null && item['root_cause'].toString().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text('Root Cause: ${item['root_cause']}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[700])),
                          ],
                          if (item['action_plan'] != null && item['action_plan'].toString().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Plan: ${item['action_plan']}', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black87)),
                          ],
                          if (item['action_plan'] == null || item['action_plan'].toString().isEmpty) ...[
                            const SizedBox(height: 8),
                            Text('No action plan defined', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic)),
                          ],
                          if (item['target_date'] != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.calendar_today, size: 14, color: Colors.indigo[400]),
                                const SizedBox(width: 4),
                                Text(
                                  'Target: ${DateFormat('dd/MM/yyyy').format(_parseDate(item['target_date']) ?? DateTime.now())}',
                                  style: GoogleFonts.outfit(fontSize: 11, color: Colors.indigo[600]),
                                ),
                                if (item['closing_date'] != null) ...[
                                  const SizedBox(width: 16),
                                  Icon(Icons.check_circle, size: 14, color: Colors.green[400]),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Closing: ${DateFormat('dd/MM/yyyy').format(_parseDate(item['closing_date']) ?? DateTime.now())}',
                                    style: GoogleFonts.outfit(fontSize: 11, color: Colors.green[600]),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  if (item['is_corrected'] == true) ...[
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2F1), // Light Teal
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF80CBC4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.build_circle, color: Color(0xFF00695C), size: 20),
                              const SizedBox(width: 8),
                              Text('On-Site Closure Details', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF00695C))),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Closure Remark', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[700])),
                                    const SizedBox(height: 4),
                                    Text(item['closure_remark']?.toString() ?? '-', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Result Status', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[700])),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.teal[200]!),
                                      ),
                                      child: Text(item['closure_status']?.toString() ?? 'OK', style: GoogleFonts.outfit(fontSize: 13, color: Colors.teal[800], fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (item['closure_photo'] != null && item['closure_photo'].toString().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text('Closure Proof', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[700])),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: () => _showFullImage(item['closure_photo']?.toString() ?? ''),
                              child: Container(
                                width: 80, height: 80,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.teal[200]!),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(item['closure_photo']?.toString() ?? '', fit: BoxFit.cover),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AuditGroup {
  String title;
  int okCount = 0;
  int notOkCount = 0;
  Map<String, AuditGroup> subGroups = {}; // For SubCategories
  List<Map<String, dynamic>> tasks = []; // For the final Tasks

  AuditGroup(this.title);
}

// ─── Flat List Data Models ──────────────────────────────────────────────────

class _FlatCategoryHeader {
  final String title;
  final int okCount;
  final int notOkCount;
  const _FlatCategoryHeader({
    required this.title,
    required this.okCount,
    required this.notOkCount,
  });
}

class _FlatSubCategoryHeader {
  final String title;
  final int ncCount;
  const _FlatSubCategoryHeader({required this.title, required this.ncCount});
}

// ─── Sticky Header Delegate ─────────────────────────────────────────────────

class _CategoryStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final _FlatCategoryHeader header;
  final bool isCollapsed;
  final VoidCallback onToggle;

  const _CategoryStickyHeaderDelegate({
    required this.header,
    required this.isCollapsed,
    required this.onToggle,
  });

  @override
  double get minExtent => 48.0;
  @override
  double get maxExtent => 48.0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        color: const Color(0xFF0D7377),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: Text(
                header.title,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            _HeaderPill(
              label: '${header.okCount} OK',
              bg: const Color(0xFF2E7D32),
              fg: Colors.white,
            ),
            const SizedBox(width: 6),
            if (header.notOkCount > 0) ...[
              _HeaderPill(
                label: '${header.notOkCount} NC',
                bg: Colors.blue.shade800,
                fg: Colors.white,
              ),
              const SizedBox(width: 6),
            ],
            Icon(
              isCollapsed ? Icons.expand_more : Icons.expand_less,
              color: Colors.white70,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CategoryStickyHeaderDelegate oldDelegate) =>
      oldDelegate.header.title != header.title ||
      oldDelegate.header.okCount != header.okCount ||
      oldDelegate.header.notOkCount != header.notOkCount ||
      oldDelegate.isCollapsed != isCollapsed;
}

// ─── Sub-Category Separator Widget ─────────────────────────────────────────

class _SubCategoryHeaderWidget extends StatelessWidget {
  final _FlatSubCategoryHeader header;
  const _SubCategoryHeaderWidget({required this.header});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF0F8F8),
      padding: const EdgeInsets.only(left: 16, right: 12, top: 7, bottom: 7),
      child: Row(
        children: [
          Icon(
            Icons.subdirectory_arrow_right_rounded,
            size: 13,
            color: const Color(0xFF0D7377).withValues(alpha: 0.6),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              header.title,
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF0D7377),
                letterSpacing: 0.2,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (header.ncCount > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${header.ncCount} NC',
                style: GoogleFonts.outfit(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Count Pill ─────────────────────────────────────────────────────────────

class _HeaderPill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _HeaderPill({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(
        label,
        style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}

class StatusRing extends StatelessWidget {
  final List<Map<String, dynamic>> tasks;
  final double size;

  const StatusRing({super.key, required this.tasks, this.size = 34});

  @override
  Widget build(BuildContext context) {
    final int notOkCount = tasks.where((t) => (t['status']?.toString().toLowerCase() ?? '') == 'not ok').length;
    final int totalCount = tasks.length;
    
    // Logic: Show Not OK count if > 0, else show Total count
    final String centerText = notOkCount > 0 ? '$notOkCount' : '$totalCount';
    final Color centerTextColor = notOkCount > 0 ? Colors.red : Colors.black;

    return CustomPaint(
      size: Size(size, size),
      painter: StatusRingPainter(tasks: tasks),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            centerText,
            style: GoogleFonts.outfit(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: centerTextColor,
            ),
          ),
        ),
      ),
    );
  }
}

class StatusRingPainter extends CustomPainter {
  final List<Map<String, dynamic>> tasks;

  StatusRingPainter({required this.tasks});

  @override
  void paint(Canvas canvas, Size size) {
    if (tasks.isEmpty) {
      return;
    }
    
    // Draw background circle (light grey) maybe? No, requirement didn't specify.

    const double strokeWidth = 4.0; 
    final Rect rect = Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2, size.width - strokeWidth, size.height - strokeWidth);
    
    double startAngle = -3.14159 / 2; // -90 degrees (Start from top)
    final double sweepAngle = (2 * 3.14159) / tasks.length;
    
    // Add a small gap between segments for visual clarity
    final double gap = tasks.length > 1 ? 0.2 : 0.0; // in radians
    double drawSweep = sweepAngle - gap;
    if (drawSweep <= 0) drawSweep = sweepAngle; // Fallback if too many tasks

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt; // Flat ends for donut segments

    for (final task in tasks) {
      paint.color = _getColor(task);
      // Center the segment in its angular slot if we have a gap
      final double currentStart = startAngle + (gap / 2);
      canvas.drawArc(rect, currentStart, drawSweep, false, paint);
      startAngle += sweepAngle;
    }
  }

  Color _getColor(Map<String, dynamic> task) {
    final status = task['status']?.toString().toLowerCase() ?? '';
    final hasObservation = task['observation']?.toString().trim().isNotEmpty ?? false;

    // Red: If status is 'Not OK'
    if (status == 'not ok' || status == 'notok' || status == 'not_ok') {
      return Colors.red;
    }
    
    // Green: If status is 'OK'
    if (status == 'ok') {
      return Colors.green;
    }
    
    // Blue: If task is 'Modified' (or has an observation but no final status yet)
    if (status.isEmpty && hasObservation) {
      return Colors.blue; 
    }

    // Yellow: If task status is null/empty (Pending Review) and no observation
    return Colors.amber;
  }

  @override
  bool shouldRepaint(covariant StatusRingPainter oldDelegate) {
    return true; 
  }
}
