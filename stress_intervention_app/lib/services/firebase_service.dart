import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  DatabaseReference? _dbRef;
  StreamSubscription<DatabaseEvent>? _subscription;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  // ストレス状態のリスナーコールバック
  Function(bool isActive)? _onStressStatusChanged;

  /// Firebaseの初期化とRealtime Databaseのリスナー設定
  Future<void> initialize({
    required String databaseUrl,
    required String path,
    required Function(bool) onStressStatusChanged,
  }) async {
    _onStressStatusChanged = onStressStatusChanged;
    
    try {
      // Firebaseが未初期化の場合のみ初期化を試みる
      if (Firebase.apps.isEmpty) {
        // 注: 通常は FlutterFire CLI を用いて生成された firebase_options.dart を渡します。
        // ここでは、ユーザーがカスタムの databaseUrl を指定して接続できるように試みます。
        await Firebase.initializeApp();
      }
      
      _isInitialized = true;
      _dbRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: databaseUrl.isNotEmpty ? databaseUrl : null,
      ).ref(path);

      // 既存のリスナーがあればキャンセル
      await _subscription?.cancel();

      // 値の監視を開始
      _subscription = _dbRef!.onValue.listen(
        (DatabaseEvent event) {
          final value = event.snapshot.value;
          if (value != null) {
            // 例: database上の値が true/1 の場合にストレス上昇とする
            bool isStressActive = false;
            if (value is bool) {
              isStressActive = value;
            } else if (value is num) {
              isStressActive = value == 1;
            } else if (value is String) {
              isStressActive = value.toLowerCase() == 'true' || value == '1';
            }
            
            _onStressStatusChanged?.call(isStressActive);
          }
        },
        onError: (error) {
          print('Firebase Database Error: $error');
          // エラー時でもアプリがクラッシュしないようにハンドリング
        },
      );
      print('Firebase Realtime Database listener initialized at path: $path');
    } catch (e) {
      _isInitialized = false;
      print('Failed to initialize Firebase: $e');
      print('Please configure your google-services.json / GoogleService-Info.plist');
    }
  }

  /// 監視の停止
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
