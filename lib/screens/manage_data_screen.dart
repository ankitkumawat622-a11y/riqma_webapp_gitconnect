import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:riqma_webapp/screens/manage/main_categories_view.dart';
import 'package:riqma_webapp/screens/manage/nc_categories_view.dart';
import 'package:riqma_webapp/screens/manage/others_config_view.dart';
import 'package:riqma_webapp/screens/manage/reference_management_screen.dart';
import 'package:riqma_webapp/screens/manage/root_causes_view.dart';
import 'package:riqma_webapp/screens/manage/sites_view.dart';
import 'package:riqma_webapp/screens/manage/states_view.dart';
import 'package:riqma_webapp/screens/manage/sub_categories_view.dart';
import 'package:riqma_webapp/screens/manage/tasks_view.dart';
import 'package:riqma_webapp/screens/manage/turbine_models_view.dart';
import 'package:riqma_webapp/screens/manage/turbines_view.dart';
class ManageDataScreen extends StatelessWidget {
  const ManageDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 11,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Enhanced Tab Bar with icons
          Container(
            margin: const EdgeInsets.only(left: 8, right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.light ? 0.08 : 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TabBar(
              isScrollable: true,
              labelColor: const Color(0xFF0277BD),
              unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color,
              indicatorSize: TabBarIndicatorSize.label,
              indicator: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Color(0xFF0277BD),
                    width: 3,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              labelPadding: const EdgeInsets.symmetric(horizontal: 16),
              labelStyle: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              tabs: [
                _buildTab(Icons.map_outlined, 'States'),
                _buildTab(Icons.location_on_outlined, 'Sites'),
                _buildTab(Icons.settings_outlined, 'Models'),
                _buildTab(Icons.wind_power_outlined, 'Turbines'),
                _buildTab(Icons.category_outlined, 'Main Categories'),
                _buildTab(Icons.segment_outlined, 'Sub Categories'),
                _buildTab(Icons.task_alt_outlined, 'Tasks'),
                _buildTab(Icons.bookmark_outline, 'References'),
                _buildTab(Icons.settings_suggest_outlined, 'Others'),
                _buildTab(Icons.report_problem_outlined, 'NC Categories'),
                _buildTab(Icons.analytics_outlined, 'Root Causes'),
              ],
            ),
          ),
          // Tab Views
          const Expanded(
            child: TabBarView(
              children: [
                StatesView(),
                SitesView(),
                TurbineModelsView(),
                TurbinesView(),
                MainCategoriesView(),
                SubCategoriesView(),
                TasksView(),
                ReferenceManagementScreen(),
                OthersConfigView(),
                NCCategoriesView(),
                RootCausesView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTab(IconData icon, String title) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(title),
        ],
      ),
    );
  }
}
