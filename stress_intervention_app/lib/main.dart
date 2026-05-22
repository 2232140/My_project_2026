import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';

void main() {
  // Widgetバインディングの初期化
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(const StressInterventionApp());
}

class StressInterventionApp extends StatelessWidget {
  const StressInterventionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ストレス介入システム',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, // 常にダークモードを使用
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981), // エメラルドグリーン（リラックス）
          secondary: Colors.redAccent,  // ストレス警告
          surface: Color(0xFF1E293B),    // カードやメニュー背景 (Slate 800)
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E293B),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(color: Colors.white70),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF1E293B),
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          contentTextStyle: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}
