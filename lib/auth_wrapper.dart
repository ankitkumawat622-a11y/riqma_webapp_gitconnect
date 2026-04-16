import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:riqma_webapp/layout/main_layout.dart';
import 'package:riqma_webapp/screens/dashboard/auditor_main_dashboard.dart';
import 'package:riqma_webapp/screens/login_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // If user is not logged in, show login screen
        if (!snapshot.hasData || snapshot.data == null) {
          return const LoginScreen();
        }

        // User is logged in, check their role
        final user = snapshot.data!;
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          builder: (context, userDocSnapshot) {
            // Show loading while fetching user document
            if (userDocSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            // Check if user document exists and has a role field
            if (userDocSnapshot.hasData && userDocSnapshot.data!.exists) {
              final userData = userDocSnapshot.data!.data() as Map<String, dynamic>?;
              
              if (userData != null) {
                final role = userData['role'] as String?;
                
                // If role is 'manager' or 'admin', navigate to main layout
                if (role == 'manager' || role == 'admin') {
                  return const MainLayout();
                }

                // If role is 'auditor', navigate to auditor dashboard
                if (role == 'auditor') {
                  return const AuditorMainDashboardScreen();
                }
              }
            }

            // Default: Navigate to MainLayout for managers and users without role
            return const MainLayout();
          },
        );
      },
    );
  }
}
