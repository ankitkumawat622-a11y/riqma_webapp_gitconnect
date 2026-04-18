import 'dart:async';
import 'dart:convert'; // Added for utf8 decoding

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Model class for individual observation item with its sub_status
class ObservationItem {
  final String text;
  final String subStatus;

  ObservationItem({required this.text, required this.subStatus});
}

// Model class for grouped reference data
class ReferenceGroup {
  final String referenceName;
  final int referenceCode; // For sorting by reference order
  final List<ObservationItem> observations;
  final String highestSubStatus;
  final String? ncCategory;
  final int workmanRating;
  final int overallRating;

  ReferenceGroup({
    required this.referenceName,
    required this.referenceCode,
    required this.observations,
    required this.highestSubStatus,
    this.ncCategory,
    required this.workmanRating,
    required this.overallRating,
  });
}

class DigitalSqaReportScreen extends StatefulWidget {
  final Map<String, dynamic> auditData;
  final String auditId;

  const DigitalSqaReportScreen({
    super.key,
    required this.auditData,
    required this.auditId,
  });

  @override
  State<DigitalSqaReportScreen> createState() => _DigitalSqaReportScreenState();
}

class _DigitalSqaReportScreenState extends State<DigitalSqaReportScreen> {
  // Metadata Controllers
  late TextEditingController _stateController;
  late TextEditingController _siteController;
  late TextEditingController _turbineIdController;
  late TextEditingController _makeController; // Added
  late TextEditingController _modelController;
  late TextEditingController _ratingController;
  late TextEditingController _customerNameController;
  late TextEditingController _auditorNameController;
  late TextEditingController _auditeeNameController;
  late TextEditingController _remarksController;
  
  // Dates
  DateTime? _commissioningDate;
  DateTime? _takeOverDate;
  DateTime? _maintPlanDate;
  DateTime? _maintDoneDate;
  DateTime? _inspectionDate;

  // Checkboxes - Assessment


  // Processed Reference Groups
  List<ReferenceGroup> _referenceGroups = [];
  
  // PM Team Details
  String? _pmTeamLeader;
  List<String> _pmTeamMembers = [];

  // Calculated Totals
  int _totalWorkmanPenalty = 0;
  int _totalOverallPenalty = 0;


  // Priority map for sub-status severity (higher = worse)
  static const Map<String, int> _subStatusPriority = {
    'CF': 3,
    'MCF': 2,
    'Aobs': 1,
    'OK': 0,
  };

  @override
  void initState() {
    super.initState();
    _initializeData();
    _processReferenceGroups();
  }

  void _initializeData() {
    final data = widget.auditData;
    final reportMeta = data['report_metadata'] as Map<String, dynamic>? ?? {};

    _stateController = TextEditingController(text: (reportMeta['state'] as String?) ?? (data['state'] as String?) ?? '');
    _siteController = TextEditingController(text: (reportMeta['site'] as String?) ?? (data['site'] as String?) ?? '');
    _turbineIdController = TextEditingController(text: (reportMeta['turbine_id'] as String?) ?? (data['turbine'] as String?) ?? '');
    _makeController = TextEditingController(text: (reportMeta['make'] as String?) ?? (data['turbine_make'] as String?) ?? ''); // Added
    _modelController = TextEditingController(text: (reportMeta['model'] as String?) ?? (data['turbine_model_name'] as String?) ?? (data['wtg_model'] as String?) ?? (data['model'] as String?) ?? '');
    _ratingController = TextEditingController(text: (reportMeta['rating'] as String?) ?? (data['wtg_rating'] as String?) ?? '');
    _customerNameController = TextEditingController(text: (reportMeta['customer_name'] as String?) ?? (data['customer_name'] as String?) ?? '');
    _auditorNameController = TextEditingController(text: (reportMeta['auditor_name'] as String?) ?? (data['auditor_name'] as String?) ?? '');
    _auditeeNameController = TextEditingController(text: (reportMeta['auditee_name'] as String?) ?? '');
    _remarksController = TextEditingController(text: (reportMeta['remarks'] as String?) ?? '');

    // Dates
    _commissioningDate = _parseDate(reportMeta['commissioning_date'] ?? data['commissioning_date']);
    _takeOverDate = _parseDate(reportMeta['take_over_date'] ?? data['date_of_take_over']);
    _maintPlanDate = _parseDate(reportMeta['maint_plan_date'] ?? data['plan_date_of_maintenance']);
    _maintDoneDate = _parseDate(reportMeta['maint_done_date'] ?? data['actual_date_of_maintenance']);
    _inspectionDate = _parseDate(reportMeta['inspection_date'] ?? data['timestamp']);

    // Checkboxes


    // PM Team Details
    _pmTeamLeader = data['pm_team_leader'] as String?;
    final members = data['pm_team_members'];
    if (members is List) {
      _pmTeamMembers = members.map((e) => e.toString()).toList();
    }
  }

  /// PART 1: Data Processing Engine - Group tasks by reference
  Future<void> _processReferenceGroups() async {
    final tasks = widget.auditData['audit_data'] as Map<String, dynamic>? ?? {};
    
    // Fetch reference order from Firestore for sorting
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
    } catch (e) {
      debugPrint('Error fetching reference orders: $e');
    }
    
    // Group tasks by reference_name
    final Map<String, List<Map<String, dynamic>>> groupedTasks = {};
    
    tasks.forEach((key, value) {
      final task = value as Map<String, dynamic>;
      final status = (task['status'] ?? '').toString().toLowerCase();
      
      // Only process Not OK tasks
      if (status != 'ok') {
        final refName = task['reference_name']?.toString() ?? 
                        task['referenceoftask']?.toString() ?? 
                        'Uncategorized';
        
        groupedTasks.putIfAbsent(refName, () => []);
        groupedTasks[refName]!.add(task);
      }
    });

    // Process each group
    final List<ReferenceGroup> groups = [];
    
