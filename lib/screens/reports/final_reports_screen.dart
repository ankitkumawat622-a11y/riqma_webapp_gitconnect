// =============================================================================
// Final Reports Screen
// =============================================================================
// Displays approved audit reports with data table and export functionality.
// Features:
// - PlutoGrid data table with pagination and Native search filters
// - Advanced Dropdown Filters (State, Site, Auditor, Year, Month)
// - Dynamic Summary Cards connected to refRows headcounts
// - SQA Dump Excel export (Bulk & Specific)
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pluto_grid/pluto_grid.dart';

import 'package:riqma_webapp/screens/audit_review_screen.dart';
import 'package:riqma_webapp/services/excel_export_service.dart';
import 'package:riqma_webapp/widgets/modern_searchable_dropdown.dart';

class FinalReportsScreen extends StatefulWidget {
  final String? auditorId;

  const FinalReportsScreen({super.key, this.auditorId});

  @override
  State<FinalReportsScreen> createState() => _FinalReportsScreenState();
}

class _FinalReportsScreenState extends State<FinalReportsScreen> {
  // ---------------------------------------------------------------------------
  // State Variables
  // ---------------------------------------------------------------------------
  PlutoGridStateManager? stateManager;
  List<PlutoRow> _allOriginalRows = [];
  List<PlutoRow> rows = [];
  bool isLoading = true;
  bool _isExporting = false;
  bool _allSelected = false;

  // Dropdown States
  String? _selectedSite;
  String? _selectedAuditor;
  String? _selectedState;
  String? _selectedMonth;
  String? _selectedYear;

  // Dropdown Options
  List<String> _siteOptions = [];
  List<String> _auditorOptions = [];
  List<String> _stateOptions = [];
  Map<String, String> _siteToStateMap = {};
  
  final List<String> _yearOptions = ['2023', '2024', '2025', '2026', '2027', '2028', '2029', '2030'];
  final List<String> _monthOptions = List.generate(12, (i) => (i + 1).toString().padLeft(2, '0'));

