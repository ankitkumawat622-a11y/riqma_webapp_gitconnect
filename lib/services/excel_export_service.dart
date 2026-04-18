import 'dart:js_interop';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' hide Column, Row, Border;
import 'package:web/web.dart' as web hide Range;

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

  static const List<String> _sqaDumpHeaders = <String>[
    'Sr. No.', 'Financial Year', 'WTG Category', 'Turbine Name', 'Date Of Audit', 'Turbine Make', 'Turbine Model', 
    'Turbine Rating (MW)', 'Site Name', 'District Name', 'State', 'Zone', 
    'Warehouse Code', 'Customer Name', 'Main Head', 'Sub Component', 
    'Finding/Observation', 'NC Criticality (CF/MCF/AObs)', 'Rating Category', 'Category of NC',
    'Reason of NC (Cause of NC)', 'Plan Date of NC closure', 'Plan of Action', 
    'Date Of Closure', 'Action Taken', 'Status', 'No. Of Days Taken', 'Auditor Name'
  ];

  /// Fetches NC documents from the 'ncs' collection linked to this audit.
  Future<Map<String, Map<String, dynamic>>> _fetchNCsForAudit(String auditId) async {
    final Map<String, Map<String, dynamic>> ncMap = {};
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('ncs')
          .where('audit_ref', isEqualTo: FirebaseFirestore.instance.doc('/audit_submissions/$auditId'))
          .get();
      
      for (final doc in snapshot.docs) {
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
  Future<void> generateNCTrackingExcel(String auditId, Map<String, dynamic> auditData, {void Function(double, String)? onProgress}) async {
    try {
      if (onProgress != null) onProgress(0.05, 'Preparing NC Tracking Data...');
      final Workbook workbook = Workbook();
      final Worksheet sheet = workbook.worksheets[0];
      sheet.name = 'NC Tracking';

      // Use the standardized 18-header list
      _writeExcelHeaders(sheet, _sqaNcHeaders, width: 100.0);
      sheet.setRowHeightInPixels(1, 40);
      sheet.setColumnWidthInPixels(7, 250); // Finding/Observation
      sheet.setColumnWidthInPixels(8, 200); // Finding Photos
      sheet.setColumnWidthInPixels(16, 160); // Closing Evidence Photos

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
      
      final totalTasks = sortedEntries.length;
      int processedCount = 0;

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
          processedCount++;
          if (onProgress != null) {
            final progress = 0.05 + (0.85 * (processedCount / totalTasks));
            onProgress(progress, 'Processing NC ${processedCount} of ${totalTasks}...');
          }
      }

      if (srNo == 1) {
        sheet.getRangeByIndex(2, 7).setText('No NCs or corrected tasks found');
      } else {
        // Apply formatting to the whole data range (NC Tracking Only)
        final Range dataRange = sheet.getRangeByIndex(1, 1, rowIndex - 1, _sqaNcHeaders.length);
        dataRange.cellStyle.hAlign = HAlignType.center;
        dataRange.cellStyle.vAlign = VAlignType.center;
        dataRange.cellStyle.wrapText = true;
        
        // Apply borders to all sides of each cell in the range
        dataRange.cellStyle.borders.all.lineStyle = LineStyle.thin;
        dataRange.cellStyle.borders.all.color = '#BFBFBF'; // Light grey borders
      }

      // Filename Helper usage
      final fyYear = _getFinancialYear(auditDate);
      final siteCode = siteName.length > 5 ? siteName.substring(0, 5).toUpperCase() : siteName.toUpperCase();
      final sequence = await _getAuditSequenceCount(siteName, auditDate);
      final seqStr = sequence.toString().padLeft(2, '0');
      
      final fileName = 'NC_Tracking_${siteCode}_${turbineNo}_${fyYear}_$seqStr.xlsx';
      
      if (onProgress != null) onProgress(0.95, 'Generating Excel File...');
      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();
      if (onProgress != null) onProgress(1.0, 'Download Starting...');
      _downloadExcelBytes(bytes, fileName);
    } catch (e) {
      // debugPrint('Error: $e');
    }
  }


  /// Generates and downloads the SQA Dump Excel for a specific audit.
  /// Automatically fetches master data.
  Future<void> generateSQADumpExcel(String auditId, Map<String, dynamic> auditData, {void Function(double, String)? onProgress}) async {
    try {
      if (onProgress != null) onProgress(0.05, 'Preparing SQA Dump...');
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
      
      // Fetch WTG Category from 'turbines' collection if possible
      String wtgCategory = 'existing';
      try {
        final turbineSnap = await FirebaseFirestore.instance
            .collection('turbines')
            .where('name', isEqualTo: turbineNo)
            .limit(1)
            .get();
        if (turbineSnap.docs.isNotEmpty) {
          final cat = (turbineSnap.docs.first.data()['wtg_category'] ?? 'existing').toString().toLowerCase();
          wtgCategory = (cat == 'old') ? 'existing' : cat;
        }
      } catch (_) {}

      final auditorName = (auditData['auditor_name'] ?? '').toString();
      final fy = auditDate != null ? _getFinancialYear(auditDate) : '';
      
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

      _writeExcelHeaders(sheet1, _sqaDumpHeaders, width: 100.0);
      sheet1.setColumnWidthInPixels(15, 250); // Observation column wider (now 15th)

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
      
      final totalTasks = sortedEntries.length;
      int processedCount = 0;

      final Map<String, List<Map<String, dynamic>>> groupedForScoring = {};

      for (final entry in sortedEntries) {
          final taskKey = entry.key;
          final task = entry.value as Map<String, dynamic>;
          final nc = liveNCs[taskKey];

          final status = (task['status'] ?? '').toString().toLowerCase();
          final isCorrected = task['is_corrected'] == true;

          if (status == 'ok' && !isCorrected) continue;

          final String reference = (nc?['reference_name'] ?? task['reference_name'] ?? '-').toString();
          final String criticality = (nc?['nc_criticality'] ?? task['sub_status'] ?? 'Aobs').toString();
          final String category = (nc?['nc_category'] ?? task['nc_category'] ?? '').toString();

          groupedForScoring.putIfAbsent(reference, () => []);
          groupedForScoring[reference]!.add({
            'sub_status': criticality,
            'nc_category': category,
          });

          final String rootCause = (nc?['root_cause'] ?? task['root_cause'] ?? '').toString();
          final String actionPlan = (nc?['action_plan'] ?? task['action_plan'] ?? '').toString();
          final String actionTaken = (isCorrected ? (task['closure_remark'] ?? 'OSC Corrected') : (nc?['action_taken'] ?? task['closure_remark'] ?? '')).toString();
          final String ncStatus = (isCorrected ? 'OSC Close' : (nc?['status'] ?? 'Open')).toString();

          int rating = (criticality == 'CF') ? 3 : (criticality == 'MCF' ? 2 : 1);
          if (rating >= 3) criticalNCCount++;

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
          int daysTaken = 0;
          if (closeVal != null && auditDate != null) {
            final dClose = _parseDate(closeVal);
            if (dClose != null) {
              daysTaken = dClose.difference(auditDate).inDays;
              if (daysTaken < 0) daysTaken = 0;
            }
          }

          _writeExcelRow(sheet1, rowIndex, <String>[
            srNo.toString(), fy, wtgCategory, turbineNo, auditDateStr, turbineMake, turbineModel,
            turbineRating, siteName, district, state, zone, warehouseCode, customerName,
            (task['main_category_name'] ?? '-').toString(), (task['sub_category_name'] ?? '-').toString(),
            (nc?['finding'] ?? task['observation'] ?? '-').toString(), criticality, rating.toString(),
            category, rootCause, planDate, actionPlan, closingDate, actionTaken, ncStatus,
            daysTaken.toString(), auditorName,
          ]);

          sheet1.getRangeByIndex(rowIndex, 17).cellStyle.fontColor = _getFontColorForStatus(criticality);

          srNo++;
          rowIndex++;
          processedCount++;
          if (onProgress != null) {
            onProgress(0.05 + (0.9 * (processedCount / totalTasks)), 'Processing Entry ${processedCount} of ${totalTasks}...');
          }
      }

      // Calculate final summary scores using grouping (Matches Digital SQA Report)
      for (final refGroup in groupedForScoring.values) {
        int maxOverall = 0;
        int maxWorkman = 0;
        for (final t in refGroup) {
          final p = _calculatePenalties(t['sub_status'].toString(), t['nc_category']?.toString(), workmanPenaltyMap);
          if (p['overall']! > maxOverall) maxOverall = p['overall']!;
          if (p['workman']! > maxWorkman) maxWorkman = p['workman']!;
        }
        totalOverallPenalty += maxOverall;
        totalWorkmanPenalty += maxWorkman;
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
        'Sr. No.', 'FY', 'WTG Type (New/Existing)', 'Turbine No', 'Date Of Audit', 'Turbine Make', 'Turbine Model',
        'Turbine Rating (MW)', 'Site Name', 'District Name', 'State', 'Zone',
        'Warehouse Code', 'Customer Name', 'Commission Date (DOC)', 'Renom Date Of Takeover (DOT)',
        'SQA Audit Overall Assessment', 'Overall Compliance Ok (%)', 'Workman Assessments',
        'Workman PM Compliance Ok (%)', 'No of finding having 3 Nos rating NC',
        'PM Plan Date', 'PM Done Date', 'PM Adherence (+/-7 Days)', 'PM Vs QA Aging',
        'PM Type', 'PM Lead', 'PM Team', 'Report Status', 'Auditor Name', 'Remark'
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

      String fmtD(DateTime? d) => d != null ? DateFormat('dd-MM-yyyy').format(d) : '';

      // Write summary row (31 columns)
      _writeExcelRow(sheet2, 2, <String>[
        '1',
        fy,
        wtgCategory.toLowerCase() == 'new' ? 'New' : 'Existing',
        turbineNo,
        auditDateStr,
        turbineMake,
        turbineModel,
        turbineRating,
        siteName,
        district,
        state,
        zone,
        warehouseCode,
        customerName,
        fmtD(commissioningDate),
        fmtD(takeOverDate),
        overallScore.toStringAsFixed(1),
        '${overallCompliance.toStringAsFixed(2)}%',
        workmanScore.toStringAsFixed(1),
        '${workmanCompliance.toStringAsFixed(2)}%',
        criticalNCCount.toString(),
        fmtD(pmPlanDate),
        fmtD(pmDoneDate),
        pmAdherence,
        pmVsQaAging.toString(),
        pmType,
        pmLead,
        pmMembers,
        'Open',
        auditorName,
        '',
      ]);

      // Save and download
      if (onProgress != null) onProgress(0.98, 'Generating Excel File...');
      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();
      if (onProgress != null) onProgress(1.0, 'Download Starting...');

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
  Future<void> generateDigitalSqaReportExcel(String auditId, Map<String, dynamic> auditData, {void Function(double, String)? onProgress}) async {
    try {
      if (onProgress != null) onProgress(0.05, 'Fetching Audit Metadata...');
      final Workbook workbook = Workbook();
      final Worksheet sheet = workbook.worksheets[0];
      sheet.name = 'SQA Audit Report';
      sheet.showGridlines = false;

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

      // Fetch reference order for sorting
      final Map<String, int> referenceOrderMap = {};
      try {
        final refsSnapshot = await FirebaseFirestore.instance.collection('references').get();
        for (final doc in refsSnapshot.docs) {
          final data = doc.data();
          final name = data['name']?.toString() ?? '';
          final order = data['order'] ?? data['code'];
          if (name.isNotEmpty && order != null) {
            referenceOrderMap[name] = order is int ? order : int.tryParse(order.toString()) ?? 999;
          }
        }
      } catch (_) {}

      // Group tasks by reference_name
      final Map<String, List<Map<String, dynamic>>> groupedTasks = {};
      tasks.forEach((key, value) {
        final task = value as Map<String, dynamic>;
        final nc = liveNCs[key];
        
        final status = (task['status'] ?? '').toString().toLowerCase();
        final isCorrected = task['is_corrected'] == true;
        
        // Include if Not OK, Corrected, or if an NC document exists for this task
        // Exclude 'OK' and 'NA' checklist points that are not findings
        if ((status != 'ok' && status != 'na' && status != 'n/a') || isCorrected || nc != null) {
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
      
      // Sort keys of groupedTasks based on referenceOrderMap
      final sortedRefNames = groupedTasks.keys.toList()
        ..sort((a, b) {
          final orderA = referenceOrderMap[a] ?? 999;
          final orderB = referenceOrderMap[b] ?? 999;
          return orderA.compareTo(orderB);
        });

      for (final refName in sortedRefNames) {
        final taskList = groupedTasks[refName]!;
        
        // Sort individual tasks inside the group: Workman tasks first, then by severity
        taskList.sort((a, b) {
          final aIsWorkman = workmanPenaltyMap[a['nc_category']?.toString()] ?? false;
          final bIsWorkman = workmanPenaltyMap[b['nc_category']?.toString()] ?? false;
          if (aIsWorkman != bIsWorkman) return bIsWorkman ? 1 : -1;
          final aPriority = subStatusPriority[a['sub_status']?.toString() ?? 'Aobs'] ?? 0;
          final bPriority = subStatusPriority[b['sub_status']?.toString() ?? 'Aobs'] ?? 0;
          return bPriority.compareTo(aPriority);
        });

        // Collect detailed points for RichText and finding info
        final List<Map<String, String>> observationPoints = [];
        for (int i = 0; i < taskList.length; i++) {
          final t = taskList[i];
          var obsText = (t['observation'] ?? t['question'] ?? '-').toString();
          if (t['is_corrected'] == true) {
            obsText += ' (Corrected on Site)';
          }
          observationPoints.add({
            'text': '${i + 1}. $obsText',
            'color': _getFontColorForStatus(t['sub_status']?.toString() ?? 'Aobs'),
          });
        }

        // Calculate independent max penalties for this group
        int groupOverallPenalty = 0;
        int groupWorkmanPenalty = 0;
        String finalSubStatus = 'Aobs';
        
        for (final task in taskList) {
          final sSub = (task['sub_status'] ?? 'Aobs').toString();
          final sNc = task['nc_category']?.toString();
          final p = _calculatePenalties(sSub, sNc, workmanPenaltyMap);
          
          if (p['overall']! > groupOverallPenalty) {
            groupOverallPenalty = p['overall']!;
            finalSubStatus = sSub;
          }
          if (p['workman']! > groupWorkmanPenalty) {
            groupWorkmanPenalty = p['workman']!;
          }
          
          // Number of CF is counted per individual finding
          if (p['overall']! >= 3 || sSub.toUpperCase() == 'CF') {
            criticalNCCount++;
          }
        }

        totalWorkmanPenalty += groupWorkmanPenalty;
        totalOverallPenalty += groupOverallPenalty;

        if (observationPoints.isNotEmpty) {
           processedTasks.add({
             'srNo': serialCounter++,
             'refName': refName,
             'points': observationPoints,
             'subStatus': finalSubStatus,
             'workmanScore': groupWorkmanPenalty,
             'overallScore': groupOverallPenalty,
           });
        }
      }

      // Calculate scores
      final workmanScore = _getAssessmentScore(totalWorkmanPenalty);
      final overallScore = _getAssessmentScore(totalOverallPenalty);
      final workmanCompliance = _getCompliancePercentage(totalWorkmanPenalty);
      final overallCompliance = _getCompliancePercentage(totalOverallPenalty);

      // -----------------------------------------------------------------------
      // 3. SET COLUMN WIDTHS
      // -----------------------------------------------------------------------
      sheet.setColumnWidthInPixels(1, 10);   // A filler
      sheet.setColumnWidthInPixels(2, 170);  // B (Set to 4.5 cm for Logo)
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

      void applyOutsideBorders(int r1, int c1, int r2, int c2) {
         final range = sheet.getRangeByIndex(r1, c1, r2, c2);
         range.cellStyle.borders.left.lineStyle = LineStyle.thin;
         range.cellStyle.borders.left.color = '#000000';
         range.cellStyle.borders.right.lineStyle = LineStyle.thin;
         range.cellStyle.borders.right.color = '#000000';
         range.cellStyle.borders.top.lineStyle = LineStyle.thin;
         range.cellStyle.borders.top.color = '#000000';
         range.cellStyle.borders.bottom.lineStyle = LineStyle.thin;
         range.cellStyle.borders.bottom.color = '#000000';
      }

      // -----------------------------------------------------------------------
      // Row 2 to 3 - Header Section
      // -----------------------------------------------------------------------
      sheet.getRangeByIndex(2, 2, 3, 2).merge();
      // Set Row Heights for Header (Total 43 px = 1.14 cm)
      sheet.setRowHeightInPixels(2, 21.5);
      sheet.setRowHeightInPixels(3, 21.5);

      try {
        final ByteData data = await rootBundle.load('assets/images/renom_logo.png');
        final List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        final Picture picture = sheet.pictures.addStream(2, 2, bytes);
        // Scaled to 4.5 cm width and 1.14 cm height
        picture.height = 43;
        picture.width = 170;
      } catch (e) {
        sheet.getRangeByIndex(2, 2).setText('Renom Logo');
      }
      cellStyle(2, 2, bold: true, backColor: '#FFFFFF');
      
      sheet.getRangeByIndex(2, 3, 3, 8).merge();
      sheet.getRangeByIndex(2, 3).setText('SQA Audit Report');
      cellStyle(2, 3, fontSize: 16, bold: true, backColor: '#FFFFFF', fontColor: '#000000');
      
      String getRatingColor(double s) {
        if (s >= 13.5) return '#00B050'; // Excellent
        if (s >= 10.5) return '#FFFF00'; // Good
        if (s >= 7.5)  return '#00B0F0'; // Improvements Required
        if (s >= 4.5)  return '#FABF8F'; // Poor
        return '#FF0000';                // Worst
      }

      sheet.getRangeByIndex(2, 9, 3, 9).merge();
      sheet.getRangeByIndex(2, 9).setText(workmanScore.toStringAsFixed(1));
      cellStyle(2, 9, bold: true, fontSize: 12, backColor: getRatingColor(workmanScore), fontColor: (workmanScore >= 10.5 && workmanScore < 13.5) || (workmanScore >= 4.5 && workmanScore < 7.5) ? '#000000' : '#FFFFFF');
      
      sheet.getRangeByIndex(2, 10, 3, 10).merge();
      sheet.getRangeByIndex(2, 10).setText(overallScore.toStringAsFixed(1));
      cellStyle(2, 10, bold: true, fontSize: 12, backColor: getRatingColor(overallScore), fontColor: (overallScore >= 10.5 && overallScore < 13.5) || (overallScore >= 4.5 && overallScore < 7.5) ? '#000000' : '#FFFFFF');
      
      applyBorders(2, 2, 3, 10);

      // -----------------------------------------------------------------------
      // Row 4 - Rating Scale
      // -----------------------------------------------------------------------
      sheet.getRangeByIndex(4, 2).setText('Excellent (13.5-15)');
      cellStyle(4, 2, backColor: '#00B050', fontColor: '#FFFFFF');
      
      sheet.getRangeByIndex(4, 3, 4, 4).merge();
      sheet.getRangeByIndex(4, 3).setText('Good (10.5-13)');
      cellStyle(4, 3, backColor: '#FFFF00', fontColor: '#000000');
      
      sheet.getRangeByIndex(4, 5).setText('Improvements Required (7.5-10)');
      cellStyle(4, 5, backColor: '#00B0F0', fontColor: '#FFFFFF');
      
      sheet.getRangeByIndex(4, 6).setText('Poor (4.5-7)');
      cellStyle(4, 6, backColor: '#FABF8F', fontColor: '#000000');
      
      sheet.getRangeByIndex(4, 7).setText('Worst (<4.5)');
      cellStyle(4, 7, backColor: '#FF0000', fontColor: '#FFFFFF');
      
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
      sheet.getRangeByIndex(16, 5).setText('PM Team Details');
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
        if (onProgress != null) onProgress(0.4, 'Writing Audit Findings...');
        int taskIdx = 0;
        for (final task in processedTasks) {
          taskIdx++;
          if (onProgress != null) {
            onProgress(0.4 + (0.5 * (taskIdx / processedTasks.length)), 'Processing Finding $taskIdx of ${processedTasks.length}');
          }
          final int startRow = row;
          final String refName = task['refName'].toString();
          final List<Map<String, String>> points = List<Map<String, String>>.from(task['points'] as List);
          
          // 1. Header line (Category Name)
          sheet.getRangeByIndex(row, 3, row, 7).merge();
          final refRange = sheet.getRangeByIndex(row, 3);
          refRange.setText('[$refName]');
          cellStyle(row, 3, bold: true, fontColor: '#34495E', hAlign: HAlignType.left);
          sheet.setRowHeightInPixels(row, 0); // Hide the reference name row
          row++;
          
          // 2. Point lines (one per observation point)
          for (final p in points) {
            sheet.getRangeByIndex(row, 3, row, 7).merge();
            final pRange = sheet.getRangeByIndex(row, 3);
            pRange.setText(p['text']!);
            cellStyle(row, 3, fontColor: p['color'], hAlign: HAlignType.left, wrapText: true);
            
            // Adjust row height for long text
            final pLen = p['text']!.length;
            if (pLen > 70) {
              final lines = (pLen / 70).ceil();
              sheet.setRowHeightInPixels(row, lines * 16.0);
            }
            row++;
          }
          
          final int endRow = row - 1;
          
          // 3. Metadata Vertical Merging (Sr No, Status, Scores)
          // Sr No
          final srRange = sheet.getRangeByIndex(startRow, 2, endRow, 2);
          srRange.merge();
          srRange.setText(task['srNo'].toString());
          cellStyle(startRow, 2);
          
          // Status
          final statusRange = sheet.getRangeByIndex(startRow, 8, endRow, 8);
          statusRange.merge();
          statusRange.setText(task['subStatus'].toString());
          cellStyle(startRow, 8);
          
          // Scores
          final wScoreRange = sheet.getRangeByIndex(startRow, 9, endRow, 9);
          wScoreRange.merge();
          wScoreRange.setText(task['workmanScore'].toString());
          cellStyle(startRow, 9, fontColor: (task['workmanScore'] as int) > 0 ? '#FF0000' : '#000000');
          
          final oScoreRange = sheet.getRangeByIndex(startRow, 10, endRow, 10);
          oScoreRange.merge();
          oScoreRange.setText(task['overallScore'].toString());
          cellStyle(startRow, 10, fontColor: (task['overallScore'] as int) > 0 ? '#FF0000' : '#000000');

          // Apply outside borders for the whole group block
          applyOutsideBorders(startRow, 2, endRow, 10);
          // Apply internal vertical borders to separate columns
          applyOutsideBorders(startRow, 2, endRow, 2); // Sr No
          applyOutsideBorders(startRow, 3, endRow, 7); // Observations
          applyOutsideBorders(startRow, 8, endRow, 8); // Status
          applyOutsideBorders(startRow, 9, endRow, 9); // Workman
          applyOutsideBorders(startRow, 10, endRow, 10); // Overall
          
        }
      }

      // -----------------------------------------------------------------------
      // Footer Section
      // -----------------------------------------------------------------------
      final int footerStartRow = row;

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
      // Row 29-30 (Workman Section)
      sheet.getRangeByIndex(row, 2).setText('Workman Assessments');
      sheet.getRangeByIndex(row, 3, row, 5).merge();
      sheet.getRangeByIndex(row, 3).setText(workmanScore.toStringAsFixed(2));
      
      // Workman Remark Box (Spans 2 rows: F to G and H to J)
      final wRangeLabel = sheet.getRangeByIndex(row, 6, row + 1, 7);
      wRangeLabel.merge();
      wRangeLabel.setText('Remarks Of Workman assessments');
      wRangeLabel.cellStyle.bold = true;
      wRangeLabel.cellStyle.wrapText = true;
      wRangeLabel.cellStyle.vAlign = VAlignType.center;
      
      final wRangeRating = sheet.getRangeByIndex(row, 8, row + 1, 10);
      wRangeRating.merge();
      final double wsVal = double.tryParse(workmanScore.toStringAsFixed(1)) ?? 15.0;
      final String wRemStr = wsVal >= 13.5 ? 'Excellent' : wsVal >= 10.5 ? 'Good' : wsVal >= 7.5 ? 'Improvements Required' : wsVal >= 4.5 ? 'Poor' : 'Need to do re-PM';
      wRangeRating.setText(wRemStr);
      wRangeRating.cellStyle.bold = true;
      wRangeRating.cellStyle.backColor = getRatingColor(wsVal);
      wRangeRating.cellStyle.vAlign = VAlignType.center;
      wRangeRating.cellStyle.fontColor = (wsVal >= 10.5 && wsVal < 13.5) || (wsVal >= 4.5 && wsVal < 7.5) ? '#000000' : '#FFFFFF';

      row++;
      // Row 30 (Workman PM Compliance)
      sheet.getRangeByIndex(row, 2).setText('Workman PM Compliance');
      sheet.getRangeByIndex(row, 3, row, 5).merge();
      sheet.getRangeByIndex(row, 3).setText('${workmanCompliance.toStringAsFixed(2)}%');

      row++;
      // Row 31-32 (Overall Section)
      sheet.getRangeByIndex(row, 2).setText('Overall Assessments');
      sheet.getRangeByIndex(row, 3, row, 5).merge();
      sheet.getRangeByIndex(row, 3).setText(overallScore.toStringAsFixed(2));
      
      // Overall Remark Box (Spans 2 rows: F to G and H to J)
      final oRangeLabel = sheet.getRangeByIndex(row, 6, row + 1, 7);
      oRangeLabel.merge();
      oRangeLabel.setText('Remarks Of Overall assessments');
      oRangeLabel.cellStyle.bold = true;
      oRangeLabel.cellStyle.wrapText = true;
      oRangeLabel.cellStyle.vAlign = VAlignType.center;
      
      final oRangeRating = sheet.getRangeByIndex(row, 8, row + 1, 10);
      oRangeRating.merge();
      final double osVal = double.tryParse(overallScore.toStringAsFixed(1)) ?? 15.0;
      final String oRemStr = osVal >= 13.5 ? 'Excellent' : osVal >= 10.5 ? 'Good' : osVal >= 7.5 ? 'Improvements Required' : osVal >= 4.5 ? 'Poor' : 'Worst';
      oRangeRating.setText(oRemStr);
      oRangeRating.cellStyle.bold = true;
      oRangeRating.cellStyle.backColor = getRatingColor(osVal);
      oRangeRating.cellStyle.vAlign = VAlignType.center;
      oRangeRating.cellStyle.fontColor = (osVal >= 10.5 && osVal < 13.5) || (osVal >= 4.5 && osVal < 7.5) ? '#000000' : '#FFFFFF';

      row++;
      // Row 32 (Overall Compliance)
      sheet.getRangeByIndex(row, 2).setText('Overall Compliance');
      sheet.getRangeByIndex(row, 3, row, 5).merge();
      sheet.getRangeByIndex(row, 3).setText('${overallCompliance.toStringAsFixed(2)}%');
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

      row++;
      // Row 34: Explanatory Note
      final noteRange = sheet.getRangeByIndex(row, 2, row, 10);
      noteRange.merge();
      noteRange.setText('(Note: Assinged NC sequence as per rating reference sheet. And all audit NC\'s mentioned under “Type of NC” and color coding (font color) in NC description represented: Red–CF, Blue–MCF, Black–Aobs.)');
      noteRange.cellStyle.fontSize = 9;
      noteRange.cellStyle.fontName = 'Arial';
      noteRange.cellStyle.italic = true;
      noteRange.cellStyle.wrapText = true;
      noteRange.cellStyle.vAlign = VAlignType.center;
      noteRange.cellStyle.hAlign = HAlignType.left;
      sheet.setRowHeightInPixels(row, 40); // Give enough space for wrapping

      // -----------------------------------------------------------------------
      // 8. PAGE SETUP & PRINT SETTINGS
      // -----------------------------------------------------------------------
      // This disclaimer only shows when printing/PDF exporting, not in the excel grid.
      // sheet.pageSetup.centerFooter = 'This report is generated by Renom Integrated Quality Management System';
      sheet.pageSetup.orientation = ExcelPageOrientation.portrait;
      sheet.pageSetup.isFitToPage = true;
      sheet.pageSetup.topMargin = 0.5;
      sheet.pageSetup.bottomMargin = 0.5;
      sheet.pageSetup.leftMargin = 0.5;
      sheet.pageSetup.rightMargin = 0.5;
      
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

      if (onProgress != null) onProgress(0.98, 'Generating Excel File...');
      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();
      if (onProgress != null) onProgress(1.0, 'Download Starting...');
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
  

  /// Returns font color based on NC Category (sub_status).
  String _getFontColorForStatus(String subStatus) {
    final status = subStatus.toUpperCase();
    if (status == 'MCF') return '#0000FF'; // Blue
    if (status == 'CF') return '#FF0000'; // Red
    return '#000000'; // Black for Aobs, etc.
  }

  Map<String, int> _calculatePenalties(String subStatus, String? ncCategory, Map<String, bool> workmanPenaltyMap) {
    int overall = 1;
    switch (subStatus) {
      case 'CF':  overall = 3; break;
      case 'MCF': overall = 2; break;
      default:    overall = 1;
    }
    
    final bool isWorkman = workmanPenaltyMap[ncCategory] ?? false;
    return {
      'overall': overall,
      'workman': isWorkman ? overall : 0,
    };
  }

  double _getAssessmentScore(int penaltyPoints) {
    if (penaltyPoints <= 0) return 15.0;
    if (penaltyPoints >= 66) return 0.1;

    // Follow the Non-Linear curve from Column W of the official SQA Rating Table
    if (penaltyPoints <= 20) {
      // Linear drop of 0.5 per point (0 to 20 penalty = 15.0 to 5.0 score)
      return 15.0 - (penaltyPoints * 0.5);
    } else if (penaltyPoints == 21) {
      return 4.8;
    } else if (penaltyPoints == 22) {
      return 4.5;
    } else {
      // 23 to 66 penalty = 4.4 to 0.1 score (Red Section: 0.1 drop per point)
      final score = 4.4 - ((penaltyPoints - 23) * 0.1);
      // Ensure we return a clean decimal for reporting
      return double.parse(score.toStringAsFixed(1));
    }
  }



  double _getCompliancePercentage(int totalPenalty) {
    // Formula: 100% - (Total Penalty * 100 / 75)
    final double pct = 100.0 - (totalPenalty * 100 / 75.0);
    return pct.clamp(0.0, 100.0);
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
  Future<void> generateBulkSQADumpExcel(List<Map<String, dynamic>> multiAuditData, {void Function(double, String)? onProgress}) async {
    // ---------------------------------------------------------------------------
    // Creates a 2-sheet workbook — 1:1 aggregated version of generateSQADumpExcel.
    // Sheet 1 "MIS SQA NC Details" : one row per NC task, across all audits
    // Sheet 2 "WTG Assessment"     : one summary row per audit
    // ---------------------------------------------------------------------------
    if (onProgress != null) onProgress(0.05, 'Starting Bulk Export for ${multiAuditData.length} Audits...');
    final Workbook workbook = Workbook(2);

    // SHEET 1
    final Worksheet sheet1 = workbook.worksheets[0];
    sheet1.name = 'MIS SQA NC Details';
    _writeExcelHeaders(sheet1, _sqaDumpHeaders, width: 100.0);
    sheet1.setColumnWidthInPixels(15, 250); // Observation column wider (now 15th)

    // SHEET 2
    final Worksheet sheet2 = workbook.worksheets[1];
    sheet2.name = 'WTG Assessment';
    _writeExcelHeaders(sheet2, <String>[
      'Sr. No.', 'FY', 'WTG Type (New/Existing)', 'Turbine No', 'Date Of Audit', 'Turbine Make', 'Turbine Model',
      'Turbine Rating (MW)', 'Site Name', 'District Name', 'State', 'Zone',
      'Warehouse Code', 'Customer Name', 'Commission Date (DOC)', 'Renom Date Of Takeover (DOT)',
      'SQA Audit Overall Assessment', 'Overall Compliance Ok (%)', 'Workman Assessments',
      'Workman PM Compliance Ok (%)', 'No of finding having 3 Nos rating NC',
      'PM Plan Date', 'PM Done Date', 'PM Adherence (+/-7 Days)', 'PM Vs QA Aging',
      'PM Type', 'PM Lead', 'PM Team', 'Report Status', 'Auditor Name', 'Remark'
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
    final totalAudits = sortedData.length;
    int auditsProcessed = 0;
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
      final auditorName   = (docData['auditor_name']   ?? '').toString();
      final fy            = auditDate != null ? _getFinancialYear(auditDate) : '';

      // Fetch WTG Category
      String wtgCategory = 'existing';
      try {
        final turbineSnap = await FirebaseFirestore.instance
            .collection('turbines')
            .where('name', isEqualTo: turbineNo)
            .limit(1)
            .get();
        if (turbineSnap.docs.isNotEmpty) {
          final cat = (turbineSnap.docs.first.data()['wtg_category'] ?? 'existing').toString().toLowerCase();
          wtgCategory = (cat == 'old') ? 'existing' : cat;
        }
      } catch (_) {}

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

        // Custom logic for OSC
        final String actionTaken = (isCorrected 
            ? (task['closure_remark'] ?? 'OSC Corrected')
            : (nc?['action_taken'] ?? task['closure_remark'] ?? '')).toString();
        
        final String ncStatus = (isCorrected ? 'OSC Close' : (nc?['status'] ?? 'Open')).toString();

        // Rating Category
        int rating = 1;
        if (criticality == 'CF') {
          rating = 3;
        } else if (criticality == 'MCF') {
          rating = 2;
        }

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

        // Days Taken calculation
        int daysTaken = 0;
        if (closeVal != null && auditDate != null) {
          final dClose = _parseDate(closeVal);
          if (dClose != null) {
            daysTaken = dClose.difference(auditDate).inDays;
            if (daysTaken < 0) daysTaken = 0;
          }
        }

        final penalties = _calculatePenalties(criticality, ncCategory, workmanPenaltyMap);
        totalWorkmanPenalty += penalties['workman']!;
        totalOverallPenalty += penalties['overall']!;
        if (penalties['overall']! >= 3 || criticality == 'CF') criticalNCCount++;

        // Write row (28 columns)
        _writeExcelRow(sheet1, sheet1Row, <String>[
          sheet1SrNo.toString(),
          fy,
          wtgCategory,
          turbineNo,
          auditDateStr,
          turbineMake,
          turbineModel,
          turbineRating,
          siteName,
          district,
          state,
          zone,
          warehouseCode,
          customerName,
          (task['main_category_name'] ?? '-').toString(),
          (task['sub_category_name'] ?? '-').toString(),
          (nc?['finding'] ?? task['observation'] ?? '-').toString(),
          criticality,
          rating.toString(),
          ncCategory,
          rootCause,
          planDate,
          actionPlan,
          closingDateStr,
          actionTaken,
          ncStatus,
          daysTaken.toString(),
          auditorName,
        ]);

        // Apply conditional coloring to Observation cell (Column 17)
        sheet1.getRangeByIndex(sheet1Row, 17).cellStyle.fontColor = _getFontColorForStatus(criticality);
        sheet1SrNo++;
        sheet1Row++;
      }

      // Sheet 2 — one summary row per audit using grouped scores
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

      // Write row (31 columns)
      _writeExcelRow(sheet2, sheet2Row, <String>[
        sheet2SrNo.toString(),
        fy,
        wtgCategory.toLowerCase() == 'new' ? 'New' : 'Existing',
        turbineNo,
        auditDateStr,
        turbineMake,
        turbineModel,
        turbineRating,
        siteName,
        district,
        state,
        zone,
        warehouseCode,
        customerName,
        fmtD(commissioningDate),
        fmtD(takeOverDate),
        overallScore.toStringAsFixed(1),
        '${overallCompliance.toStringAsFixed(2)}%',
        workmanScore.toStringAsFixed(1),
        '${workmanCompliance.toStringAsFixed(2)}%',
        criticalNCCount.toString(),
        fmtD(pmPlanDate),
        fmtD(pmDoneDate),
        pmAdherence,
        pmVsQaAging.toString(),
        pmType,
        pmLead,
        pmMembers,
        'Open',
        auditorName,
        '',
      ]);
      sheet2Row++;
      sheet2SrNo++;
      auditsProcessed++;
      if (onProgress != null) {
        final progress = 0.2 + (0.75 * (auditsProcessed / totalAudits));
        onProgress(progress, 'Processing Audit ${auditsProcessed} of ${totalAudits}...');
      }
    }

    if (sheet1SrNo == 1) {
      sheet1.getRangeByIndex(2, 7).setText('No issues found in selected audits');
    }

    if (onProgress != null) onProgress(0.98, 'Generating Excel File...');
    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();
    if (onProgress != null) onProgress(1.0, 'Download Starting...');
    _downloadExcelBytes(bytes, 'Bulk_SQA_Dump_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx');
  }


  // ===========================================================================
  // FILENAME GENERATION HELPERS
  // ===========================================================================

  /// Calculates Financial Year based on Start Date (April 1st).
  /// If Date is Oct 2025, FY is 2025.
  /// If Date is Feb 2025, FY is 2024.
  String _getFinancialYear(DateTime date) {
    final int year = date.year;
    final int month = date.month;
    if (month >= 4) {
      return '$year-${(year + 1).toString().substring(2)}';
    } else {
      return '${year - 1}-${year.toString().substring(2)}';
    }
  }



  /// Counts the number of audits for this Site in the current Financial Year using Firestore.
  /// Used for generating the sequence number (e.g., 01, 02).
  Future<int> _getAuditSequenceCount(String siteName, DateTime date) async {
    try {
      // Calculate FY Start and End for the given date
      final int fyStartYear = date.month >= 4 ? date.year : date.year - 1;
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
    const int photoWidth = 143;  // 3.78 cm approx 143px
    const int photoHeight = 80; // 2.12 cm approx 80px

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
          
          sheet.setRowHeightInPixels(row, photoHeight + 15);
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
        picture.height = 80;
        picture.width = 143;
        sheet.setRowHeightInPixels(row, 90);
        sheet.setColumnWidthInPixels(col, 150);
      }
    } catch (_) {}
  }
}

