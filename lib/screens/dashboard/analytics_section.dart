import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AnalyticsSection extends StatefulWidget {
  final String? auditorId;

  const AnalyticsSection({super.key, this.auditorId});

  @override
  State<AnalyticsSection> createState() => _AnalyticsSectionState();
}

class _AnalyticsSectionState extends State<AnalyticsSection> {
  bool _isLoading = true;
  Map<String, double> _siteCompliance = {};
  Map<String, int> _statusDistribution = {
    'approved': 0,
    'pending': 0,
    'correction': 0,
  };

  @override
  void initState() {
    super.initState();
    _fetchAnalyticsData();
  }

  Future<void> _fetchAnalyticsData() async {
    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('audit_submissions');
      
      // Filter by auditor if auditorId is provided
      if (widget.auditorId != null) {
        query = query.where('auditor_id', isEqualTo: widget.auditorId);
      }
      
      final snapshot = await query.get();
      
      final Map<String, Map<String, int>> siteStats = {};
      final Map<String, int> statusCounts = {
        'approved': 0,
        'pending': 0,
        'correction': 0,
      };

      for (var doc in snapshot.docs) {
        final data = doc.data();
        
        // Process Status Distribution
        String status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'approved') {
          statusCounts['approved'] = (statusCounts['approved'] ?? 0) + 1;
        } else if (status.contains('pending')) {
          statusCounts['pending'] = (statusCounts['pending'] ?? 0) + 1;
        } else if (status.contains('correction')) {
          statusCounts['correction'] = (statusCounts['correction'] ?? 0) + 1;
        }

        // Process Site Performance
        String siteName = (data['site'] ?? data['site_name'] ?? 'Unknown').toString();
        if (siteName.isEmpty) {
          siteName = 'Unknown';
        }
        
        if (!siteStats.containsKey(siteName)) {
          siteStats[siteName] = {'ok': 0, 'total': 0};
        }

        final auditData = data['audit_data'] as Map<String, dynamic>? ?? {};
        int ok = 0;
        int total = 0;

        auditData.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            final taskStatus = (value['status'] ?? '').toString().toLowerCase();
            if (taskStatus == 'ok') {
              ok++;
              total++;
            } else if (taskStatus == 'not ok' || taskStatus == 'not_ok') {
              total++;
            }
          }
        });

        siteStats[siteName]!['ok'] = (siteStats[siteName]!['ok'] ?? 0) + ok;
        siteStats[siteName]!['total'] = (siteStats[siteName]!['total'] ?? 0) + total;
      }

      // Calculate Compliance Rates
      final complianceRates = <String, double>{};
      siteStats.forEach((site, stats) {
        final total = stats['total'] ?? 0;
        if (total > 0) {
          complianceRates[site] = ((stats['ok'] ?? 0) / total) * 100;
        } else {
          complianceRates[site] = 0.0;
        }
      });

      if (mounted) {
        setState(() {
          _siteCompliance = complianceRates;
          _statusDistribution = statusCounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching analytics: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Graph: Site Performance (Bar Chart)
            Expanded(
              flex: 3,
              child: Container(
                height: 400,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Site Performance',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A1F36),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Compliance Rate by Site',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 32),
                    Expanded(
                      child: _siteCompliance.isEmpty
                          ? Center(child: Text('No data available', style: GoogleFonts.outfit(color: Colors.grey)))
                          : BarChart(
                              BarChartData(
                                alignment: BarChartAlignment.spaceAround,
                                maxY: 100,
                                barTouchData: BarTouchData(
                                  enabled: true,
                                  touchTooltipData: BarTouchTooltipData(
                                    getTooltipColor: (group) => Colors.blueGrey.shade900,
                                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                      String site = _siteCompliance.keys.elementAt(group.x.toInt());
                                      return BarTooltipItem(
                                        '$site\n',
                                        const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        children: <TextSpan>[
                                          TextSpan(
                                            text: '${rod.toY.toStringAsFixed(1)}%',
                                            style: const TextStyle(
                                              color: Colors.yellow,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                titlesData: FlTitlesData(
                                  show: true,
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (double value, TitleMeta meta) {
                                        if (value < 0 || value >= _siteCompliance.length) {
                                          return const SizedBox();
                                        }
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 8.0),
                                          child: Text(
                                            _siteCompliance.keys.elementAt(value.toInt()),
                                            style: GoogleFonts.outfit(
                                              color: Colors.grey[600],
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 40,
                                      getTitlesWidget: (value, meta) {
                                        return Text(
                                          '${value.toInt()}%',
                                          style: GoogleFonts.outfit(
                                            color: Colors.grey[400],
                                            fontSize: 12,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                ),
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  getDrawingHorizontalLine: (value) => FlLine(
                                    color: Colors.grey[100],
                                    strokeWidth: 1,
                                  ),
                                ),
                                borderData: FlBorderData(show: false),
                                barGroups: _siteCompliance.entries.toList().asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final value = entry.value.value;
                                  Color barColor = Colors.red;
                                  if (value > 80) {
                                    barColor = Colors.green;
                                  } else if (value > 50) {
                                    barColor = Colors.orange;
                                  }

                                  return BarChartGroupData(
                                    x: index,
                                    barRods: [
                                      BarChartRodData(
                                        toY: value,
                                        color: barColor,
                                        width: 20,
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                        backDrawRodData: BackgroundBarChartRodData(
                                          show: true,
                                          toY: 100,
                                          color: Colors.grey[100],
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),
            // Right Graph: Audit Status (Pie Chart)
            Expanded(
              flex: 2,
              child: Container(
                height: 400,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Audit Status',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A1F36),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Distribution by Status',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 32),
                    Expanded(
                      child: _statusDistribution.values.every((v) => v == 0)
                          ? Center(child: Text('No data available', style: GoogleFonts.outfit(color: Colors.grey)))
                          : Row(
                              children: [
                                Expanded(
                                  child: PieChart(
                                    PieChartData(
                                      sectionsSpace: 2,
                                      centerSpaceRadius: 40,
                                      sections: [
                                        _buildPieSection(
                                          'Approved',
                                          _statusDistribution['approved']!.toDouble(),
                                          Colors.green,
                                        ),
                                        _buildPieSection(
                                          'Pending',
                                          _statusDistribution['pending']!.toDouble(),
                                          Colors.orange,
                                        ),
                                        _buildPieSection(
                                          'Correction',
                                          _statusDistribution['correction']!.toDouble(),
                                          Colors.red,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 24),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildLegendItem('Approved', Colors.green, _statusDistribution['approved']!),
                                    const SizedBox(height: 12),
                                    _buildLegendItem('Pending', Colors.orange, _statusDistribution['pending']!),
                                    const SizedBox(height: 12),
                                    _buildLegendItem('Correction', Colors.red, _statusDistribution['correction']!),
                                  ],
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  PieChartSectionData _buildPieSection(String title, double value, Color color) {
    return PieChartSectionData(
      color: color,
      value: value,
      title: value > 0 ? '${value.toInt()}' : '',
      radius: 50,
      titleStyle: GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, int count) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 14,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '($count)',
          style: GoogleFonts.outfit(
            fontSize: 14,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }
}
