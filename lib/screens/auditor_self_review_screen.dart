import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Added for keyboard shortcuts
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:riqma_webapp/services/activity_log_service.dart';
import 'package:riqma_webapp/widgets/modern_searchable_dropdown.dart';

class AuditorSelfReviewScreen extends StatefulWidget {
  final String documentId;
  final Map<String, dynamic> auditData;

  const AuditorSelfReviewScreen({
    super.key,
    required this.documentId,
    required this.auditData,
  });

  @override
  State<AuditorSelfReviewScreen> createState() => _AuditorSelfReviewScreenState();
}

class _AuditorSelfReviewScreenState extends State<AuditorSelfReviewScreen> {
  late Map<String, dynamic> localAuditData;
  List<Map<String, dynamic>> _allReferences = [];
  final Map<String, String> _refIdToName = {};
  bool _isLoadingReferences = true;
  
  // Fetched Turbine Details
  String _fetchedMake = '';
  String _fetchedRating = '';
  bool _isLoadingDetails = false;

  // Selection & Filter Tracking
  int _selectedTaskIndex = 0;
  String _filterStatus = 'all'; // 'all' | 'OK' | 'Not OK'
  bool _isMetadataExpanded = true; // State for collapsible metadata
  List<AuditGroup> _processedGroups = []; // State for hierarchical data
  final Set<String> _collapsedCategories = {}; // tracks which main-cats are collapsed

  // Dynamic Config (fetched from Firestore)
  List<Map<String, dynamic>> _ncCategories = [];
  List<Map<String, dynamic>> _rootCauses = [];
  Map<String, dynamic> _submissionRules = {};

  // Metadata Controllers
  final TextEditingController _wtgRatingController = TextEditingController();
  final TextEditingController _wtgModelController = TextEditingController(); // Added controller
  final TextEditingController _turbineMakeController = TextEditingController(); // New Turbine Make Controller
  final TextEditingController _customerNameController = TextEditingController();
  DateTime? _commissioningDate;
  DateTime? _dateOfTakeOver;
  DateTime? _planDateMaintenance;
  DateTime? _actualDateMaintenance;

  // Task Controllers (to prevent cursor jumping)
  final TextEditingController _selectedObservationController = TextEditingController();

  // Maintenance Classification
  String? _assessmentStage;
  String? _maintenanceType;

  // Master Remark State
  List<Map<String, dynamic>> _masterRemarks = [];
  bool _hasShownAutoRemarkPopup = false;

