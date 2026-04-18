import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class AuditSummaryReportScreen extends StatefulWidget {
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
  State<AuditSummaryReportScreen> createState() => _AuditSummaryReportScreenState();
}

class _ScrollIntent extends Intent {
  final AxisDirection direction;
  const _ScrollIntent({required this.direction});
}

class _AuditSummaryReportScreenState extends State<AuditSummaryReportScreen> {
  bool _isMetadataExpanded = true;
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  Map<String, bool> _workmanPenaltyMap = {};
  Map<String, Map<String, dynamic>> _ncMap = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    await Future.wait([
      _fetchConfig(),
      _fetchNCs(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchNCs() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('ncs')
          .where('audit_ref', isEqualTo: FirebaseFirestore.instance.doc('/audit_submissions/${widget.auditId}'))
          .get();
      
      final Map<String, Map<String, dynamic>> mapping = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        final key = data['task_key']?.toString();
        if (key != null) mapping[key] = data;
      }
      _ncMap = mapping;
    } catch (_) {}
  }

  Future<void> _fetchConfig() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('audit_configs').doc('nc_categories').get();
      if (doc.exists) {
        final Map<String, bool> mapping = {};
        final items = doc.data()?['items'] as List<dynamic>? ?? [];
        for (final item in items) {
          final name = (item as Map)['name']?.toString() ?? '';
          mapping[name] = item['is_workman_penalty'] == true;
        }
        _workmanPenaltyMap = mapping;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyboardScroll(AxisDirection direction) {
    if (!_verticalController.hasClients || !_horizontalController.hasClients) return;
    
    const double step = 100.0;
    if (direction == AxisDirection.up) {
      _verticalController.animateTo((_verticalController.offset - step).clamp(0, _verticalController.position.maxScrollExtent), duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
    } else if (direction == AxisDirection.down) {
      _verticalController.animateTo((_verticalController.offset + step).clamp(0, _verticalController.position.maxScrollExtent), duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
    } else if (direction == AxisDirection.left) {
      _horizontalController.animateTo((_horizontalController.offset - step).clamp(0, _horizontalController.position.maxScrollExtent), duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
    } else if (direction == AxisDirection.right) {
      _horizontalController.animateTo((_horizontalController.offset + step).clamp(0, _horizontalController.position.maxScrollExtent), duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1F36),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final DateTime auditDate = _parseDate(widget.auditData['timestamp']) ?? DateTime.now();
    final String fy = _getFinancialYear(auditDate);
    final tasks = _getNotOkTasks();
    final metrics = _calculateMetrics(tasks);

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.arrowUp): const _ScrollIntent(direction: AxisDirection.up),
        LogicalKeySet(LogicalKeyboardKey.arrowDown): const _ScrollIntent(direction: AxisDirection.down),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft): const _ScrollIntent(direction: AxisDirection.left),
        LogicalKeySet(LogicalKeyboardKey.arrowRight): const _ScrollIntent(direction: AxisDirection.right),
      },
      child: Actions(
        actions: {
          _ScrollIntent: CallbackAction<_ScrollIntent>(onInvoke: (intent) {
            _handleKeyboardScroll(intent.direction);
            return null;
          }),
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          child: Scaffold(
            backgroundColor: const Color(0xFFF4F7FA),
            appBar: AppBar(
              title: Text(
                'Audit Summary Report',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              backgroundColor: const Color(0xFF1A1F36),
              foregroundColor: Colors.white,
              elevation: 0,
              centerTitle: false,
              leadingWidth: 40,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: Column(
              children: [
                _buildPrimaryDataHeader(context, auditDate, fy),
                _buildMetricsStrip(metrics),
                Expanded(
                  child: _buildNCTable(tasks),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryDataHeader(BuildContext context, DateTime auditDate, String fy) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFE0F2FE),
            const Color(0xFFBAE6FD),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _isMetadataExpanded = !_isMetadataExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSectionHeader('Primary Metadata'),
                    Icon(
                      _isMetadataExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: const Color(0xFF0369A1),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildMetaCard('Audit Date', DateFormat('dd.MM.yyyy').format(auditDate), Icons.calendar_month_rounded, Colors.blue),
                    _buildMetaCard('Financial Year', fy, Icons.history_edu_rounded, Colors.orange),
                    _buildMetaCard('Turbine Name', (widget.auditData['turbine'] ?? '').toString(), Icons.precision_manufacturing_rounded, Colors.teal),
                    _buildMetaCard('Turbine Make', widget.masterData['turbine_make'] ?? '', Icons.factory_rounded, Colors.cyan),
                    _buildMetaCard('Rating (MW)', widget.masterData['turbine_rating'] ?? '', Icons.bolt_rounded, Colors.amber),
                    _buildMetaCard('Model', widget.masterData['turbine_model'] ?? '', Icons.model_training_rounded, Colors.indigo),
                    _buildMetaCard('Site Name', (widget.auditData['site'] ?? '').toString(), Icons.location_on_rounded, Colors.redAccent),
                    _buildMetaCard('State', (widget.auditData['state'] ?? '').toString(), Icons.map_rounded, Colors.purple),
                    _buildMetaCard('District', widget.masterData['district'] ?? '', Icons.location_city_rounded, Colors.blueGrey),
                    _buildMetaCard('Warehouse', widget.masterData['warehouse_code'] ?? '', Icons.warehouse_rounded, Colors.brown),
                    _buildMetaCard('Zone', widget.masterData['zone'] ?? '', Icons.explore_rounded, Colors.green),
                    _buildMetaCard('Customer', (widget.auditData['customer_name'] ?? '').toString(), Icons.business_rounded, Colors.blueAccent),
                    _buildMetaCard('Auditor', (widget.auditData['auditor_name'] ?? '').toString(), Icons.person_rounded, Colors.deepPurple),
                    _buildMetaCard('DOC', _formatDate(widget.auditData['commissioning_date']), Icons.event_available_rounded, Colors.lightGreen),
                    _buildMetaCard('DOT', _formatDate(widget.auditData['date_of_take_over']), Icons.handshake_rounded, Colors.deepOrange),
                    _buildMetaCard('PM Plan', _formatDate(widget.auditData['plan_date_of_maintenance']), Icons.edit_calendar_rounded, Colors.blueGrey),
                    _buildMetaCard('PM Done', _formatDate(widget.auditData['actual_date_of_maintenance']), Icons.task_alt_rounded, Colors.green),
                    _buildMetaCard('PM Adherence', _calculateAdherence(), Icons.timer_rounded, Colors.red),
                    _buildMetaCard('QA vs PM Aging', _calculateAging(auditDate), Icons.hourglass_bottom_rounded, Colors.orangeAccent),
                    _buildMetaCard('PM Type', (widget.auditData['maintenance_type'] ?? '').toString(), Icons.settings_suggest_rounded, Colors.indigoAccent),
                  ],
                ),
              ),
              crossFadeState: _isMetadataExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(width: 3, height: 14, decoration: BoxDecoration(color: const Color(0xFF0284C7), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title, style: GoogleFonts.outfit(color: const Color(0xFF0369A1), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
      ],
    );
  }

  Widget _buildMetaCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: 165,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: GoogleFonts.outfit(color: const Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.w500)),
                Text(
                  value.isEmpty ? '-' : value,
                  style: GoogleFonts.outfit(color: const Color(0xFF1E293B), fontSize: 11, fontWeight: FontWeight.bold),
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
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
          _buildScoreBadge('Overall', metrics['overall_score'] as double, metrics['overall_compliance'] as double, Colors.teal),
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

    const double colTask = 250;
    const double colFinding = 300;
    const double colCrit = 100;
    const double colRef = 200;
    const double colCat = 150;
    const double colMat = 150;
    const double colRoot = 150;
    const double colPlan = 200;
    const double colTarget = 110;
    const double colTaken = 200;
    const double colClose = 110;
    const double colStatus = 120;
    
    final totalWidth = colTask + colFinding + colCrit + colRef + colCat + colMat + colRoot + colPlan + colTarget + colTaken + colClose + colStatus;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        controller: _horizontalController,
        thumbVisibility: true,
        thickness: 8,
        radius: const Radius.circular(4),
        child: SingleChildScrollView(
          controller: _horizontalController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalWidth,
            child: Column(
              children: [
                // Sticky Header Row
                Container(
                  color: const Color(0xFFF8FAFC),
                  child: Table(
                    columnWidths: const {
                      0: FixedColumnWidth(colTask),
                      1: FixedColumnWidth(colFinding),
                      2: FixedColumnWidth(colCrit),
                      3: FixedColumnWidth(colRef),
                      4: FixedColumnWidth(colCat),
                      5: FixedColumnWidth(colMat),
                      6: FixedColumnWidth(colRoot),
                      7: FixedColumnWidth(colPlan),
                      8: FixedColumnWidth(colTarget),
                      9: FixedColumnWidth(colTaken),
                      10: FixedColumnWidth(colClose),
                      11: FixedColumnWidth(colStatus),
                    },
                    children: [
                      TableRow(
                        children: [
                          _buildTableHeaderCell('Task Name'),
                          _buildTableHeaderCell('Finding'),
                          _buildTableHeaderCell('Criticality'),
                          _buildTableHeaderCell('Reference'),
                          _buildTableHeaderCell('NC Category'),
                          _buildTableHeaderCell('Material Details'),
                          _buildTableHeaderCell('Root Cause'),
                          _buildTableHeaderCell('Action Plan'),
                          _buildTableHeaderCell('Target Date'),
                          _buildTableHeaderCell('Action Taken'),
                          _buildTableHeaderCell('Closing Date'),
                          _buildTableHeaderCell('Status'),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1),
                // Scrollable Body
                Expanded(
                  child: Scrollbar(
                    controller: _verticalController,
                    thumbVisibility: true,
                    thickness: 8,
                    radius: const Radius.circular(4),
                    child: SingleChildScrollView(
                      controller: _verticalController,
                      child: Table(
                        columnWidths: const {
                          0: FixedColumnWidth(colTask),
                          1: FixedColumnWidth(colFinding),
                          2: FixedColumnWidth(colCrit),
                          3: FixedColumnWidth(colRef),
                          4: FixedColumnWidth(colCat),
                          5: FixedColumnWidth(colMat),
                          6: FixedColumnWidth(colRoot),
                          7: FixedColumnWidth(colPlan),
                          8: FixedColumnWidth(colTarget),
                          9: FixedColumnWidth(colTaken),
                          10: FixedColumnWidth(colClose),
                          11: FixedColumnWidth(colStatus),
                        },
                        border: TableBorder(
                          horizontalInside: BorderSide(color: Colors.grey.shade100, width: 1),
                        ),
                        children: tasks.map((task) => _buildTableDataRow(task)).toList(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeaderCell(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Text(
        label,
        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF475569)),
      ),
    );
  }

  TableRow _buildTableDataRow(Map<String, dynamic> task) {
    final bool isMaterial = task['root_cause'] == 'Material Not Available';
    final criticality = (task['nc_criticality'] ?? task['sub_status'] ?? 'Aobs').toString();

    return TableRow(
      children: [
        _buildTableCell(Text((task['task_name'] ?? task['question'] ?? '-').toString(), style: GoogleFonts.outfit(fontSize: 12))),
        _buildTableCell(Text((task['finding'] ?? task['observation'] ?? '-').toString(), style: GoogleFonts.outfit(fontSize: 12), maxLines: 3, overflow: TextOverflow.ellipsis)),
        _buildTableCell(_buildCriticalityBadge(criticality)),
        _buildTableCell(Text((task['reference_name'] ?? '-').toString(), style: GoogleFonts.outfit(fontSize: 12, color: Colors.blue.shade700))),
        _buildTableCell(Text((task['nc_category'] ?? '-').toString(), style: GoogleFonts.outfit(fontSize: 12, color: Colors.purple.shade700))),
        _buildTableCell(_buildMaterialCell(isMaterial, task)),
        _buildTableCell(Text((task['root_cause'] ?? '-').toString(), style: GoogleFonts.outfit(fontSize: 12))),
        _buildTableCell(Text((task['action_plan'] ?? '-').toString(), style: GoogleFonts.outfit(fontSize: 12))),
        _buildTableCell(Text(_formatDate(task['target_date']), style: GoogleFonts.outfit(fontSize: 12))),
        _buildTableCell(Text((task['action_taken'] ?? task['closure_remark'] ?? '-').toString(), style: GoogleFonts.outfit(fontSize: 12))),
        _buildTableCell(Text(_formatDate(task['closing_date']), style: GoogleFonts.outfit(fontSize: 12))),
        _buildTableCell(_buildStatusBadge(task)),
      ],
    );
  }

  Widget _buildTableCell(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: child,
      ),
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

  // --- LOGIC HELPERS ---

  List<Map<String, dynamic>> _getNotOkTasks() {
    final List<Map<String, dynamic>> results = [];
    final auditDataMap = widget.auditData['audit_data'] as Map<String, dynamic>? ?? {};
    
    auditDataMap.forEach((key, value) {
      final task = value as Map<String, dynamic>;
      final status = task['status']?.toString().toLowerCase();
      final isOsc = task['is_corrected'] == true;

      if (status != 'ok' || isOsc) {
        // Merge with live NC data if exists
        final liveNc = _ncMap[key] ?? {};
        results.add({
          ...task,
          ...liveNc,
          'task_key': key,
        });
      }
    });

    // Deep Match Sorting Logic: Reference Group -> Penalty Priority -> Criticality
    results.sort((a, b) {
      final refA = (a['reference_name'] ?? '-').toString();
      final refB = (b['reference_name'] ?? '-').toString();
      final refComp = refA.compareTo(refB);
      if (refComp != 0) return refComp;

      // Same Reference - Check Penalty Priority
      final catA = (a['nc_category'] ?? '').toString();
      final catB = (b['nc_category'] ?? '').toString();
      final bool isWorkmanA = _workmanPenaltyMap[catA] ?? (catA == 'Service' || catA == 'Quality of Workmanship');
      final bool isWorkmanB = _workmanPenaltyMap[catB] ?? (catB == 'Service' || catB == 'Quality of Workmanship');
      
      if (isWorkmanA && !isWorkmanB) return -1;
      if (!isWorkmanA && isWorkmanB) return 1;

      // Same Penalty status - Check Criticality
      final critA = (a['nc_criticality'] ?? a['sub_status'] ?? 'Aobs').toString();
      final critB = (b['nc_criticality'] ?? b['sub_status'] ?? 'Aobs').toString();
      final pA = (critA == 'CF') ? 3 : (critA == 'MCF' ? 2 : 1);
      final pB = (critB == 'CF') ? 3 : (critB == 'MCF' ? 2 : 1);
      return pB.compareTo(pA); // Higher penalty first
    });

    return results;
  }

  Map<String, dynamic> _calculateMetrics(List<Map<String, dynamic>> notOkTasks) {
    int cf = 0, mcf = 0, aobs = 0, material = 0, osc = 0, workman = 0;
    
    // Grouping for penalty scores
    final Map<String, List<Map<String, dynamic>>> groupedForScoring = {};

    for (final task in notOkTasks) {
      final crit = (task['nc_criticality'] ?? task['sub_status'] ?? 'Aobs').toString();
      final cat = (task['nc_category'] ?? '').toString();
      final root = (task['root_cause'] ?? '').toString();
      final ref = (task['reference_name'] ?? '-').toString();

      // Individual Counters (Task-based)
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
      
      // Workman Task Count (Purple Box)
      final bool isWorkman = _workmanPenaltyMap.isEmpty 
          ? (cat == 'Service' || cat == 'Quality of Workmanship') 
          : (_workmanPenaltyMap[cat] ?? false);

      if (isWorkman) {
        workman++;
      }

      // Grouping for penalty calculation
      groupedForScoring.putIfAbsent(ref, () => []);
      groupedForScoring[ref]!.add(task);
    }

    // Calculate final penalties using grouping (Matches Digital Report)
    int totalOverallPenalty = 0;
    int totalWorkmanPenalty = 0;

    for (final refGroup in groupedForScoring.values) {
      int maxOverall = 0;
      int maxWorkman = 0;
      for (final t in refGroup) {
        final crit = (t['nc_criticality'] ?? t['sub_status'] ?? 'Aobs').toString();
        final cat = (t['nc_category'] ?? '').toString();
        final bool isWorkman = _workmanPenaltyMap.isEmpty 
            ? (cat == 'Service' || cat == 'Quality of Workmanship') 
            : (_workmanPenaltyMap[cat] ?? false);

        int p = (crit == 'CF') ? 3 : (crit == 'MCF' ? 2 : 1);
        if (p > maxOverall) maxOverall = p;
        if (isWorkman && p > maxWorkman) maxWorkman = p;
      }
      totalOverallPenalty += maxOverall;
      totalWorkmanPenalty += maxWorkman;
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
    final plan = _parseDate(widget.auditData['plan_date_of_maintenance']);
    final done = _parseDate(widget.auditData['actual_date_of_maintenance']);
    if (plan == null || done == null) return '-';
    final diff = done.difference(plan).inDays;
    return diff == 0 ? 'On Time' : '${diff > 0 ? '+' : ''}$diff Days';
  }

  String _calculateAging(DateTime auditDate) {
    final done = _parseDate(widget.auditData['actual_date_of_maintenance']);
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

