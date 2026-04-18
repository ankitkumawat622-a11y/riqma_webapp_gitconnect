import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pluto_grid/pluto_grid.dart';

import 'package:riqma_webapp/screens/audit_review_screen.dart';

class AuditReportsScreen extends StatefulWidget {
  final String? initialStatusFilter;
  const AuditReportsScreen({super.key, this.initialStatusFilter});

  @override
  State<AuditReportsScreen> createState() => _AuditReportsScreenState();
}

class _AuditReportsScreenState extends State<AuditReportsScreen> {
  PlutoGridStateManager? stateManager;
  
  // Filter States
  String? _selectedStatus;
  String? _selectedSite;
  String? _selectedAuditor;
  String? _selectedState;
  String? _selectedYear;
  String? _selectedMonth;
  String _searchQuery = '';
  bool _showAdvancedFilters = false;

  // Options lists
  List<String> _siteOptions = [];
  List<String> _auditorOptions = [];
  List<String> _stateOptions = [];
  Map<String, String> _siteToStateMap = {};
  
  final List<String> _yearOptions = ['2023', '2024', '2025', '2026', '2027', '2028', '2029', '2030'];
  final List<String> _monthOptions = List.generate(12, (i) => (i + 1).toString().padLeft(2, '0'));

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.initialStatusFilter;
    _fetchFilterOptions();
  }

  Future<void> _fetchFilterOptions() async {
    try {
      // Sites & States
      final sitesSnap = await FirebaseFirestore.instance.collection('sites').get();
      final siteMap = <String, String>{};
      final Set<String> states = {};
      final Set<String> sites = {};

      for (final d in sitesSnap.docs) {
        final dData = d.data();
        final sName = dData['site_name']?.toString() ?? '';
        final stName = dData['state']?.toString() ?? '';
        if (sName.isNotEmpty) {
          sites.add(sName);
          if (stName.isNotEmpty) siteMap[sName] = stName;
        }
        if (stName.isNotEmpty) states.add(stName);
      }

      // Auditors
      final usersSnap = await FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'auditor').get();
      final Set<String> auditors = {};
      for (final d in usersSnap.docs) {
        final data = d.data();
        auditors.add(data['name']?.toString() ?? data['email']?.toString() ?? '');
      }

      if (mounted) {
        setState(() {
          _siteOptions = sites.toList()..sort();
          _stateOptions = states.toList()..sort();
          _auditorOptions = auditors.where((a) => a.isNotEmpty).toList()..sort();
          _siteToStateMap = siteMap;
        });
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(AuditReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialStatusFilter != oldWidget.initialStatusFilter) {
      setState(() {
        _selectedStatus = widget.initialStatusFilter;
      });
    }
  }

  final List<PlutoColumn> columns = [
    PlutoColumn(
      title: 'Sr No',
      field: 'sr_no',
      type: PlutoColumnType.number(),
      width: 80,
      enableColumnDrag: false,
      enableContextMenu: false,
      enableDropToResize: false,
    ),
    PlutoColumn(
      title: 'Audit Date',
      field: 'date',
      type: PlutoColumnType.text(),
      width: 120,
      enableColumnDrag: false,
      enableContextMenu: false,
      enableDropToResize: false,
    ),
    PlutoColumn(
      title: 'Site',
      field: 'site',
      type: PlutoColumnType.text(),
      width: 150,
      enableColumnDrag: false,
      enableContextMenu: false,
      enableDropToResize: false,
    ),
    PlutoColumn(
      title: 'Turbine',
      field: 'turbine',
      type: PlutoColumnType.text(),
      width: 100,
      enableColumnDrag: false,
      enableContextMenu: false,
      enableDropToResize: false,
    ),
    PlutoColumn(
      title: 'Auditor',
      field: 'auditor',
      type: PlutoColumnType.text(),
      width: 150,
      enableColumnDrag: false,
      enableContextMenu: false,
      enableDropToResize: false,
    ),
    PlutoColumn(
      title: 'Status',
      field: 'status',
      type: PlutoColumnType.text(),
      width: 160,
      enableColumnDrag: false,
      enableContextMenu: false,
      enableDropToResize: false,
      renderer: (rendererContext) {
        final status = rendererContext.cell.value.toString();
        Color color = Colors.grey;
        String text = status;

        if (status == 'pending' || status == 'pending_manager_approval' || status == 'pending_review') {
          color = const Color(0xFFC2410C);
          text = 'Pending Review';
        } else if (status == 'approved') {
          color = const Color(0xFF15803D);
          text = 'Approved';
        } else if (status == 'correction') {
          color = const Color(0xFFB91C1C);
          text = 'Correction Needed';
        } else if (status.startsWith('pending_')) {
          final count = status.split('_').last;
          color = const Color(0xFF1D4ED8);
          text = 'Review (Cycle $count)';
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                text,
                style: GoogleFonts.outfit(color: color, fontWeight: FontWeight.w600, fontSize: 11),
              ),
            ],
          ),
        );
      },
    ),
    PlutoColumn(
      title: 'Action',
      field: 'action',
      type: PlutoColumnType.text(),
      width: 100,
      enableSorting: false,
      enableFilterMenuItem: false,
      enableColumnDrag: false,
      enableContextMenu: false,
      enableDropToResize: false,
      renderer: (rendererContext) {
        return Center(
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF0D7377).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.visibility_outlined, color: Color(0xFF0D7377), size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                final state = rendererContext.stateManager.gridFocusNode.context?.findAncestorStateOfType<_AuditReportsScreenState>();
                final data = rendererContext.row.cells['data']?.value as Map<String, dynamic>;
                final auditId = rendererContext.row.cells['id']?.value as String;
                state?._navigateToReview(auditId, data);
              },
            ),
          ),
        );
      },
    ),
    PlutoColumn(title: 'Data', field: 'data', type: PlutoColumnType.text(), hide: true),
    PlutoColumn(title: 'ID', field: 'id', type: PlutoColumnType.text(), hide: true),
  ];

  String _getAuditorName(String email) {
    if (email.contains('2164')) return 'Ankit Kumawat';
    if (email.contains('0722')) return 'Shankar Game';
    if (email.contains('@')) return email.split('@').first;
    return email;
  }

  Stream<QuerySnapshot> _getAuditStream() {
    Query query = FirebaseFirestore.instance.collection('audit_submissions');
    if (_selectedStatus != null && _selectedStatus != 'all') {
      if (_selectedStatus == 'pending_group') {
        query = query.where('status', whereIn: ['pending', 'pending_manager_approval', 'pending_2', 'pending_3', 'pending_4', 'correction', 'pending_review']);
      } else {
        query = query.where('status', isEqualTo: _selectedStatus);
      }
    }
    return query.orderBy('timestamp', descending: true).snapshots();
  }

  List<PlutoRow> _buildRows(QuerySnapshot snapshot) {
    final List<PlutoRow> allRows = [];
    for (int i = 0; i < snapshot.docs.length; i++) {
      final doc = snapshot.docs[i];
      final data = doc.data() as Map<String, dynamic>;
      final timestamp = data['timestamp'] as Timestamp?;
      final date = timestamp != null ? DateFormat('dd/MM/yyyy').format(timestamp.toDate()) : '';
      final site = data['site']?.toString() ?? '';
      final turbine = data['turbine']?.toString() ?? data['turbineId']?.toString() ?? '';
      final auditor = _getAuditorName((data['auditor_email'] ?? data['auditor'] ?? '').toString());
      final status = (data['status'] ?? 'pending').toString();

      // Apply Local Filters
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!site.toLowerCase().contains(query) && 
            !turbine.toLowerCase().contains(query) && 
            !auditor.toLowerCase().contains(query)) {
          continue;
        }
      }
      
      if (_selectedSite != null && site != _selectedSite) continue;
      if (_selectedAuditor != null && !auditor.contains(_selectedAuditor!)) continue;
      if (_selectedState != null && _siteToStateMap[site] != _selectedState) continue;
      
      if (_selectedYear != null && !date.endsWith(_selectedYear!)) continue;
      if (_selectedMonth != null) {
         final parts = date.split('/');
         if (parts.length < 2 || parts[1] != _selectedMonth) continue;
      }

      allRows.add(PlutoRow(
        cells: {
          'sr_no': PlutoCell(value: allRows.length + 1),
          'date': PlutoCell(value: date),
          'site': PlutoCell(value: site),
          'turbine': PlutoCell(value: turbine),
          'auditor': PlutoCell(value: auditor),
          'status': PlutoCell(value: status),
          'action': PlutoCell(value: 'View'),
          'data': PlutoCell(value: data),
          'id': PlutoCell(value: doc.id),
        },
      ));
    }
    return allRows;
  }

  void _navigateToReview(String auditId, Map<String, dynamic> data) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (context) => AuditReviewScreen(auditId: auditId, auditData: data)));
  }

  Widget _buildFilterBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search Site, Turbine or Auditor...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                  ),
                  style: GoogleFonts.outfit(fontSize: 14),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ModernSearchableDropdown(
                  label: 'Status',
                  value: _selectedStatus,
                  items: const {
                    'all': 'All Statuses',
                    'pending_group': 'All Pending',
                    'approved': 'Approved',
                    'correction': 'Correction Needed',
                  },
                  color: Colors.indigo,
                  icon: Icons.filter_list_rounded,
                  onChanged: (v) => setState(() => _selectedStatus = (v == 'all' ? null : v)),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => setState(() => _showAdvancedFilters = !_showAdvancedFilters),
                icon: Icon(_showAdvancedFilters ? Icons.keyboard_arrow_up : Icons.tune_rounded, size: 18),
                label: Text('Advanced', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _showAdvancedFilters ? Colors.indigo.shade50 : Colors.grey.shade100,
                  foregroundColor: Colors.indigo.shade700,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          if (_showAdvancedFilters) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ModernSearchableDropdown(
                    label: 'State',
                    value: _selectedState,
                    items: {for (final v in _stateOptions) v: v},
                    color: Colors.blue,
                    icon: Icons.map_outlined,
                    onChanged: (v) => setState(() => _selectedState = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ModernSearchableDropdown(
                    label: 'Site',
                    value: _selectedSite,
                    items: {for (final v in _siteOptions) v: v},
                    color: Colors.teal,
                    icon: Icons.location_on_outlined,
                    onChanged: (v) => setState(() => _selectedSite = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ModernSearchableDropdown(
                    label: 'Auditor',
                    value: _selectedAuditor,
                    items: {for (final v in _auditorOptions) v: v},
                    color: Colors.cyan,
                    icon: Icons.person_search_outlined,
                    onChanged: (v) => setState(() => _selectedAuditor = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ModernSearchableDropdown(
                    label: 'Year',
                    value: _selectedYear,
                    items: {for (final v in _yearOptions) v: v},
                    color: Colors.amber,
                    icon: Icons.calendar_today_outlined,
                    onChanged: (v) => setState(() => _selectedYear = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ModernSearchableDropdown(
                    label: 'Month',
                    value: _selectedMonth,
                    items: {for (final v in _monthOptions) v: v},
                    color: Colors.orange,
                    icon: Icons.calendar_month_outlined,
                    onChanged: (v) => setState(() => _selectedMonth = v),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () => setState(() {
                    _selectedState = null;
                    _selectedSite = null;
                    _selectedAuditor = null;
                    _selectedYear = null;
                    _selectedMonth = null;
                    _searchQuery = '';
                  }),
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Reset Filters',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFilterBar(),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))],
            ),
            clipBehavior: Clip.antiAlias,
            child: StreamBuilder<QuerySnapshot>(
              stream: _getAuditStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: GoogleFonts.outfit(color: Colors.red)));
                
                final rows = _buildRows(snapshot.data!);
                if (rows.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text('No matching reports found', style: GoogleFonts.outfit(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                      ],
                    ),
                  );
                }

                return PlutoGrid(
                  columns: columns,
                  rows: rows,
                  onLoaded: (event) => stateManager = event.stateManager,
                  configuration: PlutoGridConfiguration(
                    style: PlutoGridStyleConfig(
                      gridBorderColor: Colors.transparent,
                      gridBackgroundColor: Colors.transparent,
                      borderColor: Colors.grey.withValues(alpha: 0.1),
                      iconColor: Colors.grey,
                      columnTextStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF1A1F36)),
                      cellTextStyle: GoogleFonts.outfit(color: const Color(0xFF2D3447), fontSize: 13),
                      rowHeight: 60,
                      columnHeight: 50,
                      activatedColor: const Color(0xFFF8FAFF),
                      activatedBorderColor: Colors.indigo.withValues(alpha: 0.2),
                    ),
                    columnSize: const PlutoGridColumnSizeConfig(autoSizeMode: PlutoAutoSizeMode.scale),
                  ),
                  createFooter: (sm) {
                    sm.setPageSize(10, notify: false);
                    return PlutoPagination(sm);
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