    groupedTasks.forEach((refName, taskList) {
      // 1. Collect all observations with individual sub_status
      final List<ObservationItem> observations = [];
      for (int i = 0; i < taskList.length; i++) {
        final obs = taskList[i]['observation']?.toString() ?? 
                    taskList[i]['question']?.toString() ?? '';
        final taskSubStatus = taskList[i]['sub_status']?.toString() ?? 'OK';
        if (obs.isNotEmpty) {
          observations.add(ObservationItem(
            text: '${i + 1}. $obs',
            subStatus: taskSubStatus,
          ));
        }
      }

      // 2. Find highest severity task
      Map<String, dynamic>? highestSeverityTask;
      int highestPriority = -1;
      
      for (final task in taskList) {
        final subStatus = task['sub_status']?.toString() ?? 'OK';
        final priority = _subStatusPriority[subStatus] ?? 0;
        final ncCategory = task['nc_category']?.toString();
        
        // If same priority, prefer 'Quality of Workmanship' (carries workman penalty)
        if (priority > highestPriority || 
            (priority == highestPriority && ncCategory == 'Quality of Workmanship')) {
          highestPriority = priority;
          highestSeverityTask = task;
        }
      }

      // 3. Calculate penalty points
      final subStatus = highestSeverityTask?['sub_status']?.toString() ?? 'OK';
      final ncCategory = highestSeverityTask?['nc_category']?.toString();
      final penalties = _calculatePenalties(subStatus, ncCategory);

      // 4. Get reference order for sorting (default 999 for unknown)
      final refOrder = referenceOrderMap[refName] ?? 999;

      groups.add(ReferenceGroup(
        referenceName: refName,
        referenceCode: refOrder,
        observations: observations,
        highestSubStatus: subStatus,
        ncCategory: ncCategory,
        workmanRating: penalties['workman']!,
        overallRating: penalties['overall']!,
      ));
    });

    // Sort groups by reference code (ascending - lower code comes first)
    groups.sort((a, b) => a.referenceCode.compareTo(b.referenceCode));

    // Calculate totals
    int totalWorkman = 0;
    int totalOverall = 0;
    for (final group in groups) {
      totalWorkman += group.workmanRating;
      totalOverall += group.overallRating;
    }

