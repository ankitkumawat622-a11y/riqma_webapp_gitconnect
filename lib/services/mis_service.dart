import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Service to handle automated synchronization of audit data to the 'SQA RIQMA MIS' collection.
/// This collection is designed for cross-platform tracking and deep analysis.
class MISService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Main entry point to sync audit data. Triggered on Manager Approval.
  Future<void> syncAuditToMIS(String auditId, Map<String, dynamic> auditData) async {
    try {
      // 1. Fetch Master Metadata (Site, Model, State, Turbine Type)
      final masterData = await _fetchMasterData(auditData);
      
      // 2. Fetch Latest NC Documents
      final ncs = await _fetchNCsForAudit(auditId);
      
      // 3. Fetch NC Categories for Workman Penalty Logic
      final workmanPenaltyMap = await _fetchWorkmanPenaltyMap();
      
      // 4. Extract Timing Info
      final timestamp = auditData['timestamp'] as Timestamp?;
      final auditDate = timestamp?.toDate() ?? DateTime.now();
      final fy = _getFinancialYear(auditDate);

      // 5. Calculate overall scores for this audit
      final tasks = auditData['audit_data'] as Map<String, dynamic>? ?? {};
      final metrics = _calculateAuditMetrics(tasks, ncs, workmanPenaltyMap);

      final WriteBatch batch = _firestore.batch();
      bool hasNCs = false;

      // 6. Process each task that is an NC or corrected observation
      for (final entry in tasks.entries) {
        final taskKey = entry.key;
        final task = entry.value as Map<String, dynamic>;
        
        final statusLower = (task['status'] ?? '').toString().toLowerCase();
        final isCorrected = task['is_corrected'] == true;

        // We only push NCs or observations to MIS
        if (statusLower == 'ok' && !isCorrected) continue;
        
        hasNCs = true;
        final nc = ncs[taskKey];
        
        // Determinstic ID for dynamic updates: auditId_taskKey
        final docId = '${auditId}_$taskKey';
        final docRef = _firestore.collection('SQA RIQMA MIS').doc(docId);
        
        final misData = _prepareMISData(
          auditId: auditId,
          taskKey: taskKey,
          fy: fy,
          auditData: auditData,
          task: task,
          nc: nc,
          masterData: masterData,
          metrics: metrics,
          auditDate: auditDate,
        );
        
        batch.set(docRef, misData, SetOptions(merge: true));
      }

      // 7. If no NCs found, create a single 'Compliant' summary record
      if (!hasNCs) {
        final docRef = _firestore.collection('SQA RIQMA MIS').doc('${auditId}_SUMMARY');
        final misData = _prepareMISData(
          auditId: auditId,
          taskKey: 'SUMMARY',
          fy: fy,
          auditData: auditData,
          task: {},
          nc: null,
          masterData: masterData,
          metrics: metrics,
          auditDate: auditDate,
          isSummaryOnly: true,
        );
        batch.set(docRef, misData, SetOptions(merge: true));
      }

      await batch.commit();
    } catch (e) {
      // Silently fail or log for internal monitoring
      // print('MIS Sync Error: $e');
    }
  }

  /// Maps and flattens all data points into a single MIS document.
  Map<String, dynamic> _prepareMISData({
    required String auditId,
    required String taskKey,
    required String fy,
    required Map<String, dynamic> auditData,
    required Map<String, dynamic> task,
    required Map<String, dynamic>? nc,
    required Map<String, String> masterData,
    required Map<String, dynamic> metrics,
    required DateTime auditDate,
    bool isSummaryOnly = false,
  }) {
    // Basic formatting
    final String auditDateStr = DateFormat('dd.MM.yyyy').format(auditDate);
    final String turbineNo = (auditData['turbine'] ?? '').toString();
    
    // Logic for Status (Open/Close only)
    final String rawStatus = (nc?['status'] ?? (task['is_corrected'] == true ? 'Close' : 'Open')).toString();
    // Map OSC or any variation of close to 'Close'
    final String finalStatus = (rawStatus.toLowerCase().contains('close') || rawStatus.toLowerCase().contains('osc')) 
        ? 'Close' 
        : 'Open';

    // Material Tracking Logic (Root Cause = "Material Not Available")
    final String rootCause = (nc?['root_cause'] ?? task['root_cause'] ?? '').toString();
    final bool isMaterialRelated = (rootCause == 'Material Not Available');

    // Criticality Mapping
    final String criticality = (nc?['nc_criticality'] ?? task['sub_status'] ?? 'Aobs').toString();
    int ratingCategory = 1;
    if (criticality == 'CF') {
      ratingCategory = 3;
    } else if (criticality == 'MCF') {
      ratingCategory = 2;
    }

    // Date calculations
    DateTime? closeDate;
    if (finalStatus == 'Close') {
      final val = nc?['closing_date'];
      closeDate = _parseDate(val) ?? auditDate; // Fallback to audit date for OSC
    }
    
    int daysTaken = 0;
    if (closeDate != null) {
      daysTaken = closeDate.difference(auditDate).inDays;
    }

    // Team info
    final pmLead = auditData['pm_team_leader']?.toString() ?? '';
    final pmMembers = auditData['pm_team_members'] is List 
        ? (auditData['pm_team_members'] as List).join(', ') 
        : '';

    return {
      // Identifiers
      'audit_id': auditId,
      'task_key': taskKey,
      'sync_timestamp': FieldValue.serverTimestamp(),
      'fy': fy,
      'is_summary_record': isSummaryOnly,

      // Audit Header
      'audit_date': auditDateStr,
      'auditor_name': (auditData['auditor_name'] ?? '').toString(),
      'customer_name': (auditData['customer_name'] ?? '').toString(),
      'report_status': (auditData['status'] ?? 'Open').toString(),
      'is_material_related': isMaterialRelated,
      'material_tracking_status': isMaterialRelated ? 'Pending' : null,

      // Location Details
      'site_name': (auditData['site'] ?? '').toString(),
      'state': (auditData['state'] ?? '').toString(),
      'district': masterData['district'] ?? '',
      'zone': masterData['zone'] ?? '',
      'warehouse_code': masterData['warehouse_code'] ?? '',

      // Asset Details
      'turbine_name': turbineNo,
      'wtg_category': masterData['wtg_category'] ?? 'Existing',
      'turbine_make': masterData['turbine_make'] ?? '',
      'turbine_model': masterData['turbine_model'] ?? '',
      'turbine_rating_mw': masterData['turbine_rating'] ?? '',
      'commission_date': _formatDate(auditData['commissioning_date']),
      'takeover_date': _formatDate(auditData['date_of_take_over']),

      // NC/Observation Info (Empty for summary records)
      'main_head': isSummaryOnly ? '-' : (task['main_category_name'] ?? '-').toString(),
      'sub_component': isSummaryOnly ? '-' : (task['sub_category_name'] ?? '-').toString(),
      'finding': isSummaryOnly ? 'No Issues Found' : (nc?['finding'] ?? task['observation'] ?? '-').toString(),
      'criticality': isSummaryOnly ? '-' : criticality,
      'rating_category': isSummaryOnly ? 0 : ratingCategory,
      
      // Tracking
      'status': isSummaryOnly ? 'Close' : finalStatus,
      'root_cause': isSummaryOnly ? '' : (nc?['root_cause'] ?? task['root_cause'] ?? '').toString(),
      'plan_date': isSummaryOnly ? '' : _formatDate(nc?['target_date'] ?? task['target_date']),
      'action_plan': isSummaryOnly ? '' : (nc?['action_plan'] ?? task['action_plan'] ?? '').toString(),
      'date_of_closure': finalStatus == 'Close' ? DateFormat('dd.MM.yyyy').format(closeDate!) : '',
      'action_taken': isSummaryOnly ? '' : (nc?['action_taken'] ?? task['closure_remark'] ?? '').toString(),
      'days_taken': daysTaken,

      // Photos (URLs)
      'finding_photos': isSummaryOnly ? <String>[] : (nc?['photos'] ?? task['photos'] ?? <String>[]),
      'closure_photo': isSummaryOnly ? null : (nc?['closure_photo'] ?? task['closure_photo']),

      // PM Info
      'pm_type': (auditData['maintenance_type'] ?? '').toString(),
      'pm_lead': pmLead,
      'pm_team': pmMembers,
      'pm_plan_date': _formatDate(auditData['plan_date_of_maintenance']),
      'pm_done_date': _formatDate(auditData['actual_date_of_maintenance']),

      // Assessment Scores
      'overall_score': metrics['overall_score'],
      'overall_compliance_pct': metrics['overall_compliance'],
      'workman_score': metrics['workman_score'],
      'workman_compliance_pct': metrics['workman_compliance'],
    };
  }

  /// Calculates aggregated scores and metrics for the audit.
  Map<String, dynamic> _calculateAuditMetrics(
    Map<String, dynamic> tasks,
    Map<String, Map<String, dynamic>> ncs,
    Map<String, bool> workmanPenaltyMap,
  ) {
    int totalOverallPenalty = 0;
    int totalWorkmanPenalty = 0;

    for (final entry in tasks.entries) {
      final taskKey = entry.key;
      final task = entry.value as Map<String, dynamic>;
      final nc = ncs[taskKey];

      final criticality = (nc?['nc_criticality'] ?? task['sub_status'] ?? 'Aobs').toString();
      final ncCategory = (nc?['nc_category'] ?? task['nc_category'] ?? '').toString();

      int workman = 0, overall = 0;
      final isWorkman = workmanPenaltyMap[ncCategory] ?? false;

      switch (criticality) {
        case 'Aobs': overall = 1; workman = isWorkman ? 1 : 0; break;
        case 'MCF':  overall = 2; workman = isWorkman ? 2 : 0; break;
        case 'CF':   overall = 3; workman = isWorkman ? 3 : 0; break;
      }

      totalOverallPenalty += overall;
      totalWorkmanPenalty += workman;
    }

    final double overallScore = _getAssessmentScore(totalOverallPenalty);
    final double workmanScore = _getAssessmentScore(totalWorkmanPenalty);
    final double overallCompliance = (100.0 - (totalOverallPenalty * 100 / 75.0)).clamp(0.0, 100.0);
    final double workmanCompliance = (100.0 - (totalWorkmanPenalty * 100 / 75.0)).clamp(0.0, 100.0);

    return {
      'overall_score': double.parse(overallScore.toStringAsFixed(1)),
      'workman_score': double.parse(workmanScore.toStringAsFixed(1)),
      'overall_compliance': double.parse(overallCompliance.toStringAsFixed(2)),
      'workman_compliance': double.parse(workmanCompliance.toStringAsFixed(2)),
    };
  }

  // --- PRIVATE HELPERS ---

  Future<Map<String, String>> _fetchMasterData(Map<String, dynamic> auditData) async {
    final Map<String, String> res = {};
    
    // 1. Turbine Lookup
    final tModelId = auditData['turbine_model_id']?.toString();
    if (tModelId != null && tModelId.isNotEmpty) {
      final doc = await _firestore.collection('turbinemodel').doc(tModelId).get();
      if (doc.exists) {
        final d = doc.data()!;
        res['turbine_make'] = d['turbine_make']?.toString() ?? '';
        res['turbine_model'] = d['turbine_model']?.toString() ?? '';
        res['turbine_rating'] = d['turbine_rating']?.toString() ?? '';
      }
    }

    // 2. Site Lookup
    final siteId = auditData['site_id']?.toString();
    if (siteId != null && siteId.isNotEmpty) {
      final doc = await _firestore.collection('sites').doc(siteId).get();
      if (doc.exists) {
        final d = doc.data()!;
        res['district'] = d['district']?.toString() ?? '';
        res['warehouse_code'] = d['warehouse_code']?.toString() ?? '';
      }
    }

    // 3. State/Zone Lookup
    String? stateId;
    if (auditData['state_ref'] is DocumentReference) {
      stateId = (auditData['state_ref'] as DocumentReference).id;
    } else {
      stateId = auditData['state_id']?.toString();
    }
    if (stateId != null && stateId.isNotEmpty) {
      final doc = await _firestore.collection('states').doc(stateId).get();
      if (doc.exists) {
        res['zone'] = doc.data()?['zone']?.toString() ?? '';
      }
    }

    // 4. WTG Category
    final turbineNo = (auditData['turbine'] ?? '').toString();
    final tSnap = await _firestore.collection('turbinename').where('name', isEqualTo: turbineNo).limit(1).get();
    if (tSnap.docs.isNotEmpty) {
      res['wtg_category'] = tSnap.docs.first.data()['wtg_category']?.toString() ?? 'Existing';
    }

    return res;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchNCsForAudit(String auditId) async {
    final Map<String, Map<String, dynamic>> ncMap = {};
    final snap = await _firestore.collection('ncs')
        .where('audit_ref', isEqualTo: _firestore.doc('/audit_submissions/$auditId'))
        .get();
    for (final doc in snap.docs) {
      final data = doc.data();
      final key = data['task_key']?.toString();
      if (key != null) {
        ncMap[key] = data;
      }
    }
    return ncMap;
  }

  Future<Map<String, bool>> _fetchWorkmanPenaltyMap() async {
    Map<String, bool> res = {'Quality of Workmanship': true};
    try {
      final snap = await _firestore.collection('audit_configs').doc('nc_categories').get();
      if (snap.exists) {
        res = {};
        for (final item in (snap.data()?['items'] as List<dynamic>? ?? [])) {
          final name = (item as Map)['name']?.toString() ?? '';
          res[name] = item['is_workman_penalty'] == true;
        }
      }
    } catch (_) {}
    return res;
  }

  double _getAssessmentScore(int penaltyPoints) {
    if (penaltyPoints <= 0) return 15.0;
    if (penaltyPoints >= 66) return 0.1;

    if (penaltyPoints <= 20) {
      return 15.0 - (penaltyPoints * 0.5);
    } else if (penaltyPoints == 21) {
      return 4.8;
    } else if (penaltyPoints == 22) {
      return 4.5;
    } else {
      final score = 4.4 - ((penaltyPoints - 23) * 0.1);
      return double.parse(score.toStringAsFixed(1));
    }
  }

  String _getFinancialYear(DateTime date) {
    final int year = date.year;
    if (date.month >= 4) return '$year-${(year + 1).toString().substring(2)}';
    return '${year - 1}-${year.toString().substring(2)}';
  }

  DateTime? _parseDate(dynamic val) {
    if (val is Timestamp) return val.toDate();
    if (val is String) return DateTime.tryParse(val);
    return null;
  }

  String _formatDate(dynamic val) {
    final d = _parseDate(val);
    return d != null ? DateFormat('dd.MM.yyyy').format(d) : '';
  }
}
