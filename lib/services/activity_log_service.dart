import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Enum representing all trackable user actions
enum ActivityActionType {
  login,
  logout,
  syncData,
  auditStart,
  auditSubmit,
  auditSubmitFailed,
  reportApprove,
  reportReject,
  userCreate,
  userEdit,
  masterDataEdit,
  planAdd, // New
  error,
  unknown, // New fallback
}

/// Extension to get display name and icon for action types
extension ActivityActionTypeExtension on ActivityActionType {
  String get displayName {
    switch (this) {
      case ActivityActionType.login:
        return 'Login';
      case ActivityActionType.logout:
        return 'Logout';
      case ActivityActionType.syncData:
        return 'Sync Data';
      case ActivityActionType.auditStart:
        return 'Audit Started';
      case ActivityActionType.auditSubmit:
        return 'Audit Submitted';
      case ActivityActionType.auditSubmitFailed:
        return 'Audit Submit Failed';
      case ActivityActionType.reportApprove:
        return 'Report Approved';
      case ActivityActionType.reportReject:
        return 'Report Rejected';
      case ActivityActionType.userCreate:
        return 'User Created';
      case ActivityActionType.userEdit:
        return 'User Edited';
      case ActivityActionType.masterDataEdit:
        return 'Master Data Edited';
      case ActivityActionType.planAdd:
        return 'New Plan Added';
      case ActivityActionType.error:
        return 'Error';
      case ActivityActionType.unknown:
        return 'Unknown Action';
    }
  }

  String get firestoreValue => name.toUpperCase();

  static ActivityActionType fromString(String value) {
    if (value.isEmpty) return ActivityActionType.unknown;

    // Normalize: remove underscores, convert to lowerCamelCase matching enum names
    // Example: AUDIT_START -> auditStart
    final normalized = value.replaceAll('_', '').toLowerCase();
    
    // Check for explicit error keywords first
    if (value.toUpperCase().contains('ERROR') || value.toUpperCase().contains('FAIL')) {
       // but wait, 'AUDIT_SUBMIT_FAILED' also matches this. 
       // Let's try exact enum matching first.
    }

    try {
      return ActivityActionType.values.firstWhere(
        (e) {
          // Compare Enum name (e.g. auditStart) with normalized input (auditstart)
          return e.name.toLowerCase() == normalized; 
        },
      );
    } catch (_) {
      // If no direct match found, check heuristics
      final upper = value.toUpperCase();
      if (upper.contains('ERROR') || upper.contains('FAIL')) {
        return ActivityActionType.error;
      }
      return ActivityActionType.unknown;
    }
  }
}

/// Model class representing a single activity log entry
class ActivityLogEntry {
  final String logId;
  final String userId;
  final String userName;
  final String userRole;
  final ActivityActionType actionType;
  final String description;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;

  ActivityLogEntry({
    required this.logId,
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.actionType,
    required this.description,
    required this.metadata,
    required this.timestamp,
  });

  /// Create from Firestore document
  factory ActivityLogEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ActivityLogEntry(
      logId: doc.id,
      userId: data['userId'] as String? ?? '',
      userName: data['userName'] as String? ?? 'Unknown',
      userRole: data['userRole'] as String? ?? 'Unknown',
      actionType: ActivityActionTypeExtension.fromString(data['actionType'] as String? ?? 'ERROR'),
      description: data['description'] as String? ?? '',
      metadata: data['metadata'] as Map<String, dynamic>? ?? {},
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'userName': userName,
      'userRole': userRole,
      'actionType': actionType.firestoreValue,
      'description': description,
      'metadata': metadata,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}

/// Singleton service for activity logging
/// Uses Firestore with offline persistence for automatic sync
class ActivityLogService {
  // Singleton instance
  static final ActivityLogService _instance = ActivityLogService._internal();
  static ActivityLogService get instance => _instance;

  // Private constructor
  ActivityLogService._internal();

  // Firestore collection reference
  final CollectionReference<Map<String, dynamic>> _logsCollection =
      FirebaseFirestore.instance.collection('activity_logs');

  // Cache for current user info
  String? _cachedUserName;
  String? _cachedUserRole;