  @override
  void initState() {
    super.initState();
    // Create a fresh copy of widget.auditData to ensure no stale state
    localAuditData = Map<String, dynamic>.from(widget.auditData);
    if (localAuditData['audit_data'] != null) {
      localAuditData['audit_data'] = Map<String, dynamic>.from(
        localAuditData['audit_data'] as Map<String, dynamic>,
      );
    }

    // Initialize Metadata Controllers from current audit data
    _wtgRatingController.text = widget.auditData['wtg_rating']?.toString() ?? '';
    _turbineMakeController.text = widget.auditData['turbine_make']?.toString() ?? '';
    _customerNameController.text = widget.auditData['customer_name']?.toString() ?? '';
    
    // Populate WTG Model (Read-Only)
    _wtgModelController.text = widget.auditData['turbine_model_name']?.toString() ?? 
                               widget.auditData['wtg_model']?.toString() ?? 
                               widget.auditData['turbine_model']?.toString() ?? 
                               widget.auditData['model']?.toString() ?? '';
    _fetchWtgModel(); // Fetch from Firestore if available
    
    // Initialize Dates from current audit data (null if not present)
    _commissioningDate = _parseDate(widget.auditData['commissioning_date']);
    _dateOfTakeOver = _parseDate(widget.auditData['date_of_take_over']);
    _planDateMaintenance = _parseDate(widget.auditData['plan_date_of_maintenance']);
    _actualDateMaintenance = _parseDate(widget.auditData['actual_date_of_maintenance']);

    // Initialize Maintenance Classification from current audit - explicitly null if missing
    // DO NOT use .toString() as it converts null to "null" string
    final assessmentVal = widget.auditData['assessment_stage'];
    _assessmentStage = (assessmentVal != null && assessmentVal.toString().isNotEmpty) 
        ? assessmentVal.toString() 
        : null;
    
    final maintenanceVal = widget.auditData['maintenance_type'];
    _maintenanceType = (maintenanceVal != null && maintenanceVal.toString().isNotEmpty) 
        ? maintenanceVal.toString() 
        : null;

    // Explicitly reset PM Team data in localAuditData from current audit
    // This ensures dialogs read fresh data, not stale state
    localAuditData['pm_team_leader'] = widget.auditData['pm_team_leader']?.toString() ?? '';
    final pmMembers = widget.auditData['pm_team_members'];
    localAuditData['pm_team_members'] = (pmMembers is List) 
        ? List<String>.from(pmMembers.map((e) => e.toString())) 
        : <String>[];

    // Reset task selection
    _selectedTaskIndex = 0;
    _filterStatus = 'all';

    _fetchReferences();
    _fetchAuditConfigs(); // Fetch dynamic NC categories & root causes
    _initializeMasterRemarks();
    _processAuditData(); // Process groups initially
    _fetchModelDetails(); // Auto-populate Make/Rating
    _updateSelectedTaskControllers();

    // Log Audit Start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showAutomaticRemarkPopupIfNeeded();
      ActivityLogService.instance.log(
        actionType: ActivityActionType.auditStart,
        description: 'Started/Resumed audit review for ${widget.auditData['turbine_id'] ?? widget.auditData['turbine'] ?? 'Unknown Turbine'}',
        metadata: {
          'auditId': widget.documentId,
          'turbineId': widget.auditData['turbine_id'] ?? widget.auditData['turbine'],
        },
      );
    });
  }

  Future<void> _fetchModelDetails() async {
    // Get ID from audit data
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
      if (mounted) setState(() => _isLoadingDetails = true);
      
      try {
        var doc = await FirebaseFirestore.instance
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
        debugPrint("Error fetching model details: $e");
      } finally {
        if (mounted) setState(() => _isLoadingDetails = false);
      }
    }
  }

  void _processAuditData() {
    final auditDataMap = localAuditData['audit_data'] as Map<String, dynamic>? ?? {};
    final entries = auditDataMap.entries.toList();
    // Numeric sort so Task 10 comes after Task 9 (not between 1 and 2)
    entries.sort((a, b) {
      final ia = int.tryParse(a.key);
      final ib = int.tryParse(b.key);
      if (ia != null && ib != null) return ia.compareTo(ib);
      return a.key.compareTo(b.key);
    });

    Map<String, AuditGroup> groups = {};

    for (int i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final task = entry.value as Map<String, dynamic>;
        
        final mainCat = task['main_category_name']?.toString() ?? 'Other';
        final subCat = task['sub_category_name']?.toString() ?? 'General';
        final status = task['status']?.toString();
        final isOk = status == 'OK';

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
        Map<String, dynamic> taskData = Map.from(task);
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
    _selectedObservationController.dispose();
    super.dispose();
  }

  void _initializeMasterRemarks() {
    final remarks = widget.auditData['master_remarks'];
    if (remarks is List) {
      _masterRemarks = List<Map<String, dynamic>>.from(remarks.map((e) => Map<String, dynamic>.from(e as Map)));
    }
  }

  void _showMasterRemarkHistory() {
    // Mark as seen if auditor opens history manually
    if (widget.auditData['auditor_remark_seen'] == false) {
      FirebaseFirestore.instance
          .collection('audit_submissions')
          .doc(widget.documentId)
          .update({'auditor_remark_seen': true});
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.history_edu, color: Color(0xFF0D7377)),
            const SizedBox(width: 8),
            Text('Master Remark History', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 400,
          child: _masterRemarks.isEmpty
              ? Center(child: Text('No remarks recorded yet.', style: GoogleFonts.outfit()))
              : ListView.separated(
                  itemCount: _masterRemarks.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final remark = _masterRemarks[(_masterRemarks.length - 1) - index]; // Show latest first
                    final isManager = remark['authorRole'] == 'manager';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${remark['authorName']} (${remark['authorRole'].toString().toUpperCase()})',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: isManager ? Colors.blue[700] : Colors.orange[700],
                                ),
                              ),
                              Text(
                                detailTimestamp(remark['timestamp']),
                                style: GoogleFonts.outfit(fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(remark['remark'].toString(), style: GoogleFonts.outfit(fontSize: 13)),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: GoogleFonts.outfit()),
          ),
        ],
      ),
    );
  }

  String detailTimestamp(dynamic timestamp) {
     if (timestamp is Timestamp) {
       return DateFormat('dd/MM/yyyy HH:mm').format(timestamp.toDate());
     }
     return 'Just now';
  }

  void _showAutomaticRemarkPopupIfNeeded() {
    if (_hasShownAutoRemarkPopup) return;

    final hasNewRemark = widget.auditData['auditor_remark_seen'] == false;
    if (hasNewRemark && _masterRemarks.isNotEmpty) {
      final lastRemark = _masterRemarks.last;
      // Only show if the last remark was from manager (rejection)
      if (lastRemark['authorRole'] == 'manager') {
        _hasShownAutoRemarkPopup = true;
        _showRemarkPopup(lastRemark);

        // Mark as seen in Firestore
        FirebaseFirestore.instance
            .collection('audit_submissions')
            .doc(widget.documentId)
            .update({'auditor_remark_seen': true});
      }
    }
  }

  void _showRemarkPopup(Map<String, dynamic> remarkData) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.feedback, color: Colors.orange),
            const SizedBox(width: 8),
            Text('Manager Feedback', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A manager has requested corrections for this audit:',
              style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Text(
                remarkData['remark'].toString(),
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Understood', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _updateSelectedTaskControllers() {
    final tasks = _getSortedTasks();
    if (_selectedTaskIndex < tasks.length) {
      final item = tasks[_selectedTaskIndex].value as Map<String, dynamic>;
      _selectedObservationController.text = (item['observation'] ?? '').toString();
    }
  }

  void _selectTask(int index) {
    setState(() {
      _selectedTaskIndex = index;
      _updateSelectedTaskControllers();
    });
  }

  Future<void> _fetchReferences() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('references').get();
      setState(() {
        _allReferences = snapshot.docs.map((doc) {
          final data = doc.data();
          final name = (data['name'] ?? '').toString();
          _refIdToName[doc.id] = name;
          return {
            'id': doc.id,
            'name': name,
            'code': data['code'] ?? '',
            'ref': doc.reference,
          };
        }).toList();
        _isLoadingReferences = false;
      });
    } catch (e) {
      setState(() => _isLoadingReferences = false);
      // print('Error fetching references: $e');
    }
  }

  Future<void> _fetchWtgModel() async {
    try {
      final String turbineName = (widget.auditData['turbine'] ?? '').toString();
      if (turbineName.isEmpty) {
        return;
      }

      final query = await FirebaseFirestore.instance
          .collection('turbinename')
          .where('turbine_name', isEqualTo: turbineName)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final model = query.docs.first.data()['model_name']?.toString() ?? '';
        if (mounted) {
          setState(() {
            _wtgModelController.text = model;
            localAuditData['wtg_model'] = model; // Also update local data
          });
        }
      }
    } catch (e) {
      // print('Error fetching model: $e');
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

  void _markTaskAsModified(int index) {
    _processAuditData();
  }

  Future<void> _fetchAuditConfigs() async {
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('audit_configs').doc('nc_categories').get(),
        FirebaseFirestore.instance.collection('audit_configs').doc('root_causes').get(),
        FirebaseFirestore.instance.collection('audit_configs').doc('submission_rules').get(),
      ]);
      final ncSnap = results[0];
      final rcSnap = results[1];
      final rulesSnap = results[2];
      if (mounted) {
        setState(() {
          _submissionRules = rulesSnap.exists ? rulesSnap.data() as Map<String, dynamic> : {};
          _ncCategories = ncSnap.exists
              ? List<Map<String, dynamic>>.from(
                  (ncSnap.data()?['items'] as List<dynamic>? ?? [])
                      .map((e) => Map<String, dynamic>.from(e as Map)))
              : [
                  {'name': 'Quality of Workmanship', 'is_workman_penalty': true},
                  {'name': 'RWP Point', 'is_workman_penalty': false},
                  {'name': 'HOTO Point', 'is_workman_penalty': false},
                ];
          _rootCauses = rcSnap.exists
              ? List<Map<String, dynamic>>.from(
                  (rcSnap.data()?['items'] as List<dynamic>? ?? [])
                      .map((e) => Map<String, dynamic>.from(e as Map)))
              : [
                  {'id': 'RC_001', 'label': 'Material Not available', 'is_material': true},
                  {'id': 'RC_002', 'label': 'Quality of workmanship', 'is_material': false},
                  {'id': 'RC_003', 'label': 'Tools/Equipment not available', 'is_material': false},
                  {'id': 'RC_004', 'label': 'Contractor/additional resources required', 'is_material': false},
                ];
        });
      }
    } catch (e) {
      debugPrint('Error fetching audit configs: $e');
    }
  }


  Future<void> _saveAllChanges() async {
    try {
      unawaited(showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.white)),
      ));

      localAuditData['wtg_rating'] = _wtgRatingController.text;
      localAuditData['turbine_make'] = _turbineMakeController.text;
      localAuditData['customer_name'] = _customerNameController.text;
      localAuditData['commissioning_date'] = _commissioningDate != null ? Timestamp.fromDate(_commissioningDate!) : null;
      localAuditData['date_of_take_over'] = _dateOfTakeOver != null ? Timestamp.fromDate(_dateOfTakeOver!) : null;
      localAuditData['plan_date_of_maintenance'] = _planDateMaintenance != null ? Timestamp.fromDate(_planDateMaintenance!) : null;
      localAuditData['actual_date_of_maintenance'] = _actualDateMaintenance != null ? Timestamp.fromDate(_actualDateMaintenance!) : null;

      await FirebaseFirestore.instance
          .collection('audit_submissions')
          .doc(widget.documentId)
          .update({
        'audit_data': localAuditData['audit_data'],
        'wtg_rating': localAuditData['wtg_rating'],
        'turbine_make': localAuditData['turbine_make'],
        'customer_name': localAuditData['customer_name'],
        'commissioning_date': localAuditData['commissioning_date'],
        'date_of_take_over': localAuditData['date_of_take_over'],
        'plan_date_of_maintenance': localAuditData['plan_date_of_maintenance'],
        'actual_date_of_maintenance': localAuditData['actual_date_of_maintenance'],
        // Note: status is NOT updated here, only when submitting
      });

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved Successfully', style: GoogleFonts.outfit()), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving: $e', style: GoogleFonts.outfit()), backgroundColor: Colors.red),
      );
    }
  }

  /// Shows a red snackbar with the given error message
  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.outfit()),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Validates all mandatory fields before submission
  /// Returns true if all validations pass, false otherwise
  bool _validateSubmission() {
    // A. Metadata & Date Constraints
    
    // Check Basic Info
    if (_wtgRatingController.text.trim().isEmpty) {
      _showValidationError('Please enter WTG Rating before submitting.');
      return false;
    }
    if (_customerNameController.text.trim().isEmpty) {
      _showValidationError('Please enter Customer Name before submitting.');
      return false;
    }
    if (_turbineMakeController.text.trim().isEmpty) {
      _showValidationError('Please enter Turbine Make before submitting.');
      return false;
    }
    
    // Check Global Dates Exist
    if (_commissioningDate == null) {
      _showValidationError('Please select Commissioning Date before submitting.');
      return false;
    }
    if (_dateOfTakeOver == null) {
      _showValidationError('Please select Date of Take Over before submitting.');
      return false;
    }
    if (_planDateMaintenance == null) {
      _showValidationError('Please select Plan Date of Maintenance before submitting.');
      return false;
    }
    if (_actualDateMaintenance == null) {
      _showValidationError('Please select Actual Date of Maintenance before submitting.');
      return false;
    }

    // Dynamic Date Range Logic
    if (_submissionRules['force_date_takeover_less_than_plan'] == true) {
      if (_dateOfTakeOver!.isAfter(_planDateMaintenance!)) {
        _showValidationError('Date of Take Over must be earlier than Plan Date of Maintenance.');
        return false;
      }
    }
    if (_submissionRules['force_date_actual_greater_than_takeover'] == true) {
      if (_actualDateMaintenance!.isBefore(_dateOfTakeOver!)) {
        _showValidationError('Actual Date of Maintenance must be later than Date of Take Over.');
        return false;
      }
    }

    // B. Header/Global Settings (App Bar Checks)
    final pmTeamLeader = localAuditData['pm_team_leader'];
    if (pmTeamLeader == null || (pmTeamLeader is String && pmTeamLeader.trim().isEmpty)) {
      _showValidationError('Please add PM Team details (Team Leader) from the top bar.');
      return false;
    }
    
    if (_maintenanceType == null) {
      _showValidationError('Please select Maintenance Type from the top bar.');
      return false;
    }
    if (_assessmentStage == null) {
      _showValidationError('Please select Assessment Stage from the top bar.');
      return false;
    }

    // C. Task-Level Validation (Enforced for 'Not OK' tasks)
    final auditDataMap = localAuditData['audit_data'] as Map<String, dynamic>? ?? {};
    
    for (final entry in auditDataMap.entries) {
      final task = entry.value as Map<String, dynamic>;
      final status = task['status']?.toString().toLowerCase() ?? '';
      
      if (status == 'not ok') {
        final String? refId = task['reference_id']?.toString() ?? task['ref_id']?.toString();
        final referenceName = _refIdToName[refId] ?? 
                             task['reference_name'] ?? 
                             task['ref_name'] ?? 
                             'Task ${entry.key}';
        final question = task['question'] ?? task['task'] ?? 'Unknown Question';
        final errorPrefix = '$referenceName - $question';

        // 1. NC Category
        if (_submissionRules['mandatory_nc_category'] == true) {
          final nc = task['nc_category']?.toString() ?? '';
          if (nc.isEmpty) {
            _showValidationError('NC Category is mandatory for: $errorPrefix');
            return false;
          }
        }

        // 2. Action Plan Remark
        if (_submissionRules['mandatory_action_plan'] == true) {
          final ap = task['action_plan']?.toString() ?? '';
          if (ap.isEmpty) {
            _showValidationError('Action Plan Remark is mandatory for: $errorPrefix');
            return false;
          }
        }

        // 3. Root Cause
        if (_submissionRules['mandatory_root_cause'] == true) {
          final rc = task['root_cause']?.toString() ?? '';
          if (rc.isEmpty) {
            _showValidationError('Root Cause is mandatory for: $errorPrefix');
            return false;
          }
        }

        // 4. Plan Date (Target Date)
        if (_submissionRules['mandatory_plan_date'] == true) {
          final td = task['target_date'];
          if (td == null) {
            _showValidationError('Target Date (Plan Date) is mandatory for: $errorPrefix');
            return false;
          }
        }

        // 5. PI Status (Requires Status AND PI Number)
        if (_submissionRules['mandatory_pi_status'] == true) {
          final ms = task['material_status']?.toString() ?? '';
          final pin = task['pi_number']?.toString() ?? '';
          if (ms.isEmpty || pin.isEmpty) {
             _showValidationError('Material Status and PI Number are both mandatory for: $errorPrefix');
             return false;
          }
        }

        // 6. Observation/NC Summary
        if (_submissionRules['mandatory_observation'] == true) {
          final obs = task['observation']?.toString() ?? '';
          if (obs.trim().isEmpty) {
            _showValidationError('Observation Remark (NC Summary) must not be blank for: $errorPrefix');
            return false;
          }
        }

        // 7. Sub Status
        if (_submissionRules['mandatory_sub_status'] == true) {
          final ss = task['sub_status']?.toString() ?? '';
          if (ss.isEmpty) {
            _showValidationError('Sub Status selection is mandatory for: $errorPrefix');
            return false;
          }
        }

        // 8. Reference
        if (_submissionRules['mandatory_reference'] == true) {
          if (refId == null || refId.isEmpty || refId == 'null') {
            _showValidationError('Reference selection is mandatory for: $errorPrefix');
            return false;
          }
        }

        // 9. Photos (Minimum 1)
        if (_submissionRules['mandatory_photos'] == true) {
          final photosList = task['photos'] is List ? task['photos'] as List<dynamic> : <dynamic>[];
          if (photosList.isEmpty) {
            _showValidationError('At least one photo is mandatory for: $errorPrefix');
            return false;
          }
        }
      }
    }

    return true;
  }

  Future<void> _submitToManager() async {
    // Run comprehensive validation first
    if (!_validateSubmission()) {
      return;
    }

    final remark = await _showSubmissionRemarkDialog();
    if (remark == null || remark.isEmpty) return; // User cancelled or empty

    try {
      if (!mounted) return;
      unawaited(showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.white)),
      ));

      localAuditData['wtg_rating'] = _wtgRatingController.text;
      localAuditData['turbine_make'] = _turbineMakeController.text;
      localAuditData['customer_name'] = _customerNameController.text;
      localAuditData['commissioning_date'] = _commissioningDate != null ? Timestamp.fromDate(_commissioningDate!) : null;
      localAuditData['date_of_take_over'] = _dateOfTakeOver != null ? Timestamp.fromDate(_dateOfTakeOver!) : null;
      localAuditData['plan_date_of_maintenance'] = _planDateMaintenance != null ? Timestamp.fromDate(_planDateMaintenance!) : null;
      localAuditData['actual_date_of_maintenance'] = _actualDateMaintenance != null ? Timestamp.fromDate(_actualDateMaintenance!) : null;

      final currentStatus = widget.auditData['status'] as String?;
      String newStatus = 'pending';
      
      if (currentStatus == 'correction') {
        final remarks = widget.auditData['master_remarks'] as List? ?? [];
        final managerRemarksCount = remarks.where((r) => (r as Map)['authorRole'] == 'manager').length;
        // If it was sent back once (1 manager remark), next status is pending_2
        // If sent back twice (2 manager remarks), next status is pending_3
        newStatus = managerRemarksCount >= 1 ? 'pending_${managerRemarksCount + 1}' : 'pending_2';
      }

      final user = FirebaseAuth.instance.currentUser;
      final newRemarkEntry = {
        'authorRole': 'auditor',
        'remark': remark,
        'timestamp': Timestamp.now(),
        'authorName': user?.displayName ?? user?.email?.split('@')[0] ?? 'Auditor',
      };

      await FirebaseFirestore.instance
          .collection('audit_submissions')
          .doc(widget.documentId)
          .update({
        'status': newStatus,
        'self_reviewed_at': FieldValue.serverTimestamp(),
        'audit_data': localAuditData['audit_data'],
        'wtg_rating': localAuditData['wtg_rating'],
        'turbine_make': localAuditData['turbine_make'],
        'customer_name': localAuditData['customer_name'],
        'commissioning_date': localAuditData['commissioning_date'],
        'date_of_take_over': localAuditData['date_of_take_over'],
        'plan_date_of_maintenance': localAuditData['plan_date_of_maintenance'],
        'actual_date_of_maintenance': localAuditData['actual_date_of_maintenance'],
        'master_remarks': FieldValue.arrayUnion([newRemarkEntry]),
        'manager_remark_seen': false, // Trigger popup for manager
      });
      
      // Mandatory Notification Add for Manager
      await FirebaseFirestore.instance.collection('notifications').add({
        'targetUserId': widget.auditData['manager_id'] ?? 'MANAGER_ID_PLACEHOLDER', // Ideal would be to find manager responsible
        'title': 'Audit Resubmitted',
        'message': 'Auditor resubmitted ${localAuditData['turbine_id'] ?? 'Turbine'} with remark: $remark',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'type': 'audit_resubmission',
        'auditId': widget.documentId,
      });

      // Log Success
      await ActivityLogService.instance.log(
        actionType: ActivityActionType.auditSubmit,
        description: 'Submitted audit for review: ${localAuditData['turbine_id'] ?? localAuditData['turbine'] ?? 'Unknown'}',
        metadata: {
          'auditId': widget.documentId,
          'status': newStatus,
          'turbineId': localAuditData['turbine_id'] ?? localAuditData['turbine'],
        },
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully submitted to manager', style: GoogleFonts.outfit()), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop();
    } catch (e) {
      // Log Failure
      await ActivityLogService.instance.log(
        actionType: ActivityActionType.auditSubmitFailed,
        description: 'Failed to submit audit: $e',
        metadata: {
          'auditId': widget.documentId,
          'error': e.toString(),
        },
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting: $e', style: GoogleFonts.outfit()), backgroundColor: Colors.red),
      );
    }
  }

  Future<String?> _showSubmissionRemarkDialog() async {
    final TextEditingController remarkController = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Submission Remark', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Please provide a summary of the corrections made:', style: GoogleFonts.outfit(fontSize: 14)),
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A1F36)),
            child: Text('Submit Review', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _addPhoto(String taskKey, int taskIndex) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) {
        return;
      }

      if (!mounted) {
        return;
      }
      unawaited(showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.white)),
      ));

      final bytes = await pickedFile.readAsBytes();
      final storageRef = FirebaseStorage.instance.ref();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final photoRef = storageRef.child('audit_updates/${widget.documentId}/$taskKey-$timestamp.jpg');
      
      await photoRef.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final downloadURL = await photoRef.getDownloadURL();

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();

      setState(() {
        final auditDataMap = localAuditData['audit_data'] as Map<String, dynamic>;
        final currentPhotos = auditDataMap[taskKey]['photos'] is List 
            ? List<String>.from(auditDataMap[taskKey]['photos'] as Iterable<dynamic>) 
            : <String>[];
        currentPhotos.add(downloadURL);
        auditDataMap[taskKey]['photos'] = currentPhotos;
      });
      _markTaskAsModified(taskIndex);

    } catch (e) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading photo: $e', style: GoogleFonts.outfit()), backgroundColor: Colors.red),
      );
    }
  }

  void _removePhoto(String taskKey, int photoIndex, int taskIndex) {
    setState(() {
      final auditDataMap = localAuditData['audit_data'] as Map<String, dynamic>;
      final currentPhotos = auditDataMap[taskKey]['photos'] is List 
          ? List<String>.from(auditDataMap[taskKey]['photos'] as Iterable<dynamic>) 
          : <String>[];
      if (photoIndex >= 0 && photoIndex < currentPhotos.length) {
        currentPhotos.removeAt(photoIndex);
        auditDataMap[taskKey]['photos'] = currentPhotos;
      }
    });
    _markTaskAsModified(taskIndex);
  }

  /// Shows a full-screen zoomable image viewer dialog
  void _showFullScreenImage(String imageUrl) {
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
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }


  /// Shows a searchable selection dialog for picking an item from a list.

  void _updateTaskReference(String taskKey, String? newReferenceId) {
    if (newReferenceId == null) {
      return;
    }
    final selectedRef = _allReferences.firstWhere((r) => r['id'] == newReferenceId, orElse: () => {});
    if (selectedRef.isEmpty) {
      return;
    }

    setState(() {
      final auditDataMap = localAuditData['audit_data'] as Map<String, dynamic>;
      auditDataMap[taskKey]['reference_name'] = selectedRef['name'];
      auditDataMap[taskKey]['reference_ref'] = selectedRef['ref'];
      auditDataMap[taskKey]['reference_id'] = newReferenceId; // Updated to reflect change in UI
    });
  }

  bool _isNCReviewed(Map<String, dynamic> task) {
    final status = task['status']?.toString().toLowerCase() ?? '';
    if (status == 'ok') return false;

    // A point is reviewed if it has an NC Category/Root Cause and an Action Plan
    final ncCategory = task['nc_category']?.toString() ?? '';
    final rootCause = task['root_cause']?.toString() ?? '';
    final actionPlan = task['action_plan']?.toString() ?? '';

    return (ncCategory.isNotEmpty || rootCause.isNotEmpty) && actionPlan.isNotEmpty;
  }

  void _showActionPlanDialog(int index) {
    if (index < 0 || index >= _getSortedTasks().length) {
      return;
    }
    
    final entry = _getSortedTasks()[index];
    final taskKey = entry.key;
    final item = entry.value as Map<String, dynamic>;
    
    final TextEditingController planController = TextEditingController(text: item['action_plan']?.toString());
    String? rootCause = item['root_cause']?.toString();
    DateTime? targetDate = item['target_date'] is Timestamp ? (item['target_date'] as Timestamp).toDate() : null;
    
    String? materialStatus = item['material_status']?.toString();
    final TextEditingController piNumberController = TextEditingController(text: item['pi_number']?.toString());
    DateTime? piDate = item['pi_date'] is Timestamp ? (item['pi_date'] as Timestamp).toDate() : null;

    final auditDate = localAuditData['timestamp'] is Timestamp 
        ? (localAuditData['timestamp'] as Timestamp).toDate() 
        : DateTime.now();
    
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Define Action Plan', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 500,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: planController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Action Plan',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF3F51B5), width: 2)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      ModernSearchableDropdown(
                        label: 'Root Cause',
                        value: rootCause,
                        items: {
                          for (var s in _rootCauses) s['label']?.toString() ?? '': s['label']?.toString() ?? ''
                        },
                        color: Colors.amber,
                        icon: Icons.psychology_outlined,
                        onChanged: (val) {
                          setStateDialog(() { 
                            rootCause = val;
                            
                            // Dynamic flag check instead of string matching
                            final selectedRC = _rootCauses.firstWhere(
                              (rc) => rc['label'] == val, 
                              orElse: () => {'is_material': false}
                            );
                            
                            if (selectedRC['is_material'] != true) {
                                materialStatus = null;
                                piNumberController.clear();
                                piDate = null;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: targetDate != null && targetDate!.isAfter(auditDate) ? targetDate! : auditDate.add(const Duration(days: 1)),
                            firstDate: auditDate.add(const Duration(days: 1)),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setStateDialog(() => targetDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Target Date',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            errorText: targetDate == null ? 'Required' : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(targetDate != null ? DateFormat('dd/MM/yyyy').format(targetDate!) : 'Select Date', style: GoogleFonts.outfit(color: Colors.black87)),
                              const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                      
                      if (rootCause != null && rootCause!.toLowerCase().contains('material')) ...[

                        const SizedBox(height: 16),
                        Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue[100]!),
                            ),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    Text('Material Status', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue[900])),
                                    ModernSearchableDropdown(
                                      label: 'Material Status',
                                      value: materialStatus,
                                      color: Colors.blue,
                                      icon: Icons.inventory_2_outlined,
                                      items: const {
                                        'PI Already Raised': 'PI Already Raised',
                                        'PI Need to Raise': 'PI Need to Raise',
                                      },
                                      onChanged: (v) => setStateDialog(() => materialStatus = v),
                                    ),
                                    if (materialStatus == 'PI Already Raised') ...[
                                        const SizedBox(height: 8),
                                        Row(
                                            children: [
                                                Expanded(
                                                    child: TextField(
                                                        controller: piNumberController,
                                                        style: GoogleFonts.outfit(fontSize: 13),
                                                        decoration: InputDecoration(
                                                            labelText: 'PI Number',
                                                            labelStyle: GoogleFonts.outfit(fontSize: 12),
                                                            isDense: true,
                                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                                            filled: true,
                                                            fillColor: Colors.white,
                                                        ),
                                                    ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                    child: InkWell(
                                                        onTap: () async {
                                                            final picked = await showDatePicker(
                                                                context: context,
                                                                initialDate: piDate ?? DateTime.now(),
                                                                firstDate: DateTime(2000),
                                                                lastDate: DateTime(2100),
                                                            );
                                                            if (picked != null) {
                                                                setStateDialog(() => piDate = picked);
                                                            }
                                                        },
                                                        child: InputDecorator(
                                                            decoration: InputDecoration(
                                                                labelText: 'PI Date',
                                                                isDense: true,
                                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                                                filled: true,
                                                                fillColor: Colors.white,
                                                            ),
                                                            child: Text(piDate != null ? DateFormat('dd/MM/yyyy').format(piDate!) : 'Select', style: GoogleFonts.outfit(fontSize: 13)),
                                                        ),
                                                    ),
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
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (targetDate == null) {
                      return;
                    }
                    
                    setState(() {
                         localAuditData['audit_data'][taskKey]['action_plan'] = planController.text;
                         localAuditData['audit_data'][taskKey]['root_cause'] = rootCause;
                         localAuditData['audit_data'][taskKey]['target_date'] = Timestamp.fromDate(targetDate!);
                         localAuditData['audit_data'][taskKey]['material_status'] = materialStatus;
                         localAuditData['audit_data'][taskKey]['pi_number'] = piNumberController.text;
                         localAuditData['audit_data'][taskKey]['pi_date'] = piDate != null ? Timestamp.fromDate(piDate!) : null;
                    });
                    _markTaskAsModified(index);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3F51B5), // Indigo
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Save Plan', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showNCCategoryDialog(int index) {
      if (index < 0 || index >= _getSortedTasks().length) {
        return;
      }

      final entry = _getSortedTasks()[index];
      final taskKey = entry.key;
      final item = entry.value as Map<String, dynamic>;
      String? selectedCategory = item['nc_category']?.toString();

      showDialog<void>(
          context: context,
          builder: (context) {
              return StatefulBuilder(
                  builder: (context, setStateDialog) {
                      return AlertDialog(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: Text('Select NC Category', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                          content: Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: ModernSearchableDropdown(
                              label: 'NC Category',
                              value: selectedCategory,
                              items: {
                                for (var cat in _ncCategories) cat['name']?.toString() ?? '': cat['name']?.toString() ?? ''
                              },
                              color: Colors.purple,
                              icon: Icons.category_outlined,
                              onChanged: (val) => setStateDialog(() => selectedCategory = val),
                            ),
                          ),
                          actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey)),
                              ),
                              ElevatedButton(
                                  onPressed: () {
                                      setState(() {
                                          localAuditData['audit_data'][taskKey]['nc_category'] = selectedCategory;
                                      });
                                      _markTaskAsModified(index);
                                      Navigator.pop(context);
                                  },
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF3F51B5), // Indigo
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: Text('Save', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                              ),
                          ],
                      );
                  }
              );
          }
      );
  }

  void _showMaintenanceDetailsDialog() {
    String? tempStageId = localAuditData['assessment_stage_id']?.toString();
    String? tempTypeId = localAuditData['maintenance_type_id']?.toString();
    String? tempStageLabel = _assessmentStage;
    String? tempTypeLabel = _maintenanceType;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.settings_applications, color: Colors.blue[700], size: 24),
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

                  // Provide fallbacks if config is empty (for safety/bootstrap)
                  if (stagesRaw.isEmpty) stagesRaw = [{'id': 'STAGE_AFTER', 'label': 'After maintenance'}, {'id': 'STAGE_BEFORE', 'label': 'Before maintenance'}, {'id': 'STAGE_DURING', 'label': 'During maintenance'}];
                  if (typesRaw.isEmpty) typesRaw = [{'id': 'EYPM', 'label': 'Electrical Maintenance Yearly'}, {'id': 'MYPM', 'label': 'Mechanical Maintenance Yearly'}, {'id': 'HYPM', 'label': 'Half Yearly Maintenance'}, {'id': 'VYPM', 'label': 'Visual And Grease Maintenance'}];

                  // Resolve legacy strings to ID
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
                          Text('Assessment Work Details', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[800])),
                          const SizedBox(height: 8),
                          ModernSearchableDropdown(
                            label: 'Assessment Work Details',
                            value: tempStageId,
                            items: {
                              for (var s in stagesRaw) s['id'].toString(): s['label'].toString()
                            },
                            color: Colors.lightBlue,
                            icon: Icons.checklist_rtl_rounded,
                            onChanged: (val) {
                              setStateDialog(() {
                                tempStageId = val;
                                final found = stagesRaw.firstWhere(
                                    (s) => s['id'] == val,
                                    orElse: () => <String, dynamic>{'label': val});
                                tempStageLabel = found['label']?.toString();
                              });
                            },
                          ),
                          const SizedBox(height: 20),
                          Text('Type Of Maintenance', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[800])),
                          const SizedBox(height: 8),
                          ModernSearchableDropdown(
                            label: 'Type Of Maintenance',
                            value: tempTypeId,
                            items: {
                              for (var t in typesRaw) t['id'].toString(): t['label'].toString()
                            },
                            color: Colors.indigo,
                            icon: Icons.precision_manufacturing_rounded,
                            onChanged: (val) {
                              setStateDialog(() {
                                tempTypeId = val;
                                final found = typesRaw.firstWhere(
                                    (t) => t['id'] == val,
                                    orElse: () => <String, dynamic>{'label': val});
                                tempTypeLabel = found['label']?.toString();
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
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey)),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    setState(() {
                      _assessmentStage = tempStageLabel;
                      _maintenanceType = tempTypeLabel;
                      localAuditData['assessment_stage'] = tempStageLabel;
                      localAuditData['assessment_stage_id'] = tempStageId;
                      localAuditData['maintenance_type'] = tempTypeLabel;
                      localAuditData['maintenance_type_id'] = tempTypeId;
                    });

                    try {
                      await FirebaseFirestore.instance
                          .collection('audit_submissions')
                          .doc(widget.documentId)
                          .update({
                        'assessment_stage': tempStageLabel,
                        'assessment_stage_id': tempStageId,
                        'maintenance_type': tempTypeLabel,
                        'maintenance_type_id': tempTypeId,
                      });

                      if (!context.mounted) return;
                      Navigator.pop(context);

                      if (!mounted) return;
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(content: Text('Maintenance Details Saved', style: GoogleFonts.outfit()), backgroundColor: Colors.green),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(content: Text('Error saving: $e', style: GoogleFonts.outfit()), backgroundColor: Colors.red),
                      );
                    }
                  },
                  icon: const Icon(Icons.save, size: 18),
                  label: Text('Save', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPMTeamDialog() {
    // Initialize from localAuditData
    final TextEditingController leaderController = TextEditingController(
      text: localAuditData['pm_team_leader']?.toString() ?? '',
    );
    
    List<String> members = [];
    if (localAuditData['pm_team_members'] is List) {
      members = List<String>.from(localAuditData['pm_team_members'] as Iterable<dynamic>);
    }
    
    List<TextEditingController> memberControllers = members.map((m) => TextEditingController(text: m)).toList();
    
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.people_alt, color: Colors.orange[700], size: 24),
                  const SizedBox(width: 8),
                  Text('PM Team Details', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 450,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Team Leader
                      TextField(
                        controller: leaderController,
                        decoration: InputDecoration(
                          labelText: 'Team Leader Name',
                          prefixIcon: const Icon(Icons.person, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.orange[600]!, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // Team Members Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Team Members (${memberControllers.length}/15)',
                            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700]),
                          ),
                          TextButton.icon(
                            onPressed: memberControllers.length >= 15
                                ? null
                                : () {
                                    setStateDialog(() {
                                      memberControllers.add(TextEditingController());
                                    });
                                  },
                            icon: const Icon(Icons.add, size: 18),
                            label: Text('Add Member', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                            style: TextButton.styleFrom(
                              foregroundColor: memberControllers.length >= 15 ? Colors.grey : Colors.orange[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      
                      // Member List
                      if (memberControllers.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'No team members added yet',
                              style: GoogleFonts.outfit(color: Colors.grey[500]),
                            ),
                          ),
                        )
                      else
                        ...memberControllers.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final controller = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Colors.orange[100],
                                  child: Text(
                                    '${idx + 1}',
                                    style: GoogleFonts.outfit(fontSize: 12, color: Colors.orange[800], fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: controller,
                                    decoration: InputDecoration(
                                      hintText: 'Member ${idx + 1} name',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  onPressed: () {
                                    setStateDialog(() {
                                      memberControllers[idx].dispose();
                                      memberControllers.removeAt(idx);
                                    });
                                  },
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  color: Colors.red[400],
                                  tooltip: 'Remove member',
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    // Dispose controllers
                    leaderController.dispose();
                    for (var c in memberControllers) {
                      c.dispose();
                    }
                    Navigator.pop(context);
                  },
                  child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey)),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    // Collect data
                    final leader = leaderController.text.trim();
                    final membersList = memberControllers
                        .map((c) => c.text.trim())
                        .where((m) => m.isNotEmpty)
                        .toList();
                    
                    // Update local state
                    setState(() {
                      localAuditData['pm_team_leader'] = leader;
                      localAuditData['pm_team_members'] = membersList;
                    });
                    
                    // Save to Firestore
                    try {
                      await FirebaseFirestore.instance
                          .collection('audit_submissions')
                          .doc(widget.documentId)
                          .update({
                        'pm_team_leader': leader,
                        'pm_team_members': membersList,
                      });
                      
                      if (!context.mounted) {
                        return;
                      }
                      Navigator.pop(context);
                      
                      if (!mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text('Team Details Saved', style: GoogleFonts.outfit()),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } catch (e) {
                      if (!mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text('Error saving: $e', style: GoogleFonts.outfit()),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    
                    // Dispose controllers
                    leaderController.dispose();
                    for (var c in memberControllers) {
                      c.dispose();
                    }
                  },
                  icon: const Icon(Icons.save, size: 18),
                  label: Text('Save Team', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _getSortedTasks();
    // final siteName = localAuditData['site'] ?? 'Unknown Site'; // Unused
    final String turbineName = (localAuditData['turbine'] ?? 'Unknown Turbine').toString();
    final timestamp = localAuditData['timestamp'];
    String formattedDate = 'N/A';
    if (timestamp != null && timestamp is Timestamp) {
      formattedDate = DateFormat('dd/MM/yyyy').format(timestamp.toDate());
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveAllChanges,
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
                  Text('Site Name: ${localAuditData['site'] ?? localAuditData['site_name'] ?? 'Site'}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
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
              _buildHeaderItem('Turbine Number', turbineName),
              const SizedBox(width: 16),
              _buildHeaderItem('Audit Date', formattedDate),
            ],
          ),
        ),
        actions: [
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
                    backgroundColor: widget.auditData['auditor_remark_seen'] == false
                        ? Colors.orangeAccent.withValues(alpha: 0.8)
                        : Colors.white.withValues(alpha: 0.2),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ElevatedButton.icon(
              onPressed: _saveAllChanges,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: Text('Save', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            child: ElevatedButton(
              onPressed: _submitToManager,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1F36),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text('Send for Review', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
            ),
          ),
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
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(24),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildMetadataSection(),
                        const SizedBox(height: 32),
                        _buildStatsSection(tasks),
                        const SizedBox(height: 32),
                      ]),
                    ),
                  ),
                  ..._buildHierarchicalTaskSlivers(),
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
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
                          // Selected Task Card
                          if (tasks.isNotEmpty)
                            _buildTaskCard(
                              tasks, 
                              _selectedTaskIndex,
                              isSelected: true,
                              obsController: _selectedObservationController,
                            ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Collapsible Header
        InkWell(
          onTap: () => setState(() => _isMetadataExpanded = !_isMetadataExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 20,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D7377),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Turbine Details',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0D7377),
                      ),
                    ),
                  ],
                ),
                AnimatedRotation(
                  turns: _isMetadataExpanded ? 0.0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF0D7377)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        // Collapsible Content
        AnimatedCrossFade(
          firstChild: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2, 
                    child: Stack(
                      children: [
                        _buildTextField('Turbine Make', _turbineMakeController),
                         if (_isLoadingDetails)
                          const Positioned(
                            bottom: 2, left: 2, right: 2,
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: _buildTextField('WTG Model', _wtgModelController, readOnly: true)),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1, 
                    child: Stack(
                      children: [
                        _buildTextField('WTG Rating', _wtgRatingController),
                        if (_isLoadingDetails)
                          const Positioned(
                            bottom: 2, left: 2, right: 2,
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildDatePicker('Commissioning Date', _commissioningDate, (d) => setState(() => _commissioningDate = d))),
                  const SizedBox(width: 16),
                  Expanded(child: _buildDatePicker('Date of Take Over', _dateOfTakeOver, (d) => setState(() => _dateOfTakeOver = d))),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildDatePicker('Plan Date of Maintenance', _planDateMaintenance, (d) => setState(() => _planDateMaintenance = d))),
                  const SizedBox(width: 16),
                  Expanded(child: _buildDatePicker('Actual Date of Maintenance', _actualDateMaintenance, (d) => setState(() => _actualDateMaintenance = d))),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField('Customer Name', _customerNameController),
            ],
          ),
          secondChild: const SizedBox.shrink(),
          crossFadeState: _isMetadataExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 300),
        ),
      ],
    );
  }



  Widget _buildTextField(String label, TextEditingController controller, {bool readOnly = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: readOnly ? Colors.grey[200] : const Color(0xFFE0F2F1), // Visual cue for read-only
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF80CBC4)),
          ),
          child: TextField(
            controller: controller,
            readOnly: readOnly,
            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w500, color: readOnly ? Colors.grey[700] : Colors.black87),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: GoogleFonts.outfit(color: Colors.black54, fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker(String label, DateTime? date, void Function(DateTime) onSelect) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          onSelect(picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[400]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.outfit(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  date != null ? DateFormat('dd/MM/yyyy').format(date) : 'calendar',
                  style: GoogleFonts.outfit(fontSize: 13, color: date != null ? Colors.black87 : Colors.grey[400]),
                ),
                Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection(List<MapEntry<String, dynamic>> tasks) {
    int okCount = 0;
    int notOkCount = 0;
    for (var entry in tasks) {
      final status = entry.value['status']?.toString().toLowerCase() ?? '';
      if (status == 'ok') {
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isActive ? countColor.withValues(alpha: 0.12) : Colors.purple.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? countColor : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: GoogleFonts.outfit(color: Colors.black87, fontSize: 14)),
                    if (isActive)
                      Text('Filtering', style: GoogleFonts.outfit(fontSize: 10, color: countColor, fontWeight: FontWeight.w600)),
                  ],
                ),
                Row(
                  children: [
                    Text('$count', style: GoogleFonts.outfit(color: countColor, fontSize: 24, fontWeight: FontWeight.bold)),
                    if (isActive) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.close, size: 14, color: countColor),
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


  // ─── Flat List Builder ────────────────────────────────────────────────────

  /// Flattens _processedGroups (after filter) into a heterogeneous list:
  ///   - _FlatCategoryHeader  → triggers a SliverPersistentHeader
  ///   - `Map<String, dynamic>` (task) → renders as a flat task row
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
                  .where((t) => (t['status']?.toString().toLowerCase() ?? '') == filterLower)
                  .toList();
              if (filteredTasks.isNotEmpty) {
                final newSub = AuditGroup(subGroup.title)
                  ..tasks.addAll(filteredTasks);
                newMain.subGroups[k] = newSub;
                newMain.okCount += newSub.tasks.where((t) => (t['status']?.toString().toLowerCase() ?? '') == 'ok').length;
                newMain.notOkCount += newSub.tasks.where((t) => (t['status']?.toString().toLowerCase() ?? '') != 'ok').length;
              }
            });
            return newMain;
          })
          .where((g) => g.subGroups.isNotEmpty)
          .toList();
    }

    for (final mainGroup in displayGroups) {
      final allTasks = mainGroup.subGroups.values.expand((sg) => sg.tasks).toList();
      final okCount = allTasks.where((t) => (t['status']?.toString().toLowerCase() ?? '') == 'ok').length;
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
        // Sub-category separator header
        items.add(_FlatSubCategoryHeader(
          title: subGroup.title,
          ncCount: ncCount,
        ));
        for (final task in subGroup.tasks) {
          items.add(task);
        }
      }
    }
    return items;
  }

  List<Widget> _buildHierarchicalTaskSlivers() {
    final flatItems = _buildFlatItems();

    if (flatItems.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                _filterStatus == 'all' ? 'No tasks found.' : 'No "$_filterStatus" tasks.',
                style: GoogleFonts.outfit(color: Colors.grey[500], fontStyle: FontStyle.italic),
              ),
            ),
          ),
        ),
      ];
    }

    final List<Widget> slivers = [];

    // Deferred emission: buffer sub-group tasks until the next sub-header arrives
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
    flushSubGroup(); // emit final pending sub-group

    return slivers;
  }

  /// Single flat task row with a 4px NC strip, color-coded background,
  /// truncated observation, and tap-to-select behaviour.
  Widget _buildFlatTaskItem(Map<String, dynamic> task) {
    final isOk = (task['status']?.toString().toLowerCase() ?? '') == 'ok';
    final originalIndex = task['original_index'] as int;
    final isSelected = originalIndex == _selectedTaskIndex;

    final question = task['question']?.toString() ?? 'No Question';
    final observation = task['observation']?.toString() ?? '';
    final hasObs = observation.isNotEmpty;

    // Color palette
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
                  // Question text
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
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isOk 
                          ? const Color(0xFF43A047) 
                          : (_isNCReviewed(task) ? Colors.blue[700] : const Color(0xFFE53935)),
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
                ],
              ),
              // sub_category_name removed — now shown as a dedicated SubCategoryHeader above the group
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





  Widget _buildTaskCard(
    List<MapEntry<String, dynamic>> tasks, 
    int index, 
    {
      required bool isSelected,
      required TextEditingController obsController,
    }
  ) {
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
    String? refId = item['reference_id']?.toString();
    
    // Auto-select reference by name if ID is missing
    if (refId == null || refId.isEmpty || refId == 'null') {
      final refName = (item['reference_name'] ?? item['referenceoftask'] ?? '').toString();
      if (refName.isNotEmpty) {
        final match = _allReferences.firstWhere(
          (r) => r['name'].toString().toLowerCase() == refName.toLowerCase(),
          orElse: () => {},
        );
        if (match.isNotEmpty) {
          refId = match['id'].toString();
        }
      }
    }
    // final String referenceName = (_refIdToName[refId] ?? item['reference_name'] ?? item['referenceoftask'] ?? '').toString(); // Unused
    final photosList = item['photos'] is List<dynamic> ? item['photos'] as List<dynamic> : <dynamic>[];
    final List<String> photos = photosList.whereType<String>().toList();

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
        boxShadow: const [
          BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.05), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  '# Audit Task ${index + 1}',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                if (item['is_corrected'] == true) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, size: 14, color: Colors.green),
                        const SizedBox(width: 4),
                        Text('Corrected On-Site', style: GoogleFonts.outfit(fontSize: 12, color: Colors.green[800], fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
                 // Status Toggle
                 SegmentedButton<String>(
                   segments: const [
                     ButtonSegment(
                       value: 'OK',
                       label: Text('OK', style: TextStyle(fontSize: 12)),
                       icon: Icon(Icons.check_circle_outline, size: 15),
                     ),
                     ButtonSegment(
                       value: 'Not OK',
                       label: Text('Not OK', style: TextStyle(fontSize: 12)),
                       icon: Icon(Icons.cancel_outlined, size: 15),
                     ),
                   ],
                   selected: {item['status']?.toString() ?? 'Not OK'},
                   onSelectionChanged: (Set<String> newSel) {
                     final newStatus = newSel.first;
                     setState(() {
                       localAuditData['audit_data'][taskKey]['status'] = newStatus;
                     });
                     _markTaskAsModified(index);
                     if (newStatus == 'Not OK' &&
                         (localAuditData['audit_data'][taskKey]['nc_category'] == null ||
                          localAuditData['audit_data'][taskKey]['nc_category'].toString().isEmpty)) {
                       _showNCCategoryDialog(index);
                     }
                   },
                   style: ButtonStyle(
                     visualDensity: VisualDensity.compact,
                     padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 8)),
                     backgroundColor: WidgetStateProperty.resolveWith((states) {
                       if (states.contains(WidgetState.selected)) {
                         final selectedStatus = item['status']?.toString() ?? 'Not OK';
                         return selectedStatus == 'OK' ? Colors.green.shade100 : Colors.red.shade100;
                       }
                       return null;
                     }),
                   ),
                 ),
                if (!isOk) ...[
                  // Sub-Status Dropdown
                  ModernSearchableDropdown(
                    label: 'Sub Status',
                    showLabel: false,
                    value: <String>['Aobs', 'MCF', 'CF'].contains(subStatus) ? subStatus.toString() : null,
                    items: const {'Aobs': 'Aobs', 'MCF': 'MCF', 'CF': 'CF'},
                    color: Colors.orange,
                    icon: Icons.priority_high_rounded,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => localAuditData['audit_data'][taskKey]['sub_status'] = val);
                        _markTaskAsModified(index);
                      }
                    },
                  ),
                  
                  // Reference Selector
                  if (!_isLoadingReferences) ...[
                    SizedBox(
                      width: 200,
                      child: ModernSearchableDropdown(
                        label: 'Reference',
                        showLabel: false,
                        hint: 'Select Reference',
                        value: refId,
                        items: { for (var r in _allReferences) r['id'].toString() : r['name'].toString() },
                        color: Colors.blue,
                        icon: Icons.menu_book_rounded,
                        onChanged: (val) {
                          if (val != null) {
                            _updateTaskReference(taskKey, val);
                            _markTaskAsModified(index);
                          }
                        },
                      ),
                    ),
                  ],
                ],
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
                  // Question
                  Text(question.toString(), style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  
                  // NC Category Badge (if exists)
                  if (item['nc_category'] != null && item['nc_category'].toString().isNotEmpty) ...[
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
                              item['nc_category'].toString(),
                              style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: item['nc_category'] == 'Quality of Workmanship' ? Colors.orange[800] :
                                         item['nc_category'] == 'RWP Point' ? Colors.blue[800] :
                                         Colors.purple[800]
                              ),
                          ),
                      ),
                      const SizedBox(height: 12),
                  ],
                  
                   // 2x2 Grid Layout for Not OK tasks, simple layout for OK tasks
                  if (!isOk) ...[
                    // 2x2 Grid: Left Column (Observation + Photos), Right Column (Remark + Closure)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                        // Left Column
                        Expanded(
                          flex: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top: Observation TextField
                              TextField(
                                controller: obsController,
                                decoration: InputDecoration(
                                  labelText: 'Observation',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                onChanged: (val) {
                                  localAuditData['audit_data'][taskKey]['observation'] = val;
                                  _markTaskAsModified(index);
                                },
                              ),
                              const SizedBox(height: 12),
                              // Bottom: Audit Photos with Gradient Border
                              Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Colors.blue, Colors.purple, Colors.red],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(9.5),
                                ),
                                padding: const EdgeInsets.all(1.5),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.photo_library, size: 16, color: Colors.grey[600]),
                                          const SizedBox(width: 4),
                                          Text('Audit Photos', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        height: 70,
                                        child: ListView.builder(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: photos.length + 1,
                                          itemBuilder: (context, photoIndex) {
                                            if (photoIndex == photos.length) {
                                              return InkWell(
                                                onTap: () => _addPhoto(taskKey, index),
                                                child: Container(
                                                  width: 70,
                                                  margin: const EdgeInsets.only(right: 8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey[100],
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
                                                  ),
                                                  child: const Icon(Icons.add_a_photo, color: Colors.grey),
                                                ),
                                              );
                                            }
                                            
                                            return Stack(
                                              children: [
                                                GestureDetector(
                                                  onTap: () => _showFullScreenImage(photos[photoIndex]),
                                                  child: Container(
                                                    width: 70,
                                                    height: 70,
                                                    margin: const EdgeInsets.only(right: 8),
                                                    child: ClipRRect(
                                                      borderRadius: BorderRadius.circular(8),
                                                      child: Image.network(photos[photoIndex], fit: BoxFit.cover),
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  top: 0,
                                                  right: 8,
                                                  child: InkWell(
                                                    onTap: () => _removePhoto(taskKey, photoIndex, index),
                                                    child: const CircleAvatar(
                                                      radius: 10,
                                                      backgroundColor: Colors.red,
                                                      child: Icon(Icons.close, size: 12, color: Colors.white),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Right Column
                        Expanded(
                          flex: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // On-Site Closure Details
                              Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Colors.blue, Colors.purple, Colors.red],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(9.5),
                                ),
                                padding: const EdgeInsets.all(1.5),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  child: item['is_corrected'] == true
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.build_circle, size: 16, color: Color(0xFF00695C)),
                                              const SizedBox(width: 4),
                                              Text('On-Site Closure', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF00695C))),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // Closure Photo
                                              if (item['closure_photo'] != null && item['closure_photo'].toString().isNotEmpty) ...[
                                                InkWell(
                                                  onTap: () {
                                                    showDialog<void>(
                                                      context: context,
                                                      builder: (context) => Dialog(
                                                        backgroundColor: Colors.transparent,
                                                        insetPadding: EdgeInsets.zero,
                                                        child: Stack(
                                                          alignment: Alignment.center,
                                                          children: [
                                                            InteractiveViewer(child: Image.network(item['closure_photo'].toString(), fit: BoxFit.contain)),
                                                            Positioned(
                                                              top: 40, right: 20,
                                                              child: IconButton(
                                                                icon: const Icon(Icons.close, color: Colors.white),
                                                                onPressed: () => Navigator.pop(context),
                                                                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  child: Container(
                                                    width: 54,
                                                    height: 54,
                                                    decoration: BoxDecoration(
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: Colors.teal[300]!),
                                                    ),
                                                    child: ClipRRect(
                                                      borderRadius: BorderRadius.circular(6),
                                                      child: Image.network(item['closure_photo'].toString(), fit: BoxFit.cover),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                              ],
                                              // Closure Remark & Status
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item['closure_remark'] is String && item['closure_remark'].toString().isNotEmpty 
                                                          ? item['closure_remark'].toString() 
                                                          : 'Corrected on-site',
                                                      style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF00695C)),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: (item['closure_status']?.toString().toLowerCase() ?? 'ok') == 'ok' 
                                                            ? Colors.green 
                                                            : Colors.red,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        item['closure_status'] is String ? item['closure_status'].toString() : 'OK',
                                                        style: GoogleFonts.outfit(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      )
                                    : SizedBox(
                                        height: 70,
                                        child: Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.pending_actions, size: 24, color: Colors.grey[400]),
                                              const SizedBox(height: 4),
                                              Text('Pending Closure', style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey[500])),
                                            ],
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    ),
                    const SizedBox(height: 12),
                    // Compact Action Buttons Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Compact NC Category Icon Button
                        Tooltip(
                          message: item['nc_category'] != null ? 'NC Category: ${item['nc_category']}' : 'Classify NC',
                          child: InkWell(
                            onTap: () => _showNCCategoryDialog(index),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: item['nc_category'] != null ? Colors.blue[50] : Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: item['nc_category'] != null ? Colors.blue : Colors.grey[300]!,
                                ),
                              ),
                              child: Icon(
                                Icons.category,
                                size: 20,
                                color: item['nc_category'] != null ? Colors.blue[700] : Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Compact Action Plan Icon Button
                        Tooltip(
                          message: item['action_plan'] != null && item['action_plan'].toString().isNotEmpty 
                              ? 'Action Plan Saved' 
                              : 'Create Action Plan',
                          child: InkWell(
                            onTap: () => _showActionPlanDialog(index),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: item['action_plan'] != null && item['action_plan'].toString().isNotEmpty 
                                    ? Colors.green[50] 
                                    : const Color(0xFFE8EAF6),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: item['action_plan'] != null && item['action_plan'].toString().isNotEmpty 
                                      ? Colors.green 
                                      : const Color(0xFF3F51B5),
                                ),
                              ),
                              child: Icon(
                                item['action_plan'] != null && item['action_plan'].toString().isNotEmpty 
                                    ? Icons.check_circle 
                                    : Icons.assignment_turned_in,
                                size: 20,
                                color: item['action_plan'] != null && item['action_plan'].toString().isNotEmpty 
                                    ? Colors.green[700] 
                                    : const Color(0xFF3F51B5),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Display Saved Action Plan (if exists)
                    if (item['action_plan'] != null && item['action_plan'].toString().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.assignment_turned_in, size: 20, color: Colors.indigo[700]),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Action Plan', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo[800])),
                                  const SizedBox(height: 6),
                                  Text('Plan: ${item['action_plan']}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.indigo[900])),
                                  if (item['root_cause'] != null && item['root_cause'].toString().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text('Root Cause: ${item['root_cause']}', style: GoogleFonts.outfit(fontSize: 12, color: Colors.indigo[700])),
                                  ],
                                  if (item['target_date'] != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Target Date: ${item['target_date'] is Timestamp ? DateFormat('dd/MM/yyyy').format((item['target_date'] as Timestamp).toDate()) : item['target_date'].toString()}',
                                      style: GoogleFonts.outfit(fontSize: 12, color: Colors.indigo[700]),
                                    ),
                                  ],
                                  if (item['material_status'] == 'PI Already Raised' && item['pi_number'] != null && item['pi_number'].toString().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'PI: ${item['pi_number']}${item['pi_date'] != null ? ' (${item['pi_date'] is Timestamp ? DateFormat('dd/MM/yyyy').format((item['pi_date'] as Timestamp).toDate()) : item['pi_date'].toString()})' : ''}',
                                      style: GoogleFonts.outfit(fontSize: 12, color: Colors.indigo[700]),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ] else ...[
                    // OK tasks - simple vertical layout
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: obsController,
                            decoration: InputDecoration(
                              labelText: 'Observation',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            onChanged: (val) {
                              localAuditData['audit_data'][taskKey]['observation'] = val;
                              _markTaskAsModified(index);
                            },
                          ),
                        ),
                      ],

                    ),
                    const SizedBox(height: 16),
                    // Photos for OK tasks
                    SizedBox(
                      height: 80,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: photos.length + 1,
                        itemBuilder: (context, photoIndex) {
                          if (photoIndex == photos.length) {
                            return InkWell(
                              onTap: () => _addPhoto(taskKey, index),
                              child: Container(
                                width: 80,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
                                ),
                                child: const Icon(Icons.add_a_photo, color: Colors.grey),
                              ),
                            );
                          }
                          
                          return Stack(
                            children: [
                              Container(
                                width: 80,
                                margin: const EdgeInsets.only(right: 8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(photos[photoIndex], fit: BoxFit.cover),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 8,
                                child: InkWell(
                                  onTap: () => _removePhoto(taskKey, photoIndex, index),
                                  child: const CircleAvatar(
                                    radius: 10,
                                    backgroundColor: Colors.red,
                                    child: Icon(Icons.close, size: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
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

// ─── Flat List Data Models ─────────────────────────────────────────────────

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

/// Light-weight data class for a sub-category separator row.
class _FlatSubCategoryHeader {
  final String title;
  final int ncCount;
  const _FlatSubCategoryHeader({required this.title, required this.ncCount});
}

// ─── Sticky Header Delegate ────────────────────────────────────────────────

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
                bg: const Color(0xFFB71C1C),
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

/// Subtle separator shown between sub-category groups in the left panel.
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
                color: const Color(0xFFB71C1C).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${header.ncCount} NC',
                style: GoogleFonts.outfit(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFB71C1C),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _HeaderPill({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
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
    int notOkCount = tasks.where((t) => (t['status']?.toString().toLowerCase() ?? '') == 'not ok').length;
    int totalCount = tasks.length;
    
    // Logic: Show Not OK count if > 0, else show Total count
    String centerText = notOkCount > 0 ? '$notOkCount' : '$totalCount';
    Color centerTextColor = notOkCount > 0 ? Colors.red : Colors.black;

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

    final double strokeWidth = 4.0; 
    final Rect rect = Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2, size.width - strokeWidth, size.height - strokeWidth);
    
    double startAngle = -3.14159 / 2; // -90 degrees (Start from top)
    double sweepAngle = (2 * 3.14159) / tasks.length;
    
    // Add a small gap between segments for visual clarity
    double gap = tasks.length > 1 ? 0.2 : 0.0; // in radians
    double drawSweep = sweepAngle - gap;
    if (drawSweep <= 0) drawSweep = sweepAngle; // Fallback if too many tasks

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt; // Flat ends for donut segments

    for (var task in tasks) {
      paint.color = _getColor(task);
      // Center the segment in its angular slot if we have a gap
      double currentStart = startAngle + (gap / 2);
      canvas.drawArc(rect, currentStart, drawSweep, false, paint);
      startAngle += sweepAngle;
    }
  }

  Color _getColor(Map<String, dynamic> task) {
    final status = task['status']?.toString().toLowerCase() ?? '';
    final hasObservation = (task['observation']?.toString().trim().isNotEmpty ?? false);

    // Red: If status is 'Not OK'
    if (status == 'not ok' || status == 'notok' || status == 'not_ok') {
      return Colors.red;
    }
    
    // Green: If status is 'OK'
    if (status == 'ok') {
      return Colors.green;
    }
    
    // Blue: If task is 'Modified' (or has an observation but no final status yet)
    // Interpret 'Modified' as: Status is empty/pending BUT observation exists
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
