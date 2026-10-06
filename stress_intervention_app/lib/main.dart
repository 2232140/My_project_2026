import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:stress_intervention_app/services/firebase_service.dart' as my_service;
import 'package:stress_intervention_app/services/api_service.dart';


void main() async {
  // Widgetバインディングの初期化
  WidgetsFlutterBinding.ensureInitialized();
  
  // firebaseの初期化
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Realtime Databaseの監視を開始
  await my_service.FirebaseService.instance.initialize(
    databaseUrl: 'https://expt-d5356-default-rtdb.asia-southeast1.firebasedatabase.app/',
    path: 'music_control', // 監視するキーパス
    onStressStatusChanged: (bool isStressActive) async {
      debugPrint('【通知受信】Firebaseのmusic_controlが変化しました: $isStressActive');

      if (isStressActive) {
        // ストレスを検出した場合（true）、flaskサーバー経由でMongoDBにログを送信
        bool success = await ApiService().logStressEvent(
          eventType: 'stress_received',
          extraData: {'description': 'Firebase music_control turned ON'},
        );

        if (success) {
          debugPrint('Flask/MongoDB への書き込みに成功しました');
        } else {
          debugPrint('Flask/MongoDB への書き込みに失敗しました。URLやネットワークを確認してください。');
        }
      }
    }
  );

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
