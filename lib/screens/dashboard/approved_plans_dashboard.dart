import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:riqma_webapp/widgets/modern_searchable_dropdown.dart';

class ApprovedPlansDashboard extends StatefulWidget {
  const ApprovedPlansDashboard({super.key});

  @override
  State<ApprovedPlansDashboard> createState() => _ApprovedPlansDashboardState();
}

class _ApprovedPlansDashboardState extends State<ApprovedPlansDashboard> {
  // Filters
  String? _selectedState;
  String? _selectedSite;
  String? _selectedMake;
  String? _selectedModel;
  String? _selectedAuditor;
  String? _selectedMonth;
  String? _selectedYear;

  final List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  final List<String> _years = List.generate(5, (index) => (DateTime.now().year - 2 + index).toString());

  // Master Data
  Map<String, String> _auditorMap = {};
  Map<String, String> _modelMakeMap = {};
  Map<String, String> _modelNameToMakeMap = {};

  @override
  void initState() {
    super.initState();
    _initializeMasterData();
  }

  Future<void> _initializeMasterData() async {
    try {
      // Fetch Auditors
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'auditor')
          .get();
      
      final Map<String, String> auditors = {};
      for (final doc in usersSnap.docs) {
        auditors[doc.id] = (doc.data()['name'] ?? 'Unknown').toString();
      }

      // Fetch Models (for Make lookup)
      final modelsSnap = await FirebaseFirestore.instance.collection('turbinemodel').get();
      final Map<String, String> models = {};
      final Map<String, String> modelNames = {};
      for (final doc in modelsSnap.docs) {
        final data = doc.data();
        final make = (data['turbine_make'] ?? 'Unknown').toString();
        models[doc.id] = make;
        final name = data['turbine_model']?.toString() ?? data['model_name']?.toString() ?? data['model']?.toString() ?? data['name']?.toString();
        if (name != null) {
          modelNames[name.trim()] = make;
          // Also store lowercase for case-insensitive lookup
          modelNames[name.trim().toLowerCase()] = make;
        }
      }

      if (mounted) {
        setState(() {
          _auditorMap = auditors;
          _modelMakeMap = models;
          _modelNameToMakeMap = modelNames;
        });
      }
    } catch (e) {
      debugPrint('Error initializing master data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          _buildStickyFilterBar(),
          _buildMainContent(),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 120.0,
      floating: false,
      pinned: true,
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        title: Text(
          'Approved Audit Pipeline',
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1A1F36),
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.blue.shade50.withValues(alpha: 0.5),
                Colors.white,
              ],
            ),
          ),
        ),
      ),
      iconTheme: const IconThemeData(color: Color(0xFF1A1F36)),
    );
  }

  Widget _buildStickyFilterBar() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _FilterBarDelegate(
        child: Container(
          height: 100,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('planning_data')
                .where('status', isEqualTo: 'approved')
                .snapshots(),
            builder: (context, snapshot) {
              final Set<String> states = {};
              final Set<String> sites = {};
              final Set<String> makes = {};
              final Set<String> models = {};

              if (snapshot.hasData) {
                for (final doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (data['state'] != null) states.add(data['state'].toString());
                  if (data['site_name'] != null) sites.add(data['site_name'].toString());
                  if (data['turbine_model'] != null) models.add(data['turbine_model'].toString());
                  
                  // Resolve Make
                  final modelId = data['turbine_model_id']?.toString();
                  if (modelId != null && _modelMakeMap.containsKey(modelId)) {
                    makes.add(_modelMakeMap[modelId]!);
                  }
                }
              }

              return ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterDropdown(
                    label: 'State',
                    value: _selectedState,
                    items: states,
                    color: Colors.blue,
                    icon: Icons.map_rounded,
                    onChanged: (val) => setState(() => _selectedState = val),
                  ),
                  const SizedBox(width: 12),
                  _buildFilterDropdown(
                    label: 'Site',
                    value: _selectedSite,
                    items: sites,
                    color: Colors.orange,
                    icon: Icons.location_on_rounded,
                    onChanged: (val) => setState(() => _selectedSite = val),
                  ),
                  const SizedBox(width: 12),
                  _buildFilterDropdown(
                    label: 'Auditor',
                    value: _selectedAuditor,
                    items: _auditorMap.values.toSet(),
                    color: Colors.teal,
                    icon: Icons.person_rounded,
                    onChanged: (val) => setState(() => _selectedAuditor = val),
                  ),
                  const SizedBox(width: 12),
                  _buildFilterDropdown(
                    label: 'Make',
                    value: _selectedMake,
                    items: makes,
                    color: Colors.indigo,
                    icon: Icons.factory_rounded,
                    onChanged: (val) => setState(() => _selectedMake = val),
                  ),
                  const SizedBox(width: 12),
                  _buildFilterDropdown(
                    label: 'Model',
                    value: _selectedModel,
                    items: models,
                    color: Colors.deepPurple,
                    icon: Icons.settings_rounded,
                    onChanged: (val) => setState(() => _selectedModel = val),
                  ),
                  const SizedBox(width: 12),
                  _buildFilterDropdown(
                    label: 'Month',
                    value: _selectedMonth,
                    items: _months.toSet(),
                    color: Colors.pink,
                    icon: Icons.calendar_month_rounded,
                    onChanged: (val) => setState(() => _selectedMonth = val),
                  ),
                  const SizedBox(width: 12),
                  _buildFilterDropdown(
                    label: 'Year',
                    value: _selectedYear,
                    items: _years.toSet(),
                    color: Colors.cyan,
                    icon: Icons.timer_rounded,
                    onChanged: (val) => setState(() => _selectedYear = val),
                  ),
                  if (_hasActiveFilters) ...[
                    const SizedBox(width: 16),
                    Center(
                      child: TextButton.icon(
                        onPressed: _resetFilters,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text('Reset', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade400,
                          backgroundColor: Colors.red.shade50,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String? value,
    required Set<String> items,
    required MaterialColor color,
    required IconData icon,
    required void Function(String?) onChanged,
  }) {
    final Map<String, String> itemMap = {for (final item in items) item: item};
    return SizedBox(
      width: 180,
      child: ModernSearchableDropdown(
        label: label,
        value: value,
        items: itemMap,
        color: color,
        icon: icon,
        onChanged: onChanged,
      ),
    );
  }

  bool get _hasActiveFilters =>
      _selectedState != null ||
      _selectedSite != null ||
      _selectedMake != null ||
      _selectedModel != null ||
      _selectedAuditor != null ||
      _selectedMonth != null ||
      _selectedYear != null;

  void _resetFilters() {
    setState(() {
      _selectedState = null;
      _selectedSite = null;
      _selectedMake = null;
      _selectedModel = null;
      _selectedAuditor = null;
      _selectedMonth = null;
      _selectedYear = null;
    });
  }

  Widget _buildMainContent() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('planning_data')
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return SliverFillRemaining(child: Center(child: Text('Error: ${snapshot.error}')));
        }

        final docs = snapshot.data?.docs ?? [];
        final filteredDocs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          
          // State Filter
          if (_selectedState != null && data['state'] != _selectedState) return false;
          
          // Site Filter
          if (_selectedSite != null && data['site_name'] != _selectedSite) return false;
          
          // Auditor Filter
          if (_selectedAuditor != null && data['auditor_name'] != _selectedAuditor) return false;
          
          // Model Filter
          if (_selectedModel != null && data['turbine_model'] != _selectedModel) return false;
          
          // Make Filter
          if (_selectedMake != null) {
            final modelId = data['turbine_model_id']?.toString();
            if (modelId == null || _modelMakeMap[modelId] != _selectedMake) return false;
          }

          // Time Filter
          final timestamp = data['planned_date'] as Timestamp?;
          if (timestamp != null) {
            final date = timestamp.toDate();
            if (_selectedMonth != null && DateFormat('MMMM').format(date) != _selectedMonth) return false;
            if (_selectedYear != null && DateFormat('yyyy').format(date) != _selectedYear) return false;
          }

          return true;
        }).toList();

        if (filteredDocs.isEmpty) {
          return SliverFillRemaining(child: _buildEmptyState());
        }

        return SliverPadding(
          padding: const EdgeInsets.all(32),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 450,
              mainAxisExtent: 200,
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final doc = filteredDocs[index];
                final data = doc.data() as Map<String, dynamic>;
                return ApprovedPlanCard(docId: doc.id, data: data, makeMap: _modelMakeMap, nameToMakeMap: _modelNameToMakeMap);
              },
              childCount: filteredDocs.length,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.search_off_rounded, size: 64, color: Colors.blue.shade300),
          ),
          const SizedBox(height: 24),
          Text(
            'No matching audits found',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A1F36),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Adjust your filters to see more results.',
            style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _resetFilters,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A1F36),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Clear All Filters', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class ApprovedPlanCard extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  final Map<String, String> makeMap;
  final Map<String, String> nameToMakeMap;

  const ApprovedPlanCard({
    super.key,
    required this.docId,
    required this.data,
    required this.makeMap,
    required this.nameToMakeMap,
  });

  @override
  State<ApprovedPlanCard> createState() => _ApprovedPlanCardState();
}

