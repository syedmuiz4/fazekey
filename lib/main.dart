import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'providers/area_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/face_provider.dart';
import 'providers/log_provider.dart';
import 'providers/system_provider.dart';
import 'screens/access_result_screen.dart';
import 'screens/add_area_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/face_login_screen.dart';
import 'screens/face_registration_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/register_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/firebase_service.dart';
import 'services/face_recognition_service.dart';
import 'services/local_database_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final localDb = LocalDatabaseService();
  await localDb.database;
  final firebase = FirebaseService();
  runApp(FaceKeyApp(firebase: firebase, localDb: localDb));
}

class FaceKeyApp extends StatelessWidget {
  const FaceKeyApp({super.key, required this.firebase, required this.localDb});

  final FirebaseService firebase;
  final LocalDatabaseService localDb;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(firebase, localDb)..bootstrap(),
        ),
        ChangeNotifierProvider(
          create: (_) => FaceProvider(FaceRecognitionService(localDb), firebase),
        ),
        ChangeNotifierProvider(create: (_) => AreaProvider(firebase)),
        ChangeNotifierProvider(create: (_) => LogProvider(firebase, localDb)),
        ChangeNotifierProvider(create: (_) => SystemProvider(firebase)..listen()),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return MaterialApp(
            title: 'FaceKey',
            debugShowCheckedModeBanner: false,
            themeMode: auth.darkMode ? ThemeMode.dark : ThemeMode.light,
            theme: _theme(Brightness.light),
            darkTheme: _theme(Brightness.dark),
            initialRoute: SplashScreen.route,
            routes: {
              SplashScreen.route: (_) => const SplashScreen(),
              WelcomeScreen.route: (_) => const WelcomeScreen(),
              LoginScreen.route: (_) => const LoginScreen(),
              RegisterScreen.route: (_) => const RegisterScreen(),
              FaceRegistrationScreen.route: (_) => const FaceRegistrationScreen(),
              FaceLoginScreen.route: (_) => const FaceLoginScreen(),
              DashboardScreen.route: (_) => const DashboardScreen(),
              NotificationsScreen.route: (_) => const NotificationsScreen(),
              AddAreaScreen.route: (_) => const AddAreaScreen(),
              AccessResultScreen.route: (_) => const AccessResultScreen(),
            },
          );
        },
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6C63FF),
        brightness: brightness,
      ),
      textTheme: GoogleFonts.spaceGroteskTextTheme(
        ThemeData(brightness: brightness).textTheme,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: dark ? const Color(0xFF080A12) : const Color(0xFFF6F7FB),
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? Colors.white.withValues(alpha: .07) : Colors.white.withValues(alpha: .72),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
