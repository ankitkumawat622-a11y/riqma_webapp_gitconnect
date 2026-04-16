import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('audit_submissions').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Something went wrong', style: GoogleFonts.outfit(color: Colors.red)));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        final totalAudits = docs.length;

        // Calculate metrics
        int pendingIssues = 0;
        int totalTasks = 0;
        int okTasks = 0;
        final Set<String> activeSites = {};
        final Map<String, int> auditsPerMonth = {};

        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final site = data['site'] as String? ?? 'Unknown';
          activeSites.add(site);

          final timestamp = data['timestamp'] as Timestamp?;
          if (timestamp != null) {
            final date = timestamp.toDate();
            final monthKey = DateFormat('MMM').format(date);
            auditsPerMonth[monthKey] = (auditsPerMonth[monthKey] ?? 0) + 1;
          }

          final auditData = data['audit_data'] as Map<String, dynamic>? ?? {};
          auditData.forEach((key, value) {
            final task = value as Map<String, dynamic>;
            final status = task['status'];
            totalTasks++;
            if (status == 'Ok') {
              okTasks++;
            } else if (status == 'Not Ok') {
              pendingIssues++;
            }
          });
        }

        final complianceRate = totalTasks > 0 ? (okTasks / totalTasks) * 100 : 0.0;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dashboard Overview',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1F36),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Real-time insights and performance metrics',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 32),
              // Header Cards
              Row(
                children: [
                  _buildStatCard(
                    'Total Audits',
                    totalAudits.toString(),
                    Icons.assignment_turned_in_rounded,
                    [const Color(0xFF4facfe), const Color(0xFF00f2fe)],
                  ),
                  _buildStatCard(
                    'Pending Issues',
                    pendingIssues.toString(),
                    Icons.warning_amber_rounded,
                    [const Color(0xFFff9a9e), const Color(0xFFfecfef)],
                    textColor: const Color(0xFFD32F2F),
                  ),
                  _buildStatCard(
                    'Compliance Rate',
                    '${complianceRate.toStringAsFixed(1)}%',
                    Icons.verified_user_rounded,
                    [const Color(0xFF43e97b), const Color(0xFF38f9d7)],
                    textColor: const Color(0xFF1B5E20),
                  ),
                  _buildStatCard(
                    'Active Sites',
                    activeSites.length.toString(),
                    Icons.location_on_rounded,
                    [const Color(0xFF667eea), const Color(0xFF764ba2)],
                  ),
                ],
              ),
              const SizedBox(height: 32),
              // Charts Section
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildChartContainer(
                      'Audits per Month',
                      _buildBarChart(auditsPerMonth),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 1,
                    child: _buildChartContainer(
                      'Overall Compliance',
                      _buildPieChart(okTasks, pendingIssues),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildChartContainer(
                'Defect Trend (Last 6 Weeks)',
                _buildLineChart(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, List<Color> gradientColors, {Color? textColor}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: gradientColors.first.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                // Optional trend indicator could go here
              ],
            ),
            const SizedBox(height: 20),
            Text(
              value,
              style: GoogleFonts.outfit(
                color: textColor ?? const Color(0xFF1A1F36),
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: GoogleFonts.outfit(
                color: Colors.grey[500],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartContainer(String title, Widget chart) {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
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
            title,
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A1F36),
            ),
          ),
          const SizedBox(height: 32),
          Expanded(child: chart),
        ],
      ),
    );
  }

  Widget _buildBarChart(Map<String, int> data) {
    if (data.isEmpty) {
      return Center(child: Text('No data available', style: GoogleFonts.outfit(color: Colors.grey)));
    }

    final List<BarChartGroupData> barGroups = [];
    int index = 0;
    data.forEach((key, value) {
      barGroups.add(
        BarChartGroupData(
          x: index++,
          barRods: [
            BarChartRodData(
              toY: value.toDouble(),
              gradient: const LinearGradient(
                colors: [Color(0xFF4facfe), Color(0xFF00f2fe)],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
              width: 24,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: 20, // Max Y
                color: const Color(0xFFF0F2F5),
              ),
            ),
          ],
        ),
      );
    });

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 20,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => const Color(0xFF1A1F36),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${rod.toY.toInt()}',
                GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
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
                if (value.toInt() < data.keys.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      data.keys.elementAt(value.toInt()),
                      style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  );
                }
                return const Text('');
              },
              reservedSize: 40,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: GoogleFonts.outfit(color: Colors.grey[400], fontSize: 12),
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
            color: Colors.grey[200],
            strokeWidth: 1,
            dashArray: [5, 5],
          ),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _buildPieChart(int ok, int notOk) {
    if (ok == 0 && notOk == 0) {
      return Center(child: Text('No data', style: GoogleFonts.outfit(color: Colors.grey)));
    }

    return PieChart(
      PieChartData(
        sectionsSpace: 4,
        centerSpaceRadius: 50,
        sections: [
          PieChartSectionData(
            color: const Color(0xFF43e97b),
            value: ok.toDouble(),
            title: '${((ok / (ok + notOk)) * 100).toStringAsFixed(0)}%',
            radius: 60,
            titleStyle: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            badgeWidget: _buildBadge(Icons.check_circle, const Color(0xFF43e97b)),
            badgePositionPercentageOffset: .98,
          ),
          PieChartSectionData(
            color: const Color(0xFFff9a9e),
            value: notOk.toDouble(),
            title: '${((notOk / (ok + notOk)) * 100).toStringAsFixed(0)}%',
            radius: 60,
            titleStyle: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            badgeWidget: _buildBadge(Icons.warning, const Color(0xFFff9a9e)),
            badgePositionPercentageOffset: .98,
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 6,
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 16),
    );
  }

  Widget _buildLineChart() {
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey[200],
            strokeWidth: 1,
            dashArray: [5, 5],
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
             sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'W${value.toInt() + 1}',
                      style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 12),
                    ),
                  );
                },
             )
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: GoogleFonts.outfit(color: Colors.grey[400], fontSize: 12),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: 6,
        minY: 0,
        maxY: 10,
        lineBarsData: [
          LineChartBarData(
            spots: const [
              FlSpot(0, 3),
              FlSpot(1, 1),
              FlSpot(2, 4),
              FlSpot(3, 2),
              FlSpot(4, 5),
              FlSpot(5, 1),
              FlSpot(6, 0),
            ],
            isCurved: true,
            gradient: const LinearGradient(
              colors: [Color(0xFFff9a9e), Color(0xFFfecfef)],
            ),
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 4,
                  color: Colors.white,
                  strokeWidth: 2,
                  strokeColor: const Color(0xFFff9a9e),
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFff9a9e).withValues(alpha: 0.3),
                  const Color(0xFFfecfef).withValues(alpha: 0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