class _ApprovedPlanCardState extends State<ApprovedPlanCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final timestamp = widget.data['planned_date'] as Timestamp?;
    final dateStr = timestamp != null
        ? DateFormat('dd MMM yyyy').format(timestamp.toDate())
        : 'TBD';
    
    final siteName = widget.data['site_name']?.toString() ?? 'Unknown Site';
    final state = widget.data['state']?.toString() ?? 'State';
    final modelRaw = widget.data['turbine_model']?.toString() ?? 'Model';
    final model = modelRaw.trim();
    final modelId = widget.data['turbine_model_id']?.toString();
    
    // Resolve Make: Priority 1: Data field 'turbine_make', Priority 2: Lookup via modelId, Priority 3: Lookup via modelName, Priority 4: Data field 'make'
    final make = widget.data['turbine_make']?.toString() ?? 
                 (modelId != null ? widget.makeMap[modelId] : null) ?? 
                 (model != 'Model' ? (widget.nameToMakeMap[model] ?? widget.nameToMakeMap[model.toLowerCase()]) : null) ??
                 widget.data['make']?.toString() ?? 
                 'Manufacturer';
                 
    final auditor = widget.data['auditor_name']?.toString() ?? 'Assigned Auditor';

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: AnimatedScale(
        scale: _isHovering ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _isHovering ? 0.12 : 0.06),
                blurRadius: _isHovering ? 30 : 15,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: _isHovering ? Colors.blue.shade200 : Colors.transparent,
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Glassy Background Effect
              Positioned(
                top: -20,
                right: -20,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '$state • $siteName',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.blue.shade700,
                              letterSpacing: 0.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _buildStatusBadge(),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '$make $model',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A1F36),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.person_outline_rounded, size: 14, color: Colors.grey[400]),
                                const SizedBox(width: 6),
                                Text(
                                  auditor,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.calendar_today_rounded, size: 14, color: Colors.grey[400]),
                                const SizedBox(width: 6),
                                Text(
                                  dateStr,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () {
                            // Quick View Logic
                            _showQuickView(context);
                          },
                          icon: Icon(
                            Icons.visibility_outlined,
                            color: _isHovering ? Colors.blue : Colors.grey[400],
                          ),
                          tooltip: 'Quick View',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.grey[50],
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            'APPROVED',
            style: GoogleFonts.outfit(
              color: Colors.green.shade700,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  void _showQuickView(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Audit Details', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Turbine ID', widget.data['turbine_id']?.toString() ?? 'N/A'),
            _buildDetailRow('State', widget.data['state']?.toString() ?? 'N/A'),
            _buildDetailRow('Site', widget.data['site_name']?.toString() ?? 'N/A'),
            _buildDetailRow('Model', widget.data['turbine_model']?.toString() ?? 'N/A'),
            _buildDetailRow('Auditor', widget.data['auditor_name']?.toString() ?? 'N/A'),
            _buildDetailRow('Planned Date', DateFormat('dd MMM yyyy').format((widget.data['planned_date'] as Timestamp).toDate())),
          ],
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ', style: GoogleFonts.outfit(color: Colors.grey[600], fontWeight: FontWeight.w500)),
          Text(value, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _FilterBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _FilterBarDelegate({required this.child});

  @override
  double get minExtent => 100;
  @override
  double get maxExtent => 100;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(_FilterBarDelegate oldDelegate) {
    return true;
  }
}
