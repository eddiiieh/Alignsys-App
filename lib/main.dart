import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_vault_screen.dart';
import 'screens/splash_screen.dart';
import 'services/mfiles_service.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final svc = MFilesService();

        // ✅ Don't do initialization in create - let SplashScreen handle it
        return svc;
      },
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ALIGNSYS',

        scrollBehavior: const MaterialScrollBehavior().copyWith(
          scrollbars: true,
        ),

        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          scrollbarTheme: const ScrollbarThemeData(
            thumbVisibility: WidgetStatePropertyAll(false),
            interactive: true,
          ),
        ),

        home: const SplashScreen(),
        routes: {
          '/splash': (context) => const SplashScreen(),
          '/login': (context) => const LoginVaultScreen(),
          '/home': (context) => const HomeScreen(),
        },
      ),
    );
  }
}