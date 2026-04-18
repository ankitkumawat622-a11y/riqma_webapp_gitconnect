import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:riqma_webapp/screens/activity_log_screen.dart';
import 'package:riqma_webapp/screens/analytics/analytics_screen.dart';
import 'package:riqma_webapp/screens/audit_reports_screen.dart';
import 'package:riqma_webapp/screens/dashboard/main_dashboard_screen.dart';
import 'package:riqma_webapp/screens/manage_data_screen.dart';
import 'package:riqma_webapp/screens/planning_screen.dart';
import 'package:riqma_webapp/screens/user_management_screen.dart';
import 'package:riqma_webapp/services/activity_log_service.dart';
import 'package:riqma_webapp/services/theme_service.dart';
import 'package:riqma_webapp/widgets/modern_searchable_dropdown.dart';
class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;
  bool _isSidebarCollapsed = false;
  String? _auditStatusFilter;

  // Analytics State Lifted Up
  String? _analyticsSelectedState;
  String? _analyticsSelectedSite;
  Set<String> _analyticsAvailableStates = {};
  Map<String, List<String>> _analyticsSitesByState = {};

  void _onDashboardNavigate(int index, String? statusFilter) {
    setState(() {
      _selectedIndex = index;
      _auditStatusFilter = statusFilter;
    });
  }

  void _onAnalyticsFiltersLoaded(Set<String> states, Map<String, List<String>> sitesMap) {
    // Only update if changed to avoid loops
    if (_analyticsAvailableStates.length != states.length || 
        _analyticsSitesByState.length != sitesMap.length) {
        setState(() {
          _analyticsAvailableStates = states;
          _analyticsSitesByState = sitesMap;
        });
    }
  }

  List<Widget> get _screens => [
    MainDashboardScreen(onNavigateToTab: _onDashboardNavigate),
    AuditReportsScreen(initialStatusFilter: _auditStatusFilter),
    const PlanningScreen(),
    const ManageDataScreen(),
    const UserManagementScreen(),
    AnalyticsScreen(
      selectedState: _analyticsSelectedState,
      selectedSite: _analyticsSelectedSite,
      onFiltersLoaded: _onAnalyticsFiltersLoaded,
    ),
    const ActivityLogScreen(),
  ];

  final List<String> _titles = [
    'Dashboard',
    'Audit Reports',
    'Planning',
    'Manage Data',
    'Manage Users',
    'Analytics',
    'Activity Log',
  ];

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Confirm Logout',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to logout?',
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.outfit()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A1F36),
              foregroundColor: Colors.white,
            ),
            child: Text('Logout', style: GoogleFonts.outfit()),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Log logout before signing out
        await ActivityLogService.instance.log(
          actionType: ActivityActionType.logout, 
          description: 'User logged out manually',
        );
        ActivityLogService.instance.clearCache(); // clear cache
        
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error logging out: $e', style: GoogleFonts.outfit()),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine sites for dropdown based on selection
    final sites = (_analyticsSelectedState != null && 
                   _analyticsSelectedState != 'All States' && 
                   _analyticsSitesByState.containsKey(_analyticsSelectedState)) 
        ? _analyticsSitesByState[_analyticsSelectedState]! 
        : _analyticsSitesByState.values.expand((element) => element).toSet().toList()..sort();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseAuth.instance.currentUser?.uid != null
          ? FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).snapshots()
          : null,
      builder: (context, userSnapshot) {
        String role = 'auditor';
        String displayName = 'Admin User';
        if (userSnapshot.hasData && userSnapshot.data!.exists) {
           final data = userSnapshot.data!.data() as Map<String, dynamic>?;
           role = data?['role']?.toString() ?? 'auditor';
           final userName = data?['name']?.toString();
           final userEmail = data?['email']?.toString();
           displayName = userName ?? userEmail?.split('@').first ?? 'User';
        }
        final bool isAuditor = (role == 'auditor');

        return Scaffold(
          body: Row(
            children: [
          // Sidebar
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: _isSidebarCollapsed ? 80 : 260,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.light
                  ? const Color(0xFFE3F2FD).withValues(alpha: 0.8)
                  : const Color(0xFF1A1F36).withValues(alpha: 0.8),
              border: Border(
                right: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Column(
                  children: [
                    // Logo Area
                    Container(
                      height: 80,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _isSidebarCollapsed
                          ? Image.asset(
                              'assets/images/riqma_logo.png',
                              height: 32,
                              fit: BoxFit.contain,
                            )
                          : SvgPicture.asset(
                              'assets/images/renom_logo.svg',
                              height: 40,
                              fit: BoxFit.contain,
                            ),
                    ),
                    Divider(color: Theme.of(context).dividerColor.withValues(alpha: 0.1), height: 1),
                    const SizedBox(height: 20),
                    // Navigation Items
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          _buildNavItem(0, Icons.dashboard_rounded, 'Dashboard'),
                          _buildNavItem(1, Icons.table_chart_rounded, 'Audit Reports'),
                          _buildNavItem(2, Icons.calendar_month_rounded, 'Planning'),
                          if (!isAuditor) _buildNavItem(3, Icons.storage_rounded, 'Manage Data'),
                          if (!isAuditor) _buildNavItem(4, Icons.people_rounded, 'Manage Users'),
                          _buildNavItem(5, Icons.analytics_rounded, 'Analytics'),
                          _buildNavItem(6, Icons.history_rounded, 'Activity Log'),
                        ],
                      ),
                    ),
                    // Collapse Button
                    IconButton(
                      icon: Icon(
                        _isSidebarCollapsed
                            ? Icons.keyboard_double_arrow_right_rounded
                            : Icons.keyboard_double_arrow_left_rounded,
                        color: Theme.of(context).brightness == Brightness.light
                            ? const Color(0xFF0277BD)
                            : Colors.blue[200],
                        size: 24,
                      ),
                      onPressed: () {
                        setState(() {
                          _isSidebarCollapsed = !_isSidebarCollapsed;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
          // Main Content
          Expanded(
            child: Column(
              children: [
                // Top Bar - Hide for Manage Data (3) and Manage Users (4)
                if (_selectedIndex != 3 && _selectedIndex != 4)
                  ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        height: 70,
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor.withValues(alpha: 0.7),
                          border: Border(
                            bottom: BorderSide(
                              color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Breadcrumbs
                            Icon(Icons.home_rounded, color: Colors.grey[400], size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '/',
                              style: GoogleFonts.outfit(color: Colors.grey[400], fontSize: 16),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _titles[_selectedIndex],
                              style: GoogleFonts.outfit(
                                color: Theme.of(context).textTheme.titleLarge?.color,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_selectedIndex == 5) ...[
                               const SizedBox(width: 40),
                               Expanded(
                                 child: Row(
                                   children: [
                                      Expanded(
                                        child: ModernSearchableDropdown(
                                          label: 'State',
                                          value: _analyticsSelectedState != 'All States' ? _analyticsSelectedState : null,
                                          items: {
                                            'All States': 'All States',
                                            for (final s in _analyticsAvailableStates) s: s,
                                          },
                                          color: Colors.blue,
                                          icon: Icons.map_rounded,
                                          onChanged: (val) {
                                            setState(() {
                                              _analyticsSelectedState = val;
                                              _analyticsSelectedSite = null;
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: ModernSearchableDropdown(
                                          label: 'Site',
                                          value: _analyticsSelectedSite != 'All Sites' ? _analyticsSelectedSite : null,
                                          items: {
                                            'All Sites': 'All Sites',
                                            for (final s in sites) s: s,
                                          },
                                          color: Colors.teal,
                                          icon: Icons.location_city_rounded,
                                          onChanged: (val) => setState(() => _analyticsSelectedSite = val),
                                        ),
                                      ),
                                   ],
                                 ),
                               ),
                               const SizedBox(width: 40),
                            ] else 
                               const Spacer(),
                            // Audit Submission Rules (Manager Only)
                            if (!isAuditor) ...[
                              _buildModernHeaderButton(
                                icon: Icons.rule_rounded,
                                tooltip: 'Audit Submission Rules',
                                onPressed: () => _showValidationRulesDialog(context),
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 12),
                            ],
                            // Theme Toggle
                            _buildThemeToggle(),
                            const SizedBox(width: 20),
                            // User Profile & Logout Section
                            _buildUserAndLogout(displayName, context),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Screen Content - Use less padding for Manage Data and Manage Users
                Expanded(
                  child: Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    padding: _selectedIndex == 3
                        ? const EdgeInsets.fromLTRB(16, 0, 16, 16)
                        : (_selectedIndex == 4
                            ? const EdgeInsets.all(16)
                            : const EdgeInsets.all(32)),
                    child: _screens[_selectedIndex],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
        },
    );
  }

  Future<void> _showValidationRulesDialog(BuildContext context) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('audit_configs').doc('submission_rules').get();
      final Map<String, dynamic> currentRules = doc.exists ? doc.data() as Map<String, dynamic> : {};

      if (!context.mounted) return;

      unawaited(showDialog<void>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              Widget buildRuleSwitch(String key, String title, String subtitle) {
                return SwitchListTile(
                  title: Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(subtitle, style: GoogleFonts.outfit(fontSize: 12)),
                  value: currentRules[key] as bool? ?? false,
                  activeThumbColor: Colors.blue[700],
                  onChanged: (val) {
                    setStateDialog(() {
                      currentRules[key] = val;
                    });
                  },
                );
              }

              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Row(
                  children: [
                    const Icon(Icons.gavel_rounded, color: Colors.blue),
                    const SizedBox(width: 12),
                    Text('Submission Validation Rules', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  ],
                ),
                content: SizedBox(
                  width: 500,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                         buildRuleSwitch('mandatory_nc_category', 'NC Category', 'Require selection for Not OK tasks'),
                         buildRuleSwitch('mandatory_action_plan', 'Action Plan Remark', 'Require remark for Not OK tasks'),
                         buildRuleSwitch('mandatory_root_cause', 'Root Cause', 'Require root cause for Not OK tasks'),
                         buildRuleSwitch('mandatory_plan_date', 'Plan Date (Target Date)', 'Require target date for Not OK tasks'),
                         buildRuleSwitch('mandatory_pi_status', 'PI Status & Number', 'Require PI details for material related issues'),
                         buildRuleSwitch('mandatory_observation', 'Observation/NC Summary', 'Require observation text for Not OK tasks'),
                         buildRuleSwitch('mandatory_sub_status', 'Sub Status', 'Require sub-status selection (Aobs, MCF, CF)'),
                         buildRuleSwitch('mandatory_reference', 'Reference', 'Require reference selection'),
                         buildRuleSwitch('mandatory_photos', 'Photos', 'Require at least one photo per Not OK task'),
                         const Divider(),
                         buildRuleSwitch('force_date_takeover_less_than_plan', 'Take Over < Plan Date', 'Ensure Date of Take Over is before Plan Date of Maintenance'),
                         buildRuleSwitch('force_date_actual_greater_than_takeover', 'Actual Date > Take Over', 'Ensure Actual Date of Maintenance is after Date of Take Over'),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: GoogleFonts.outfit()),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      await FirebaseFirestore.instance.collection('audit_configs').doc('submission_rules').set(currentRules);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Validation rules updated successfully', style: GoogleFonts.outfit()), backgroundColor: Colors.green),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1F36),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Save Changes', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  ),
                ],
              );
            },
          );
        },
      ));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading rules: $e', style: GoogleFonts.outfit()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildNavItem(int index, IconData icon, String title) {
    final isSelected = _selectedIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedIndex = index;
              _auditStatusFilter = null;
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              vertical: 12,
              horizontal: _isSidebarCollapsed ? 0 : 16,
            ),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      colors: isDark
                          ? [Colors.blue[900]!.withValues(alpha: 0.3), Colors.blue[800]!.withValues(alpha: 0.1)]
                          : [const Color(0xFF0277BD).withValues(alpha: 0.1), const Color(0xFF0277BD).withValues(alpha: 0.02)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(
                      color: (isDark ? (Colors.blue[400] ?? Colors.blue) : const Color(0xFF0277BD)).withValues(alpha: 0.2),
                      width: 1,
                    )
                  : null,
            ),
            child: _isSidebarCollapsed
                ? Center(
                    child: Icon(
                      icon,
                      color: isSelected 
                          ? (isDark ? Colors.blue[300] : const Color(0xFF0277BD)) 
                          : (isDark ? Colors.blueGrey[200] : Colors.blueGrey.shade800),
                      size: 24,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Icon(
                        icon,
                        color: isSelected 
                            ? (isDark ? Colors.blue[300] : const Color(0xFF0277BD)) 
                            : (isDark ? Colors.blueGrey[200] : Colors.blueGrey.shade800),
                        size: 24,
                      ),
                      const SizedBox(width: 16),
                      Flexible(
                        child: Text(
                          title,
                          style: GoogleFonts.outfit(
                            color: isSelected 
                                ? (isDark ? Colors.blue[300] : const Color(0xFF0277BD)) 
                                : (isDark ? Colors.blueGrey[200] : Colors.blueGrey.shade800),
                            fontSize: 15,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernHeaderButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, color: isDark ? color.withValues(alpha: 0.9) : color.withValues(alpha: 0.8), size: 20),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildThemeToggle() {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final themeMode = ThemeService.instance.themeMode;
        IconData icon;
        Color iconColor;
        String tooltip;

        switch (themeMode) {
          case ThemeMode.light:
            icon = Icons.light_mode_rounded;
            iconColor = Colors.amber[600]!;
            tooltip = 'Switch to Dark Mode';
            break;
          case ThemeMode.dark:
            icon = Icons.dark_mode_rounded;
            iconColor = Colors.indigo[300]!;
            tooltip = 'Switch to System Mode';
            break;
          default:
            icon = Icons.settings_brightness_rounded;
            iconColor = Colors.teal[400]!;
            tooltip = 'Switch to Light Mode';
        }

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light
                ? Colors.grey[100]
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return ScaleTransition(scale: animation, child: FadeTransition(opacity: animation, child: child));
              },
              child: Icon(
                icon,
                key: ValueKey<ThemeMode>(themeMode),
                color: iconColor,
                size: 20,
              ),
            ),
            onPressed: () => ThemeService.instance.toggleTheme(),
            tooltip: tooltip,
          ),
        );
      },
    );
  }

  Widget _buildUserAndLogout(String displayName, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // User Name (Left of Logout)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey[200]!,
            ),
          ),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [const Color(0xFF1A1F36), Colors.blue[900]!],
                  ),
                ),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.transparent,
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                displayName,
                style: GoogleFonts.outfit(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Animated Logout Button
        _AnimatedLogoutButton(onPressed: () => _handleLogout(context)),
      ],
    );
  }
}

class _AnimatedLogoutButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _AnimatedLogoutButton({required this.onPressed});

  @override
  State<_AnimatedLogoutButton> createState() => _AnimatedLogoutButtonState();
}

class _AnimatedLogoutButtonState extends State<_AnimatedLogoutButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        transform: Matrix4.diagonal3Values(_isHovered ? 1.05 : 1.0, _isHovered ? 1.05 : 1.0, 1.0),
        decoration: BoxDecoration(
          color: _isHovered ? Colors.red[600] : Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          boxShadow: _isHovered ? [
            BoxShadow(color: Colors.red.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))
          ] : [],
        ),
        child: IconButton(
          icon: Icon(
            Icons.logout_rounded,
            color: _isHovered ? Colors.white : Colors.red[600],
            size: 20,
          ),
          onPressed: widget.onPressed,
          tooltip: 'Logout',
        ),
      ),
    );
  }
}