    setState(() {
      _referenceGroups = groups;
      _totalWorkmanPenalty = totalWorkman;
      _totalOverallPenalty = totalOverall;
    });
  }

  /// Calculate penalty points based on sub-status and NC category
  Map<String, int> _calculatePenalties(String subStatus, String? ncCategory) {
    int workman = 0;
    int overall = 0;

    final isQualityOfWorkmanship = ncCategory == 'Quality of Workmanship';

    switch (subStatus) {
      case 'Aobs':
        overall = 1;
        workman = isQualityOfWorkmanship ? 1 : 0;
        break;
      case 'MCF':
        overall = 2;
        workman = isQualityOfWorkmanship ? 2 : 0;
        break;
      case 'CF':
        overall = 3;
        workman = isQualityOfWorkmanship ? 3 : 0;
        break;
      default:
        workman = 0;
        overall = 0;
    }

    return {'workman': workman, 'overall': overall};
  }

  /// Assessment score lookup based on penalty points
  double _getAssessmentScore(int penaltyPoints) {
    // Score starts at 15 for 0 penalty, decreases by 0.5 for each penalty point
    // Max penalty is 66 which gives 0.1
    if (penaltyPoints <= 0) {
      return 15.0;
    }
    if (penaltyPoints >= 66) {
      return 0.1;
    }
    
    // Formula: 15 - (penalty * 0.5)
    // Adjusted to ensure: 1->14.5, 2->14, 3->13.5, etc.
    return 15.0 - (penaltyPoints * 0.5);
  }

  /// Calculate compliance percentage
  double _getCompliancePercentage(int totalPenalty) {
    // Formula: (1 - (Total Penalty / 75)) * 100%
    final compliance = (1 - (totalPenalty / 75)) * 100;
    return compliance.clamp(0.0, 100.0);
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
    _stateController.dispose();
    _siteController.dispose();
    _turbineIdController.dispose();
    _makeController.dispose(); // Added
    _modelController.dispose();
    _ratingController.dispose();
    _customerNameController.dispose();
    _auditorNameController.dispose();
    _auditeeNameController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _saveReport() async {
    // Local-only save: No Firebase write, just refresh UI
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Changes applied for printing'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _generatePdf() async {
    // Show loading indicator
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    ));

    try {
      final timestamp = widget.auditData['timestamp'];
      String auditDateStr = 'N/A';
      if (timestamp is Timestamp) {
        auditDateStr = DateFormat('dd/MM/yyyy').format(timestamp.toDate());
      }
      final turbineName = _turbineIdController.text.isNotEmpty 
          ? _turbineIdController.text 
          : ((widget.auditData['turbine'] as String?) ?? 'Unknown');

      // Calculate scores using current controller values
      final workmanScore = _getAssessmentScore(_totalWorkmanPenalty);
      final overallScore = _getAssessmentScore(_totalOverallPenalty);
      final workmanCompliance = _getCompliancePercentage(_totalWorkmanPenalty);
      final overallCompliance = _getCompliancePercentage(_totalOverallPenalty);

      // Load SVG logo safely (Binary load + decode)
      String? logoSvg;
      try {
        final ByteData data = await rootBundle.load('assets/images/renom_logo.svg');
        logoSvg = utf8.decode(data.buffer.asUint8List());
        // Sanitize SVG: remove width/height percentages which confuse the PDF renderer
        logoSvg = logoSvg.replaceAll('width="100%"', '');
        logoSvg = logoSvg.replaceAll('height="100%"', '');
      } catch (e) {
        debugPrint('Error loading logo: $e');
      }

      // Load Google Fonts for PDF
      final regularFont = await PdfGoogleFonts.robotoRegular();
      final boldFont = await PdfGoogleFonts.robotoBold();
      final italicFont = await PdfGoogleFonts.robotoItalic();

      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(
          base: regularFont,
          bold: boldFont,
          italic: italicFont,
        ),
      );

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          maxPages: 200,
          build: (pw.Context context) => [
            // Header with Logo and Title
            _buildPdfHeaderSection(logoSvg, workmanScore, overallScore, workmanCompliance, overallCompliance),
            pw.SizedBox(height: 6),
            // Metadata Table
            _buildPdfMetadataTable(auditDateStr),
            pw.SizedBox(height: 6),
            // Maintenance Section
            _buildPdfMaintenanceSection(),
            pw.SizedBox(height: 6),
            // Findings Table (compact)
            _buildPdfFindingsTable(),
            pw.SizedBox(height: 6),
            // Footer with Scores
            _buildPdfFooterSection(workmanScore, overallScore, workmanCompliance, overallCompliance),
          ],
        ),
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'SQA_Report_${turbineName}_$auditDateStr.pdf',
      );
    } catch (e) {
      // Close loading dialog if open
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating PDF: $e'), backgroundColor: Colors.red),
        );
      }
      debugPrint('PDF generation error: $e');
    }
  }



  // ==================== PDF HEADER SECTION (NEW DESIGN) ====================
  pw.Widget _buildPdfHeaderSection(String? logoSvg, double workmanScore, double overallScore, double workmanCompliance, double overallCompliance) {
    pw.Widget colorCell(String text, PdfColor color) {
      return pw.Container(
        color: color,
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        alignment: pw.Alignment.center,
        child: pw.Text(text, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black), textAlign: pw.TextAlign.center),
      );
    }
    
    pw.Widget labelCell(String text) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        alignment: pw.Alignment.center,
        child: pw.Text(text, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black), textAlign: pw.TextAlign.center),
      );
    }
    
    // Map score to PdfColor helper (Excel-based logic)
    PdfColor getPdfScoreColor(double score) {
      if (score >= 14.0) {
        return PdfColors.green;
      }
      if (score >= 10.5) {
        return PdfColors.yellow;
      }
      if (score >= 8.0) {
        return PdfColors.cyan; // Improvement
      }
      if (score >= 5.0) {
        return PdfColors.orange;
      }
      return PdfColors.red;
    }

    return pw.Column(
      children: [
        // TOP TABLE
        pw.Table(
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
          border: const pw.TableBorder(
             top: pw.BorderSide(color: PdfColors.black),
             left: pw.BorderSide(color: PdfColors.black),
             right: pw.BorderSide(color: PdfColors.black),
             verticalInside: pw.BorderSide(color: PdfColors.black),
             bottom: pw.BorderSide(color: PdfColors.black),
          ),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.2), 
            1: pw.FlexColumnWidth(5.2),
            2: pw.FlexColumnWidth(0.8),
            3: pw.FlexColumnWidth(0.8),
          },
          children: [
             pw.TableRow(children: [
               // 1. LOGO
               pw.Container(
                 height: 50,
                 padding: const pw.EdgeInsets.all(8),
                 alignment: pw.Alignment.centerLeft,
                 child: logoSvg != null 
                    ? pw.SvgImage(svg: logoSvg, fit: pw.BoxFit.contain)
                    : pw.Text('RENOM', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
               ),
               // 2. TITLE
               pw.Container(
                 height: 50,
                 alignment: pw.Alignment.center,
                 child: pw.Text('SQA Audit Report', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
               ),
               // 3. SCORE 1
               pw.Container(
                 height: 50,
                 width: double.infinity, // Fill width
                 color: getPdfScoreColor(workmanScore),
                 alignment: pw.Alignment.center,
                 child: pw.Text(workmanScore.toStringAsFixed(1), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
               ),
               // 4. SCORE 2
               pw.Container(
                 height: 50,
                 width: double.infinity, // Fill width
                 color: getPdfScoreColor(overallScore),
                 alignment: pw.Alignment.center,
                 child: pw.Text(overallScore.toStringAsFixed(1), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
               ),
             ]),
          ],
        ),
        // BOTTOM TABLE
        pw.Table(
           defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
           border: const pw.TableBorder(
             left: pw.BorderSide(color: PdfColors.black),
             right: pw.BorderSide(color: PdfColors.black),
             bottom: pw.BorderSide(color: PdfColors.black),
             verticalInside: pw.BorderSide(color: PdfColors.black),
             top: pw.BorderSide.none, 
           ),
           columnWidths: const {
              0: pw.FlexColumnWidth(1.2), 
              1: pw.FlexColumnWidth(1),   
              2: pw.FlexColumnWidth(1),   
              3: pw.FlexColumnWidth(1),   
              4: pw.FlexColumnWidth(1),   
              5: pw.FlexColumnWidth(1.2), 
              6: pw.FlexColumnWidth(0.8), 
              7: pw.FlexColumnWidth(0.8), 
           },
           children: [
              pw.TableRow(children: [
                 colorCell('Excellent (14-15)', PdfColors.green),
                 colorCell('Good (11-13)', PdfColors.yellow),
                 colorCell('Improvement (8-10)', PdfColors.cyan),
                 colorCell('Poor (5-7)', PdfColors.orange),
                 colorCell('Worst (<4.5)', PdfColors.red),
                 labelCell('SQA Indicator'),
                 labelCell('Workman'),
                 labelCell('Overall'),
              ]),
           ],
        ),
      ],
    );
  }

  pw.Widget _buildPdfMetadataTable(String auditDateStr) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black),
      children: [
        // Audit ID Row removed
        pw.TableRow(children: [
          _pdfLabelCell('State'),
          _pdfValueCell(_stateController.text),
          _pdfLabelCell('Site'),
          _pdfValueCell(_siteController.text),
        ]),
        pw.TableRow(children: [
          _pdfLabelCell('Turbine ID'),
          _pdfValueCell(_turbineIdController.text),
          _pdfLabelCell('Turbine Make'),
          _pdfValueCell(_makeController.text),
        ]),
        pw.TableRow(children: [
          _pdfLabelCell('Turbine Model'),
          _pdfValueCell(_modelController.text),
          _pdfLabelCell('WTG Rating'),
          _pdfValueCell(_ratingController.text),
        ]),
        pw.TableRow(children: [
          _pdfLabelCell('Date of Commissioning'),
          _pdfValueCell(_commissioningDate != null ? DateFormat('dd/MM/yyyy').format(_commissioningDate!) : '-'),
          _pdfLabelCell('Customer Name'),
          _pdfValueCell(_customerNameController.text),
        ]),
        pw.TableRow(children: [
          _pdfLabelCell('Date of Take Over'),
          _pdfValueCell(_takeOverDate != null ? DateFormat('dd/MM/yyyy').format(_takeOverDate!) : '-'),
          _pdfLabelCell('Auditor Name'),
          _pdfValueCell(_auditorNameController.text),
        ]),
      ],
    );
  }

  pw.Widget _pdfLabelCell(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      color: PdfColors.grey100,
      child: pw.Text(text, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
    );
  }

  pw.Widget _pdfValueCell(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 9)),
    );
  }

  // ==================== PDF MAINTENANCE SECTION (REFACTORED) ====================
  pw.Widget _buildPdfMaintenanceSection() {
    // Extract data
    final String assessmentStage = widget.auditData['assessment_stage']?.toString() ?? '';
    final String maintenanceType = widget.auditData['maintenance_type']?.toString() ?? '';

    final maintPlanStr = _maintPlanDate != null ? DateFormat('dd/MM/yyyy').format(_maintPlanDate!) : '-';
    final maintDoneStr = _maintDoneDate != null ? DateFormat('dd/MM/yyyy').format(_maintDoneDate!) : '-';
    final inspectionStr = _inspectionDate != null ? DateFormat('dd/MM/yyyy').format(_inspectionDate!) : '-';

    // PM Team Info String
    final teamLeader = _pmTeamLeader ?? 'N/A';
    
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black),
      columnWidths: {
        0: const pw.FlexColumnWidth(1), // Left Half
        1: const pw.FlexColumnWidth(1), // Right Half
      },
      children: [
        // HEADER ROW
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            // Left Half Header
            pw.Container(
              decoration: const pw.BoxDecoration(
                border: pw.Border(right: pw.BorderSide(color: PdfColors.black)),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(child: _pdfHeaderCell('Assessment Work Details')),
                  pw.Container(width: 1, height: 16, color: PdfColors.black),
                  pw.Expanded(child: _pdfHeaderCell('Type of Maintenance')),
                ],
              ),
            ),
            // Right Half Header
            _pdfHeaderCell('PM Team Details'),
          ],
        ),
        // CONTENT ROW: Checkboxes (Left) & PM Team (Right)
        pw.TableRow(children: [
          // LEFT CELL: Checkboxes
          pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black)), // Separator for dates below
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Assessment
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildPdfDynamicOption('Before Maintenance', assessmentStage),
                        _buildPdfDynamicOption('During Maintenance', assessmentStage),
                        _buildPdfDynamicOption('After Maintenance', assessmentStage),

                      ],
                    ),
                  ),
                ),
                pw.Container(width: 1, height: 60, color: PdfColors.black),
                // Maintenance Type
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildPdfDynamicOption('Electrical Maintenance Yearly', maintenanceType),
                        _buildPdfDynamicOption('Mechanical Maintenance Yearly', maintenanceType),
                        _buildPdfDynamicOption('Half Yearly Maintenance', maintenanceType),
                        _buildPdfDynamicOption('Visual And Grease Maintenance', maintenanceType),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // RIGHT CELL: PM Team Details
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(left: pw.BorderSide(color: PdfColors.black)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Team Leader: $teamLeader', style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 2),
                pw.Text('Members:', style: const pw.TextStyle(fontSize: 9)),
                pw.Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    if (_pmTeamMembers.isEmpty) pw.Text('N/A', style: const pw.TextStyle(fontSize: 8)),
                    ..._pmTeamMembers.asMap().entries.map((e) => pw.Text('${e.key + 1}. ${e.value}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700))),
                  ],
                ),
              ],
            ),
          ),
        ]),
        // DATE ROW 1: Plan Date & Delay
        pw.TableRow(children: [
          // Left: Plan
          pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
            child: pw.Row(children: [
               pw.Expanded(child: _pdfLabelCell('Maint. Plan Date')),
               pw.Expanded(child: _pdfValueCell(maintPlanStr)),
            ]),
          ),
          // Right: Delay
          pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
            child: pw.Row(children: [
               pw.Expanded(child: _pdfLabelCell('Maint. Delay')),
               pw.Expanded(child: _pdfValueCell(_calculateDelay())),
            ]),
          ),
        ]),
        // DATE ROW 2: Done Date & Inspection
        pw.TableRow(children: [
          // Left: Done
          pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
            child: pw.Row(children: [
               pw.Expanded(child: _pdfLabelCell('Maint. Done Date')),
               pw.Expanded(child: _pdfValueCell(maintDoneStr)),
            ]),
          ),
          // Right: Inspection
          pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
            child: pw.Row(children: [
               pw.Expanded(child: _pdfLabelCell('Date of Inspection')),
               pw.Expanded(child: _pdfValueCell(inspectionStr)),
            ]),
          ),
        ]),
      ],
    );
  }

  pw.Widget _buildPdfDynamicOption(String label, String? databaseValue) {
    // Normalize strings
    final bool isSelected = (databaseValue ?? '').trim().toLowerCase() == label.trim().toLowerCase();
    
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.0),
      child: pw.Row(
        children: [
          pw.Container(
            width: 8,
            height: 8,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: isSelected ? PdfColors.blue800 : PdfColors.black),
              color: isSelected ? PdfColors.blue800 : null,
            ),
          ),
          pw.SizedBox(width: 4),
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: isSelected ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: isSelected ? PdfColors.blue800 : PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfFindingsTable() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(4),
          color: PdfColors.grey300,
          child: pw.Text(
            'FINDINGS / OBSERVATIONS',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center,
          ),
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black),
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          columnWidths: {
            0: const pw.FixedColumnWidth(100),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FixedColumnWidth(60),
            3: const pw.FixedColumnWidth(60),
            4: const pw.FixedColumnWidth(60),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _pdfHeaderCell('Sr No'),
                _pdfHeaderCell('Observations'),
                _pdfHeaderCell('Type'),
                _pdfHeaderCell('Workman'),
                _pdfHeaderCell('Overall'),
              ],
            ),
            ..._referenceGroups.asMap().entries.map((entry) {
              final index = entry.key;
              final group = entry.value;
              // Build observations as vertical list with individual colors
              final observationsToShow = group.observations.take(3).toList();
              return pw.TableRow(
              children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.all(4),
                    alignment: pw.Alignment.center,
                    child: pw.Text('${index + 1}', style: const pw.TextStyle(fontSize: 9)),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: observationsToShow.map((obs) {
                        // Determine color based on individual sub_status
                        PdfColor textColor = PdfColors.black;
                        if (obs.subStatus == 'CF') {
                          textColor = PdfColors.red;
                        } else if (obs.subStatus == 'MCF') {
                          textColor = PdfColors.blue;
                        }
                        // Truncate long text
                        final truncatedText = obs.text.length > 100 
                            ? '${obs.text.substring(0, 100)}...' 
                            : obs.text;
                        return pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 2),
                          child: pw.Text(
                            truncatedText,
                            style: pw.TextStyle(fontSize: 8, color: textColor),
                            maxLines: 2,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(4),
                    alignment: pw.Alignment.center,
                    child: pw.Text(group.highestSubStatus, style: const pw.TextStyle(fontSize: 9)),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(4),
                    alignment: pw.Alignment.center,
                    color: group.workmanRating > 0 ? PdfColors.red50 : null,
                    child: pw.Text(
                      group.workmanRating.toString(),
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: group.workmanRating > 0 ? pw.FontWeight.bold : pw.FontWeight.normal,
                      ),
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(4),
                    alignment: pw.Alignment.center,
                    color: group.overallRating > 0 ? PdfColors.orange50 : null,
                    child: pw.Text(
                      group.overallRating.toString(),
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: group.overallRating > 0 ? pw.FontWeight.bold : pw.FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              );
            }),
            if (_referenceGroups.isEmpty)
              pw.TableRow(children: [
                _pdfValueCell('-'),
                _pdfValueCell('No Issues Found - All Tasks OK'),
                pw.Container(padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('-', style: const pw.TextStyle(fontSize: 9))),
                pw.Container(padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('0', style: const pw.TextStyle(fontSize: 9))),
                pw.Container(padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('0', style: const pw.TextStyle(fontSize: 9))),
              ]),
            // Totals row
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                _pdfValueCell(''),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text('TOTAL PENALTY:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ),
                _pdfValueCell(''),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  alignment: pw.Alignment.center,
                  color: PdfColors.red100,
                  child: pw.Text(_totalWorkmanPenalty.toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  alignment: pw.Alignment.center,
                  color: PdfColors.orange100,
                  child: pw.Text(_totalOverallPenalty.toString(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _pdfHeaderCell(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      alignment: pw.Alignment.center,
      child: pw.Text(text, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
    );
  }

  pw.Widget _buildPdfFooterSection(double workmanScore, double overallScore, double workmanCompliance, double overallCompliance) {
    // Map score to PdfColor helper (Excel-based logic)
    PdfColor getPdfScoreColor(double score) {
      if (score >= 14.0) {
        return PdfColors.green;
      }
      if (score >= 10.5) {
        return PdfColors.yellow;
      }
      if (score >= 8.0) {
        return PdfColors.cyan; // Improvement
      }
      if (score >= 5.0) {
        return PdfColors.orange;
      }
      return PdfColors.red;
    }

    // Map compliance percentage to PdfColor helper
    PdfColor getPdfComplianceColor(double compliance) {
      if (compliance >= 90) {
        return PdfColors.green;
      }
      if (compliance >= 80) {
        return PdfColors.yellow;
      }
      if (compliance >= 60) {
        return PdfColors.cyan;
      }
      if (compliance >= 40) {
        return PdfColors.orange;
      }
      return PdfColors.red;
    }

    return pw.Column(
      children: [
        pw.Table(
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
          children: [
            pw.TableRow(children: [
              _pdfLabelCell('Workman Score'),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(6),
                color: getPdfScoreColor(workmanScore),
                alignment: pw.Alignment.center,
                child: pw.Text(workmanScore.toStringAsFixed(1), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ),
              _pdfLabelCell('Overall Score'),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(6),
                color: getPdfScoreColor(overallScore),
                alignment: pw.Alignment.center,
                child: pw.Text(overallScore.toStringAsFixed(1), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ),
            ]),
            pw.TableRow(children: [
              _pdfLabelCell('Workman Compliance'),
              pw.Container(
                width: double.infinity, 
                padding: const pw.EdgeInsets.all(6),
                color: getPdfComplianceColor(workmanCompliance),
                alignment: pw.Alignment.center,
                child: pw.Text('${workmanCompliance.toStringAsFixed(2)}%', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ),
              _pdfLabelCell('Overall Compliance'),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(6),
                color: getPdfComplianceColor(overallCompliance),
                alignment: pw.Alignment.center,
                child: pw.Text('${overallCompliance.toStringAsFixed(2)}%', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ),
            ]),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.5),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(1.5),
            3: pw.FlexColumnWidth(1),
          },
          children: [
             pw.TableRow(children: [
              _pdfLabelCell('Remarks (Workman)'),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(6),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  _getRemark(workmanScore, isOverall: false),
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: _getRemark(workmanScore, isOverall: false) == 'Worst' ? PdfColors.red : PdfColors.black,
                  ),
                ),
              ),
              _pdfLabelCell('Remarks (Overall)'),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(6),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  _getRemark(overallScore, isOverall: true),
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: _getRemark(overallScore, isOverall: true) == 'Need to do re-PM' ? PdfColors.red : PdfColors.black,
                  ),
                ),
              ),
            ]),
          ],
        ),
        pw.SizedBox(height: 4),

      ],
    );
  }

  @override
  Widget build(BuildContext context) {



    // Calculate scores for header display
    final workmanScore = _getAssessmentScore(_totalWorkmanPenalty);
    final overallScore = _getAssessmentScore(_totalOverallPenalty);
    final workmanCompliance = _getCompliancePercentage(_totalWorkmanPenalty);
    final overallCompliance = _getCompliancePercentage(_totalOverallPenalty);

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: Text('Digital SQA Report', style: GoogleFonts.outfit(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: _saveReport,
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Apply Changes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: _generatePdf,
              icon: const Icon(Icons.print, size: 16),
              label: const Text('Print PDF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[800],
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderSection(workmanScore, overallScore, workmanCompliance, overallCompliance),
                  _buildMetadataGrid(),
                  _buildMaintenanceSection(),
                  _buildFindingsTable(),
                  _buildFooterSection(workmanScore, overallScore, workmanCompliance, overallCompliance),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== HEADER SECTION (NEW DESIGN) ====================
  Widget _buildHeaderSection(double workmanScore, double overallScore, double workmanCompliance, double overallCompliance) {
    // Top Row Column Flexes (Calculated to align with Bottom Row 8 cols)
    // Bot: 1.2, 1, 1, 1, 1, 1.2, 0.8, 0.8
    // Top Col 0 (Logo) = Bot Col 0 = 1.2
    // Top Col 1 (Title) = Bot Col 1+2+3+4+5 = 5.2 (1+1+1+1+1.2)
    // Top Col 2 (Score1) = Bot Col 6 = 0.8
    // Top Col 3 (Score2) = Bot Col 7 = 0.8
    
    Widget colorCell(String text, Color color) {
      return Container(
        color: color,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        alignment: Alignment.center,
        child: Text(text, style: GoogleFonts.robotoCondensed(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black), textAlign: TextAlign.center),
      );
    }
    
    Widget labelCell(String text) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        alignment: Alignment.center,
        child: Text(text, style: GoogleFonts.robotoCondensed(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black), textAlign: TextAlign.center),
      );
    }

    return Column(
      children: [
        // TOP TABLE (Logo, Title, Scores)
        Table(
          border: const TableBorder(
             top: BorderSide(color: Colors.black),
             left: BorderSide(color: Colors.black),
             right: BorderSide(color: Colors.black),
             verticalInside: BorderSide(color: Colors.black),
             bottom: BorderSide(color: Colors.black),
          ),
          columnWidths: const {
            0: FlexColumnWidth(1.2), 
            1: FlexColumnWidth(5.2),
            2: FlexColumnWidth(0.8),
            3: FlexColumnWidth(0.8),
          },
          children: [
             TableRow(children: [
               // 1. LOGO
               Container(
                 height: 50,
                 padding: const EdgeInsets.all(8),
                 alignment: Alignment.centerLeft,
                 child: SvgPicture.asset('assets/images/renom_logo.svg', fit: BoxFit.contain),
               ),
               // 2. TITLE
               Container(
                 height: 50,
                 alignment: Alignment.center,
                 child: Text('SQA Audit Report', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
               ),
               // 3. SCORE 1 (Workman) - Color based on score
               Container(
                 height: 50,
                 color: _getScoreColor(workmanScore),
                 alignment: Alignment.center,
                 child: Text(workmanScore.toStringAsFixed(1), style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
               ),
               // 4. SCORE 2 (Overall)
               Container(
                 height: 50,
                  color: _getScoreColor(overallScore),
                 alignment: Alignment.center,
                 child: Text(overallScore.toStringAsFixed(1), style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
               ),
             ]),
          ],
        ),
        // BOTTOM TABLE (Legend)
        Table(
           border: const TableBorder(
             left: BorderSide(color: Colors.black),
             right: BorderSide(color: Colors.black),
             bottom: BorderSide(color: Colors.black),
             verticalInside: BorderSide(color: Colors.black),
             top: BorderSide.none, // Avoid double border
           ),
           columnWidths: const {
              0: FlexColumnWidth(1.2), // Exc
              1: FlexColumnWidth(1),   // Good
              2: FlexColumnWidth(1),   // Imp
              3: FlexColumnWidth(1),   // Poor
              4: FlexColumnWidth(1),   // Worst
              5: FlexColumnWidth(1.2), // SQA Ind
              6: FlexColumnWidth(0.8), // Workman
              7: FlexColumnWidth(0.8), // Overall
           },
           children: [
              TableRow(children: [
                 colorCell('Excellent (14-15)', Colors.green),
                 colorCell('Good (11-13)', Colors.yellow),
                 colorCell('Improvement (8-10)', Colors.cyan),
                 colorCell('Poor (5-7)', Colors.orange),
                 colorCell('Worst (<4.5)', Colors.red),
                 labelCell('SQA Indicator'),
                 labelCell('Workman'),
                 labelCell('Overall'),
              ]),
           ],
        ),
      ],
    );
  }



  // ==================== METADATA GRID ====================
  Widget _buildMetadataGrid() {
    return Table(
      border: TableBorder.all(color: Colors.black, width: 0.5),
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1.5),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(1.5),
      },
      children: [
        // Audit Reference ID Removed
        TableRow(children: [
          _buildLabelCell('State'),
          _buildInputCell(_stateController),
          _buildLabelCell('Site'),
          _buildInputCell(_siteController),
        ]),
        TableRow(children: [
        _buildLabelCell('Turbine ID'),
        _buildInputCell(_turbineIdController),
        _buildLabelCell('Turbine Make'),
        _buildInputCell(_makeController),
      ]),
      TableRow(children: [
        _buildLabelCell('Turbine Model'),
        _buildInputCell(_modelController),
        _buildLabelCell('WTG Rating'),
        _buildInputCell(_ratingController),
      ]),
      TableRow(children: [
        _buildLabelCell('Date of Commissioning'),
        _buildDateCell(_commissioningDate, (d) => setState(() => _commissioningDate = d)),
        _buildLabelCell('Customer Name'),
        _buildInputCell(_customerNameController),
      ]),
      TableRow(children: [
         _buildLabelCell('Date of Take Over'),
        _buildDateCell(_takeOverDate, (d) => setState(() => _takeOverDate = d)),
         _buildLabelCell('Auditor Name'),
         _buildInputCell(_auditorNameController),
      ]),
      ],
    );
  }

  Widget _buildDynamicOption(String label, String? databaseValue) {
    // Normalize strings to ensure robust matching (ignore case and spaces)
    final bool isSelected = (databaseValue ?? '').trim().toLowerCase() == label.trim().toLowerCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dynamic Icon: Checked & Blue if matched, Empty & Black if not
          Icon(
            isSelected ? Icons.check_box : Icons.check_box_outline_blank,
            color: isSelected ? Colors.blue[800] : Colors.black,
            size: 16,
          ),
          const SizedBox(width: 4),
          // Dynamic Text: Wrapped in Flexible to handle overflow
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.blue[800] : Colors.black,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== MAINTENANCE SECTION (REFACTORED) ====================
  Widget _buildMaintenanceSection() {
    final String assessmentStage = widget.auditData['assessment_stage']?.toString() ?? '';
    final String maintenanceType = widget.auditData['maintenance_type']?.toString() ?? '';

    return Table(
      border: TableBorder.all(color: Colors.black, width: 0.5),
      columnWidths: const {
        0: FlexColumnWidth(1), // Left Half (50%)
        1: FlexColumnWidth(1), // Right Half (50%)
      },
      children: [
        // HEADER ROW
        TableRow(
          decoration: BoxDecoration(color: Colors.grey[200]),
          children: [
            // Left Half Header
            Container(
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: Colors.black)),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(child: _buildHeaderCell('Assessment Work Details')),
                    Container(width: 1, color: Colors.black),
                    Expanded(child: _buildHeaderCell('Type of Maintenance')),
                  ],
                ),
              ),
            ),
            // Right Half Header
            _buildHeaderCell('PM Team Details'),
          ],
        ),
        // CONTENT ROW: Checkboxes (Left) & PM Team (Right)
        TableRow(children: [
          // LEFT CELL: Checkboxes
          IntrinsicHeight(
             child: Row(
               crossAxisAlignment: CrossAxisAlignment.stretch,
               children: [
                 // Sub-column 1: Assessment
                 Expanded(
                   child: Padding(
                     padding: const EdgeInsets.all(8),
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         _buildDynamicOption('Before Maintenance', assessmentStage),
                         _buildDynamicOption('During Maintenance', assessmentStage),
                         _buildDynamicOption('After Maintenance', assessmentStage),
                       ],
                     ),
                   ),
                 ),
                 Container(width: 1, color: Colors.black), // Vertical Divider
                 // Sub-column 2: Maintenance Type
                 Expanded(
                   child: Padding(
                     padding: const EdgeInsets.all(8),
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         _buildDynamicOption('Electrical Maintenance Yearly', maintenanceType),
                         _buildDynamicOption('Mechanical Maintenance Yearly', maintenanceType),
                         _buildDynamicOption('Half Yearly Maintenance', maintenanceType),
                         _buildDynamicOption('Visual And Grease Maintenance', maintenanceType),
                       ],
                     ),
                   ),
                 ),
               ],
             ),
          ),
          
          // RIGHT CELL: PM Team
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.robotoCondensed(fontSize: 12, color: Colors.black),
                    children: [
                      const TextSpan(text: 'Team Leader: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(text: _pmTeamLeader ?? 'N/A'),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text('Team Members:', style: GoogleFonts.robotoCondensed(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                // WRAP for members
                Wrap(
                  spacing: 8.0,
                  runSpacing: 4.0,
                  children: [
                     if (_pmTeamMembers.isEmpty)
                       Text('N/A', style: GoogleFonts.robotoCondensed(fontSize: 12, color: Colors.grey)),
                     ..._pmTeamMembers.asMap().entries.map((e) => Text('${e.key + 1}. ${e.value}', style: GoogleFonts.robotoCondensed(fontSize: 12))),
                  ],
                ),
              ],
            ),
          ),
        ]),
        // DATE ROW 1: Plan Date & Delay
        TableRow(
          decoration: BoxDecoration(border: Border.all(color: Colors.black)),
          children: [
            // Left: Plan
            Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.black)),
              child: Row(children: [
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black))),
                    child: _buildLabelCell('Maint. Plan Date'),
                  ),
                ),
                Expanded(child: _buildDateCell(_maintPlanDate, (d) => setState(() => _maintPlanDate = d))),
              ]),
            ),
            // Right: Delay
            Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.black)),
              child: Row(children: [
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black))),
                    child: _buildLabelCell('Maint. Delay'),
                  ),
                ),
                Expanded(child: _buildCell(_calculateDelay())),
              ]),
            ),
          ]
        ),
         // DATE ROW 2: Done Date & Inspection
        TableRow(
          decoration: BoxDecoration(border: Border.all(color: Colors.black)),
          children: [
            // Left: Done
            Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.black)),
              child: Row(children: [
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black))),
                    child: _buildLabelCell('Maint. Done Date'),
                  ),
                ),
                Expanded(child: _buildDateCell(_maintDoneDate, (d) => setState(() => _maintDoneDate = d))),
              ]),
            ),
            // Right: Inspection
            Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.black)),
              child: Row(children: [
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black))),
                    child: _buildLabelCell('Date of Inspection'),
                  ),
                ),
                Expanded(child: _buildDateCell(_inspectionDate, (d) => setState(() => _inspectionDate = d))),
              ]),
            ),
          ]
        ),
      ],
    );
  }

  String _calculateDelay() {
    if (_maintPlanDate != null && _maintDoneDate != null) {
      final diff = _maintDoneDate!.difference(_maintPlanDate!).inDays;
      if (diff > 0) {
        return '$diff days';
      }
      if (diff < 0) {
        return '${-diff} days early';
      }
      return 'On time';
    }
    return '-';
  }



  // ==================== FINDINGS TABLE (GROUPED BY REFERENCE) ====================
  Widget _buildFindingsTable() {
    return Column(
      children: [
        // Findings Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.grey[300],
            border: const Border(
              left: BorderSide(color: Colors.black),
              right: BorderSide(color: Colors.black),
              top: BorderSide(color: Colors.black),
            ),
          ),
          child: Text(
            'FINDINGS / OBSERVATIONS (Grouped by Reference)',
            style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
        // Table Header
        Table(
          border: TableBorder.all(color: Colors.black),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: const {
            0: FixedColumnWidth(100),  // Reference
            1: FlexColumnWidth(3),     // Description (Observations)
            2: FixedColumnWidth(60),   // Type NC
            3: FixedColumnWidth(60),   // Workman
            4: FixedColumnWidth(60),   // Overall
          },
          children: [
            TableRow(
              decoration: BoxDecoration(color: Colors.grey[200]),
              children: [
                _buildHeaderCell('Sr No'),
                _buildHeaderCell('Observations'),
                _buildHeaderCell('Type NC'),
                _buildHeaderCell('Workman'),
                _buildHeaderCell('Overall'),
              ],
            ),
            // Data Rows - One per Reference Group
            ..._referenceGroups.asMap().entries.map((entry) {
              final index = entry.key;
              final group = entry.value;

              return TableRow(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    alignment: Alignment.center,
                    child: Text(
                      '${index + 1}',
                      style: GoogleFonts.robotoCondensed(fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  // Observations column with individual colors per item
                  Container(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: group.observations.map((obs) {
                        // Determine color based on individual sub_status
                        Color textColor = Colors.black;
                        if (obs.subStatus == 'CF') {
                          textColor = Colors.red;
                        } else if (obs.subStatus == 'MCF') {
                          textColor = Colors.blue;
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            obs.text,
                            style: GoogleFonts.robotoCondensed(
                              fontSize: 11,
                              color: textColor,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  _buildCell(group.highestSubStatus, align: TextAlign.center),
                  Container(
                    padding: const EdgeInsets.all(6),
                    alignment: Alignment.center,
                    color: group.workmanRating > 0 ? Colors.red[50] : null,
                    child: Text(
                      group.workmanRating.toString(),
                      style: GoogleFonts.robotoCondensed(
                        fontSize: 11,
                        fontWeight: group.workmanRating > 0 ? FontWeight.bold : FontWeight.normal,
                        color: group.workmanRating > 0 ? Colors.red[800] : Colors.black,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    alignment: Alignment.center,
                    color: group.overallRating > 0 ? Colors.orange[50] : null,
                    child: Text(
                      group.overallRating.toString(),
                      style: GoogleFonts.robotoCondensed(
                        fontSize: 11,
                        fontWeight: group.overallRating > 0 ? FontWeight.bold : FontWeight.normal,
                        color: group.overallRating > 0 ? Colors.orange[800] : Colors.black,
                      ),
                    ),
                  ),
                ],
              );
            }),
            // Empty state
            if (_referenceGroups.isEmpty)
              TableRow(children: [
                _buildCell('-'),
                _buildCell('No Issues Found - All Tasks OK'),
                _buildCell('-', align: TextAlign.center),
                _buildCell('0', align: TextAlign.center),
                _buildCell('0', align: TextAlign.center),
              ]),
            // Totals Row
            TableRow(
              decoration: BoxDecoration(color: Colors.grey[100]),
              children: [
                _buildCell(''),
                Container(
                  padding: const EdgeInsets.all(6),
                  alignment: Alignment.centerRight,
                  child: Text('TOTAL PENALTY POINTS:', style: GoogleFonts.robotoCondensed(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                _buildCell(''),
                Container(
                  padding: const EdgeInsets.all(6),
                  alignment: Alignment.center,
                  color: Colors.red[100],
                  child: Text(
                    _totalWorkmanPenalty.toString(),
                    style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red[900]),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  alignment: Alignment.center,
                  color: Colors.orange[100],
                  child: Text(
                    _totalOverallPenalty.toString(),
                    style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange[900]),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ==================== FOOTER SECTION ====================
  Widget _buildFooterSection(double workmanScore, double overallScore, double workmanCompliance, double overallCompliance) {
    return Column(
      children: [
        // Assessment Scores Row
        Table(
          border: TableBorder.all(color: Colors.black, width: 0.5),
          columnWidths: const {
            0: FlexColumnWidth(1.5),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1.5),
            3: FlexColumnWidth(1),
          },
          children: [
            TableRow(children: [
              _buildLabelCell('Workman Assessment Score'),
              Container(
                padding: const EdgeInsets.all(6),
                color: _getScoreColor(workmanScore),
                alignment: Alignment.center,
                child: Text(
                  workmanScore.toStringAsFixed(1),
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
              _buildLabelCell('Overall Assessment Score'),
              Container(
                padding: const EdgeInsets.all(6),
                color: _getScoreColor(overallScore),
                alignment: Alignment.center,
                child: Text(
                  overallScore.toStringAsFixed(1),
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ]),
            TableRow(children: [
              _buildLabelCell('Workman PM Compliance'),
              Container(
                padding: const EdgeInsets.all(6),
                color: _getComplianceColor(workmanCompliance),
                alignment: Alignment.center,
                child: Text(
                  '${workmanCompliance.toStringAsFixed(2)}%',
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
              _buildLabelCell('Overall Compliance'),
              Container(
                padding: const EdgeInsets.all(6),
                color: _getComplianceColor(overallCompliance),
                alignment: Alignment.center,
                child: Text(
                  '${overallCompliance.toStringAsFixed(2)}%',
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ]),
          ],
        ),

        // Remarks of Assessment Row
        Table(
          border: TableBorder.all(color: Colors.black, width: 0.5),
          columnWidths: const {
            0: FlexColumnWidth(1.5),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1.5),
            3: FlexColumnWidth(1),
          },
          children: [
            TableRow(children: [
              _buildLabelCell('Remarks (Workman)'),
              Container(
                padding: const EdgeInsets.all(6),
                alignment: Alignment.center,
                child: Text(
                  _getRemark(workmanScore, isOverall: false),
                  style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _getRemark(workmanScore, isOverall: false) == 'Worst' ? Colors.red : Colors.black
                  ),
                ),
              ),
              _buildLabelCell('Remarks (Overall)'),
              Container(
                padding: const EdgeInsets.all(6),
                alignment: Alignment.center,
                child: Text(
                  _getRemark(overallScore, isOverall: true),
                  style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _getRemark(overallScore, isOverall: true) == 'Need to do re-PM' ? Colors.red : Colors.black
                  ),
                ),
              ),
            ]),
          ],
        ),

      ],
    );
  }

  Color _getComplianceColor(double value) {
    if (value >= 90) {
      return Colors.green[100]!;
    }
    if (value >= 80) {
      return Colors.yellow[100]!;
    }
    if (value >= 60) {
      return Colors.cyan[100]!;
    }
    if (value >= 40) {
      return Colors.orange[100]!;
    }
    return Colors.red[100]!;
  }

  /// Score-based color helper (Excel-based logic) - matches indicator colors
  Color _getScoreColor(double score) {
    if (score >= 14.0) {
      return Colors.green;
    }
    if (score >= 10.5) {
      return Colors.yellow;
    }
    if (score >= 8.0) {
      return Colors.cyan; // Improvement
    }
    if (score >= 5.0) {
      return Colors.orange;
    }
    return Colors.red;
  }

  String _getRemark(double score, {required bool isOverall}) {
    if (score >= 14.0) {
      return 'Excellent';
    }
    if (score >= 10.5) {
      return 'Good';
    }
    if (score >= 7.5) {
      return 'Improvements Required';
    }
    if (score >= 4.5) {
      return 'Poor';
    }
    
    // Score < 4.5
    return isOverall ? 'Need to do re-PM' : 'Worst';
  }

  // ==================== HELPER WIDGETS ====================
  Widget _buildLabelCell(String text) {
    return Container(
      padding: const EdgeInsets.all(6),
      color: Colors.grey[100],
      alignment: Alignment.centerLeft,
      child: Text(text, style: GoogleFonts.robotoCondensed(fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildHeaderCell(String text) {
    return Container(
      padding: const EdgeInsets.all(6),
      alignment: Alignment.center,
      child: Text(text, style: GoogleFonts.robotoCondensed(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
    );
  }

  Widget _buildCell(String text, {TextAlign align = TextAlign.left, Color? textColor}) {
    return Container(
      padding: const EdgeInsets.all(6),
      alignment: align == TextAlign.center ? Alignment.center : Alignment.centerLeft,
      child: Text(
        text,
        style: GoogleFonts.robotoCondensed(
          fontSize: 11,
          color: textColor ?? Colors.black,
        ),
        textAlign: align,
      ),
    );
  }

  Widget _buildInputCell(TextEditingController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: controller,
        style: GoogleFonts.robotoCondensed(fontSize: 11),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }

  Widget _buildDateCell(DateTime? date, void Function(DateTime) onSelect) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null) {
          onSelect(picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        alignment: Alignment.centerLeft,
        child: Text(
          date != null ? DateFormat('dd/MM/yyyy').format(date) : 'Select',
          style: GoogleFonts.robotoCondensed(fontSize: 11, color: date != null ? Colors.black : Colors.grey),
        ),
      ),
    );
  }
}
