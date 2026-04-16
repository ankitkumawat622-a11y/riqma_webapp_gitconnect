import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:riqma_webapp/services/activity_log_service.dart';
import 'package:riqma_webapp/widgets/modern_searchable_dropdown.dart';

/// Activity Log Screen with role-based views
/// - Auditor: Sees only their own logs
/// - Manager: Sees all logs with filtering options
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  String? _userRole;
  bool _isLoading = true;

  // Filters (Manager only)
  String? _selectedUserId;
  ActivityActionType? _selectedActionType;
  List<Map<String, String>> _usersList = [];

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists) {
          setState(() {
            _userRole = doc.data()?['role'] as String? ?? 'auditor';
            _isLoading = false;
          });

          // If manager, load users list for filter
          if (_userRole == 'manager' || _userRole == 'admin') {
            unawaited(_loadUsersList());
          }
        } else {
          setState(() {
            _userRole = 'auditor';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading user role: $e');
      setState(() {
        _userRole = 'auditor';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUsersList() async {
    final users = await ActivityLogService.instance.getLoggedUsers();
    setState(() {
      _usersList = users;
    });
  }

  Query<Map<String, dynamic>> _getQuery() {
    if (_userRole == 'manager' || _userRole == 'admin') {
      return ActivityLogService.instance.getAllLogsQuery(
        filterByUserId: _selectedUserId,
        filterByActionType: _selectedActionType,
      );
    } else {
      return ActivityLogService.instance.getMyLogsQuery();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final isManager = _userRole == 'manager' || _userRole == 'admin';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Compact Header & Filters Bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              if (isManager) ...[
                // User Filter
                Expanded(
                  flex: 2,
                  child: ModernSearchableDropdown(
                    label: 'User',
                    value: _selectedUserId,
                    items: {
                      for (var user in _usersList) user['userId']!: user['userName']!
                    },
                    color: Colors.blue,
                    icon: Icons.person_rounded,
                    onChanged: (val) => setState(() => _selectedUserId = val),
                  ),
                ),
                const SizedBox(width: 12),
                // Action Filter
                Expanded(
                  flex: 3,
                  child: ModernSearchableDropdown(
                    label: 'Action',
                    value: _selectedActionType?.name, // Use name for value mapping key
                    items: {
                      for (var type in ActivityActionType.values) type.name: type.displayName
                    },
                    color: Colors.purple,
                    icon: Icons.category_rounded,
                    onChanged: (val) {
                      setState(() {
                         // Find enum by name
                         _selectedActionType = val != null 
                             ? ActivityActionType.values.firstWhere((e) => e.name == val)
                             : null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Clear Filters
                if (_selectedUserId != null || _selectedActionType != null)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                         setState(() {
                           _selectedUserId = null;
                           _selectedActionType = null;
                         });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red[100]!),
                        ),
                        child: Icon(Icons.refresh_rounded, color: Colors.red[400], size: 20),
                      ),
                    ),
                  ),
                 const Spacer(),
              ],
              
              if (!isManager) const Spacer(),

              // Subtitle/Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isManager 
                        ? [Colors.purple[50]!, Colors.deepPurple[50]!]
                        : [Colors.blue[50]!, Colors.lightBlue[50]!],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: isManager ? Colors.purple[100]! : Colors.blue[100]!,
                  ),
                  boxShadow: [
                    BoxShadow(
                      // ignore: deprecated_member_use
                      color: (isManager ? Colors.purple : Colors.blue).withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isManager ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                      size: 16,
                      color: isManager ? Colors.purple[700] : Colors.blue[700],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isManager ? 'Manager View' : 'My Activity',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isManager ? Colors.purple[800] : Colors.blue[800],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 24, indent: 16, endIndent: 16),

        // Activity List
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _getQuery().limit(200).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading logs',
                        style: GoogleFonts.outfit(color: Colors.red[700]),
                      ),
                      Text(
                        '${snapshot.error}',
                        style: GoogleFonts.robotoCondensed(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.inbox_rounded, size: 64, color: Colors.grey[300]),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No activity logs found',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: docs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final entry = ActivityLogEntry.fromFirestore(docs[index]);
                  return _buildLogTile(entry, isManager);
                },
              );
            },
          ),
        ),
      ],
    );
  }


  Widget _buildLogTile(ActivityLogEntry entry, bool showUserName) {
    final colorScheme = _getColorScheme(entry.actionType);
    final icon = _getActionIcon(entry.actionType);
    
    String formattedTime;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToCheck = DateTime(entry.timestamp.year, entry.timestamp.month, entry.timestamp.day);

    if (dateToCheck == today) {
      formattedTime = 'Today, ${DateFormat('hh:mm a').format(entry.timestamp)}';
    } else if (dateToCheck == yesterday) {
      formattedTime = 'Yesterday, ${DateFormat('hh:mm a').format(entry.timestamp)}';
    } else {
      formattedTime = DateFormat('dd MMM, hh:mm a').format(entry.timestamp);
    }

    return HoverLogTile(
      gradientColors: colorScheme['gradient'] as List<Color>,
      borderColor: colorScheme['border'] as Color,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              // ignore: deprecated_member_use
              color: Colors.white.withValues(alpha: 0.6),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  // ignore: deprecated_member_use
                  color: (colorScheme['icon'] as Color).withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: colorScheme['icon'] as Color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.description,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1F36), // Deep Slate instead of Black
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded, size: 12, color: Colors.blueGrey),
                    const SizedBox(width: 4),
                    Text(
                      formattedTime,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.blueGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (showUserName) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          // ignore: deprecated_member_use
                          color: Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          // ignore: deprecated_member_use
                          border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person_outline_rounded, size: 12, color: Colors.blueGrey),
                            const SizedBox(width: 4),
                            Text(
                              entry.userName,
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: Colors.blueGrey[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: colorScheme['badge'] as Color,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                // ignore: deprecated_member_use
                color: (colorScheme['badgeText'] as Color).withValues(alpha: 0.2),
              ),
              boxShadow: [
                BoxShadow(
                  // ignore: deprecated_member_use
                  color: (colorScheme['badge'] as Color).withValues(alpha: 0.4),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              entry.actionType.displayName,
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme['badgeText'] as Color,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getColorScheme(ActivityActionType actionType) {
    switch (actionType) {
      case ActivityActionType.login:
      case ActivityActionType.logout:
        return {
          'border': const Color(0xFF90CAF9),
          'gradient': [const Color(0xFFE3F2FD), const Color(0xFFBBDEFB)],
          'icon': const Color(0xFF1565C0),
          'badge': const Color(0xFFE3F2FD),
          'badgeText': const Color(0xFF1565C0),
        };
      case ActivityActionType.auditSubmit: // Changed to Blue/Indigo
        return {
          'border': const Color(0xFF7986CB),
          'gradient': [const Color(0xFFE8EAF6), const Color(0xFFC5CAE9)],
          'icon': const Color(0xFF283593),
          'badge': const Color(0xFFE8EAF6),
          'badgeText': const Color(0xFF283593),
        };
      case ActivityActionType.reportApprove:
      case ActivityActionType.syncData:
        return {
          'border': const Color(0xFFA5D6A7),
          'gradient': [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)],
          'icon': const Color(0xFF2E7D32),
          'badge': const Color(0xFFE8F5E9),
          'badgeText': const Color(0xFF2E7D32),
        };
      case ActivityActionType.auditSubmitFailed:
      case ActivityActionType.error:
      case ActivityActionType.reportReject:
        return {
          'border': const Color(0xFFEF9A9A),
          'gradient': [const Color(0xFFFFEBEE), const Color(0xFFFFCDD2)],
          'icon': const Color(0xFFC62828),
          'badge': const Color(0xFFFFEBEE),
          'badgeText': const Color(0xFFC62828),
        };
      case ActivityActionType.auditStart: // Orange/Amber
      case ActivityActionType.userCreate:
      case ActivityActionType.userEdit:
      case ActivityActionType.masterDataEdit:
        return {
          'border': const Color(0xFFFFCC80),
          'gradient': [const Color(0xFFFFF3E0), const Color(0xFFFFE0B2)],
          'icon': const Color(0xFFEF6C00),
          'badge': const Color(0xFFFFF3E0),
          'badgeText': const Color(0xFFEF6C00),
        };
      case ActivityActionType.planAdd: // Teal/Purple
        return {
          'border': const Color(0xFF80CBC4),
          'gradient': [const Color(0xFFE0F2F1), const Color(0xFFB2DFDB)],
          'icon': const Color(0xFF00695C),
          'badge': const Color(0xFFE0F2F1),
          'badgeText': const Color(0xFF00695C),
        };
      case ActivityActionType.unknown: // Grey
        return {
          'border': const Color(0xFFBDBDBD),
          'gradient': [const Color(0xFFF5F5F5), const Color(0xFFEEEEEE)],
          'icon': const Color(0xFF616161),
          'badge': const Color(0xFFF5F5F5),
          'badgeText': const Color(0xFF616161),
        };
    }
  }

  IconData _getActionIcon(ActivityActionType actionType) {
    switch (actionType) {
      case ActivityActionType.login:
        return Icons.login_rounded;
      case ActivityActionType.logout:
        return Icons.logout_rounded;
      case ActivityActionType.syncData:
        return Icons.sync_rounded;
      case ActivityActionType.auditStart:
        return Icons.play_circle_outline_rounded;
      case ActivityActionType.auditSubmit:
        return Icons.assignment_turned_in_outlined; // Changed Icon
      case ActivityActionType.auditSubmitFailed:
        return Icons.error_outline_rounded;
      case ActivityActionType.reportApprove:
        return Icons.thumb_up_alt_outlined;
      case ActivityActionType.reportReject:
        return Icons.thumb_down_alt_outlined;
      case ActivityActionType.userCreate:
        return Icons.person_add_alt_1_rounded;
      case ActivityActionType.userEdit:
        return Icons.edit_rounded;
      case ActivityActionType.masterDataEdit:
        return Icons.storage_rounded;
      case ActivityActionType.planAdd:
        return Icons.calendar_today_outlined;
      case ActivityActionType.error:
        return Icons.warning_amber_rounded;
      case ActivityActionType.unknown:
        return Icons.help_outline_rounded;
    }
  }
}

class HoverLogTile extends StatefulWidget {
  final Widget child;
  final List<Color> gradientColors;
  final Color borderColor;
  final VoidCallback? onTap;

  const HoverLogTile({
    super.key,
    required this.child,
    required this.gradientColors,
    required this.borderColor,
    this.onTap,
  });

  @override
  State<HoverLogTile> createState() => _HoverLogTileState();
}

class _HoverLogTileState extends State<HoverLogTile> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            // ignore: deprecated_member_use
            color: _isHovering ? widget.borderColor : widget.borderColor.withValues(alpha: 0.3),
            width: _isHovering ? 1.5 : 1,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _isHovering 
                // ignore: deprecated_member_use
                ? [widget.gradientColors.first.withValues(alpha: 0.6), widget.gradientColors.last.withValues(alpha: 0.8)]
                // ignore: deprecated_member_use
                : [widget.gradientColors.first.withValues(alpha: 0.3), widget.gradientColors.last.withValues(alpha: 0.4)],
          ),
          boxShadow: [
            BoxShadow(
              // ignore: deprecated_member_use
              color: widget.borderColor.withValues(alpha: _isHovering ? 0.15 : 0.05),
              blurRadius: _isHovering ? 12 : 4,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}