  // Metrics
  int _totalAuditsCount = 0;
  int _thisMonthCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchDropdownOptions();
    _fetchReports();
  }

  // ---------------------------------------------------------------------------
  // Data Fetching
  // ---------------------------------------------------------------------------
  Future<void> _fetchDropdownOptions() async {
    if (widget.auditorId != null) return; // Auditors skip these global options
    
    try {
      // Fetch Sites and Map to State
      final sitesSnap = await FirebaseFirestore.instance.collection('sites').get();
      final siteMap = <String, String>{};
      final Set<String> states = {};
      final Set<String> sites = {};

      for (final d in sitesSnap.docs) {
         final dData = d.data();
         final siteName = dData['site_name']?.toString() ?? '';
         final stateName = dData['state']?.toString() ?? '';
         if (siteName.isNotEmpty) {
           sites.add(siteName);
           if (stateName.isNotEmpty) siteMap[siteName] = stateName;
         }
         if (stateName.isNotEmpty) states.add(stateName);
      }
      
      // Fetch Auditors
      final usersSnap = await FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'auditor').get();
      final Set<String> auditors = {};
      for (final d in usersSnap.docs) {
         final data = d.data();
         auditors.add(data['name']?.toString() ?? data['email']?.toString() ?? '');
      }

      if (mounted) {
        setState(() {
          _siteToStateMap = siteMap;
          _siteOptions = sites.toList()..sort();
          _stateOptions = states.toList()..sort();
          _auditorOptions = auditors.where((a) => a.isNotEmpty).toList()..sort();
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchReports() async {
    try {
      Query query = FirebaseFirestore.instance
          .collection('audit_submissions')
          .where('status', isEqualTo: 'approved');
      
      if (widget.auditorId != null) {
        query = query.where('auditor_id', isEqualTo: widget.auditorId);
      }
      
      final snapshot = await query.orderBy('timestamp', descending: true).get();
      
      final newRows = <PlutoRow>[];
      for (int i = 0; i < snapshot.docs.length; i++) {
        final doc = snapshot.docs[i];
        final data = doc.data() as Map<String, dynamic>;
        final timestamp = data['timestamp'] as Timestamp?;
        final date = timestamp != null
            ? DateFormat('dd/MM/yyyy').format(timestamp.toDate())
            : '';

        if (widget.auditorId != null) {
           final site = data['site']?.toString() ?? '';
           if (site.isNotEmpty && !_siteOptions.contains(site)) {
              _siteOptions.add(site);
           }
        }

        newRows.add(PlutoRow(
          cells: {
            'selected': PlutoCell(value: 'false'),
            'sr_no': PlutoCell(value: i + 1),
            'date': PlutoCell(value: date),
            'site': PlutoCell(value: data['site'] ?? ''),
            'turbine': PlutoCell(value: data['turbine'] ?? data['turbineId'] ?? ''),
            'auditor': PlutoCell(value: _getAuditorName((data['auditor_email'] ?? data['auditor'] ?? '').toString())),
            'status': PlutoCell(value: 'approved'),
            'action': PlutoCell(value: 'View'),
            'data': PlutoCell(value: data),
            'id': PlutoCell(value: doc.id),
          },
        ));
      }

      if (mounted) {
        setState(() {
          _allOriginalRows = newRows;
          rows = List.from(_allOriginalRows);
          if (widget.auditorId != null) _siteOptions.sort();
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        _showError('Error loading reports: $e');
      }
    }
  }

  String _getAuditorName(String email) {
    if (email.contains('2164')) return 'Ankit Kumawat';
    if (email.contains('0722')) return 'Shankar Game';
    if (email.contains('@')) return email.split('@').first;
    return email;
  }

  // ---------------------------------------------------------------------------
  // Advanced Filter Logic
  // ---------------------------------------------------------------------------
  void _applyDropdownFilters() {
    List<PlutoRow> filtered = _allOriginalRows;
    
    if (_selectedSite != null && _selectedSite!.isNotEmpty) {
      filtered = filtered.where((r) => r.cells['site']?.value.toString() == _selectedSite).toList();
    }
    
    if (_selectedAuditor != null && _selectedAuditor!.isNotEmpty) {
      // Use contains to be safer since _getAuditorName might not perfectly match 'users' collection name
      filtered = filtered.where((r) => r.cells['auditor']?.value.toString().contains(_selectedAuditor!) ?? false).toList();
    }
    
    if (_selectedState != null && _selectedState!.isNotEmpty) {
       filtered = filtered.where((r) {
          final siteVal = r.cells['site']?.value.toString() ?? '';
          return _siteToStateMap[siteVal] == _selectedState;
       }).toList();
    }
    
    if (_selectedYear != null && _selectedYear!.isNotEmpty) {
      filtered = filtered.where((r) {
        final dateStr = r.cells['date']?.value.toString() ?? '';
        return dateStr.endsWith(_selectedYear!);
      }).toList();
    }
    
    if (_selectedMonth != null && _selectedMonth!.isNotEmpty) {
      filtered = filtered.where((r) {
        final dateStr = r.cells['date']?.value.toString() ?? '';
        if (dateStr.length == 10) {
           final parts = dateStr.split('/');
           if (parts.length == 3) {
              return parts[1] == _selectedMonth;
           }
        }
        return false;
      }).toList();
    }
    
    setState(() {
      rows = filtered;
    });
    
    if (stateManager != null) {
      stateManager!.removeAllRows(notify: false);
      stateManager!.appendRows(filtered);
      _updateHeadcounts();
    }
  }

  void _onGridStateChange() {
     _updateHeadcounts();
  }

  void _updateHeadcounts() {
    if (stateManager == null) return;
    
    final int total = stateManager!.refRows.length;
    int thisMonth = 0;
    
    final currentMonth = DateTime.now().month.toString().padLeft(2, '0');
    final currentYear = DateTime.now().year.toString();

    for (final row in stateManager!.refRows) {
        final dateStr = row.cells['date']?.value.toString() ?? '';
        if (dateStr.length == 10) {
           final parts = dateStr.split('/');
           if (parts.length == 3 && parts[1] == currentMonth && parts[2] == currentYear) {
              thisMonth++;
           }
        }
    }
    
    // Use addPostFrameCallback if calling inside build phase to avoid strict setState during render
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_totalAuditsCount != total || _thisMonthCount != thisMonth) {
        setState(() {
          _totalAuditsCount = total;
          _thisMonthCount = thisMonth;
        });
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Quick Date Filters
  // ---------------------------------------------------------------------------
  /// Filters rows by the previous calendar month (lastMonth=true) or previous
  /// calendar year (lastMonth=false). Reads the raw Timestamp from each row's
  /// 'data' cell to avoid string-parsing fragility.
  void _applyQuickFilter(bool lastMonth) {
    final now = DateTime.now();
    final DateTime start;
    final DateTime end;
    if (lastMonth) {
      start = DateTime(now.year, now.month - 1, 1);
      end   = DateTime(now.year, now.month,     0, 23, 59, 59);
    } else {
      start = DateTime(now.year - 1, 1,  1);
      end   = DateTime(now.year - 1, 12, 31, 23, 59, 59);
    }
    // Clear dropdown year/month to avoid double-filtering
    setState(() {
      _selectedYear  = null;
      _selectedMonth = null;
    });
    final filtered = _allOriginalRows.where((r) {
      final data = r.cells['data']?.value as Map<String, dynamic>?;
      final ts   = data?['timestamp'] as Timestamp?;
      if (ts == null) return false;
      final d = ts.toDate();
      return !d.isBefore(start) && !d.isAfter(end);
    }).toList();
    setState(() => rows = filtered);
    stateManager?.removeAllRows(notify: false);
    stateManager?.appendRows(filtered);
    _updateHeadcounts();
  }

  Widget _quickFilterBtn(String label, IconData icon, VoidCallback onPressed) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label, style: GoogleFonts.outfit(fontSize: 12)),
      style: TextButton.styleFrom(foregroundColor: Colors.indigo[700]),
    );
  }

  // ---------------------------------------------------------------------------
  // UI Building Blocks
  // ---------------------------------------------------------------------------

  Widget _buildSummaryCards() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        children: [
          _summaryCard('Total Audits', _totalAuditsCount.toString(), Icons.fact_check, Colors.blue),
          const SizedBox(width: 16),
          _summaryCard('This Month', _thisMonthCount.toString(), Icons.calendar_month, Colors.orange),
          const SizedBox(width: 16),
          _summaryCard('Approved', _totalAuditsCount.toString(), Icons.verified, Colors.green), // Approved matches filtered total since we query only approved
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String count, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 14)),
                Text(count, style: GoogleFonts.outfit(color: const Color(0xFF1A1F36), fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    final bool isManager = widget.auditorId == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Icon(Icons.filter_list, color: Colors.grey[600]),
            const SizedBox(width: 16),
            if (isManager) ...[
              Expanded(
                child: ModernSearchableDropdown(
                  label: 'State',
                  value: _selectedState,
                  items: {for (final v in _stateOptions) v: v},
                  color: Colors.blue,
                  icon: Icons.map_outlined,
                  onChanged: (String? v) => setState(() { _selectedState = v; _applyDropdownFilters(); }),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: ModernSearchableDropdown(
                label: 'Site',
                value: _selectedSite,
                items: {for (final v in _siteOptions) v: v},
                color: Colors.teal,
                icon: Icons.location_on_outlined,
                onChanged: (String? v) => setState(() { _selectedSite = v; _applyDropdownFilters(); }),
              ),
            ),
            const SizedBox(width: 12),
            if (isManager) ...[
              Expanded(
                child: ModernSearchableDropdown(
                  label: 'Auditor',
                  value: _selectedAuditor,
                  items: {for (final v in _auditorOptions) v: v},
                  color: Colors.cyan,
                  icon: Icons.person_search_outlined,
                  onChanged: (String? v) => setState(() { _selectedAuditor = v; _applyDropdownFilters(); }),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: ModernSearchableDropdown(
                label: 'Year',
                value: _selectedYear,
                items: {for (final v in _yearOptions) v: v},
                color: Colors.amber,
                icon: Icons.calendar_today_outlined,
                onChanged: (String? v) => setState(() { _selectedYear = v; _applyDropdownFilters(); }),
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
                onChanged: (String? v) => setState(() { _selectedMonth = v; _applyDropdownFilters(); }),
              ),
            ),
            const SizedBox(width: 8),
            _quickFilterBtn('Last Month', Icons.calendar_today, () => _applyQuickFilter(true)),
            _quickFilterBtn('Last Year', Icons.date_range, () => _applyQuickFilter(false)),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedState = null;
                  _selectedSite = null;
                  _selectedAuditor = null;
                  _selectedYear = null;
                  _selectedMonth = null;
                  _applyDropdownFilters();
                });
              },
              icon: const Icon(Icons.clear_all, size: 18),
              label: Text('Clear', style: GoogleFonts.outfit()),
            ),
          ],
        ),
      ),
    );
  }

  // Dropped legacy _buildDropdown as it is replaced by ModernSearchableDropdown

  // ---------------------------------------------------------------------------
  // Column Definitions
  // ---------------------------------------------------------------------------
  List<PlutoColumn> get columns => [
    PlutoColumn(
      title: '',
      field: 'selected',
      type: PlutoColumnType.text(),
      width: 50,
      enableSorting: false,
      enableFilterMenuItem: false,
      enableColumnDrag: false,
      enableContextMenu: false,
      enableDropToResize: false,
      renderer: (ctx) {
        final checked = ctx.row.cells['selected']?.value == 'true';
        return Checkbox(
          value: checked,
          activeColor: Colors.indigo,
          onChanged: (_) {
            ctx.stateManager.changeCellValue(
              ctx.cell, checked ? 'false' : 'true', notify: true,
            );
          },
        );
      },
    ),
    _buildColumn('Sr No', 'sr_no', 80, type: PlutoColumnType.number()),
    _buildColumn('Audit Date', 'date', 120),
    _buildColumn('Site', 'site', 150),
    _buildColumn('Turbine', 'turbine', 100),
    _buildColumn('Auditor', 'auditor', 150),
    _buildStatusColumn(),
    _buildActionColumn(),
    PlutoColumn(title: 'Data', field: 'data', type: PlutoColumnType.text(), hide: true),
    PlutoColumn(title: 'ID', field: 'id', type: PlutoColumnType.text(), hide: true),
  ];

  PlutoColumn _buildColumn(String title, String field, double width, {PlutoColumnType? type}) {
    return PlutoColumn(
      title: title,
      field: field,
      type: type ?? PlutoColumnType.text(),
      width: width,
      enableColumnDrag: false,
      enableContextMenu: false,
      enableDropToResize: false,
      enableFilterMenuItem: true, // Native PlutoGrid filtering
    );
  }

  PlutoColumn _buildStatusColumn() {
    return PlutoColumn(
      title: 'Status',
      field: 'status',
      type: PlutoColumnType.text(),
      width: 140,
      enableColumnDrag: false,
      enableContextMenu: false,
      enableDropToResize: false,
      enableFilterMenuItem: false,
      renderer: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.green.withValues(alpha: 0.5))),
        child: Text('Approved', style: GoogleFonts.outfit(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 12)),
      ),
    );
  }

  PlutoColumn _buildActionColumn() {
    return PlutoColumn(
      title: 'Action',
      field: 'action',
      type: PlutoColumnType.text(),
      width: 180,
      enableSorting: false,
      enableFilterMenuItem: false,
      enableColumnDrag: false,
      enableContextMenu: false,
      enableDropToResize: false,
      renderer: (ctx) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _actionButton(Icons.visibility_rounded, Colors.blueAccent, 'View Audit', () => _onViewAudit(ctx)),
          _actionButton(Icons.table_chart, Colors.teal, 'Digital Report (Excel)', () => _onDigitalReportExcel(ctx)),
          _actionButton(Icons.table_view, Colors.green, 'Export NC Tracking', () => _onExportNC(ctx)),
          _actionButton(Icons.file_download, Colors.blue, 'Export SQA Dump', () => _onExportSQA(ctx)),
        ],
      ),
    );
  }

  Widget _actionButton(IconData icon, Color color, String tooltip, VoidCallback onPressed) {
    return IconButton(icon: Icon(icon, color: color, size: 20), tooltip: tooltip, onPressed: onPressed);
  }

  // ---------------------------------------------------------------------------
  // Action Handlers
  // ---------------------------------------------------------------------------
  void _onViewAudit(PlutoColumnRendererContext ctx) {
    final state = ctx.stateManager.gridFocusNode.context?.findAncestorStateOfType<_FinalReportsScreenState>();
    final data = ctx.row.cells['data']?.value as Map<String, dynamic>;
    final auditId = ctx.row.cells['id']?.value as String;
    state?._navigateToReview(auditId, data);
  }

  Future<void> _onDigitalReportExcel(PlutoColumnRendererContext ctx) async {
    final state = ctx.stateManager.gridFocusNode.context?.findAncestorStateOfType<_FinalReportsScreenState>();
    final data = ctx.row.cells['data']?.value as Map<String, dynamic>;
    final auditId = ctx.row.cells['id']?.value as String;
    if (state != null) await state._handleExport('Generating Digital SQA Report Excel...', () => ExcelExportService().generateDigitalSqaReportExcel(auditId, data));
  }

  Future<void> _onExportNC(PlutoColumnRendererContext ctx) async {
    final state = ctx.stateManager.gridFocusNode.context?.findAncestorStateOfType<_FinalReportsScreenState>();
    final data = ctx.row.cells['data']?.value as Map<String, dynamic>;
    final auditId = ctx.row.cells['id']?.value as String;
    if (state != null) await state._handleExport('Generating NC Tracking Excel with Images...', () => ExcelExportService().generateNCTrackingExcel(auditId, data));
  }

  Future<void> _onExportSQA(PlutoColumnRendererContext ctx) async {
    final state = ctx.stateManager.gridFocusNode.context?.findAncestorStateOfType<_FinalReportsScreenState>();
    final data = ctx.row.cells['data']?.value as Map<String, dynamic>;
    final auditId = ctx.row.cells['id']?.value as String;
    if (state != null) await state._handleExport('Generating SQA Dump...', () => ExcelExportService().generateSQADumpExcel(auditId, data));
  }

  Future<void> _onBulkExportSQA() async {
    if (stateManager == null || stateManager!.refRows.isEmpty) {
      _showError('No records available to export.');
      return;
    }
    // Use checked rows if any are selected; otherwise export all visible rows
    final checked = stateManager!.refRows
        .where((r) => r.cells['selected']?.value == 'true')
        .toList();
    final source = checked.isNotEmpty ? checked : stateManager!.refRows;
    final List<Map<String, dynamic>> bulkData = source.map((r) {
      final data = Map<String, dynamic>.from(r.cells['data']?.value as Map<String, dynamic>);
      data['doc_id'] = r.cells['id']?.value as String;
      return data;
    }).toList();

    await _handleExport(
      'Generating Bulk SQA Dump (${bulkData.length} Audits)...',
      () => ExcelExportService().generateBulkSQADumpExcel(bulkData),
    );
  }

  Future<void> _handleExport(String loadingMessage, Future<void> Function() exportTask) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    _showLoadingSnackBar(loadingMessage);

    try {
      await exportTask();
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showSuccess('Export Completed Successfully');
      }
    } catch (e) {
      if (mounted) _showError('Export Failed: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Messaging & UI Helpers
  // ---------------------------------------------------------------------------
  void _showLoadingSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 16),
          Text(message, style: GoogleFonts.outfit()),
        ]),
        duration: const Duration(minutes: 5), // Manual dismiss
        backgroundColor: Colors.blue[700],
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: GoogleFonts.outfit()), backgroundColor: Colors.green));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: GoogleFonts.outfit()), backgroundColor: Colors.red));
  }

  void _navigateToReview(String auditId, Map<String, dynamic> data) {
    Navigator.push<void>(context, MaterialPageRoute<void>(builder: (context) => AuditReviewScreen(auditId: auditId, auditData: data, isReadOnly: true)));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: Text(widget.auditorId != null ? 'My Reports' : 'Final Reports Dashboard', style: GoogleFonts.outfit(color: const Color(0xFF1A1F36), fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1F36)),
        actions: [
          IconButton(
            icon: Icon(
              _allSelected ? Icons.deselect : Icons.select_all,
              color: Colors.indigo[600],
            ),
            tooltip: _allSelected ? 'Deselect All' : 'Select All Visible',
            onPressed: () {
              if (stateManager == null) return;
              final newVal = _allSelected ? 'false' : 'true';
              for (final row in stateManager!.refRows) {
                final cell = row.cells['selected'];
                if (cell != null) {
                  stateManager!.changeCellValue(cell, newVal, notify: false);
                }
              }
              stateManager!.notifyListeners();
              setState(() => _allSelected = !_allSelected);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 8, bottom: 8),
            child: ElevatedButton.icon(
              onPressed: _onBulkExportSQA, 
              icon: const Icon(Icons.download_for_offline, size: 20), 
              label: Text('Bulk Export', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            _buildSummaryCards(),
            _buildFilterBar(),
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))]),
                clipBehavior: Clip.antiAlias,
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : PlutoGrid(
                        columns: columns,
                        rows: rows,
                        onLoaded: (event) {
                          stateManager = event.stateManager;
                          stateManager!.addListener(_onGridStateChange);
                          _updateHeadcounts();
                        },
                        configuration: PlutoGridConfiguration(
                          style: PlutoGridStyleConfig(
                            gridBorderColor: Colors.transparent,
                            gridBackgroundColor: Colors.white,
                            borderColor: Colors.transparent,
                            iconColor: Colors.grey,
                            columnTextStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: const Color(0xFF1A1F36)),
                            cellTextStyle: GoogleFonts.outfit(color: const Color(0xFF2D3447)),
                            rowHeight: 60,
                            columnHeight: 50,
                          ),
                        ),
                        createFooter: (sm) {
                          sm.setPageSize(10, notify: false);
                          return PlutoPagination(sm);
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
