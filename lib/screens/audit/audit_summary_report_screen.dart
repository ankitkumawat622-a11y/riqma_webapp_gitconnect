import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class AuditSummaryReportScreen extends StatelessWidget {
  final String auditId;
  final Map<String, dynamic> auditData;
  final Map<String, String> masterData; // turbine info, site info, etc.

  const AuditSummaryReportScreen({
    super.key,
    required this.auditId,
    required this.auditData,
    required this.masterData,
  });

  @override
  Widget build(BuildContext context) {
    final DateTime auditDate = _parseDate(auditData['timestamp']) ?? DateTime.now();
    final String fy = _getFinancialYear(auditDate);
    final tasks = _getNotOkTasks();
    final metrics = _calculateMetrics(tasks);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: Text(
          'Audit Summary Report',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: const Color(0xFF1A1F36),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // 1. TOP 30% - PRIMARY DATA GRID
          _buildPrimaryDataHeader(context, auditDate, fy),

          // 2. MIDDLE STRIP - METRICS
          _buildMetricsStrip(metrics),

          // 3. BOTTOM 70% - NC DATA TABLE
          Expanded(
            child: _buildNCTable(tasks),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryDataHeader(BuildContext context, DateTime auditDate, String fy) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1F36),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        children: [
          _buildSectionHeader('Primary Metadata'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildMetaCard('Audit Date', DateFormat('dd.MM.yyyy').format(auditDate), Icons.calendar_month_rounded, Colors.blue),
              _buildMetaCard('Financial Year', fy, Icons.history_edu_rounded, Colors.orange),
              _buildMetaCard('Turbine Name', (auditData['turbine'] ?? '').toString(), Icons.precision_manufacturing_rounded, Colors.teal),
              _buildMetaCard('Turbine Make', masterData['turbine_make'] ?? '', Icons.factory_rounded, Colors.cyan),
              _buildMetaCard('Rating (MW)', masterData['turbine_rating'] ?? '', Icons.bolt_rounded, Colors.amber),
              _buildMetaCard('Model', masterData['turbine_model'] ?? '', Icons.model_training_rounded, Colors.indigo),
              _buildMetaCard('Site Name', (auditData['site'] ?? '').toString(), Icons.location_on_rounded, Colors.redAccent),
              _buildMetaCard('State', (auditData['state'] ?? '').toString(), Icons.map_rounded, Colors.purple),
              _buildMetaCard('District', masterData['district'] ?? '', Icons.location_city_rounded, Colors.blueGrey),
              _buildMetaCard('Warehouse', masterData['warehouse_code'] ?? '', Icons.warehouse_rounded, Colors.brown),
              _buildMetaCard('Zone', masterData['zone'] ?? '', Icons.explore_rounded, Colors.green),
              _buildMetaCard('Customer', (auditData['customer_name'] ?? '').toString(), Icons.business_rounded, Colors.blueAccent),
              _buildMetaCard('Auditor', (auditData['auditor_name'] ?? '').toString(), Icons.person_rounded, Colors.deepPurple),
              _buildMetaCard('DOC', _formatDate(auditData['commissioning_date']), Icons.event_available_rounded, Colors.lightGreen),
              _buildMetaCard('DOT', _formatDate(auditData['date_of_take_over']), Icons.handshake_rounded, Colors.deepOrange),
              _buildMetaCard('PM Plan', _formatDate(auditData['plan_date_of_maintenance']), Icons.edit_calendar_rounded, Colors.blueGrey),
              _buildMetaCard('PM Done', _formatDate(auditData['actual_date_of_maintenance']), Icons.task_alt_rounded, Colors.green),
              _buildMetaCard('PM Adherence', _calculateAdherence(), Icons.timer_rounded, Colors.red),
              _buildMetaCard('QA vs PM Aging', _calculateAging(auditDate), Icons.hourglass_bottom_rounded, Colors.orangeAccent),
              _buildMetaCard('PM Type', (auditData['maintenance_type'] ?? '').toString(), Icons.settings_suggest_rounded, Colors.indigoAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: 175,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: GoogleFonts.outfit(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500)),
                Text(
                  value.isEmpty ? '-' : value,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsStrip(Map<String, dynamic> metrics) {
    return Container(
      height: 70,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildMetricBadge('NCs', metrics['total_nc'], Colors.red),
          _buildMetricBadge('OSC', metrics['total_osc'], Colors.green),
          _buildMetricBadge('Material', metrics['total_material'], Colors.orange),
          _buildMetricBadge('Workman', metrics['total_workman'], Colors.purple),
          _buildMetricBadge('CF', metrics['count_cf'], Colors.red.shade900),
          _buildMetricBadge('MCF', metrics['count_mcf'], Colors.blue.shade900),
          _buildMetricBadge('Aobs', metrics['count_aobs'], Colors.blueGrey),
          _buildScoreBadge('SQA Score', metrics['overall_score'] as double, metrics['overall_compliance'] as double, Colors.teal),
          _buildScoreBadge('Workman', metrics['workman_score'] as double, metrics['workman_compliance'] as double, Colors.indigo),
        ],
      ),
    );
  }

  Widget _buildMetricBadge(String label, dynamic value, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey[600])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(value.toString(), style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreBadge(String label, double score, double compliance, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey[600])),
          Row(
            children: [
              Text(score.toStringAsFixed(1), style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
              const SizedBox(width: 4),
              Text('($compliance%)', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w500, color: color.withValues(alpha: 0.7))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNCTable(List<Map<String, dynamic>> tasks) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade200),
            const SizedBox(height: 16),
            Text('No Issues Found', style: GoogleFonts.outfit(fontSize: 18, color: Colors.grey[600])),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
            columnSpacing: 24,
            horizontalMargin: 20,
            columns: [
              _buildTableColumn('Task Name'),
              _buildTableColumn('Finding'),
              _buildTableColumn('Criticality'),
              _buildTableColumn('Reference'),
              _buildTableColumn('NC Category'),
              _buildTableColumn('Material Details'),
              _buildTableColumn('Root Cause'),
              _buildTableColumn('Action Plan'),
              _buildTableColumn('Target Date'),
              _buildTableColumn('Action Taken'),
              _buildTableColumn('Closing Date'),
              _buildTableColumn('Status'),
            ],
            rows: tasks.map((task) => _buildTableRow(task)).toList(),
          ),
        ),
      ),
    );
  }

  DataColumn _buildTableColumn(String label) {
    return DataColumn(
      label: Text(label, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF475569))),
    );
  }

  DataRow _buildTableRow(Map<String, dynamic> task) {
    final bool isMaterial = task['root_cause'] == 'Material Not Available';
    final criticality = (task['nc_criticality'] ?? task['sub_status'] ?? 'Aobs').toString();
    
    return DataRow(
      cells: [
        DataCell(Text((task['task_name'] ?? task['question'] ?? '-').toString(), style: GoogleFonts.outfit(fontSize: 12))),
        DataCell(SizedBox(width: 250, child: Text((task['finding'] ?? task['observation'] ?? '-').toString(), style: GoogleFonts.outfit(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis))),
        DataCell(_buildCriticalityBadge(criticality)),
        DataCell(Text((task['reference_name'] ?? '-').toString(), style: GoogleFonts.outfit(fontSize: 12, color: Colors.blue.shade700))),
        DataCell(Text((task['nc_category'] ?? '-').toString(), style: GoogleFonts.outfit(fontSize: 12, color: Colors.purple.shade700))),
        DataCell(_buildMaterialCell(isMaterial, task)),
        DataCell(Text((task['root_cause'] ?? '-').toString(), style: GoogleFonts.outfit(fontSize: 12))),
        DataCell(SizedBox(width: 200, child: Text((task['action_plan'] ?? '-').toString(), style: GoogleFonts.outfit(fontSize: 12)))),
        DataCell(Text(_formatDate(task['target_date']), style: GoogleFonts.outfit(fontSize: 12))),
        DataCell(SizedBox(width: 200, child: Text((task['action_taken'] ?? task['closure_remark'] ?? '-').toString(), style: GoogleFonts.outfit(fontSize: 12)))),
        DataCell(Text(_formatDate(task['closing_date']), style: GoogleFonts.outfit(fontSize: 12))),
        DataCell(_buildStatusBadge(task)),
      ],
    );
  }

  Widget _buildCriticalityBadge(String crit) {
    Color color = Colors.blueGrey;
    if (crit == 'CF') {
      color = Colors.red.shade700;
    } else if (crit == 'MCF') {
      color = Colors.orange.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Text(crit, style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _buildMaterialCell(bool isMaterial, Map<String, dynamic> task) {
    if (!isMaterial) return Text('-', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey));
    
    final piNumber = task['pi_number']?.toString() ?? 'N/A';
    final piDate = _formatDate(task['pi_date']);
    
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.orange.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PI: $piNumber', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
          if (piDate.isNotEmpty)
            Text('Date: $piDate', style: GoogleFonts.outfit(fontSize: 9, color: Colors.orange.shade800)),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(Map<String, dynamic> task) {
    final bool isOsc = task['is_corrected'] == true;
    final String status = isOsc ? 'Close (OSC)' : (task['status'] ?? 'Open').toString();
    final Color color = (status.contains('Close') || isOsc) ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(status, style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(width: 4, height: 16, decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title, style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ],
    );
  }

  // --- LOGIC HELPERS ---

  List<Map<String, dynamic>> _getNotOkTasks() {
    final List<Map<String, dynamic>> results = [];
    final auditDataMap = auditData['audit_data'] as Map<String, dynamic>? ?? {};
    
    // Sort keys numerically
    final keys = auditDataMap.keys.toList();
    keys.sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

    for (final key in keys) {
      final task = auditDataMap[key] as Map<String, dynamic>;
      final status = task['status']?.toString().toLowerCase();
      final isCorrected = task['is_corrected'] == true;

      if (status != 'ok' || isCorrected) {
        results.add({
          ...task,
          'task_key': key,
        });
      }
    }
    return results;
  }

  Map<String, dynamic> _calculateMetrics(List<Map<String, dynamic>> notOkTasks) {
    int cf = 0, mcf = 0, aobs = 0, material = 0, osc = 0, workman = 0;
    int totalOverallPenalty = 0;
    int totalWorkmanPenalty = 0;

    for (final task in notOkTasks) {
      final crit = (task['nc_criticality'] ?? task['sub_status'] ?? 'Aobs').toString();
      final cat = (task['nc_category'] ?? '').toString();
      final root = (task['root_cause'] ?? '').toString();
      
      if (crit == 'CF') {
        cf++;
      } else if (crit == 'MCF') {
        mcf++;
      } else {
        aobs++;
      }

      if (root == 'Material Not Available') {
        material++;
      }
      if (task['is_corrected'] == true) {
        osc++;
      }
      
      // Workman Logic
      final isWorkman = cat == 'Quality of Workmanship'; // Simplified for summary UI
      if (isWorkman) {
        workman++;
      }

      int p = 0;
      if (crit == 'CF') {
        p = 3;
      } else if (crit == 'MCF') {
        p = 2;
      } else {
        p = 1;
      }
      
      totalOverallPenalty += p;
      if (isWorkman) {
        totalWorkmanPenalty += p;
      }
    }

    final double oScore = _getAssessmentScore(totalOverallPenalty);
    final double wScore = _getAssessmentScore(totalWorkmanPenalty);
    final double oComp = (100.0 - (totalOverallPenalty * 100 / 75.0)).clamp(0.0, 100.0);
    final double wComp = (100.0 - (totalWorkmanPenalty * 100 / 75.0)).clamp(0.0, 100.0);

    return {
      'total_nc': notOkTasks.length,
      'total_osc': osc,
      'total_material': material,
      'total_workman': workman,
      'count_cf': cf,
      'count_mcf': mcf,
      'count_aobs': aobs,
      'overall_score': oScore,
      'workman_score': wScore,
      'overall_compliance': double.parse(oComp.toStringAsFixed(2)),
      'workman_compliance': double.parse(wComp.toStringAsFixed(2)),
    };
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

  String _calculateAdherence() {
    final plan = _parseDate(auditData['plan_date_of_maintenance']);
    final done = _parseDate(auditData['actual_date_of_maintenance']);
    if (plan == null || done == null) return '-';
    final diff = done.difference(plan).inDays;
    return diff == 0 ? 'On Time' : '${diff > 0 ? '+' : ''}$diff Days';
  }

  String _calculateAging(DateTime auditDate) {
    final done = _parseDate(auditData['actual_date_of_maintenance']);
    if (done == null) return '-';
    final diff = auditDate.difference(done).inDays;
    return '$diff Days';
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

  String _getFinancialYear(DateTime date) {
    final int year = date.year;
    if (date.month >= 4) return '$year-${(year + 1).toString().substring(2)}';
    return '${year - 1}-${year.toString().substring(2)}';
  }
}