  /// Log an activity
  /// 
  /// [actionType] - The type of action being logged
  /// [description] - Human-readable description of the action
  /// [metadata] - Additional context data (turbineId, siteId, etc.)
  Future<void> log({
    required ActivityActionType actionType,
    required String description,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('ActivityLogService: Cannot log - no user logged in');
        return;
      }

      // Get user info (cached or from Firestore)
      await _ensureUserInfoCached(user.uid);

      final logData = {
        'userId': user.uid,
        'userName': _cachedUserName ?? user.email?.split('@')[0] ?? 'Unknown',
        'userRole': _cachedUserRole ?? 'Unknown',
        'actionType': actionType.firestoreValue,
        'description': description,
        'metadata': {
          ...?metadata,
          'platform': kIsWeb ? 'web' : 'mobile',
        },
        'timestamp': FieldValue.serverTimestamp(),
      };

      // Add to Firestore (will be cached offline if no connection)
      await _logsCollection.add(logData);
      debugPrint('ActivityLogService: Logged ${actionType.displayName} - $description');
    } catch (e) {
      debugPrint('ActivityLogService: Error logging activity: $e');
    }
  }

  /// Log login event with user info override (since user doc might not exist yet)
  Future<void> logLogin({
    required String userId,
    required String userName,
    required String userRole,
    String? description,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // Cache the user info
      _cachedUserName = userName;
      _cachedUserRole = userRole;

      final logData = {
        'userId': userId,
        'userName': userName,
        'userRole': userRole,
        'actionType': ActivityActionType.login.firestoreValue,
        'description': description ?? 'User logged in',
        'metadata': {
          ...?metadata,
          'platform': kIsWeb ? 'web' : 'mobile',
        },
        'timestamp': FieldValue.serverTimestamp(),
      };

      await _logsCollection.add(logData);
      debugPrint('ActivityLogService: Logged LOGIN for $userName');
    } catch (e) {
      debugPrint('ActivityLogService: Error logging login: $e');
    }
  }

  /// Clear cached user info (call on logout)
  void clearCache() {
    _cachedUserName = null;
    _cachedUserRole = null;
  }

  /// Ensure user info is cached
  Future<void> _ensureUserInfoCached(String userId) async {
    if (_cachedUserName != null && _cachedUserRole != null) {
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data();
        _cachedUserName = data?['name'] as String? ?? 
            FirebaseAuth.instance.currentUser?.email?.split('@')[0] ?? 'Unknown';
        _cachedUserRole = data?['role'] as String? ?? 'Unknown';
      }
    } catch (e) {
      debugPrint('ActivityLogService: Error fetching user info: $e');
    }
  }

  /// Query logs for current user (Auditor view)
  Query<Map<String, dynamic>> getMyLogsQuery() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return _logsCollection.limit(0);
    }
    return _logsCollection
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true);
  }

  /// Query all logs (Manager view)
  Query<Map<String, dynamic>> getAllLogsQuery({
    String? filterByUserId,
    ActivityActionType? filterByActionType,
  }) {
    Query<Map<String, dynamic>> query = _logsCollection
        .orderBy('timestamp', descending: true);

    if (filterByUserId != null && filterByUserId.isNotEmpty) {
      query = query.where('userId', isEqualTo: filterByUserId);
    }

    if (filterByActionType != null) {
      query = query.where('actionType', isEqualTo: filterByActionType.firestoreValue);
    }

    return query;
  }

  /// Get distinct users who have logs (for Manager filter dropdown)
  Future<List<Map<String, String>>> getLoggedUsers() async {
    try {
      final snapshot = await _logsCollection
          .orderBy('timestamp', descending: true)
          .limit(500)
          .get();

      final usersMap = <String, String>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final userId = data['userId'] as String?;
        final userName = data['userName'] as String?;
        if (userId != null && userName != null && !usersMap.containsKey(userId)) {
          usersMap[userId] = userName;
        }
      }

      return usersMap.entries
          .map((e) => {'userId': e.key, 'userName': e.value})
          .toList();
    } catch (e) {
      debugPrint('ActivityLogService: Error fetching logged users: $e');
      return [];
    }
  }
}
