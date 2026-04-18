import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:riqma_webapp/auth_wrapper.dart';
import 'package:riqma_webapp/firebase_options.dart';
import 'package:riqma_webapp/services/theme_service.dart';
import 'package:riqma_webapp/services/toast_service.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await ThemeService.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, child) {
        return MaterialApp(
          navigatorKey: ToastService.navigatorKey,
          title: 'RIQMA - Renom Integrated Quality Management',
          themeMode: ThemeService.instance.themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0277BD),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            cardTheme: const CardThemeData(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
              margin: EdgeInsets.zero,
            ),
            dividerTheme: const DividerThemeData(color: Color(0xFFE2E8F0)),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF3B82F6),
              brightness: Brightness.dark,
              surface: const Color(0xFF0F172A),
              onSurface: const Color(0xFFF1F5F9),
            ),
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFF020617),
            cardTheme: const CardThemeData(
              color: Color(0xFF1E293B),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
              margin: EdgeInsets.zero,
            ),
            dividerTheme: const DividerThemeData(color: Color(0xFF334155)),
          ),
          home: const AuthWrapper(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

