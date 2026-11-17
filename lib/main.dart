import 'package:flutter/material.dart';
import 'package:mfiles_app/screens/server_address_screen.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_vault_screen.dart';
import 'screens/splash_screen.dart';
import 'services/mfiles_service.dart';
import 'services/network_service.dart';
import 'theme/app_theme.dart';                 // 👈 NEW
import 'theme/theme_service.dart';             // 👈 NEW

import 'dss/services/dss_auth_service.dart';
import 'dss/services/dss_api_service.dart';
import 'navigation/app_navigator.dart';

import 'security/trusted_http.dart';
import 'package:launcher_shortcuts/launcher_shortcuts.dart';
import 'services/shortcut_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeTrustedCertificates();

  await LauncherShortcuts.initialize();
  ShortcutRouter.attachGlobalListener();

  LauncherShortcuts.setShortcuts([
    ShortcutItem(
      type: 'scan',
      localizedTitle: 'Scan Document',
      androidConfig: AndroidConfig(icon: 'assets/shortcuts/ic_scan.svg'),
    ),
    ShortcutItem(
      type: 'create',
      localizedTitle: 'Create',
      androidConfig: AndroidConfig(icon: 'assets/shortcuts/ic_create.svg'),
    ),
    ShortcutItem(
      type: 'search',
      localizedTitle: 'Search',
      androidConfig: AndroidConfig(icon: 'assets/shortcuts/ic_search.svg'),
    ),
    ShortcutItem(
      type: 'assigned',
      localizedTitle: 'Assigned',
      androidConfig: AndroidConfig(icon: 'assets/shortcuts/ic_assigned.svg'),
    ),
  ]);

  // 👈 NEW: load persisted theme before first frame so there's no flash
  final themeService = ThemeService();
  await themeService.load();

  runApp(MainApp(themeService: themeService));
}

class MainApp extends StatelessWidget {
  final ThemeService themeService;

  const MainApp({super.key, required this.themeService});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeService>.value(value: themeService), // 👈 NEW
        ChangeNotifierProvider(create: (_) => MFilesService()),
        ChangeNotifierProvider(create: (_) => NetworkService()),
        ProxyProvider<MFilesService, DssApiService>(
          update: (_, mfiles, __) {
            final auth = DssAuthService()
              ..accessToken  = mfiles.dssAccessToken
              ..refreshToken = mfiles.dssRefreshToken;
            return DssApiService(authService: auth);
          },
        ),
      ],
      // 👈 NEW: rebuild MaterialApp when the theme flips
      child: Consumer<ThemeService>(
        builder: (context, themeService, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            title: 'ALIGNSYS',

            scrollBehavior: const MaterialScrollBehavior().copyWith(
              scrollbars: true,
            ),

            theme: buildLightTheme(),        // 👈 NEW
            darkTheme: buildDarkTheme(),     // 👈 NEW
            themeMode: themeService.mode,    // 👈 NEW

            home: const SplashScreen(),
            routes: {
              '/splash':         (context) => const SplashScreen(),
              '/login':          (context) => const LoginVaultScreen(),
              '/server_address': (context) => const ServerAddressScreen(),
              '/home':           (context) => const HomeScreen(),
            },
          );
        },
      ),
    );
  }
}