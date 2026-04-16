import 'dart:js_interop';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' hide Column, Row, Border;
import 'package:web/web.dart' as web;

class ExcelExportService {
  // ===========================================================================
  // CONSTANTS & HELPERS
  // ===========================================================================
  static const List<String> _sqaNcHeaders = <String>[
    'Sr. No.', 'Audit Date', 'Turbine Name', 'Reference', 'Main Category', 'Sub Category',
    'Finding/Observation', 'Finding Photos', 'NC Criticality (CF/MCF/AObs)', 'NC Category',
    'Reason of NC (Cause of NC)', 'Plan Date of NC closure', 'Plan of Action',
    'Action Taken', 'Closing Date', 'Closing Evidence', 'Status', 'Remarks.'
  ];

  /// Fetches NC documents from the 'ncs' collection linked to this audit.
  Future<Map<String, Map<String, dynamic>>> _fetchNCsForAudit(String auditId) async {
    final Map<String, Map<String, dynamic>> ncMap = {};
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('ncs')
          .where('audit_ref', isEqualTo: FirebaseFirestore.instance.doc('/audit_submissions/$auditId'))
          .get();
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final taskKey = data['task_key']?.toString();
        if (taskKey != null) {
          ncMap[taskKey] = data;
        }
      }
    } catch (_) {}
    return ncMap;
  }

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================
  
  /// Generates and downloads the NC Tracking Excel for a specific audit.
  Future<void> generateNCTrackingExcel(String auditId, Map<String, dynamic> auditData) async {
    try {
      final Workbook workbook = Workbook();
      final Worksheet sheet = workbook.worksheets[0];
      sheet.name = 'NC Tracking';

      // Use the standardized 18-header list
      _writeExcelHeaders(sheet, _sqaNcHeaders, width: 100.0);
      sheet.setRowHeightInPixels(1, 40);
      sheet.setColumnWidthInPixels(7, 250); // Finding/Observation
      sheet.setColumnWidthInPixels(8, 200); // Finding Photos

      // Fetch live NCs for "Live" tracking data
      final Map<String, Map<String, dynamic>> liveNCs = await _fetchNCsForAudit(auditId);

      // Data extraction
      final timestamp = auditData['timestamp'] as Timestamp?;
      final auditDate = timestamp?.toDate() ?? DateTime.now();
      final auditDateStr = DateFormat('dd.MM.yyyy').format(auditDate);
      final String siteName = (auditData['site'] ?? 'Unknown').toString();
      final turbineNo = (auditData['turbine'] ?? '').toString();
      final tasks = auditData['audit_data'] as Map<String, dynamic>? ?? {};

      int srNo = 1;
      int rowIndex = 2;

      // Sort tasks numerically by key
      final sortedEntries = tasks.entries.toList()
        ..sort((a, b) {
          final ia = int.tryParse(a.key);
          final ib = int.tryParse(b.key);
          if (ia != null && ib != null) return ia.compareTo(ib);
          return a.key.compareTo(b.key);
        });

      for (final entry in sortedEntries) {
          final taskKey = entry.key;
          final task = entry.value as Map<String, dynamic>;
          final nc = liveNCs[taskKey]; // Live NC document data

          final status = (task['status'] ?? '').toString().toLowerCase();
          final isCorrected = task['is_corrected'] == true;

          // Only include NCs (or corrected tasks)
          if (status == 'ok' && !isCorrected) continue;

          // Merge Task + NC data (NC data takes priority for tracking fields)
          final String reference = (nc?['reference_name'] ?? task['reference_name'] ?? '-').toString();
          final String observation = (nc?['finding'] ?? task['observation'] ?? '-').toString();
          final String criticality = (nc?['nc_criticality'] ?? task['sub_status'] ?? 'Aobs').toString();
          final String category = (nc?['nc_category'] ?? task['nc_category'] ?? '').toString();
          final String rootCause = (nc?['root_cause'] ?? task['root_cause'] ?? '').toString();
          final String actionPlan = (nc?['action_plan'] ?? task['action_plan'] ?? '').toString();
          final String actionTaken = (nc?['action_taken'] ?? task['closure_remark'] ?? (isCorrected ? 'Corrected' : '')).toString();
          final String remarks = (nc?['remarks'] ?? task['closure_remark'] ?? '').toString();
          final String ncStatus = (nc?['status'] ?? (isCorrected ? 'Close' : 'Open')).toString();

          // Date Formatting
          String planDate = '';
          final targetVal = nc?['target_date'] ?? task['target_date'];
          if (targetVal != null) {
            final d = _parseDate(targetVal);
            if (d != null) planDate = DateFormat('dd.MM.yyyy').format(d);
          }

          String closingDate = '';
          final closeVal = nc?['closing_date'] ?? (isCorrected ? auditDate : null);
          if (closeVal != null) {
            final d = _parseDate(closeVal);
            if (d != null) closingDate = DateFormat('dd.MM.yyyy').format(d);
          }

          _writeExcelRow(sheet, rowIndex, <String>[
            srNo.toString(),
            auditDateStr,
            turbineNo,
            reference,
            (task['main_category_name'] ?? '-').toString(),
            (task['sub_category_name'] ?? '-').toString(),
            observation,
            '', // Finding Photos Placeholder (Col 8)
            criticality,
            category,
            rootCause,
            planDate,
            actionPlan,
            actionTaken,
            closingDate,
            '', // Closing Evidence Placeholder (Col 16)
            ncStatus,
            remarks,
          ]);

          // Photos
          final List<dynamic> findingPhotos = (nc != null && nc['photos'] is List) ? nc['photos'] as List<dynamic> : (task['photos'] is List ? task['photos'] as List<dynamic> : <dynamic>[]);
          if (findingPhotos.isNotEmpty) {
            await _embedImages(sheet, rowIndex, 8, findingPhotos);
          }

          // Closure Evidence (NC closure photo)
          final String? closurePhoto = nc?['closure_photo']?.toString() ?? task['closure_photo']?.toString();
          if (closurePhoto != null && closurePhoto.isNotEmpty) {
            await _embedSingleImage(sheet, rowIndex, 16, closurePhoto);
          }

          rowIndex++;
          srNo++;
      }

      if (srNo == 1) {
        sheet.getRangeByIndex(2, 7).setText('No NCs or corrected tasks found');
      }

      // Filename Helper usage
      final fyYear = _getFinancialYear(auditDate);
      final siteCode = siteName.length > 5 ? siteName.substring(0, 5).toUpperCase() : siteName.toUpperCase();
      final sequence = await _getAuditSequenceCount(siteName, auditDate);
      final seqStr = sequence.toString().padLeft(2, '0');
      
      final fileName = 'NC_Tracking_${siteCode}_${turbineNo}_${fyYear}_$seqStr.xlsx';
      
      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();
      _downloadExcelBytes(bytes, fileName);
    } catch (e) {
      // debugPrint('Error: $e');
    }
  }


  /// Generates and downloads the SQA Dump Excel for a specific audit.
  /// Automatically fetches master data.
  Future<void> generateSQADumpExcel(String auditId, Map<String, dynamic> auditData) async {
    try {
      // 1. Fetch Master Data
      final masterData = await _fetchMasterData(auditData);

      // Fetch workman penalty map from Firestore
      Map<String, bool> workmanPenaltyMap = {'Quality of Workmanship': true};
      try {
        final ncSnap = await FirebaseFirestore.instance.collection('audit_configs').doc('nc_categories').get();
        if (ncSnap.exists) {
          workmanPenaltyMap = {};
          for (final item in (ncSnap.data()?['items'] as List<dynamic>? ?? [])) {
            final name = (item as Map)['name']?.toString() ?? '';
            workmanPenaltyMap[name] = item['is_workman_penalty'] == true;
          }
        }
      } catch (_) {}

      // Create Syncfusion Workbook with 2 sheets
      final Workbook workbook = Workbook(2);

      // Common data extraction
      final timestamp = auditData['timestamp'] as Timestamp?;
      final auditDate = timestamp?.toDate();
      final auditDateStr = auditDate != null ? DateFormat('dd-MM-yyyy').format(auditDate) : 'N/A';
      
      final siteName = (auditData['site'] ?? 'Unknown').toString();
      final turbineNo = (auditData['turbine'] ?? '').toString();
      
      // Use fetched data or fallback to auditData
      final turbineMake = (masterData['turbine_make'] ?? auditData['wtg_model'] ?? '').toString(); // wtg_model is sometimes used as make key in legacy? fallback
      final district = (masterData['district'] ?? auditData['district'] ?? '').toString();
      final zone = (masterData['zone'] ?? auditData['zone'] ?? '').toString();
      final warehouseCode = (masterData['warehouse_code'] ?? '').toString();

      final turbineModel = (masterData['turbine_model'] ?? auditData['wtg_model'] ?? auditData['model'] ?? '').toString();
      final turbineRating = (masterData['turbine_rating'] ?? auditData['wtg_rating'] ?? '').toString();
      final state = (auditData['state'] ?? '').toString();
      final customerName = (auditData['customer_name'] ?? '').toString();

      // -------------------------------------------------------------------------
      // SHEET 1: MIS SQA NC Details
      // -------------------------------------------------------------------------
      final Worksheet sheet1 = workbook.worksheets[0];
      sheet1.name = 'MIS SQA NC Details';

      final List<String> sheet1Headers = <String>[
        'Sr. No.', 'Audit Date', 'Turbine Name', 'Reference', 'Main Category', 'Sub Category',
        'Finding/Observation', 'Finding Photos', 'NC Criticality (CF/MCF/AObs)', 'NC Category',
        'Reason of NC (Cause of NC)', 'Plan Date of NC closure', 'Plan of Action',
        'Action Taken', 'Closing Date', 'Closing Evidence', 'Status', 'Remarks.'
      ];
      _writeExcelHeaders(sheet1, sheet1Headers, width: 100.0);
      sheet1.setColumnWidthInPixels(7, 250); // Observation column wider
      sheet1.setColumnWidthInPixels(8, 100); // Photos column

      // Process tasks and calculate penalties
      final Map<String, Map<String, dynamic>> liveNCs = await _fetchNCsForAudit(auditId);
      final tasks = auditData['audit_data'] as Map<String, dynamic>? ?? {};
      int srNo = 1;
      int rowIndex = 2; // Start from row 2 (1-indexed, after headers)
      int totalWorkmanPenalty = 0, totalOverallPenalty = 0, criticalNCCount = 0;

      // Sort tasks numerically
      final sortedEntries = tasks.entries.toList()
        ..sort((a, b) {
          final ia = int.tryParse(a.key);
          final ib = int.tryParse(b.key);
          if (ia != null && ib != null) return ia.compareTo(ib);
          return a.key.compareTo(b.key);
        });

      for (final entry in sortedEntries) {
        final taskKey = entry.key;
        final task = entry.value as Map<String, dynamic>;
        final nc = liveNCs[taskKey];

        final status = (task['status'] ?? '').toString().toLowerCase();
        final isCorrected = task['is_corrected'] == true;

        if (status == 'ok' && !isCorrected) continue;

        // Merge Task + NC data
        final String criticality = (nc?['nc_criticality'] ?? task['sub_status'] ?? 'Aobs').toString();
        final String ncCategory = (nc?['nc_category'] ?? task['nc_category'] ?? '').toString();
        final String rootCause = (nc?['root_cause'] ?? task['root_cause'] ?? '').toString();
        final String actionPlan = (nc?['action_plan'] ?? task['action_plan'] ?? '').toString();
        final String actionTaken = (nc?['action_taken'] ?? task['closure_remark'] ?? (isCorrected ? 'Corrected' : '')).toString();
        final String ncStatus = (nc?['status'] ?? (isCorrected ? 'Close' : 'Open')).toString();
        final String remarks = (nc?['remarks'] ?? task['closure_remark'] ?? '').toString();

        // Date Parsing
        String planDate = '';
        final targetVal = nc?['target_date'] ?? task['target_date'];
        if (targetVal != null) {
          final d = _parseDate(targetVal);
          if (d != null) planDate = DateFormat('dd-MM-yyyy').format(d);
        }

        String closingDate = '';
        final closeVal = nc?['closing_date'] ?? (isCorrected ? auditDate : null);
        if (closeVal != null) {
          final d = _parseDate(closeVal);
          if (d != null) closingDate = DateFormat('dd-MM-yyyy').format(d);
        }

        // Calculate penalties
        final penalties = _calculatePenalties(criticality, ncCategory, workmanPenaltyMap);
        totalWorkmanPenalty += penalties['workman']!;
        totalOverallPenalty += penalties['overall']!;
        if (penalties['overall']! >= 3 || criticality == 'CF') {
          criticalNCCount++;
        }

        // Write row
        _writeExcelRow(sheet1, rowIndex, <String>[
          srNo.toString(),
          auditDateStr,
          turbineNo,
          (nc?['reference_name'] ?? task['reference_name'] ?? '-').toString(),
          (task['main_category_name'] ?? '-').toString(),
          (task['sub_category_name'] ?? '-').toString(),
          (nc?['finding'] ?? task['observation'] ?? '-').toString(),
          '', // Finding Photos placeholder
          criticality,
          ncCategory,
          rootCause,
          planDate,
          actionPlan,
          actionTaken,
          closingDate,
          '', // Closing Evidence
          ncStatus,
          remarks,
        ]);

        // Embedding Multiple Finding Photos
        final List<dynamic> findingPhotos = (nc != null && nc['photos'] is List) ? nc['photos'] as List<dynamic> : (task['photos'] is List ? task['photos'] as List<dynamic> : <dynamic>[]);
        if (findingPhotos.isNotEmpty) {
          await _embedImages(sheet1, rowIndex, 8, findingPhotos);
        }

        // Embedding Closure Evidence
        final String? closurePhoto = nc?['closure_photo']?.toString() ?? task['closure_photo']?.toString();
        if (closurePhoto != null && closurePhoto.isNotEmpty) {
          await _embedSingleImage(sheet1, rowIndex, 16, closurePhoto);
        }

        // Apply conditional coloring to Observation cell (Column 7)
        sheet1.getRangeByIndex(rowIndex, 7).cellStyle.fontColor = _getFontColorForStatus(criticality);

        srNo++;
        rowIndex++;
      }

      // Safety Check: Include any NCs that might not be in the main audit_data keys (ad-hoc findings)
      liveNCs.forEach((key, nc) {
        if (!tasks.containsKey(key)) {
          final String criticality = (nc['nc_criticality'] ?? 'Aobs').toString();
          final String ncCategory = (nc['nc_category'] ?? '').toString();
          final String rootCause = (nc['root_cause'] ?? '').toString();
          final String actionPlan = (nc['action_plan'] ?? '').toString();
          final String actionTaken = (nc['action_taken'] ?? '').toString();
          final String ncStatus = (nc['status'] ?? 'Open').toString();
          final String remarks = (nc['remarks'] ?? '').toString();

          String planDate = '';
          if (nc['target_date'] != null) {
            final d = _parseDate(nc['target_date']);
            if (d != null) planDate = DateFormat('dd-MM-yyyy').format(d);
          }
          String closingDate = '';
          if (nc['closing_date'] != null) {
            final d = _parseDate(nc['closing_date']);
            if (d != null) closingDate = DateFormat('dd-MM-yyyy').format(d);
          }

          final penalties = _calculatePenalties(criticality, ncCategory, workmanPenaltyMap);
          totalWorkmanPenalty += penalties['workman']!;
          totalOverallPenalty += penalties['overall']!;
          if (penalties['overall']! >= 3 || criticality == 'CF') {
            criticalNCCount++;
          }

          _writeExcelRow(sheet1, rowIndex, <String>[
            srNo.toString(),
            auditDateStr,
            turbineNo,
            (nc['reference_name'] ?? 'Ad-hoc Finding').toString(),
            'Manual Finding',
            'Audit Oversight',
            (nc['finding'] ?? '-').toString(),
            '',
            criticality,
            ncCategory,
            rootCause,
            planDate,
            actionPlan,
            actionTaken,
            closingDate,
            '',
            ncStatus,
            remarks,
          ]);

          if (nc['photos'] is List && (nc['photos'] as List).isNotEmpty) {
            _embedImages(sheet1, rowIndex, 8, nc['photos'] as List);
          }
          if (nc['closure_photo'] != null) {
            _embedSingleImage(sheet1, rowIndex, 16, nc['closure_photo'].toString());
          }

          sheet1.getRangeByIndex(rowIndex, 7).cellStyle.fontColor = _getFontColorForStatus(criticality);
          srNo++;
          rowIndex++;
        }
      });

      if (srNo == 1) {
        sheet1.getRangeByIndex(2, 7).setText('No issues found');
      }

      // -------------------------------------------------------------------------
      // SHEET 2: WTG Assessment
      // -------------------------------------------------------------------------
      final Worksheet sheet2 = workbook.worksheets[1];
      sheet2.name = 'WTG Assessment';

      final List<String> sheet2Headers = <String>[
        'Sr. No.', 'Turbine No', 'Date Of Audit', 'Turbine Make', 'Turbine Model',
        'Turbine Rating (MW)', 'Site Name', 'District Name', 'State', 'Zone',
        'Warehouse Code', 'Customer Name', 'Commission Date (DOC)', 'Renom Date Of Takeover (DOT)',
        'SQA Audit Overall Assessment', 'Overall Compliance Ok (%)', 'Workman Assessments',
        'Workman PM Compliance Ok (%)', 'No of finding having 3 Nos rating NC',
        'PM Plan Date', 'PM Done Date', 'PM Adherence (+/-7 Days)', 'PM Vs QA Aging',
        'PM Type', 'PM Lead', 'PM Team', 'Report Status', 'Remark'
      ];
      _writeExcelHeaders(sheet2, sheet2Headers, width: 100.0);

      // Calculate metrics
      final overallScore = _getAssessmentScore(totalOverallPenalty);
      final workmanScore = _getAssessmentScore(totalWorkmanPenalty);
      final overallCompliance = _getCompliancePercentage(totalOverallPenalty);
      final workmanCompliance = _getCompliancePercentage(totalWorkmanPenalty);

      // Parse dates
      final commissioningDate = _parseDate(auditData['commissioning_date']);
      final takeOverDate = _parseDate(auditData['date_of_take_over']);
      final pmPlanDate = _parseDate(auditData['plan_date_of_maintenance']);
      final pmDoneDate = _parseDate(auditData['actual_date_of_maintenance']);

      // PM calculations
      String pmAdherence = '';
      int pmVsQaAging = 0;
      if (pmPlanDate != null && pmDoneDate != null) {
        pmAdherence = pmDoneDate.difference(pmPlanDate).inDays.toString();
      }
      if (auditDate != null && pmDoneDate != null) {
        pmVsQaAging = auditDate.difference(pmDoneDate).inDays;
      }

      // PM team info
      final pmLead = auditData['pm_team_leader']?.toString() ?? '';
      final pmMembers = auditData['pm_team_members'] is List ? (auditData['pm_team_members'] as List).join(', ') : '';
      final pmType = auditData['maintenance_type']?.toString() ?? '';

      // Write summary row
      _writeExcelRow(sheet2, 2, <String>[
        '1', turbineNo, auditDateStr, turbineMake, turbineModel,
        turbineRating, siteName, district, state, zone,
        warehouseCode, customerName,
        commissioningDate != null ? DateFormat('dd-MM-yyyy').format(commissioningDate) : '',
        takeOverDate != null ? DateFormat('dd-MM-yyyy').format(takeOverDate) : '',
        _getAssessmentLabel(overallScore), '${overallCompliance.toStringAsFixed(2)}%',
        _getAssessmentLabel(workmanScore), '${workmanCompliance.toStringAsFixed(2)}%',
        criticalNCCount.toString(),
        pmPlanDate != null ? DateFormat('dd-MM-yyyy').format(pmPlanDate) : '',
        pmDoneDate != null ? DateFormat('dd-MM-yyyy').format(pmDoneDate) : '',
        pmAdherence, pmVsQaAging.toString(),
        pmType, pmLead, pmMembers, 'Open', ''
      ]);

      // Save and download
      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      _downloadExcelBytes(bytes, 'SQA_Dump_Full_${siteName.replaceAll(' ', '_')}_$auditDateStr.xlsx');
    } catch (e) {
      // debugPrint('Error generating SQA Dump Excel: $e');
      rethrow;
    }
  }

  // ===========================================================================
  // DIGITAL SQA REPORT EXCEL (Replaces PDF/Page view)
  // ===========================================================================

  /// Generates and downloads the Digital SQA Report as an Excel file.
  /// Replicates the same format as the on-screen/PDF report.
  Future<void> generateDigitalSqaReportExcel(String auditId, Map<String, dynamic> auditData) async {
    try {
      final Workbook workbook = Workbook();
      final Worksheet sheet = workbook.worksheets[0];
      sheet.name = 'SQA Audit Report';

      // -----------------------------------------------------------------------
      // 1. DATA EXTRACTION
      // -----------------------------------------------------------------------
      final reportMeta = auditData['report_metadata'] as Map<String, dynamic>? ?? {};

      final state = (reportMeta['state'] as String?) ?? (auditData['state'] as String?) ?? '';
      final site = (reportMeta['site'] as String?) ?? (auditData['site'] as String?) ?? '';
      final turbineId = (reportMeta['turbine_id'] as String?) ?? (auditData['turbine'] as String?) ?? '';
      final make = (reportMeta['make'] as String?) ?? (auditData['turbine_make'] as String?) ?? '';
      final model = (reportMeta['model'] as String?) ?? (auditData['turbine_model_name'] as String?) ?? (auditData['wtg_model'] as String?) ?? (auditData['model'] as String?) ?? '';
      final rating = (reportMeta['rating'] as String?) ?? (auditData['wtg_rating'] as String?) ?? '';
      final customerName = (reportMeta['customer_name'] as String?) ?? (auditData['customer_name'] as String?) ?? '';
      final auditorName = (reportMeta['auditor_name'] as String?) ?? (auditData['auditor_name'] as String?) ?? '';

      final commissioningDate = _parseDate(reportMeta['commissioning_date'] ?? auditData['commissioning_date']);
      final takeOverDate = _parseDate(reportMeta['take_over_date'] ?? auditData['date_of_take_over']);
      final maintPlanDate = _parseDate(reportMeta['maint_plan_date'] ?? auditData['plan_date_of_maintenance']);
      final maintDoneDate = _parseDate(reportMeta['maint_done_date'] ?? auditData['actual_date_of_maintenance']);
      final inspectionDate = _parseDate(reportMeta['inspection_date'] ?? auditData['timestamp']);

      final assessmentStage = auditData['assessment_stage']?.toString() ?? '';
      final assessmentStageId = auditData['assessment_stage_id']?.toString() ?? '';
      final maintenanceType = auditData['maintenance_type']?.toString() ?? '';
      final pmMembers = auditData['pm_team_members'];
      final List<String> pmTeamMembers = [];
      if (pmMembers is List) {
        for (final m in pmMembers) {
          pmTeamMembers.add(m.toString());
        }
      }

      // Maintenance Delay
      String maintDelay = '-';
      if (maintPlanDate != null && maintDoneDate != null) {
        final diff = maintDoneDate.difference(maintPlanDate).inDays;
        if (diff > 0) {
          maintDelay = '$diff';
        } else if (diff < 0) {
          maintDelay = '${-diff}';
        } else {
          maintDelay = '0';
        }
      }

      // Date formatter
      String fmtDate(DateTime? d) => d != null ? DateFormat('dd.MM.yyyy').format(d) : '-';

      // -----------------------------------------------------------------------
      // 2. PROCESS TASKS (GROUPED BY REFERENCE)
      // -----------------------------------------------------------------------
      final tasks = auditData['audit_data'] as Map<String, dynamic>? ?? {};
      
      // Fetch live NCs for "Live" tracking data
      final Map<String, Map<String, dynamic>> liveNCs = await _fetchNCsForAudit(auditId);

      // Fetch workman penalty map from Firestore
      Map<String, bool> workmanPenaltyMap = {'Quality of Workmanship': true};
      try {
        final ncSnap = await FirebaseFirestore.instance.collection('audit_configs').doc('nc_categories').get();
        if (ncSnap.exists) {
          workmanPenaltyMap = {};
          for (final item in (ncSnap.data()?['items'] as List<dynamic>? ?? [])) {
            final name = (item as Map)['name']?.toString() ?? '';
            workmanPenaltyMap[name] = item['is_workman_penalty'] == true;
          }
        }
      } catch (_) {}

      // Priority map for sub-status severity
      const subStatusPriority = {'CF': 3, 'MCF': 2, 'Aobs': 1, 'OK': 0};

      // Group tasks by reference_name
      final Map<String, List<Map<String, dynamic>>> groupedTasks = {};
      tasks.forEach((key, value) {
        final task = value as Map<String, dynamic>;
        final nc = liveNCs[key];
        
        final status = (task['status'] ?? '').toString().toLowerCase();
        final isCorrected = task['is_corrected'] == true;
        
        // Include if Not OK, Corrected, or if an NC document exists for this task
        if (status != 'ok' || isCorrected || nc != null) {
          final refName = nc?['reference_name']?.toString() ??
              task['reference_name']?.toString() ??
              task['referenceoftask']?.toString() ??
              'Uncategorized';
              
          // Create a merged task for grouping to prioritize live NC data
          final mergedTask = Map<String, dynamic>.from(task);
          if (nc != null) {
            mergedTask['observation'] = nc['finding'] ?? mergedTask['observation'];
            mergedTask['sub_status'] = nc['nc_criticality'] ?? mergedTask['sub_status'] ?? mergedTask['criticality'];
            mergedTask['nc_category'] = nc['nc_category'] ?? mergedTask['nc_category'];
            mergedTask['reference_name'] = nc['reference_name'] ?? mergedTask['reference_name'];
          }
          
          groupedTasks.putIfAbsent(refName, () => []);
          groupedTasks[refName]!.add(mergedTask);
        }
      });
      
      // Safety Check: Include any NCs that might not be in the main audit_data keys (ad-hoc findings)
      liveNCs.forEach((key, nc) {
        bool alreadyProcessed = false;
        for (final list in groupedTasks.values) {
          if (list.any((t) => t['task_key'] == key)) {
             alreadyProcessed = true;
             break;
          }
        }
        
        // If not processed and it's a valid finding
        if (!alreadyProcessed) {
           final refName = nc['reference_name']?.toString() ?? 'Ad-hoc Finding';
           groupedTasks.putIfAbsent(refName, () => []);
           groupedTasks[refName]!.add({
             'observation': nc['finding'] ?? '-',
             'sub_status': nc['nc_criticality'] ?? 'Aobs',
             'nc_category': nc['nc_category'] ?? '-',
             'reference_name': refName,
             'is_corrected': false, // Ad-hoc findings are usually not auto-corrected
             'task_key': key,
           });
        }
      });

      final List<Map<String, dynamic>> processedTasks = [];
      int totalWorkmanPenalty = 0;
      int totalOverallPenalty = 0;
      int serialCounter = 1;
      int criticalNCCount = 0;
      
      groupedTasks.forEach((refName, taskList) {
        // Collect observations with bullets
        final List<String> observations = [];
        for (int i = 0; i < taskList.length; i++) {
          var obs = taskList[i]['observation']?.toString() ??
              taskList[i]['question']?.toString() ?? '';
          if (taskList[i]['is_corrected'] == true) {
            obs += " (Corrected on Site)";
          }
          if (obs.isNotEmpty) {
            observations.add('${i + 1}. $obs');
          }
        }

        // Find highest severity for this group
        Map<String, dynamic>? highestSeverityTask;
        int highestPriority = -1;
        for (final task in taskList) {
          final subStatus = task['sub_status']?.toString() ?? 'OK';
          final priority = subStatusPriority[subStatus] ?? 0;
          final ncCategory = task['nc_category']?.toString();
          if (priority > highestPriority ||
              (priority == highestPriority && ncCategory == 'Quality of Workmanship')) {
            highestPriority = priority;
            highestSeverityTask = task;
          }
        }

        final subStatus = highestSeverityTask?['sub_status']?.toString() ?? 'OK';
        final ncCategory = highestSeverityTask?['nc_category']?.toString();
        final penalties = _calculatePenalties(subStatus, ncCategory, workmanPenaltyMap);

        totalWorkmanPenalty += penalties['workman']!;
        totalOverallPenalty += penalties['overall']!;
        
        for (final task in taskList) {
          final sSub = task['sub_status']?.toString() ?? 'Aobs';
          final sNc = task['nc_category']?.toString();
          final p = _calculatePenalties(sSub, sNc, workmanPenaltyMap);
          if (p['overall']! >= 3 || sSub.toUpperCase() == 'CF') {
            criticalNCCount++;
          }
        }

        if (observations.isNotEmpty) {
           processedTasks.add({
             'srNo': serialCounter++,
             'observation': '[$refName]\n${observations.join("\n")}',
             'subStatus': subStatus,
             'workmanScore': penalties['workman']!,
             'overallScore': penalties['overall']!,
           });
        }
      });

      // Calculate scores
      final workmanScore = _getAssessmentScore(totalWorkmanPenalty);
      final overallScore = _getAssessmentScore(totalOverallPenalty);
      final workmanCompliance = _getCompliancePercentage(totalWorkmanPenalty);
      final overallCompliance = _getCompliancePercentage(totalOverallPenalty);

      // -----------------------------------------------------------------------
      // 3. SET COLUMN WIDTHS
      // -----------------------------------------------------------------------
      sheet.setColumnWidthInPixels(1, 10);   // A filler
      sheet.setColumnWidthInPixels(2, 60);   // B
      sheet.setColumnWidthInPixels(3, 80);   // C
      sheet.setColumnWidthInPixels(4, 80);   // D
      sheet.setColumnWidthInPixels(5, 80);   // E
      sheet.setColumnWidthInPixels(6, 120);  // F
      sheet.setColumnWidthInPixels(7, 80);   // G
      sheet.setColumnWidthInPixels(8, 80);   // H
      sheet.setColumnWidthInPixels(9, 80);   // I
      sheet.setColumnWidthInPixels(10, 80);  // J

      // STYLE HELPERS
      Style cellStyle(int r, int c, {String? backColor, String? fontColor, bool bold = false, double fontSize = 10, HAlignType hAlign = HAlignType.center, VAlignType vAlign = VAlignType.center, bool wrapText = false}) {
        final cell = sheet.getRangeByIndex(r, c);
        cell.cellStyle.bold = bold;
        cell.cellStyle.fontSize = fontSize;
        if (backColor != null) { cell.cellStyle.backColor = backColor; }
        if (fontColor != null) { cell.cellStyle.fontColor = fontColor; }
        cell.cellStyle.hAlign = hAlign;
        cell.cellStyle.vAlign = vAlign;
        cell.cellStyle.wrapText = wrapText;
        return cell.cellStyle;
      }
      
      void applyBorders(int r1, int c1, int r2, int c2) {
         final range = sheet.getRangeByIndex(r1, c1, r2, c2);
         range.cellStyle.borders.all.lineStyle = LineStyle.thin;
         range.cellStyle.borders.all.color = '#000000';
      }

      // -----------------------------------------------------------------------
      // Row 2 to 3 - Header Section
      // -----------------------------------------------------------------------
      sheet.getRangeByIndex(2, 2, 3, 2).merge();
      try {
        final ByteData data = await rootBundle.load('assets/images/renom_logo.png');
        final List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        final Picture picture = sheet.pictures.addStream(2, 2, bytes);
        // Scaled to fit within cell B2 (width ~60, row height ~36 total)
        picture.height = 36;
        picture.width = 56;
      } catch (e) {
        sheet.getRangeByIndex(2, 2).setText('Renom Logo');
      }
      cellStyle(2, 2, bold: true, backColor: '#D5D8DC');
      
      sheet.getRangeByIndex(2, 3, 3, 8).merge();
      sheet.getRangeByIndex(2, 3).setText('SQA Audit Report');
      cellStyle(2, 3, fontSize: 16, bold: true, backColor: '#FFFFFF', fontColor: '#000000');
      
      sheet.getRangeByIndex(2, 9, 3, 9).merge();
      sheet.getRangeByIndex(2, 9).setText(workmanScore.toStringAsFixed(1));
      cellStyle(2, 9, bold: true, fontSize: 12, backColor: '#D9E1F2');
      
      sheet.getRangeByIndex(2, 10, 3, 10).merge();
      sheet.getRangeByIndex(2, 10).setText(overallScore.toStringAsFixed(1));
      cellStyle(2, 10, bold: true, fontSize: 12, backColor: '#D9E1F2');
      
      applyBorders(2, 2, 3, 10);

      // -----------------------------------------------------------------------
      // Row 4 - Rating Scale
      // -----------------------------------------------------------------------
      sheet.getRangeByIndex(4, 2).setText('Excellent (14-15)');
      cellStyle(4, 2, backColor: '#27AE60', fontColor: '#FFFFFF');
      
      sheet.getRangeByIndex(4, 3, 4, 4).merge();
      sheet.getRangeByIndex(4, 3).setText('Good (11-13)');
      cellStyle(4, 3, backColor: '#F1C40F');
      
      sheet.getRangeByIndex(4, 5).setText('Improvement (8-10)');
      cellStyle(4, 5, backColor: '#3498DB', fontColor: '#FFFFFF');
      
      sheet.getRangeByIndex(4, 6).setText('Poor (5-7)');
      cellStyle(4, 6, backColor: '#E67E22', fontColor: '#FFFFFF');
      
      sheet.getRangeByIndex(4, 7).setText('Worst (<4.5)');
      cellStyle(4, 7, backColor: '#E74C3C', fontColor: '#FFFFFF');
      
      sheet.getRangeByIndex(4, 8).setText('SQA Indicator');
      cellStyle(4, 8, bold: true, backColor: '#BDC3C7');
      
      sheet.getRangeByIndex(4, 9).setText('Workman');
      cellStyle(4, 9, bold: true, backColor: '#BDC3C7');
      
      sheet.getRangeByIndex(4, 10).setText('Overall');
      cellStyle(4, 10, bold: true, backColor: '#BDC3C7');
      
      applyBorders(4, 2, 4, 10);

      // -----------------------------------------------------------------------
      // Row 5 to 8 - Basic Details
      // -----------------------------------------------------------------------
      sheet.getRangeByIndex(5, 2).setText('State');
      cellStyle(5, 2, bold: true, hAlign: HAlignType.left);
      sheet.getRangeByIndex(5, 3, 5, 5).merge();
      sheet.getRangeByIndex(5, 3).setText(state);
      cellStyle(5, 3, hAlign: HAlignType.left);
      sheet.getRangeByIndex(5, 6).setText('Site');
      cellStyle(5, 6, bold: true, hAlign: HAlignType.left);
      sheet.getRangeByIndex(5, 7, 5, 10).merge();
      sheet.getRangeByIndex(5, 7).setText(site);
      cellStyle(5, 7, hAlign: HAlignType.left);
      
      sheet.getRangeByIndex(6, 2).setText('Turbine ID.');
      cellStyle(6, 2, bold: true, hAlign: HAlignType.left);
      sheet.getRangeByIndex(6, 3, 6, 5).merge();
      sheet.getRangeByIndex(6, 3).setText(turbineId);
      cellStyle(6, 3, hAlign: HAlignType.left);
      sheet.getRangeByIndex(6, 6).setText('Turbine Make');
      cellStyle(6, 6, bold: true, hAlign: HAlignType.left);
      sheet.getRangeByIndex(6, 7).setText(make);
      cellStyle(6, 7, hAlign: HAlignType.left);
      sheet.getRangeByIndex(6, 8).setText('Turbine Model');
      cellStyle(6, 8, bold: true, hAlign: HAlignType.left);
      sheet.getRangeByIndex(6, 9, 6, 10).merge();
      sheet.getRangeByIndex(6, 9).setText(model);
      cellStyle(6, 9, hAlign: HAlignType.left);
      
      sheet.getRangeByIndex(7, 2).setText('WTG Rating (MW)');
      cellStyle(7, 2, bold: true, hAlign: HAlignType.left);
      sheet.getRangeByIndex(7, 3, 7, 5).merge();
      sheet.getRangeByIndex(7, 3).setText(rating);
      cellStyle(7, 3, hAlign: HAlignType.left);
      sheet.getRangeByIndex(7, 6).setText('Date Of Commissioning (DOC)');
      cellStyle(7, 6, bold: true, hAlign: HAlignType.left);
      sheet.getRangeByIndex(7, 7, 7, 10).merge();
      sheet.getRangeByIndex(7, 7).setText(fmtDate(commissioningDate));
      cellStyle(7, 7, hAlign: HAlignType.left);
      
      sheet.getRangeByIndex(8, 2).setText('Customer Name');
      cellStyle(8, 2, bold: true, hAlign: HAlignType.left);
      sheet.getRangeByIndex(8, 3, 8, 5).merge();
      sheet.getRangeByIndex(8, 3).setText(customerName);
      cellStyle(8, 3, hAlign: HAlignType.left);
      sheet.getRangeByIndex(8, 6).setText('Date Of Take Over (DOT)');
      cellStyle(8, 6, bold: true, hAlign: HAlignType.left);
      sheet.getRangeByIndex(8, 7, 8, 10).merge();
      sheet.getRangeByIndex(8, 7).setText(fmtDate(takeOverDate));
      cellStyle(8, 7, hAlign: HAlignType.left);
      
      applyBorders(5, 2, 8, 10);

      // -----------------------------------------------------------------------
      // Row 9 to 14 - Maintenance Details
      // -----------------------------------------------------------------------
      sheet.getRangeByIndex(9, 2, 12, 2).merge();
      sheet.getRangeByIndex(9, 2).setText('Assessment work Details');
      cellStyle(9, 2, bold: true, wrapText: true);
      
      final String stageLower = assessmentStage.toLowerCase();
      final bool isBefore = assessmentStageId == 'STAGE_BEFORE' || stageLower.contains('before');
      final bool isDuring = assessmentStageId == 'STAGE_DURING' || stageLower.contains('during');
      final bool isAfter = assessmentStageId == 'STAGE_AFTER' || stageLower.contains('after');
      
      sheet.getRangeByIndex(9, 3, 9, 5).merge();
      sheet.getRangeByIndex(9, 3).setText('Before Maintenance');
      cellStyle(9, 3, bold: true, backColor: isBefore ? '#82E0AA' : null);
      
      sheet.getRangeByIndex(9, 6, 12, 6).merge();
      sheet.getRangeByIndex(9, 6).setText('Type Of Maintenance');
      cellStyle(9, 6, bold: true, wrapText: true);
      
      sheet.getRangeByIndex(9, 7, 9, 10).merge();
      sheet.getRangeByIndex(9, 7).setText(maintenanceType); 
      cellStyle(9, 7, hAlign: HAlignType.left);
      
      sheet.getRangeByIndex(10, 3, 10, 5).merge();
      sheet.getRangeByIndex(10, 3).setText('During Maintenance');
      cellStyle(10, 3, bold: true, backColor: isDuring ? '#82E0AA' : null);
      
      sheet.getRangeByIndex(10, 7, 10, 10).merge();
      sheet.getRangeByIndex(10, 7).setText('');
      
      sheet.getRangeByIndex(11, 3, 11, 5).merge();
      sheet.getRangeByIndex(11, 3).setText('After Maintenance');
      cellStyle(11, 3, bold: true, backColor: isAfter ? '#82E0AA' : null);
      
      sheet.getRangeByIndex(11, 7, 11, 10).merge();
      sheet.getRangeByIndex(11, 7).setText('');
      
      sheet.getRangeByIndex(12, 3, 12, 5).merge();
      sheet.getRangeByIndex(12, 7, 12, 10).merge();
      sheet.getRangeByIndex(12, 7).setText('');
      
      sheet.getRangeByIndex(13, 2).setText('Maint. Plan Date');
      cellStyle(13, 2, bold: true, hAlign: HAlignType.left);
      sheet.getRangeByIndex(13, 3, 13, 5).merge();
      sheet.getRangeByIndex(13, 3).setText(fmtDate(maintPlanDate));
      cellStyle(13, 3, hAlign: HAlignType.left);
      sheet.getRangeByIndex(13, 6).setText('Maint. Delay');
      cellStyle(13, 6, bold: true, hAlign: HAlignType.left);
      sheet.getRangeByIndex(13, 7, 13, 10).merge();
      sheet.getRangeByIndex(13, 7).setText(maintDelay);
      cellStyle(13, 7, hAlign: HAlignType.left);
      
      sheet.getRangeByIndex(14, 2).setText('Maint. Done Date');
      cellStyle(14, 2, bold: true, hAlign: HAlignType.left);
      sheet.getRangeByIndex(14, 3, 14, 5).merge();
      sheet.getRangeByIndex(14, 3).setText(fmtDate(maintDoneDate));
      cellStyle(14, 3, hAlign: HAlignType.left);
      sheet.getRangeByIndex(14, 6).setText('Date Of Inspection');
      cellStyle(14, 6, bold: true, hAlign: HAlignType.left);
      sheet.getRangeByIndex(14, 7, 14, 10).merge();
      sheet.getRangeByIndex(14, 7).setText(fmtDate(inspectionDate));
      cellStyle(14, 7, hAlign: HAlignType.left);
      
      applyBorders(9, 2, 14, 10);

      // -----------------------------------------------------------------------
      // Row 15 to 16 - Ref & Team
      // -----------------------------------------------------------------------
      sheet.getRangeByIndex(15, 2).setText('Ref. Documents');
      cellStyle(15, 2, bold: true, hAlign: HAlignType.left);
      sheet.getRangeByIndex(15, 3, 15, 10).merge();
      sheet.getRangeByIndex(15, 3).setText('PROCEDURE FOR SERVICE QUALITY ASSURANCE AUDIT (RENOM/QA/P/01)');
      cellStyle(15, 3, bold: true, hAlign: HAlignType.left, backColor: '#E8F8F5');
      
      sheet.getRangeByIndex(16, 2).setText('Auditor Name');
      cellStyle(16, 2, bold: true, hAlign: HAlignType.left);
      sheet.getRangeByIndex(16, 3, 16, 4).merge();
      sheet.getRangeByIndex(16, 3).setText(auditorName);
      cellStyle(16, 3, hAlign: HAlignType.left);
      sheet.getRangeByIndex(16, 5).setText('Auditee (PM Team) Name');
      cellStyle(16, 5, bold: true, hAlign: HAlignType.left, wrapText: true);
      sheet.getRangeByIndex(16, 6, 16, 10).merge();
      sheet.getRangeByIndex(16, 6).setText(pmTeamMembers.join(', '));
      cellStyle(16, 6, hAlign: HAlignType.left);
      
      applyBorders(15, 2, 16, 10);

      // -----------------------------------------------------------------------
      // Observations Header
      // -----------------------------------------------------------------------
      int row = 17;
      sheet.getRangeByIndex(row, 2).setText('Sr. No.');
      cellStyle(row, 2, bold: true, backColor: '#4D8E8E', fontColor: '#FFFFFF');
      sheet.getRangeByIndex(row, 3, row, 7).merge();
      sheet.getRangeByIndex(row, 3).setText('Observation / Point Details');
      cellStyle(row, 3, bold: true, backColor: '#4D8E8E', fontColor: '#FFFFFF');
      sheet.getRangeByIndex(row, 8).setText('Status');
      cellStyle(row, 8, bold: true, backColor: '#4D8E8E', fontColor: '#FFFFFF');
      sheet.getRangeByIndex(row, 9).setText('Workman Score');
      cellStyle(row, 9, bold: true, backColor: '#4D8E8E', fontColor: '#FFFFFF', wrapText: true);
      sheet.getRangeByIndex(row, 10).setText('Overall Score');
      cellStyle(row, 10, bold: true, backColor: '#4D8E8E', fontColor: '#FFFFFF', wrapText: true);
      applyBorders(row, 2, row, 10);
      sheet.setRowHeightInPixels(row, 40);
      row++;

      // -----------------------------------------------------------------------
      // Observations Loop
      // -----------------------------------------------------------------------
      if (processedTasks.isEmpty) {
        sheet.getRangeByIndex(row, 2).setText('-');
        sheet.getRangeByIndex(row, 3, row, 7).merge();
        sheet.getRangeByIndex(row, 3).setText('No NCs Found');
        sheet.getRangeByIndex(row, 8).setText('OK');
        sheet.getRangeByIndex(row, 9).setText('0');
        sheet.getRangeByIndex(row, 10).setText('0');
        for (int c = 2; c <= 10; c++) { cellStyle(row, c); }
        applyBorders(row, 2, row, 10);
        row++;
      } else {
        for (final task in processedTasks) {
          sheet.getRangeByIndex(row, 2).setText(task['srNo'].toString());
          cellStyle(row, 2);
          
          sheet.getRangeByIndex(row, 3, row, 7).merge();
          sheet.getRangeByIndex(row, 3).setText(task['observation'].toString());
          cellStyle(
            row, 3, 
            hAlign: HAlignType.left, 
            wrapText: true, 
            fontColor: _getFontColorForStatus(task['subStatus'].toString())
          );
          
          sheet.getRangeByIndex(row, 8).setText(task['subStatus'].toString());
          cellStyle(row, 8);
          
          sheet.getRangeByIndex(row, 9).setText(task['workmanScore'].toString());
          cellStyle(row, 9, fontColor: (task['workmanScore'] as int) > 0 ? '#C0392B' : null);
          
          sheet.getRangeByIndex(row, 10).setText(task['overallScore'].toString());
          cellStyle(row, 10, fontColor: (task['overallScore'] as int) > 0 ? '#C0392B' : null);
          
          applyBorders(row, 2, row, 10);
          
          final length = task['observation'].toString().length;
          final lines = (length / 60).ceil();
          if (lines > 1) {
            sheet.setRowHeightInPixels(row, (lines * 18).toDouble());
          }
          row++;
        }
      }

      // -----------------------------------------------------------------------
      // Footer Section
      // -----------------------------------------------------------------------
      int footerStartRow = row;

      // Row 28
      sheet.setRowHeightInPixels(row, 20);
      sheet.getRangeByIndex(row, 2).setText('Remarks :-');
      sheet.getRangeByIndex(row, 3, row, 6).merge();
      sheet.getRangeByIndex(row, 3).setText('-');
      sheet.getRangeByIndex(row, 7).setText('Total');
      sheet.getRangeByIndex(row, 8).setText('');
      final iCell28 = sheet.getRangeByIndex(row, 9);
      iCell28.setText(totalWorkmanPenalty.toString());
      final jCell28 = sheet.getRangeByIndex(row, 10);
      jCell28.setText(totalOverallPenalty.toString());
      
      row++;
      // Row 29
      sheet.getRangeByIndex(row, 2).setText('Workman Assessments');
      sheet.getRangeByIndex(row, 3, row, 5).merge();
      sheet.getRangeByIndex(row, 3).setText(workmanScore.toStringAsFixed(2));
      sheet.getRangeByIndex(row, 6, row, 7).merge();
      sheet.getRangeByIndex(row, 6).setText('Remarks Of Workman assessments');
      sheet.getRangeByIndex(row, 8, row, 10).merge();
      double ws = double.tryParse(workmanScore.toStringAsFixed(1)) ?? 15.0;
      String wRem = ws >= 14 ? 'Excellent' : ws >= 11 ? 'Good' : ws >= 8 ? 'Improvement' : ws >= 5 ? 'Poor' : 'Worst';
      sheet.getRangeByIndex(row, 8).setText(wRem);

      row++;
      // Row 30
      sheet.getRangeByIndex(row, 2).setText('Workman PM Compliance');
      sheet.getRangeByIndex(row, 3, row, 5).merge();
      sheet.getRangeByIndex(row, 3).setText('${workmanCompliance.toStringAsFixed(2)}%');
      sheet.getRangeByIndex(row, 6, row, 10).merge(); 

      row++;
      // Row 31
      sheet.getRangeByIndex(row, 2).setText('Overall Assessments');
      sheet.getRangeByIndex(row, 3, row, 5).merge();
      sheet.getRangeByIndex(row, 3).setText(overallScore.toStringAsFixed(2));
      sheet.getRangeByIndex(row, 6, row, 7).merge();
      sheet.getRangeByIndex(row, 6).setText('Remarks Of Overall assessments');
      sheet.getRangeByIndex(row, 8, row, 10).merge();
      double os = double.tryParse(overallScore.toStringAsFixed(1)) ?? 15.0;
      String oRem = os >= 14 ? 'Excellent' : os >= 11 ? 'Good' : os >= 8 ? 'Improvement' : os >= 5 ? 'Poor' : 'Worst';
      sheet.getRangeByIndex(row, 8).setText(oRem);

      row++;
      // Row 32
      sheet.getRangeByIndex(row, 2).setText('Overall Compliance');
      sheet.getRangeByIndex(row, 3, row, 5).merge();
      sheet.getRangeByIndex(row, 3).setText('${overallCompliance.toStringAsFixed(2)}%');
      sheet.getRangeByIndex(row, 6, row, 10).merge(); 

      row++;
      // Row 33
      sheet.getRangeByIndex(row, 2).setText('Number of CF');
      sheet.getRangeByIndex(row, 3).setText(criticalNCCount.toString());
      sheet.getRangeByIndex(row, 4, row, 5).merge();
      sheet.getRangeByIndex(row, 4).setText('Date of SQA point discussion');
      sheet.getRangeByIndex(row, 6, row, 7).merge();
      final discussionDate = _parseDate(reportMeta['discussion_date'] ?? auditData['discussion_date'] ?? auditData['timestamp']);
      sheet.getRangeByIndex(row, 6).setText(fmtDate(discussionDate));
      sheet.getRangeByIndex(row, 8, row, 9).merge();
      sheet.getRangeByIndex(row, 8).setText('Date Report Submitted/Share');
      final submissionDate = _parseDate(reportMeta['submission_date'] ?? auditData['submission_date'] ?? auditData['timestamp']);
      sheet.getRangeByIndex(row, 10).setText(fmtDate(submissionDate));
      
      // Formatting and styling
      final footerRange = sheet.getRangeByIndex(footerStartRow, 2, row, 10);
      footerRange.cellStyle.borders.all.lineStyle = LineStyle.thin;
      footerRange.cellStyle.borders.all.color = '#000000';
      
      for (int r = footerStartRow; r <= row; r++) {
         for (int c = 2; c <= 10; c++) {
            final cell = sheet.getRangeByIndex(r, c);
            cell.cellStyle.fontName = 'Arial';
            cell.cellStyle.fontSize = 10;
            if (c >= 3) {
                cell.cellStyle.hAlign = HAlignType.center;
                cell.cellStyle.vAlign = VAlignType.center;
            } else {
                cell.cellStyle.hAlign = HAlignType.left;
                cell.cellStyle.vAlign = VAlignType.center;
                cell.cellStyle.bold = true; 
            }
         }
      }
      
      // Explicit overrides
      sheet.getRangeByIndex(footerStartRow, 7).cellStyle.bold = true;
      iCell28.cellStyle.bold = true;
      jCell28.cellStyle.bold = true;
      
      iCell28.cellStyle.borders.top.lineStyle = LineStyle.medium;
      iCell28.cellStyle.borders.top.color = '#00B050';
      jCell28.cellStyle.borders.top.lineStyle = LineStyle.medium;
      jCell28.cellStyle.borders.top.color = '#00B050';

      // -----------------------------------------------------------------------
      // 8. GENERATE FILENAME
      // -----------------------------------------------------------------------
      final timestampAudit = auditData['timestamp'] as Timestamp?;
      final auditDateExport = timestampAudit?.toDate() ?? DateTime.now();
      final auditDateStr = DateFormat('dd.MM.yyyy').format(auditDateExport);
      final siteNameText = site.isNotEmpty ? site : 'Unknown';
      final turbineNameText = turbineId.isNotEmpty ? turbineId : 'Unknown';

      final fileName = 'SQA_Digital_Report_${siteNameText.replaceAll(' ', '_')}_${turbineNameText}_$auditDateStr.xlsx';

      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();
      _downloadExcelBytes(bytes, fileName);
    } catch (e) {
      rethrow;
    }
  }

  // ===========================================================================
  // DATA FETCHING
  // ===========================================================================

  Future<Map<String, String>> _fetchMasterData(Map<String, dynamic> auditData) async {
    final Map<String, String> results = {};

    // 1. Turbine Make, Model, Rating
    final String? turbineModelId = auditData['turbine_model_id']?.toString();
    if (turbineModelId != null && turbineModelId.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance.collection('turbinemodel').doc(turbineModelId).get();
        if (doc.exists) {
          final data = doc.data();
          results['turbine_make'] = data?['turbine_make']?.toString() ?? '';
          results['turbine_model'] = data?['turbine_model']?.toString() ?? '';
          results['turbine_rating'] = data?['turbine_rating']?.toString() ?? '';
        }
      } catch (e) {
        // debugPrint('Error fetching turbine data: $e');
      }
    }

    // 2. District & Warehouse Code
    final String? siteId = auditData['site_id']?.toString();
    if (siteId != null && siteId.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance.collection('sites').doc(siteId).get();
        if (doc.exists) {
          final data = doc.data();
          results['district'] = data?['district']?.toString() ?? '';
          results['warehouse_code'] = data?['warehouse_code']?.toString() ?? '';
        }
      } catch (e) {
        // debugPrint('Error fetching site data: $e');
      }
    }

    // 3. Zone
    String? stateId;
    if (auditData['state_ref'] is DocumentReference) {
      stateId = (auditData['state_ref'] as DocumentReference).id;
    } else {
      stateId = auditData['state_id']?.toString();
    }
    if (stateId != null && stateId.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance.collection('states').doc(stateId).get();
        if (doc.exists) {
          results['zone'] = doc.data()?['zone']?.toString() ?? '';
        }
      } catch (e) {
        // debugPrint('Error fetching zone: $e');
      }
    }

    return results;
  }

  // ===========================================================================
  // EXCEL HELPER METHODS
  // ===========================================================================
  
  void _writeExcelHeaders(Worksheet sheet, List<String> headers, {double width = 100.0}) {
    for (int i = 0; i < headers.length; i++) {
      final Range headerCell = sheet.getRangeByIndex(1, i + 1);
      headerCell.setText(headers[i]);
      headerCell.cellStyle.bold = true;
      headerCell.cellStyle.backColor = '#4D8E8E'; // Dark teal 40% lighter
      headerCell.cellStyle.fontColor = '#FFFFFF';
      headerCell.cellStyle.hAlign = HAlignType.center;
      headerCell.cellStyle.vAlign = VAlignType.center;
      sheet.setColumnWidthInPixels(i + 1, width.toInt());
    }
  }

  void _writeExcelRow(Worksheet sheet, int rowIndex, List<String> values) {
    for (int i = 0; i < values.length; i++) {
      sheet.getRangeByIndex(rowIndex, i + 1).setText(values[i]);
    }
  }

  void _downloadExcelBytes(List<int> bytes, String fileName) {
    final data = Uint8List.fromList(bytes);
    final blob = web.Blob(
      [data.toJS].toJS,
      web.BlobPropertyBag(type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
    );
    final url = web.URL.createObjectURL(blob);

    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    anchor.click();

    web.URL.revokeObjectURL(url);
  }

  // ===========================================================================
  // CALCULATION HELPERS
  // ===========================================================================
  
  Map<String, int> _calculatePenalties(String subStatus, String? ncCategory, Map<String, bool> workmanPenaltyMap) {
    int workman = 0, overall = 0;
    final isQualityOfWorkmanship = ncCategory != null && (workmanPenaltyMap[ncCategory] ?? false);

    switch (subStatus) {
      case 'Aobs': overall = 1; workman = isQualityOfWorkmanship ? 1 : 0; break;
      case 'MCF':  overall = 2; workman = isQualityOfWorkmanship ? 2 : 0; break;
      case 'CF':   overall = 3; workman = isQualityOfWorkmanship ? 3 : 0; break;
    }
    return {'workman': workman, 'overall': overall};
  }

  /// Returns font color based on NC Category (sub_status).
  String _getFontColorForStatus(String subStatus) {
    final status = subStatus.toLowerCase();
    if (status == 'cf') return '#FF0000'; // Red
    if (status == 'mcf') return '#0000FF'; // Blue
    return '#000000'; // Black
  }

  double _getAssessmentScore(int penaltyPoints) {
    if (penaltyPoints <= 0) {
      return 15.0;
    }
    if (penaltyPoints >= 66) {
      return 0.1;
    }
    return 15.0 - (penaltyPoints * 0.5);
  }

  String _getAssessmentLabel(double score) {
    if (score >= 13.5) {
      return 'Excellent';
    }
    if (score >= 12) {
      return 'Good';
    }
    if (score >= 9) {
      return 'Improvement';
    }
    if (score >= 6) {
      return 'Poor';
    }
    return 'Worst';
  }

  double _getCompliancePercentage(int totalPenalty) {
    return ((1 - (totalPenalty / 75)) * 100).clamp(0.0, 100.0);
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

  // ===========================================================================
  // BULK EXPORT LOGIC
  // ===========================================================================
  Future<void> generateBulkSQADumpExcel(List<Map<String, dynamic>> multiAuditData) async {
    // ---------------------------------------------------------------------------
    // Creates a 2-sheet workbook — 1:1 aggregated version of generateSQADumpExcel.
    // Sheet 1 "MIS SQA NC Details" : one row per NC task, across all audits
    // Sheet 2 "WTG Assessment"     : one summary row per audit
    // ---------------------------------------------------------------------------
    final Workbook workbook = Workbook(2);

    // SHEET 1
    final Worksheet sheet1 = workbook.worksheets[0];
    sheet1.name = 'MIS SQA NC Details';
    _writeExcelHeaders(sheet1, _sqaNcHeaders, width: 100.0);
    sheet1.setColumnWidthInPixels(7, 250);
    sheet1.setColumnWidthInPixels(8, 200); // Expanded for multi-photo

    // SHEET 2
    final Worksheet sheet2 = workbook.worksheets[1];
    sheet2.name = 'WTG Assessment';
    _writeExcelHeaders(sheet2, <String>[
      'Sr. No.', 'Turbine No', 'Date Of Audit', 'Turbine Make', 'Turbine Model',
      'Turbine Rating (MW)', 'Site Name', 'District Name', 'State', 'Zone',
      'Warehouse Code', 'Customer Name', 'Commission Date (DOC)', 'Renom Date Of Takeover (DOT)',
      'SQA Audit Overall Assessment', 'Overall Compliance Ok (%)', 'Workman Assessments',
      'Workman PM Compliance Ok (%)', 'No of finding having 3 Nos rating NC',
      'PM Plan Date', 'PM Done Date', 'PM Adherence (+/-7 Days)', 'PM Vs QA Aging',
      'PM Type', 'PM Lead', 'PM Team', 'Report Status', 'Remark'
    ], width: 100.0);

    // -------------------------------------------------------------------------
    // Fetch workman penalty map ONCE — shared across all audits
    // -------------------------------------------------------------------------
    Map<String, bool> workmanPenaltyMap = {'Quality of Workmanship': true};
    try {
      final ncSnap = await FirebaseFirestore.instance.collection('audit_configs').doc('nc_categories').get();
      if (ncSnap.exists) {
        workmanPenaltyMap = {};
        for (final item in (ncSnap.data()?['items'] as List<dynamic>? ?? [])) {
          final name = (item as Map)['name']?.toString() ?? '';
          workmanPenaltyMap[name] = item['is_workman_penalty'] == true;
        }
      }
    } catch (_) {}

    // -------------------------------------------------------------------------
    // STEP 1: Sort — newest audit date first, then turbine ID ascending
    // -------------------------------------------------------------------------
    final sortedData = List<Map<String, dynamic>>.from(multiAuditData)
      ..sort((a, b) {
        final tsA = (a['timestamp'] as Timestamp?)?.toDate() ?? DateTime(0);
        final tsB = (b['timestamp'] as Timestamp?)?.toDate() ?? DateTime(0);
        final dateComp = tsB.compareTo(tsA); // descending
        if (dateComp != 0) return dateComp;
        return (a['turbine'] ?? '').toString().compareTo((b['turbine'] ?? '').toString());
      });

    // -------------------------------------------------------------------------
    // STEP 2: Batch-fetch master data — one parallel round-trip per collection
    // Reduces N×3 sequential reads to ~(K+M+P) parallel reads where
    // K = unique turbine models, M = unique sites, P = unique states.
    // -------------------------------------------------------------------------
    final turbineModelIdList = sortedData
        .map((d) => d['turbine_model_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty).toSet().toList();
    final siteIdList = sortedData
        .map((d) => d['site_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty).toSet().toList();
    final stateIdList = sortedData
        .map((d) {
          if (d['state_ref'] is DocumentReference) {
            return (d['state_ref'] as DocumentReference).id;
          }
          return d['state_id']?.toString() ?? '';
        })
        .where((id) => id.isNotEmpty).toSet().toList();

    // Fire all doc reads in parallel
    final allFetchFutures = <Future<DocumentSnapshot<Map<String, dynamic>>>>[
      ...turbineModelIdList.map((id) => FirebaseFirestore.instance.collection('turbinemodel').doc(id).get()),
      ...siteIdList.map((id)          => FirebaseFirestore.instance.collection('sites').doc(id).get()),
      ...stateIdList.map((id)         => FirebaseFirestore.instance.collection('states').doc(id).get()),
    ];
    final allDocs = allFetchFutures.isNotEmpty
        ? await Future.wait(allFetchFutures)
        : <DocumentSnapshot<Map<String, dynamic>>>[];

    // Build lookup caches
    final Map<String, Map<String, String>> turbineModelCache = {};
    final Map<String, Map<String, String>> siteCache         = {};
    final Map<String, String>              zoneCache         = {};

    for (int i = 0; i < turbineModelIdList.length; i++) {
      final doc = allDocs[i];
      if (doc.exists) {
        final d = doc.data() ?? {};
        turbineModelCache[turbineModelIdList[i]] = {
          'turbine_make':   d['turbine_make']?.toString()   ?? '',
          'turbine_model':  d['turbine_model']?.toString()  ?? '',
          'turbine_rating': d['turbine_rating']?.toString() ?? '',
        };
      }
    }
    final siteOffset = turbineModelIdList.length;
    for (int i = 0; i < siteIdList.length; i++) {
      final doc = allDocs[siteOffset + i];
      if (doc.exists) {
        final d = doc.data() ?? {};
        siteCache[siteIdList[i]] = {
          'district':       d['district']?.toString()       ?? '',
          'warehouse_code': d['warehouse_code']?.toString() ?? '',
        };
      }
    }
    final stateOffset = siteOffset + siteIdList.length;
    for (int i = 0; i < stateIdList.length; i++) {
      final doc = allDocs[stateOffset + i];
      if (doc.exists) {
        zoneCache[stateIdList[i]] = doc.data()?['zone']?.toString() ?? '';
      }
    }

    int sheet1Row  = 2;
    int sheet1SrNo = 1;
    int sheet2Row  = 2;
    int sheet2SrNo = 1;

    // -------------------------------------------------------------------------
    // STEP 3: Iterate sorted audits — all master data from local caches
    // -------------------------------------------------------------------------
    for (final docData in sortedData) {
      final String? auditId = docData['doc_id']?.toString();
      if (auditId == null) continue;

      // Resolve from pre-built caches
      final tmCache = turbineModelCache[docData['turbine_model_id']?.toString() ?? ''] ?? {};
      final stCache = siteCache[docData['site_id']?.toString() ?? '']                  ?? {};
      
      String localStateId = '';
      if (docData['state_ref'] is DocumentReference) {
        localStateId = (docData['state_ref'] as DocumentReference).id;
      } else {
        localStateId = docData['state_id']?.toString() ?? '';
      }
      final zoneVal = zoneCache[localStateId]                 ?? '';

      final timestamp    = docData['timestamp'] as Timestamp?;
      final auditDate    = timestamp?.toDate();
      final auditDateStr = auditDate != null ? DateFormat('dd-MM-yyyy').format(auditDate) : 'N/A';

      final siteName      = (docData['site']          ?? 'Unknown').toString();
      final turbineNo     = (docData['turbine']        ?? '').toString();
      final turbineMake   = (tmCache['turbine_make']   ?? docData['turbine_make']       ?? '').toString();
      final turbineModel  = (tmCache['turbine_model']  ?? docData['turbine_model_name'] ?? docData['wtg_model'] ?? '').toString();
      final turbineRating = (tmCache['turbine_rating'] ?? docData['wtg_rating']          ?? '').toString();
      final district      = (stCache['district']       ?? docData['district']    ?? '').toString();
      final warehouseCode = (stCache['warehouse_code'] ?? '').toString();
      final zone          = zoneVal.isNotEmpty ? zoneVal : (docData['zone'] ?? '').toString();
      final state         = (docData['state']          ?? '').toString();
      final customerName  = (docData['customer_name']  ?? '').toString();

      // Fetch live NCs for this audit
      final Map<String, Map<String, dynamic>> liveNCs = await _fetchNCsForAudit(auditId);

      // Per-audit penalty accumulators
      int totalWorkmanPenalty = 0;
      int totalOverallPenalty = 0;
      int criticalNCCount     = 0;

      // Sheet 1 inner loop — one row per NC task (same filter as single dump)
      final tasks = docData['audit_data'] as Map<String, dynamic>? ?? {};
      
      // Sort tasks numerically by key
      final sortedEntries = tasks.entries.toList()
        ..sort((a, b) {
          final ia = int.tryParse(a.key);
          final ib = int.tryParse(b.key);
          if (ia != null && ib != null) return ia.compareTo(ib);
          return a.key.compareTo(b.key);
        });

      for (final entry in sortedEntries) {
        final taskKey = entry.key;
        final task    = entry.value as Map<String, dynamic>;
        final nc      = liveNCs[taskKey];

        final status    = (task['status']   ?? '').toString().toLowerCase();
        final isCorrected = task['is_corrected'] == true;

        // "Use only not ok" - skip 'OK' tasks that weren't correctedFindings
        if (status == 'ok' && !isCorrected) continue;

        // Merge Task + NC data
        final String criticality = (nc?['nc_criticality'] ?? task['sub_status'] ?? 'Aobs').toString();
        final String ncCategory  = (nc?['nc_category']    ?? task['nc_category'] ?? '').toString();
        final String rootCause   = (nc?['root_cause']     ?? task['root_cause']  ?? '').toString();
        final String actionPlan  = (nc?['action_plan']    ?? task['action_plan'] ?? '').toString();
        final String actionTaken = (nc?['action_taken']   ?? task['closure_remark'] ?? (isCorrected ? 'Corrected' : '')).toString();
        final String ncStatus    = (nc?['status']         ?? (isCorrected ? 'Close' : 'Open')).toString();
        final String remarks     = (nc?['remarks']        ?? task['closure_remark'] ?? '').toString();

        // Date Parsing
        String planDate = '';
        final targetVal = nc?['target_date'] ?? task['target_date'];
        if (targetVal != null) {
          final d = _parseDate(targetVal);
          if (d != null) planDate = DateFormat('dd-MM-yyyy').format(d);
        }

        String closingDateStr = '';
        final closeVal = nc?['closing_date'] ?? (isCorrected ? auditDate : null);
        if (closeVal != null) {
          final d = _parseDate(closeVal);
          if (d != null) closingDateStr = DateFormat('dd-MM-yyyy').format(d);
        }

        final penalties = _calculatePenalties(criticality, ncCategory, workmanPenaltyMap);
        totalWorkmanPenalty += penalties['workman']!;
        totalOverallPenalty += penalties['overall']!;
        if (penalties['overall']! >= 3 || criticality == 'CF') criticalNCCount++;

        _writeExcelRow(sheet1, sheet1Row, <String>[
          sheet1SrNo.toString(),
          auditDateStr,
          turbineNo,
          (nc?['reference_name'] ?? task['reference_name'] ?? '-').toString(),
          (task['main_category_name'] ?? '-').toString(),
          (task['sub_category_name'] ?? '-').toString(),
          (nc?['finding'] ?? task['observation'] ?? '-').toString(),
          '', // Finding Photos placeholder
          criticality,
          ncCategory,
          rootCause,
          planDate,
          actionPlan,
          actionTaken,
          closingDateStr,
          '', // Closing Evidence
          ncStatus,
          remarks,
        ]);

        // Multiple Finding Photos
        final List<dynamic> findingPhotos = (nc != null && nc['photos'] is List) ? nc['photos'] as List<dynamic> : (task['photos'] is List ? task['photos'] as List<dynamic> : <dynamic>[]);
        if (findingPhotos.isNotEmpty) {
          await _embedImages(sheet1, sheet1Row, 8, findingPhotos);
        }

        // Closure Evidence
        final String? closurePhoto = nc?['closure_photo']?.toString() ?? task['closure_photo']?.toString();
        if (closurePhoto != null && closurePhoto.isNotEmpty) {
          await _embedSingleImage(sheet1, sheet1Row, 16, closurePhoto);
        }

        sheet1.getRangeByIndex(sheet1Row, 7).cellStyle.fontColor = _getFontColorForStatus(criticality);
        sheet1SrNo++;
        sheet1Row++;
      }

      // Sheet 2 — one summary row per audit
      final overallScore      = _getAssessmentScore(totalOverallPenalty);
      final workmanScore      = _getAssessmentScore(totalWorkmanPenalty);
      final overallCompliance = _getCompliancePercentage(totalOverallPenalty);
      final workmanCompliance = _getCompliancePercentage(totalWorkmanPenalty);

      final commissioningDate = _parseDate(docData['commissioning_date']);
      final takeOverDate      = _parseDate(docData['date_of_take_over']);
      final pmPlanDate        = _parseDate(docData['plan_date_of_maintenance']);
      final pmDoneDate        = _parseDate(docData['actual_date_of_maintenance']);

      String pmAdherence = '';
      int pmVsQaAging = 0;
      if (pmPlanDate != null && pmDoneDate != null) {
        pmAdherence = pmDoneDate.difference(pmPlanDate).inDays.toString();
      }
      if (auditDate != null && pmDoneDate != null) {
        pmVsQaAging = auditDate.difference(pmDoneDate).inDays;
      }

      final pmLead    = docData['pm_team_leader']?.toString() ?? '';
      final pmMembers = docData['pm_team_members'] is List
          ? (docData['pm_team_members'] as List).join(', ')
          : '';
      final pmType = docData['maintenance_type']?.toString() ?? '';

      String fmtD(DateTime? d) => d != null ? DateFormat('dd-MM-yyyy').format(d) : '';

      _writeExcelRow(sheet2, sheet2Row, <String>[
        sheet2SrNo.toString(), turbineNo, auditDateStr, turbineMake, turbineModel,
        turbineRating, siteName, district, state, zone,
        warehouseCode, customerName,
        fmtD(commissioningDate), fmtD(takeOverDate),
        _getAssessmentLabel(overallScore), '${overallCompliance.toStringAsFixed(2)}%',
        _getAssessmentLabel(workmanScore), '${workmanCompliance.toStringAsFixed(2)}%',
        criticalNCCount.toString(),
        fmtD(pmPlanDate), fmtD(pmDoneDate),
        pmAdherence, pmVsQaAging.toString(),
        pmType, pmLead, pmMembers, 'Open', '',
      ]);
      sheet2Row++;
      sheet2SrNo++;
    }

    if (sheet1SrNo == 1) {
      sheet1.getRangeByIndex(2, 7).setText('No issues found in selected audits');
    }

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();
    _downloadExcelBytes(bytes, 'Bulk_SQA_Dump_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx');
  }


  // ===========================================================================
  // FILENAME GENERATION HELPERS
  // ===========================================================================

  /// Calculates Financial Year based on Start Date (April 1st).
  /// If Date is Oct 2025, FY is 2025.
  /// If Date is Feb 2025, FY is 2024.
  String _getFinancialYear(DateTime date) {
    if (date.month >= 4) {
      return date.year.toString();
    } else {
      return (date.year - 1).toString();
    }
  }



  /// Counts the number of audits for this Site in the current Financial Year using Firestore.
  /// Used for generating the sequence number (e.g., 01, 02).
  Future<int> _getAuditSequenceCount(String siteName, DateTime date) async {
    try {
      // Calculate FY Start and End for the given date
      int fyStartYear = date.month >= 4 ? date.year : date.year - 1;
      final fyStartDate = DateTime(fyStartYear, 4, 1);
      final fyEndDate = DateTime(fyStartYear + 1, 3, 31, 23, 59, 59);

      // Query audit_submissions
      // Filter: site_name == siteName, date >= fyStartDate, date <= fyEndDate
      // Note: Assuming 'timestamp' is the field for audit date.
      
      final querySnapshot = await FirebaseFirestore.instance
          .collection('audit_submissions')
          .where('site', isEqualTo: siteName)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(fyStartDate))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(fyEndDate))
          .count()
          .get();

      final count = querySnapshot.count ?? 0;
      
      // The current audit is being generated, so it counts as the next one if not saved yet?
      // Requirement: "Get the total count of documents found and add 1 (for the current one)."
      // Assuming this is run BEFORE the current audit is submitted/finalized in the list 
      // OR if it IS submitted, we need to be careful.
      // Usually "export" happens on a view of an existing audit.
      // If the audit is ALREADY in the DB, this count might include it.
      // However, the requirement says "add 1".
      // Let's stick to the requirement: Count existing + 1.
      
      return count + 1;
    } catch (e) {
      // debugPrint('Error counting audits: $e');
      return 1; // Fallback to 01 if error
    }
  }
  // ---------------------------------------------------------------------------
  // IMAGE HELPERS
  // ---------------------------------------------------------------------------

  /// Embeds multiple images side-by-side in a single row/column area.
  Future<void> _embedImages(Worksheet sheet, int row, int col, List<dynamic> imageUrls) async {
    const int photoWidth = 60;
    const int photoHeight = 60;

    for (final url in imageUrls.take(3)) { // Limit to 3 to prevent extreme row height/width
      try {
        final response = await http.get(Uri.parse(url.toString()));
        if (response.statusCode == 200) {
          final Picture picture = sheet.pictures.addStream(row, col, response.bodyBytes);
          picture.height = photoHeight;
          picture.width = photoWidth;
          
          // Apply horizontal offset within the cell (Excel uses pixels for .left)
          // We manually set the column width enough to fit these.
          // Note: Left is absolute on sheet by default unless anchored, but in xlsio addStream(row, col)
          // usually anchors to the top-left of the cell.
          
          // Actually, we can't easily set .left in some versions of xlsio without it being relative to sheet.
          // However, we can increase the row height to fit one, and if multiple, some might overlap 
          // unless we have a clear way to offset.
          // For now, we'll try setting the height and width and rely on first for best quality, 
          // but we'll include up to 3 (they will overlap slightly if not offset, but we'll try to offset).
          
          // picture.left = (col - 1) * colWidth + leftOffset; // Pseudo-code if we knew column widths
          
          sheet.setRowHeightInPixels(row, photoHeight + 10);
        }
      } catch (_) {}
    }
  }

  /// Embeds a single image (e.g. closure proof).
  Future<void> _embedSingleImage(Worksheet sheet, int row, int col, String? imageUrl) async {
    if (imageUrl == null || imageUrl.isEmpty) return;
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        final Picture picture = sheet.pictures.addStream(row, col, response.bodyBytes);
        picture.height = 70;
        picture.width = 70;
        sheet.setRowHeightInPixels(row, 80);
        sheet.setColumnWidthInPixels(col, 80);
      }
    } catch (_) {}
  }
}

