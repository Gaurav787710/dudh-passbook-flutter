import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:workmanager/workmanager.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/language_selection_screen.dart';
import 'services/firebase_config.dart';
import 'services/firestore_sync_service.dart';
import 'services/google_drive_backup_service.dart';
import 'screens/splash_screen.dart';
import 'utils/localization.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// WorkManager callback for background tasks
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case 'autoBackupTask':
        try {
          WidgetsFlutterBinding.ensureInitialized();
          await Firebase.initializeApp(
            options: DefaultFirebaseConfig.platformOptions,
          );

          // Skip if already backed up today
          final prefs = await SharedPreferences.getInstance();
          final lastBackup = prefs.getString('lastAutoBackupDate');
          if (lastBackup != null) {
            final lastDate = DateTime.tryParse(lastBackup);
            if (lastDate != null) {
              final now = DateTime.now();
              if (lastDate.year == now.year &&
                  lastDate.month == now.month &&
                  lastDate.day == now.day) {
                debugPrint('[WorkManager] Already backed up today, skipping');
                return true;
              }
            }
          }

          await GoogleDriveBackupService.performAutoBackup();
        } catch (e) {
          debugPrint('[WorkManager] autoBackupTask failed: $e');
          return false; // Tell WorkManager to retry later
        }
        break;
    }
    return true;
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase only if not already initialized
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseConfig.platformOptions);
    }
  } catch (e) {
    debugPrint('[Main] Firebase init error: $e');
  }

  // Initialize Firestore Sync Service (non-fatal if fails)
  try {
    await FirestoreSyncService.instance.initialize();
  } catch (e) {
    debugPrint('[Main] Firestore sync init failed: $e');
  }

  // Initialize WorkManager for auto-backup (non-fatal if fails)
  try {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    await _scheduleDailyBackup();
  } catch (e) {
    debugPrint('[Main] WorkManager init failed: $e');
  }

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load saved language preference
  final prefs = await SharedPreferences.getInstance();
  final savedLanguageCode = prefs.getString('language_code') ?? 'hi';
  final languageSelected = prefs.getBool('language_selected') ?? false;
  final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

  runApp(
    DairyMasterProApp(
      initialLanguageCode: savedLanguageCode,
      languageSelected: languageSelected,
      isLoggedIn: isLoggedIn,
    ),
  );
}

/// Schedule daily auto-backup at midnight
Future<void> _scheduleDailyBackup() async {
  try {
    // Calculate initial delay to next midnight
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);
    final initialDelay = nextMidnight.difference(now);

    // Register periodic task — runs approximately every 24 hours.
    // existingWorkPolicy.keep ensures we don't re-register on every app launch
    // (only registers if no existing task with this name).
    await Workmanager().registerPeriodicTask(
      'dailyAutoBackup',
      'autoBackupTask',
      initialDelay: initialDelay,
      frequency: const Duration(hours: 24),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 10),
    );
  } catch (e) {
    debugPrint('[Main] _scheduleDailyBackup failed: $e');
  }
}

class DairyMasterProApp extends StatefulWidget {
  final String initialLanguageCode;
  final bool languageSelected;
  final bool isLoggedIn;

  const DairyMasterProApp({
    super.key,
    required this.initialLanguageCode,
    required this.languageSelected,
    required this.isLoggedIn,
  });

  static void setLocale(BuildContext context, Locale newLocale) {
    _DairyMasterProAppState? state = context
        .findAncestorStateOfType<_DairyMasterProAppState>();
    state?.setLocale(newLocale);
  }

  static void setThemeMode(BuildContext context, ThemeMode newThemeMode) {
    _DairyMasterProAppState? state = context
        .findAncestorStateOfType<_DairyMasterProAppState>();
    state?.setThemeMode(newThemeMode);
  }

  @override
  State<DairyMasterProApp> createState() => _DairyMasterProAppState();
}

class _DairyMasterProAppState extends State<DairyMasterProApp> {
  late Locale _locale;
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _locale = Locale(widget.initialLanguageCode);
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('theme_mode') ?? 'light';
    setState(() {
      switch (mode) {
        case 'dark':
          _themeMode = ThemeMode.dark;
          break;
        case 'system':
          _themeMode = ThemeMode.system;
          break;
        default:
          _themeMode = ThemeMode.light;
      }
    });
  }

  void setLocale(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  void setThemeMode(ThemeMode themeMode) {
    setState(() {
      _themeMode = themeMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dudh Passbook',
      locale: _locale,
      supportedLocales: const [Locale('en'), Locale('hi')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2E7D32),
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Color(0xFF2E7D32),
          foregroundColor: Colors.white,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF2E7D32),
          foregroundColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF5C6BC0),       // Indigo/Navy accent
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFF1A237E), // Deep navy
          secondary: const Color(0xFF7986CB),
          surface: const Color(0xFF1E1E2E),        // Dark card surface
          onSurface: Colors.white,
          onSurfaceVariant: Colors.white70,
          outline: Colors.white24,
          error: const Color(0xFFCF6679),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),  // Dark charcoal bg
        cardColor: const Color(0xFF1E1E2E),
        dividerColor: Colors.white12,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Color(0xFF1A237E),      // Navy blue AppBar
          foregroundColor: Colors.white,
          iconTheme: IconThemeData(color: Colors.white),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          color: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF3F51B5),
          foregroundColor: Colors.white,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1E1E2E),
          selectedItemColor: Color(0xFF7986CB),
          unselectedItemColor: Colors.white54,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2A2A3E),
          labelStyle: const TextStyle(color: Colors.white70),
          hintStyle: const TextStyle(color: Colors.white38),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF5C6BC0), width: 2)),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
          bodySmall: TextStyle(color: Colors.white70),
          titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          titleMedium: TextStyle(color: Colors.white),
          labelLarge: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white70),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF2A2A3E),
          contentTextStyle: TextStyle(color: Colors.white),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3F51B5),
            foregroundColor: Colors.white,
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF1E1E2E),
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: Color(0xFF1E1E2E),
        ),
        chipTheme: const ChipThemeData(
          backgroundColor: Color(0xFF2A2A3E),
          labelStyle: TextStyle(color: Colors.white),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          indicatorColor: Color(0xFF5C6BC0),
        ),
      ),
      home: _getInitialScreen(),
    );
  }

  Widget _getInitialScreen() {
    // Determine the destination screen
    Widget destination;
    if (!widget.languageSelected) {
      destination = const LanguageSelectionScreen();
    } else if (widget.isLoggedIn) {
      destination = const HomeScreen();
    } else {
      destination = const LoginScreen();
    }

    // Wrap in animated splash so user sees animation from the very first frame
    return SplashScreen(nextScreen: destination);
  }
}
