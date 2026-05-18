import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'providers/area_provider.dart';
import 'providers/alert_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/face_provider.dart';
import 'providers/log_provider.dart';
import 'providers/system_provider.dart';
import 'screens/access_result_screen.dart';
import 'screens/add_area_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/edit_profile_screen.dart';
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
import 'services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final push = PushNotificationService();
  await push.initialize();
  final localDb = LocalDatabaseService();
  await localDb.database;
  final firebase = FirebaseService();
  runApp(FaceKeyApp(firebase: firebase, localDb: localDb, push: push));
}

class FaceKeyApp extends StatelessWidget {
  const FaceKeyApp({
    super.key,
    required this.firebase,
    required this.localDb,
    required this.push,
  });

  final FirebaseService firebase;
  final LocalDatabaseService localDb;
  final PushNotificationService push;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<FirebaseService>.value(value: firebase),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(firebase, localDb)..bootstrap(),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              FaceProvider(FaceRecognitionService(localDb), firebase),
        ),
        ChangeNotifierProvider(create: (_) => AreaProvider(firebase)),
        ChangeNotifierProvider(create: (_) => LogProvider(firebase, localDb)),
        ChangeNotifierProvider(create: (_) => SystemProvider(firebase)),
        ChangeNotifierProvider(create: (_) => AlertProvider(push)..listen()),
      ],
      child: _FaceKeyMaterialApp(theme: _theme(Brightness.light)),
    );
  }

  ThemeData _theme(Brightness brightness) {
    const frostBackground = Color(0xFFF0F9FF);
    const deepTeal = Color(0xFF0D9488);
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: deepTeal,
            brightness: Brightness.light,
          ).copyWith(
            primary: deepTeal,
            secondary: const Color(0xFF0284C7),
            surface: Colors.white,
            surfaceContainerHighest: const Color(0xFFE0F2FE),
          ),
      textTheme: GoogleFonts.spaceGroteskTextTheme(
        ThemeData(brightness: Brightness.light).textTheme,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: frostBackground,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        foregroundColor: Color(0xFF0F172A),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: .82),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: deepTeal,
          foregroundColor: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}

class _FaceKeyMaterialApp extends StatefulWidget {
  const _FaceKeyMaterialApp({required this.theme});

  final ThemeData theme;

  @override
  State<_FaceKeyMaterialApp> createState() => _FaceKeyMaterialAppState();
}

class _FaceKeyMaterialAppState extends State<_FaceKeyMaterialApp> {
  bool _firestoreListenersActive = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    _syncFirestoreListeners(auth.hasSignedInAccount);
    return MaterialApp(
      title: 'Campus Access',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: widget.theme,
      initialRoute: SplashScreen.route,
      routes: {
        SplashScreen.route: (_) => const SplashScreen(),
        WelcomeScreen.route: (_) => const WelcomeScreen(),
        LoginScreen.route: (_) => const LoginScreen(),
        RegisterScreen.route: (_) => const RegisterScreen(),
        FaceRegistrationScreen.route: (_) => const FaceRegistrationScreen(),
        FaceLoginScreen.route: (_) => const FaceLoginScreen(),
        DashboardScreen.route: (_) => const DashboardScreen(),
        EditProfileScreen.route: (_) => const EditProfileScreen(),
        NotificationsScreen.route: (_) => const NotificationsScreen(),
        AddAreaScreen.route: (_) => const AddAreaScreen(),
        AccessResultScreen.route: (_) => const AccessResultScreen(),
      },
    );
  }

  void _syncFirestoreListeners(bool signedIn) {
    if (_firestoreListenersActive == signedIn) return;
    _firestoreListenersActive = signedIn;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final areas = context.read<AreaProvider>();
      final logs = context.read<LogProvider>();
      final system = context.read<SystemProvider>();
      if (signedIn) {
        areas.listen();
        logs.listen();
        system.listen();
        unawaited(logs.syncPending());
      } else {
        unawaited(areas.stop());
        unawaited(logs.stop());
        unawaited(system.stop());
      }
    });
  }
}
