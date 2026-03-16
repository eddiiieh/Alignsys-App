import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_vault_screen.dart';
import 'screens/splash_screen.dart';
import 'services/mfiles_service.dart';
import 'services/network_service.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
Widget build(BuildContext context) {
  return MultiProvider(  // 👈 add "return" here
    providers: [
      ChangeNotifierProvider(create: (_) => MFilesService()),
      ChangeNotifierProvider(create: (_) => NetworkService()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ALIGNSYS',

      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: true,
      ),

      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        scrollbarTheme: ScrollbarThemeData(
          thumbVisibility: WidgetStatePropertyAll(true),
          thickness: WidgetStatePropertyAll(6),
          radius: const Radius.circular(8),
          thumbColor: WidgetStatePropertyAll(
            Color(0xFF072F5F).withOpacity(0.35),
          ),
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