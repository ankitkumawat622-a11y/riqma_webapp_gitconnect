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
  String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.initialStatusFilter;
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
      width: 140,
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
        return Container(
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
        );
      },
    ),
    PlutoColumn(
      title: 'Data',
      field: 'data',
      type: PlutoColumnType.text(),
      hide: true,
    ),
    PlutoColumn(
      title: 'ID',
      field: 'id',
      type: PlutoColumnType.text(),
      hide: true,
    ),
  ];

  String _getAuditorName(String email) {
    if (email.contains('2164')) {
      return 'Ankit Kumawat';
    }
    if (email.contains('0722')) {
      return 'Shankar Game';
    }
    // Add more mappings here or return email prefix as fallback
    if (email.contains('@')) {
      return email.split('@').first;
    }
    return email;
  }

  Stream<QuerySnapshot> _getAuditStream() {
    Query query = FirebaseFirestore.instance.collection('audit_submissions');

    if (_selectedStatus != null) {
      if (_selectedStatus == 'pending_group') {
        query = query.where('status', whereIn: ['pending', 'pending_manager_approval', 'pending_2', 'pending_3', 'pending_4', 'correction', 'pending_review']);
      } else {
        query = query.where('status', isEqualTo: _selectedStatus);
      }
    } else {
      query = query.where('status', whereIn: ['pending', 'correction', 'pending_2', 'approved', 'pending_manager_approval', 'pending_review']);
    }

    return query.orderBy('timestamp', descending: true).snapshots();
  }

  List<PlutoRow> _buildRows(QuerySnapshot snapshot) {
    final List<PlutoRow> newRows = [];
    
    for (int i = 0; i < snapshot.docs.length; i++) {
      final doc = snapshot.docs[i];
      final data = doc.data() as Map<String, dynamic>;
      final timestamp = data['timestamp'] as Timestamp?;
      final date = timestamp != null
          ? DateFormat('dd/MM/yyyy').format(timestamp.toDate())
          : '';

      String status = (data['status'] ?? 'pending').toString();

      newRows.add(PlutoRow(
        cells: {
          'sr_no': PlutoCell(value: i + 1),
          'date': PlutoCell(value: date),
          'site': PlutoCell(value: data['site']?.toString() ?? ''),
          'turbine': PlutoCell(value: data['turbine']?.toString() ?? data['turbineId']?.toString() ?? ''),
          'auditor': PlutoCell(value: _getAuditorName((data['auditor_email'] ?? data['auditor'] ?? '').toString())),
          'status': PlutoCell(value: status),
          'action': PlutoCell(value: 'View'),
          'data': PlutoCell(value: data),
          'id': PlutoCell(value: doc.id),
        },
      ));
    }

    return newRows;
  }

  void _navigateToReview(String auditId, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => AuditReviewScreen(
          auditId: auditId,
          auditData: data,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header removed
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.light ? 0.04 : 0.2),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: StreamBuilder<QuerySnapshot>(
              stream: _getAuditStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading reports: ${snapshot.error}',
                      style: GoogleFonts.outfit(color: Colors.red),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.light ? Colors.grey[50] : Colors.white.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.assignment_outlined, size: 48, color: Colors.grey[400]),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No audit reports found',
                          style: GoogleFonts.outfit(
                            fontSize: 18, 
                            color: Theme.of(context).textTheme.bodySmall?.color, 
                            fontWeight: FontWeight.w500
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final rows = _buildRows(snapshot.data!);

                return PlutoGrid(
                  columns: columns,
                  rows: rows,
                  onLoaded: (PlutoGridOnLoadedEvent event) {
                    stateManager = event.stateManager;
                  },
                  configuration: PlutoGridConfiguration(
                    style: PlutoGridStyleConfig(
                      gridBorderColor: Colors.transparent,
                      gridBackgroundColor: Colors.transparent,
                      borderColor: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                      iconColor: Theme.of(context).brightness == Brightness.light ? Colors.white70 : Colors.blueGrey[200]!,
                      columnTextStyle: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.white,
                      ),
                      cellTextStyle: GoogleFonts.outfit(
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                        fontSize: 13,
                      ),
                      rowHeight: 56,
                      columnHeight: 48,
                      columnFilterHeight: 40,
                      activatedColor: Theme.of(context).brightness == Brightness.light ? const Color(0xFFF0F7FF) : Colors.white.withValues(alpha: 0.05),
                      activatedBorderColor: const Color(0xFF0D7377).withValues(alpha: 0.3),
                      oddRowColor: Theme.of(context).brightness == Brightness.light ? const Color(0xFFFAFBFC) : Colors.white.withValues(alpha: 0.02),
                      evenRowColor: Colors.transparent,
                      columnAscendingIcon: const Icon(Icons.arrow_upward_rounded, size: 14, color: Colors.white70),
                      columnDescendingIcon: const Icon(Icons.arrow_downward_rounded, size: 14, color: Colors.white70),
                    ),
                    columnSize: const PlutoGridColumnSizeConfig(
                      autoSizeMode: PlutoAutoSizeMode.scale,
                    ),
                  ),
                  createFooter: (stateManager) {
                    stateManager.setPageSize(10, notify: false);
                    return PlutoPagination(stateManager);
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
