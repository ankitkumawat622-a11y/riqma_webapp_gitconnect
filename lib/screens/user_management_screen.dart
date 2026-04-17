import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:riqma_webapp/firebase_options.dart';
import 'package:riqma_webapp/services/activity_log_service.dart';
import 'package:riqma_webapp/widgets/modern_searchable_dropdown.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _states = [];

  @override
  void initState() {
    super.initState();
    _fetchStates();
  }

  Future<void> _fetchStates() async {
    try {
      final snapshot = await _firestore.collection('states').get();
      setState(() {
        _states = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'name': (data['state'] ?? data['name'] ?? 'Unknown').toString(),
          };
        }).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading states: $e', style: GoogleFonts.outfit()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _createUserWithSecondaryApp({
    required String email,
    required String password,
    required String name,
    required String role,
    required String assignedState,
  }) async {
    FirebaseApp? secondaryApp;
    
    try {
      // Show loading
      unawaited(showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ));

      // Create secondary Firebase app
      secondaryApp = await Firebase.initializeApp(
        name: 'SecondaryApp-${DateTime.now().millisecondsSinceEpoch}',
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      // Create user
      final userCredential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = userCredential.user!.uid;

      // Save to Firestore
      await _firestore.collection('users').doc(uid).set({
        'uid': uid,
        'name': name,
        'email': email,
        'password': password,
        'role': role.toLowerCase(),
        'assigned_state': assignedState,
        'created_at': FieldValue.serverTimestamp(),
      });

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Log User Creation
      await ActivityLogService.instance.log(
        actionType: ActivityActionType.userCreate, 
        description: 'Created new user: $name ($email)',
        metadata: {
          'newUserId': uid,
          'role': role.toLowerCase(),
          'assignedState': assignedState,
        },
      );

      // Show success
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User created successfully!', style: GoogleFonts.outfit()),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Log Failure
      await ActivityLogService.instance.log(
        actionType: ActivityActionType.error,
        description: 'Failed to create user ($email): $e',
      );

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Show error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating user: $e', style: GoogleFonts.outfit()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // Delete secondary app
      if (secondaryApp != null) {
        await secondaryApp.delete();
      }
    }
  }

  Future<void> _editUser(String uid, String name, String assignedState) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'name': name,
        'assigned_state': assignedState,
      });

      // Log User Edit
      await ActivityLogService.instance.log(
        actionType: ActivityActionType.userEdit,
        description: 'Updated user details: $name',
        metadata: {
          'targetUserId': uid,
          'assignedState': assignedState,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User updated successfully!', style: GoogleFonts.outfit()),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Log Failure
      await ActivityLogService.instance.log(
        actionType: ActivityActionType.error,
        description: 'Failed to update user ($uid): $e',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating user: $e', style: GoogleFonts.outfit()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAddUserDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'Auditor';
    String? selectedState = _states.isNotEmpty ? _states.first['name']?.toString() : null;

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add New User', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ModernSearchableDropdown(
                    label: 'Role',
                    value: selectedRole,
                    items: const {'Manager': 'Manager', 'Auditor': 'Auditor'},
                    color: Colors.orange,
                    icon: Icons.badge_outlined,
                    onChanged: (value) {
                      if (value != null) setDialogState(() => selectedRole = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_states.isNotEmpty)
                    ModernSearchableDropdown(
                      label: 'Assigned State',
                      value: selectedState,
                      items: {
                        for (var state in _states)
                          state['name'].toString(): state['name'].toString()
                      },
                      color: Colors.blue,
                      icon: Icons.map_outlined,
                      onChanged: (value) {
                        setDialogState(() => selectedState = value ?? '');
                      },
                    ),
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
                if (nameController.text.isEmpty ||
                    emailController.text.isEmpty ||
                    passwordController.text.isEmpty ||
                    selectedState == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please fill all fields', style: GoogleFonts.outfit()),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                Navigator.pop(context);
                
                await _createUserWithSecondaryApp(
                  email: emailController.text.trim(),
                  password: passwordController.text,
                  name: nameController.text.trim(),
                  role: selectedRole,
                  assignedState: selectedState!,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1F36),
                foregroundColor: Colors.white,
              ),
              child: Text('Create User', style: GoogleFonts.outfit()),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditUserDialog(Map<String, dynamic> user) {
    final nameController = TextEditingController(text: (user['name'] ?? '').toString());
    String selectedState = (user['assigned_state'] ?? (_states.isNotEmpty ? _states.first['name'] : '')).toString();

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit User', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 16),
                if (_states.isNotEmpty)
                  ModernSearchableDropdown(
                    label: 'Assigned State',
                    value: selectedState,
                    items: {
                      for (var state in _states)
                        state['name'].toString(): state['name'].toString()
                    },
                    color: Colors.blue,
                    icon: Icons.map_outlined,
                    onChanged: (value) {
                      setDialogState(() => selectedState = value ?? '');
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.outfit()),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _editUser(user['uid'].toString(), nameController.text.trim(), selectedState);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1F36),
                foregroundColor: Colors.white,
              ),
              child: Text('Save', style: GoogleFonts.outfit()),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).cardTheme.color,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade600, Colors.indigo.shade600],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.people_alt_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Text(
              'User Management',
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).textTheme.titleLarge?.color,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: _showAddUserDialog,
              icon: const Icon(Icons.person_add_rounded, size: 20),
              label: Text('Add User', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).brightness == Brightness.light ? const Color(0xFF1A1F36) : Colors.blue[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: Colors.grey.shade200,
            height: 1,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}', style: GoogleFonts.outfit(color: Colors.red)),
                ],
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }

          final users = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {...data, 'uid': doc.id};
          }).toList();

          if (users.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No users found',
                    style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Click "Add User" to create your first user',
                    style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade500),
                  ),
                ],
              ),
            );
          }

          return Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.light ? 0.05 : 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  // Table Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.list_alt_rounded, size: 20, color: Colors.grey.shade600),
                        const SizedBox(width: 12),
                        Text(
                          '${users.length} User${users.length != 1 ? 's' : ''}',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Data Table
                  Expanded(
                    child: SingleChildScrollView(
                      child: SizedBox(
                        width: double.infinity,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(Theme.of(context).brightness == Brightness.light ? Colors.grey.shade50 : Colors.white.withValues(alpha: 0.05)),
                          headingRowHeight: 56,
                          dataRowMinHeight: 64,
                          dataRowMaxHeight: 72,
                          columnSpacing: 32,
                          horizontalMargin: 24,
                          columns: [
                            DataColumn(
                              label: Text('USER', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.grey.shade600, letterSpacing: 0.5)),
                            ),
                            DataColumn(
                              label: Text('EMAIL', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color, letterSpacing: 0.5)),
                            ),
                            DataColumn(
                              label: Text('ROLE', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color, letterSpacing: 0.5)),
                            ),
                            DataColumn(
                              label: Text('STATE', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color, letterSpacing: 0.5)),
                            ),
                            DataColumn(
                              label: Text('ACTIONS', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color, letterSpacing: 0.5)),
                            ),
                          ],
                          rows: users.map((user) {
                            final isManager = user['role'] == 'manager';
                            return DataRow(
                              cells: [
                                DataCell(
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: isManager ? Colors.blue.shade100 : Colors.teal.shade100,
                                        child: Text(
                                          (user['name']?.toString() ?? 'U')[0].toUpperCase(),
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.w600,
                                            color: isManager ? Colors.blue.shade700 : Colors.teal.shade700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                          user['name']?.toString() ?? 'N/A',
                                          style: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 14, color: Theme.of(context).textTheme.bodyLarge?.color),
                                        ),
                                    ],
                                  ),
                                ),
                                DataCell(
                                    Text(
                                      user['email']?.toString() ?? 'N/A',
                                      style: GoogleFonts.outfit(fontSize: 14, color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7)),
                                    ),
                                ),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: isManager
                                            ? [Colors.blue.shade50, Colors.indigo.shade50]
                                            : [Colors.teal.shade50, Colors.green.shade50],
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isManager ? Colors.blue.shade200 : Colors.teal.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      user['role']?.toString().toUpperCase() ?? 'N/A',
                                      style: GoogleFonts.outfit(
                                        color: isManager ? Colors.blue.shade700 : Colors.teal.shade700,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    children: [
                                      Icon(Icons.location_on_outlined, size: 16, color: Colors.grey.shade500),
                                      const SizedBox(width: 6),
                                      Text(
                                        user['assigned_state']?.toString() ?? 'N/A',
                                        style: GoogleFonts.outfit(fontSize: 14, color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7)),
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      color: Colors.grey.shade700,
                                      onPressed: () => _showEditUserDialog(user),
                                      tooltip: 'Edit User',
                                      splashRadius: 20,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
