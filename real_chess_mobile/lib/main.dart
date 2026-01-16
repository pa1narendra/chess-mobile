import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'providers/auth_provider.dart';
import 'providers/game_provider.dart';

import 'utils/config.dart';

// App Theme Colors
class AppColors {
  // Backgrounds
  static const deepDark = Color(0xFF0D1117);
  static const surfaceDark = Color(0xFF161B22);
  static const surfaceLight = Color(0xFF21262D);
  static const borderColor = Color(0xFF30363D);

  // Accents
  static const tealAccent = Color(0xFF14B8A6);
  static const electricBlue = Color(0xFF3B82F6);
  static const emeraldGreen = Color(0xFF10B981);
  static const amberWarning = Color(0xFFF59E0B);
  static const roseError = Color(0xFFF43F5E);
  static const purpleAccent = Color(0xFF8B5CF6);

  // Text
  static const textPrimary = Color(0xFFF0F6FC);
  static const textSecondary = Color(0xFF8B949E);
  static const textMuted = Color(0xFF6E7681);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.deepDark,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  await Config.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => GameProvider()),
      ],
      child: const ChessingApp(),
    ),
  );
}

class ChessingApp extends StatelessWidget {
  const ChessingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chessing',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: AppColors.tealAccent,
        scaffoldBackgroundColor: AppColors.deepDark,

        colorScheme: const ColorScheme.dark(
          primary: AppColors.tealAccent,
          secondary: AppColors.electricBlue,
          surface: AppColors.surfaceDark,
          error: AppColors.roseError,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: AppColors.textPrimary,
          onError: Colors.white,
        ),

        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.surfaceDark,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          titleTextStyle: GoogleFonts.inter(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),

        cardTheme: CardTheme(
          color: AppColors.surfaceDark,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.borderColor, width: 1),
          ),
        ),

        dialogTheme: DialogTheme(
          backgroundColor: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titleTextStyle: GoogleFonts.inter(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          contentTextStyle: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.tealAccent, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.roseError),
          ),
          labelStyle: GoogleFonts.inter(color: AppColors.textSecondary),
          hintStyle: GoogleFonts.inter(color: AppColors.textMuted),
          prefixIconColor: AppColors.textSecondary,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.tealAccent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.tealAccent,
            textStyle: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.surfaceLight,
          contentTextStyle: GoogleFonts.inter(color: AppColors.textPrimary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          behavior: SnackBarBehavior.floating,
        ),

        popupMenuTheme: PopupMenuThemeData(
          color: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.borderColor),
          ),
          textStyle: GoogleFonts.inter(color: AppColors.textPrimary),
        ),

        listTileTheme: ListTileThemeData(
          iconColor: AppColors.textSecondary,
          textColor: AppColors.textPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),

        textTheme: GoogleFonts.interTextTheme(
          const TextTheme(
            headlineLarge: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
            headlineMedium: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
            headlineSmall: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            titleLarge: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            titleMedium: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
            titleSmall: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500),
            bodyLarge: TextStyle(color: AppColors.textPrimary),
            bodyMedium: TextStyle(color: AppColors.textSecondary),
            bodySmall: TextStyle(color: AppColors.textMuted),
            labelLarge: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
            labelMedium: TextStyle(color: AppColors.textSecondary),
            labelSmall: TextStyle(color: AppColors.textMuted),
          ),
        ),

        useMaterial3: true,
      ),
      home: Consumer<AuthProvider>(
        builder: (context, auth, child) {
          if (!auth.isInitialized) {
            return Scaffold(
              backgroundColor: AppColors.deepDark,
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.grid_view_rounded,
                      size: 64,
                      color: AppColors.tealAccent,
                    ),
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(
                      color: AppColors.tealAccent,
                      strokeWidth: 3,
                    ),
                  ],
                ),
              ),
            );
          }
          return auth.isAuthenticated ? const HomeScreen() : const LoginScreen();
        },
      ),
    );
  }
}
