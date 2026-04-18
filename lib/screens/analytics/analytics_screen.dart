import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';


class AnalyticsScreen extends StatefulWidget {
  final String? selectedState;
  final String? selectedSite;
  final void Function(Set<String> states, Map<String, List<String>> sites)? onFiltersLoaded;

  const AnalyticsScreen({
    super.key, 
    this.selectedState, 
    this.selectedSite, 
    this.onFiltersLoaded,
  });

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  // State
  List<DocumentSnapshot> _allAudits = [];
  
  Map<String, Map<String, int>> _severityData = {}; 
  Map<String, int> _rootCauseData = {}; 
  Map<String, int> _materialData = {};
  Map<String, int> _ncData = {};
  
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAnalyticsData();
  }

  @override
  void didUpdateWidget(AnalyticsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedState != oldWidget.selectedState || widget.selectedSite != oldWidget.selectedSite) {
      _processData();
    }
  }

  Future<void> _fetchAnalyticsData() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('audit_submissions').get();
      _allAudits = snapshot.docs;
      
      // Optimization: Single Pass Loop for Filters AND Initial Data
      final states = <String>{};
      final siteMap = <String, List<String>>{};
      
      final Map<String, Map<String, int>> severity = {};
      final Map<String, int> rootCause = {};
      final Map<String, int> material = {};
      final Map<String, int> nc = {};

      for (final doc in _allAudits) {
        final data = doc.data() as Map<String, dynamic>;
        
        // 1. Extract Filters
        final state = (data['state'] ?? '').toString();
        final site = (data['site'] ?? 'Unknown').toString();
        
        if (state.isNotEmpty) {
          states.add(state);
          if (!siteMap.containsKey(state)) {
            siteMap[state] = [];
          }
          if (!siteMap[state]!.contains(site)) {
            siteMap[state]!.add(site);
          }
        }

        // 2. Process Data (Apply current filters immediately)
        // Note: Even on initial load, we might have filters if passed from parent, 
        // though typically they are null/'All' initially.
        final bool matchState = widget.selectedState == null || widget.selectedState == 'All States' || data['state'] == widget.selectedState;
        final bool matchSite = widget.selectedSite == null || widget.selectedSite == 'All Sites' || data['site'] == widget.selectedSite;

        if (matchState && matchSite) {
             final auditData = data['audit_data'] as Map<String, dynamic>? ?? {};
             for (final entry in auditData.values) {
                final task = entry as Map<String, dynamic>;
                final status = (task['status'] ?? '').toString().toLowerCase();

                // Global Filter: Only 'not ok' items
                if (status != 'not ok') continue; 

                // Severity Distribution
                final mainCat = (task['main_category_name'] ?? 'Other').toString();
                final subStatus = (task['sub_status'] ?? 'Aobs').toString();
                
                if (!severity.containsKey(mainCat)) {
                  severity[mainCat] = {'CF': 0, 'MCF': 0, 'Aobs': 0};
                }
                severity[mainCat]![subStatus] = (severity[mainCat]![subStatus] ?? 0) + 1;

                // Root Cause
                final rc = (task['root_cause'] ?? '').toString();
                final cause = rc.isEmpty ? 'Unidentified' : rc;
                rootCause[cause] = (rootCause[cause] ?? 0) + 1;

                // Material Procurement
                final matStatus = task['material_status']?.toString();
                if (matStatus != null && matStatus.isNotEmpty) {
                   material[matStatus] = (material[matStatus] ?? 0) + 1;
                }

                // NC Classification
                final ncCat = (task['nc_category'] ?? 'Unclassified').toString();
                nc[ncCat] = (nc[ncCat] ?? 0) + 1;
             }
        }
      }

      if (mounted) {
        // Notify parent of available filters
        if (widget.onFiltersLoaded != null) {
           widget.onFiltersLoaded!(states, siteMap);
        }
        
        // Set processed data directly without re-looping
        setState(() {
          _severityData = severity;
          _rootCauseData = rootCause;
          _materialData = material;
          _ncData = nc;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // Still needed for filter updates
  void _processData() {
    final Map<String, Map<String, int>> severity = {};
    final Map<String, int> rootCause = {};
    final Map<String, int> material = {};
    final Map<String, int> nc = {};

    for (final doc in _allAudits) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      
      // Apply Filters (from props)
      if (widget.selectedState != null && widget.selectedState != 'All States') {
        if (data['state'] != widget.selectedState) continue;
      }
      if (widget.selectedSite != null && widget.selectedSite != 'All Sites') {
        if (data['site'] != widget.selectedSite) continue;
      }

      final auditData = data['audit_data'] as Map<String, dynamic>? ?? {};

      for (final entry in auditData.values) {
        final task = entry as Map<String, dynamic>;
        final status = (task['status'] ?? '').toString().toLowerCase();

        // Global Filter: Only 'not ok' items
        if (status != 'not ok') continue; 

        // 1. Severity Distribution
        final mainCat = (task['main_category_name'] ?? 'Other').toString();
        final subStatus = (task['sub_status'] ?? 'Aobs').toString();
        
        if (!severity.containsKey(mainCat)) {
          severity[mainCat] = {'CF': 0, 'MCF': 0, 'Aobs': 0};
        }
        severity[mainCat]![subStatus] = (severity[mainCat]![subStatus] ?? 0) + 1;

        // 2. Root Cause
        final rc = (task['root_cause'] ?? '').toString();
        final cause = rc.isEmpty ? 'Unidentified' : rc;
        rootCause[cause] = (rootCause[cause] ?? 0) + 1;

        // 3. Material Procurement
        final matStatus = task['material_status']?.toString();
        if (matStatus != null && matStatus.isNotEmpty) {
           material[matStatus] = (material[matStatus] ?? 0) + 1;
        }

        // 4. NC Classification
        final ncCat = (task['nc_category'] ?? 'Unclassified').toString();
        nc[ncCat] = (nc[ncCat] ?? 0) + 1;
      }
    }

    setState(() {
      _severityData = severity;
      _rootCauseData = rootCause;
      _materialData = material;
      _ncData = nc;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text('Error loading analytics: $_error', style: GoogleFonts.outfit(color: Colors.red)));
    }

    if (_severityData.isEmpty && _rootCauseData.isEmpty && _materialData.isEmpty && _ncData.isEmpty) {
       return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No defects found for analysis', style: GoogleFonts.outfit(fontSize: 18, color: Colors.grey[500])),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Row Removed (Shifted to AppBar)
          const SizedBox(height: 24),
          
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 900;


              return Column(
                children: [
                  // Row 1
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildSeverityChart()),
                        const SizedBox(width: 24),
                        Expanded(child: _buildRootCauseChart()),
                      ],
                    )
                  else ...[
                    _buildSeverityChart(),
                    const SizedBox(height: 24),
                    _buildRootCauseChart(),
                  ],

                  const SizedBox(height: 24),

                  // Row 2
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildMaterialChart()),
                        const SizedBox(width: 24),
                        Expanded(child: _buildNCChart()),
                      ],
                    )
                  else ...[
                    _buildMaterialChart(),
                    const SizedBox(height: 24),
                    _buildNCChart(),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required String title, required String subtitle, required Widget child}) {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1A1F36))),
          Text(subtitle, style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey[600])),
          const SizedBox(height: 24),
          Expanded(child: child),
        ],
      ),
    );
  }

  // 1. Severity Distribution (Stacked Bar)
  Widget _buildSeverityChart() {
    final groups = <BarChartGroupData>[];
    int index = 0;
    
    // Sort categories by total defects for better visualization
    final sortedKeys = _severityData.keys.toList()
      ..sort((a, b) {
        final totalA = _severityData[a]!.values.reduce((s, c) => s + c);
        final totalB = _severityData[b]!.values.reduce((s, c) => s + c);
        return totalB.compareTo(totalA);
      });

    // Take top 7 categories to prevent overcrowding
    final displayKeys = sortedKeys.take(7).toList();

    for (final key in displayKeys) {
      final data = _severityData[key]!;
      final cf = data['CF']?.toDouble() ?? 0;
      final mcf = data['MCF']?.toDouble() ?? 0;
      final aobs = data['Aobs']?.toDouble() ?? 0;

      groups.add(BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: cf + mcf + aobs,
            width: 20,
            borderRadius: BorderRadius.circular(4),
            rodStackItems: [
              BarChartRodStackItem(0, aobs, Colors.blueGrey.shade200),
              BarChartRodStackItem(aobs, aobs + mcf, Colors.orange),
              BarChartRodStackItem(aobs + mcf, aobs + mcf + cf, Colors.red),
            ],
          ),
        ],
      ));
      index++;
    }

    return _buildCard(
      title: 'Severity by Assembly',
      subtitle: 'Critical defects per component category',
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: GoogleFonts.outfit(fontSize: 10, color: Colors.grey))),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, meta) {
                  if (val.toInt() >= 0 && val.toInt() < displayKeys.length) {
                     return Padding(
                       padding: const EdgeInsets.only(top: 8.0),
                       child: Text(
                         displayKeys[val.toInt()].split(' ').first, // Shorten name
                         style: GoogleFonts.outfit(fontSize: 10, color: Colors.grey[700]),
                       ),
                     );
                  }
                  return const Text('');
                },
                interval: 1,
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withValues(alpha: 0.1), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: groups,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => Colors.blueGrey.shade900,
              getTooltipItem: (BarChartGroupData group, int groupIndex, BarChartRodData rod, int rodIndex) {
                 final key = displayKeys[groupIndex];
                 final data = _severityData[key]!;
                 return BarTooltipItem(
                   '$key\n',
                   GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                   children: [
                     TextSpan(text: 'CF: ${data['CF'] ?? 0}  ', style: const TextStyle(color: Colors.red)),
                     TextSpan(text: 'MCF: ${data['MCF'] ?? 0}  ', style: const TextStyle(color: Colors.orange)),
                     TextSpan(text: 'Obs: ${data['Aobs'] ?? 0}', style: TextStyle(color: Colors.blueGrey.shade200)),
                   ],
                 );
              },
            ),
          ),
        ),
      ),
    );
  }

  // 2. Root Cause Breakdown (Donut)
  Widget _buildRootCauseChart() {
    final List<PieChartSectionData> sections = [];
    final colors = [const Color(0xFF5E35B1), const Color(0xFF3949AB), const Color(0xFF1E88E5), const Color(0xFF039BE5), const Color(0xFF00ACC1)];
    
    int index = 0;
    final int total = _rootCauseData.values.fold(0, (a, b) => a + b);

    // Guard against division by zero
    if (total == 0) {
      return _buildCard(
        title: 'Root Cause Breakdown',
        subtitle: 'Primary reasons for failures',
        child: Center(
          child: Text('No root cause data', style: GoogleFonts.outfit(color: Colors.grey)),
        ),
      );
    }

    // Sort to show largest causes first
    final sortedEntries = _rootCauseData.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in sortedEntries) {
      final percentage = (entry.value / total) * 100;
      final isLarge = percentage > 10;
      
      sections.add(PieChartSectionData(
        color: colors[index % colors.length],
        value: entry.value.toDouble(),
        title: '${percentage.toStringAsFixed(1)}%',
        radius: isLarge ? 60 : 50,
        titleStyle: GoogleFonts.outfit(
          fontSize: isLarge ? 14 : 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ));
      index++;
    }

    return _buildCard(
      title: 'Root Cause Breakdown',
      subtitle: 'Primary reasons for failures',
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: sections,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: ListView.builder(
              itemCount: sortedEntries.length,
              itemBuilder: (context, i) {
                final entry = sortedEntries[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: colors[i % colors.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.key,
                          style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[700]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 3. Material Procurement (Horizontal Bar)
  Widget _buildMaterialChart() {
      // Sort logic: 'PI Need to Raise' first
      final keys = _materialData.keys.toList()
        ..sort((a, b) {
            if (a.contains('Need')) return -1;
            if (b.contains('Need')) return 1;
            return a.compareTo(b);
        });

      final groups = <BarChartGroupData>[];
      int index = 0;

      for (final key in keys) {
        groups.add(BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: _materialData[key]!.toDouble(),
              color: key.contains('Need') ? Colors.redAccent : Colors.green,
              width: 16,
              borderRadius: const BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4)), 
            ),
          ],
        ));
        index++;
      }

      if (groups.isEmpty) {
         return _buildCard(title: 'Material Procurement', subtitle: 'Spare parts status', child: Center(child: Text('No material requests', style: GoogleFonts.outfit(color: Colors.grey))));
      }

      return _buildCard(
        title: 'Material Pipeline',
        subtitle: 'Spare parts procurement status',
        child: RotatedBox(
          quarterTurns: 1, // Horizontal List
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceEvenly,
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 110,
                    interval: 1,
                    getTitlesWidget: (val, meta) {
                      if (val.toInt() >= 0 && val.toInt() < keys.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: RotatedBox(
                            quarterTurns: -1, 
                            child: SizedBox(
                              width: 100,
                              child: Text(
                                keys[val.toInt()], 
                                style: GoogleFonts.outfit(fontSize: 10),
                                overflow: TextOverflow.ellipsis, // Handle long names
                                maxLines: 1,
                              ),
                            ),
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), // Hide counts on axis
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              barGroups: groups,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => Colors.blueGrey.shade900,
                  rotateAngle: -90, // Fix tooltip rotation
                  getTooltipItem: (BarChartGroupData group, int groupIndex, BarChartRodData rod, int rodIndex) {
                     return BarTooltipItem(
                       '${keys[groupIndex]}: ${rod.toY.toInt()}',
                       GoogleFonts.outfit(color: Colors.white),
                     );
                  },
                ),
              ),
            ),
          ),
        ),
      );
  }

  // 4. NC Classification (Bar)
  Widget _buildNCChart() {
    final groups = <BarChartGroupData>[];
    int index = 0;
    
    final sortedKeys = _ncData.keys.toList();

    for (final key in sortedKeys) {
      groups.add(BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: _ncData[key]!.toDouble(),
            color: const Color(0xFF00897B),
            width: 24,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ));
      index++;
    }

    return _buildCard(
      title: 'NC Classification',
      subtitle: 'Workmanship vs Manufacturing Issues',
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: GoogleFonts.outfit(fontSize: 10, color: Colors.grey))),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, meta) {
                   if (val.toInt() >= 0 && val.toInt() < sortedKeys.length) {
                     return Padding(
                       padding: const EdgeInsets.only(top: 8.0),
                       child: Text(
                         sortedKeys[val.toInt()].split(' ').first, 
                         style: GoogleFonts.outfit(fontSize: 10),
                       ),
                     );
                   }
                   return const Text('');
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withValues(alpha: 0.1), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: groups,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => Colors.blueGrey.shade900,
              getTooltipItem: (BarChartGroupData group, int groupIndex, BarChartRodData rod, int rodIndex) {
                 return BarTooltipItem(
                   '${sortedKeys[groupIndex]}: ${rod.toY.toInt()}',
                   GoogleFonts.outfit(color: Colors.white),
                 );
              },
            ),
          ),
        ),
      ),
    );
  }
}
