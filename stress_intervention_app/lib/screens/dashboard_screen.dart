import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/firebase_service.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/health_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  // 定期送信の間隔（分） ※テスト時: 1  本番: 5
  static const int _sendIntervalMinutes = 1;

  // ポーリングの間隔（秒） ※テスト時: 30  本番: 30
  static const int _pollIntervalSeconds = 30;

  // サービスインスタンス
  final FirebaseService _firebaseService = FirebaseService();
  final ApiService _apiService = ApiService();
  final AudioService _audioService = AudioService();
  final HealthService _healthService = HealthService();

  // ヘルスデータ状態
  Map<String, dynamic>? _healthData;
  bool _isLoadingHealth = false;
  bool _healthPermissionsGranted = false;

  // 定期送信状態
  Timer? _healthSendTimer;
  bool _isSendingPeriodically = false;

  // ポーリング状態
  Timer? _pollingTimer;
  bool _isPollingActive = false;

  // UIリアルタイム更新タイマー（送信とは独立して30秒ごとに表示を更新）
  Timer? _uiRefreshTimer;
  static const int _uiRefreshIntervalSeconds = 30;

  // 参加者ID
  final TextEditingController _participantIdController = TextEditingController(text: 'participant_001');

  // 設定用コントローラー
  final TextEditingController _firebaseUrlController = TextEditingController(
    text: 'https://expt-d5356-default-rtdb.asia-southeast1.firebasedatabase.app/',
  );
  final TextEditingController _firebasePathController = TextEditingController(
    text: 'music_control',
  );
  // iPhoneからはMacのIPアドレスを指定する（localhostはiPhone自身を指すため使えない）
  final TextEditingController _flaskUrlController = TextEditingController(
    text: '',
  );

  // 状態管理
  bool _isStressActive = false;
  bool _isPlayingMusic = false;
  bool _isFirebaseListening = false;
  Timer? _musicTimer; // 音楽の自動停止用タイマー
  
  // 送信ログ履歴
  final List<Map<String, dynamic>> _logs = [];

  // アニメーション用
  late AnimationController _stressPulseController;
  late AnimationController _equalizerController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // 画面が起動したら、3秒後にfirebaseの監視をスタート
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_isFirebaseListening) {
        _toggleFirebaseListener();
      }
    });

    // ヘルスケア権限の要求と初回データ取得
    _initHealth();

    // 設定を読み込み、自動起動する
    _loadSettings();
    
    // ストレス時の鼓動アニメーション
    _stressPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _stressPulseController, curve: Curves.easeInOut),
    );

    // イコライザーアニメーション（音楽再生用）
    _equalizerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // 音楽再生状態の監視
    _audioService.onPlayerStateChanged.listen((PlayerState state) {
      if (mounted) {
        setState(() {
          _isPlayingMusic = state == PlayerState.playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _musicTimer?.cancel();
    _healthSendTimer?.cancel();
    _pollingTimer?.cancel();
    _uiRefreshTimer?.cancel();
    _stressPulseController.dispose();
    _equalizerController.dispose();
    _firebaseUrlController.dispose();
    _firebasePathController.dispose();
    _flaskUrlController.dispose();
    _participantIdController.dispose();
    _firebaseService.dispose();
    super.dispose();
  }

  // 参加者ID・Flask URLをSharedPreferencesから読み込み、自動起動する
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final savedId = prefs.getString('participant_id');
    if (savedId != null && savedId.isNotEmpty && mounted) {
      setState(() => _participantIdController.text = savedId);
    }

    final savedUrl = prefs.getString('flask_url');
    if (savedUrl != null && savedUrl.isNotEmpty && mounted) {
      setState(() => _flaskUrlController.text = savedUrl);
    }

    // HealthKit権限取得を待ってから自動起動（5秒後）
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _startPeriodicHealthSend();
        _startPolling();
        _startUiRefreshTimer();
      }
    });
  }

  // 参加者ID・Flask URLをSharedPreferencesに保存する
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('participant_id', _participantIdController.text.trim());
    await prefs.setString('flask_url', _flaskUrlController.text.trim());
    _addLog('設定', '参加者ID・FlaskURLを保存しました', true);
  }

  // 定期送信を開始する（_sendIntervalMinutes 分ごと）
  void _startPeriodicHealthSend() {
    final url = _flaskUrlController.text.trim();
    if (url.isEmpty || url.contains('localhost')) {
      _addLog('定期送信', 'Flask URL を設定してください（例: http://192.168.x.x:5000）', false);
      return;
    }
    _apiService.setBaseUrl(url);
    _addLog('定期送信', '$_sendIntervalMinutes分ごとの送信を開始しました', true);

    // 即時1回送信してから定期実行
    _fetchAndSendHealthData();
    _healthSendTimer = Timer.periodic(
      Duration(minutes: _sendIntervalMinutes),
      (_) => _fetchAndSendHealthData(),
    );
    setState(() => _isSendingPeriodically = true);
  }

  // 定期送信を停止する
  void _stopPeriodicHealthSend() {
    _healthSendTimer?.cancel();
    _healthSendTimer = null;
    setState(() => _isSendingPeriodically = false);
    _addLog('定期送信', '定期送信を停止しました', true);
  }

  // UIリアルタイム更新タイマーを開始する（Flaskへの送信は行わず表示のみ更新）
  void _startUiRefreshTimer() {
    _uiRefreshTimer?.cancel();
    _uiRefreshTimer = Timer.periodic(
      Duration(seconds: _uiRefreshIntervalSeconds),
      (_) => _refreshHealthData(),
    );
  }

  // ヘルスデータを取得してFlaskに送信する（1回分）
  Future<void> _fetchAndSendHealthData() async {
    final userId = _participantIdController.text.trim();
    if (userId.isEmpty) {
      _addLog('定期送信', '参加者IDが未設定です。設定パネルで入力してください', false);
      return;
    }

    // データ取得
    final data = await _healthService.fetchRecentData();
    if (mounted) setState(() => _healthData = data);

    // Flask へ送信
    _addLog('定期送信', '[$userId] データ送信中...', true);
    _apiService.setBaseUrl(_flaskUrlController.text.trim());
    final success = await _apiService.sendHealthData(
      userId: userId,
      healthData: data,
    );

    final hr = data['heart_rate']?.toStringAsFixed(0) ?? '---';
    final steps = data['steps']?.toString() ?? '---';
    if (success) {
      _addLog('定期送信', '[$userId] 送信成功 HR:${hr}bpm 歩数:$steps', true);
    } else {
      _addLog('定期送信', '[$userId] 送信失敗 (FlaskサーバーのURLと起動状況を確認)', false);
    }
  }

  // ヘルスケアの権限要求と初回データ取得
  Future<void> _initHealth() async {
    final granted = await _healthService.requestPermissions();
    if (!mounted) return;
    setState(() => _healthPermissionsGranted = granted);
    if (granted) {
      await _refreshHealthData();
    }
  }

  // ヘルスデータの更新
  Future<void> _refreshHealthData() async {
    if (!mounted) return;
    setState(() => _isLoadingHealth = true);
    final data = await _healthService.fetchRecentData();
    if (!mounted) return;
    setState(() {
      _healthData = data;
      _isLoadingHealth = false;
    });
    final src = data['heart_rate_source'] != null ? ' (${data['heart_rate_source']})' : '';
    _addLog('ヘルスケア', 'HR: ${data['heart_rate']?.toStringAsFixed(0) ?? '---'} bpm$src, 歩数: ${data['steps'] ?? '---'} 歩', !data.containsKey('error'));
  }

  // ログを追加するヘルパー
  void _addLog(String title, String details, bool isSuccess) {
    if (mounted) {
      setState(() {
        _logs.insert(0, {
          'time': DateTime.now().toString().substring(11, 19),
          'title': title,
          'details': details,
          'success': isSuccess,
        });
      });
    }
  }

  // Firebaseの監視開始/停止
  void _toggleFirebaseListener() async {
    if (_isFirebaseListening) {
      await _firebaseService.dispose();
      setState(() {
        _isFirebaseListening = false;
      });
      _addLog('Firebase', '監視を停止しました', true);
    } else {
      _addLog('Firebase', '接続初期化中...', true);
      
      // ユーザー設定の適用
      _apiService.setBaseUrl(_flaskUrlController.text.trim());

      await _firebaseService.initialize(
        databaseUrl: _firebaseUrlController.text.trim(),
        path: _firebasePathController.text.trim(),
        onStressStatusChanged: (bool isActive) {
          _handleStressStatusChange(isActive, isSimulated: false);
        },
      );

      setState(() {
        _isFirebaseListening = _firebaseService.isInitialized;
      });

      if (_isFirebaseListening) {
        _addLog('Firebase', '接続成功: 監視を開始しました', true);
      } else {
        _addLog('Firebase', '接続失敗: 設定を確認してください。手動シミュレーションをご利用いただけます。', false);
      }
    }
  }

  // ポーリングを開始する
  void _startPolling() {
    _apiService.setBaseUrl(_flaskUrlController.text.trim());
    _addLog('ポーリング', '$_pollIntervalSeconds秒ごとの介入命令チェックを開始しました', true);
    _checkForIntervention(); // 即時1回実行
    _pollingTimer = Timer.periodic(
      Duration(seconds: _pollIntervalSeconds),
      (_) => _checkForIntervention(),
    );
    setState(() => _isPollingActive = true);
  }

  // ポーリングを停止する
  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    setState(() => _isPollingActive = false);
    _addLog('ポーリング', 'ポーリングを停止しました', true);
  }

  // Flask に介入命令がないかチェック（ポーリング1回分）
  Future<void> _checkForIntervention() async {
    final userId = _participantIdController.text.trim();
    if (userId.isEmpty) return;

    _apiService.setBaseUrl(_flaskUrlController.text.trim());
    final result = await _apiService.checkIntervention(userId: userId);

    if (result['has_command'] == true) {
      final command = result['command'] as String?;
      final commandId = result['command_id'] as String?;

      _addLog('ポーリング', '介入命令を受信: $command (ID: $commandId)', true);

      // 命令をACK済みにする
      if (commandId != null) {
        await _apiService.acknowledgeIntervention(
          commandId: commandId,
          userId: userId,
        );
      }

      // 命令に応じた処理
      if (command == 'stress_on') {
        _handleStressStatusChange(true, isSimulated: false, sourceLabel: 'Flaskポーリング');
      } else if (command == 'stress_off') {
        _handleStressStatusChange(false, isSimulated: false, sourceLabel: 'Flaskポーリング');
      }
    }
  }

  // ストレス状態の変化ハンドラ
  void _handleStressStatusChange(bool isActive, {required bool isSimulated, String? sourceLabel}) {
    if (isActive == _isStressActive) return; // 状態が変わらなければスルー

    setState(() {
      _isStressActive = isActive;
      if (_isStressActive) {
        _stressPulseController.repeat(reverse: true);
      } else {
        _stressPulseController.stop();
        _stressPulseController.reset();
      }
    });

    final source = sourceLabel ?? (isSimulated ? 'シミュレーション' : 'Firebase');
    _addLog(source, 'ストレス状態変化検知: ${isActive ? "ON" : "OFF"}', true);

    if (_isStressActive) {
      // Firebaseからの命令（ストレスON）を受領したことをFlask経由でMongoDBに記録
      _sendEventToFlask('stress_received', extraData: {'source': source});
      
      // ダイアログ通知を表示
      _showStressInterventionDialog(source);
    } else {
      // ストレスが下がった場合、音楽を停止するかどうか
      if (_isPlayingMusic) {
        _stopMusic();
        _addLog('介入システム', 'ストレス低下に伴い、音楽を自動停止しました', true);
      }
    }
  }

  // Flaskサーバーにイベントを送信
  Future<void> _sendEventToFlask(String eventType, {Map<String, dynamic>? extraData}) async {
    _apiService.setBaseUrl(_flaskUrlController.text.trim());
    _addLog('MongoDB記録', '$eventType の送信を試行中...', true);
    
    bool success = await _apiService.logStressEvent(
      eventType: eventType,
      extraData: extraData,
    );

    if (success) {
      _addLog('MongoDB記録', 'データ保存成功: $eventType', true);
    } else {
      _addLog('MongoDB記録', 'データ保存失敗 (Flaskサーバーの接続設定と稼働状況を確認してください)', false);
    }
  }

  // 介入ダイアログの表示
  void _showStressInterventionDialog(String source) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
              SizedBox(width: 10),
              Text(
                'ストレス検知',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            'ストレスが上昇しています。\n心を落ち着かせるためのリラックス音楽を流しますか？',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _addLog('ユーザー操作', '介入拒否 (音楽再生スキップ)', true);
                _sendEventToFlask('music_declined', extraData: {'source': source});
              },
              child: const Text('いいえ', style: TextStyle(color: Colors.white54, fontSize: 16)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _playMusic();
                _sendEventToFlask('music_started', extraData: {'source': source});
              },
              child: const Text('はい、流します', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  // 音楽再生
  void _playMusic() async {
    // すでにタイマーが動いていたら一度リセットする
    _musicTimer?.cancel();

    await _audioService.setLoop(true);
    await _audioService.playRelaxMusic();
    _addLog('音楽再生', 'リラックス音楽の再生を開始しました', true);

    // 指定時間（テスト用に15秒に設定）で自動停止するタイマーを開始
  _musicTimer = Timer(const Duration(seconds: 15), () {
    _addLog('介入システム', '制限時間に達したため、音楽を自動停止します', true);
    _stopMusic(reason: 'auto_timeout'); // 自動停止のログを送る
    });
  }

  // 音楽停止
  void _stopMusic({String reason = 'manual_user'}) async {
    // 動いているタイマーを止める
    _musicTimer?.cancel();
    _musicTimer = null;
    
    await _audioService.stop();
    _addLog('音楽再生', '音楽を停止しました', true);

    // Firebaseの値を自動で false にリセットする
    await FirebaseDatabase.instance
      .ref(_firebasePathController.text.trim())
      .set(false);

    // 音楽が止まった瞬間のログを　Flask → MongoDB へ送信する
    _sendEventToFlask('music_stopped', extraData: {
      'reason': reason, // manual_user（手動）か auto_timeout（自動）かを記録
      'descriptioin': 'Music playback has ended'
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate 900
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B), // Slate 800
        title: const Text(
          'ストレス介入システム',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 生体データパネル（HealthKit / Health Connect）
            _buildHealthDataPanel(),
            const SizedBox(height: 16),

            // 2. ストレスステータスパネル（アニメーション付き）
            _buildStatusPanel(),
            const SizedBox(height: 16),

            // 3. 音楽プレイヤー
            _buildPlayerPanel(),
            const SizedBox(height: 16),

            // 4. 設定パネル (Firebase & Flask)
            _buildSettingsPanel(),
            const SizedBox(height: 16),

            // 5. イベント・通信ログ
            _buildLogsPanel(),
          ],
        ),
      ),
    );
  }

  // 0. 生体データパネルのUI構築（HealthKit / Health Connect）
  Widget _buildHealthDataPanel() {
    final hr = _healthData?['heart_rate'] as double?;
    final steps = _healthData?['steps'] as int?;
    final measuredAt = _healthData?['measured_at'] as String?;
    final hasError = _healthData?.containsKey('error') ?? false;

    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '生体データ (ヘルスケア連携)',
                  style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                if (_isLoadingHealth)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF10B981),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_healthPermissionsGranted) ...[
              const Text(
                'ヘルスケアへのアクセス許可が必要です',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed: () async {
                  final granted = await _healthService.requestPermissions();
                  if (mounted) setState(() => _healthPermissionsGranted = granted);
                  if (granted) _refreshHealthData();
                },
                icon: const Icon(Icons.health_and_safety, color: Colors.white),
                label: const Text('許可を要求する', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ] else ...[
              if (hasError)
                const Text(
                  'データ取得に失敗しました。ヘルスケアアプリにデータが存在するか確認してください。',
                  style: TextStyle(color: Colors.amber, fontSize: 12),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetricTile(
                      icon: Icons.favorite_rounded,
                      label: '心拍数',
                      value: hr != null ? '${hr.toStringAsFixed(0)} bpm' : '---',
                      color: Colors.redAccent,
                    ),
                    _buildMetricTile(
                      icon: Icons.directions_walk_rounded,
                      label: '歩数（今日）',
                      value: steps != null ? '$steps 歩' : '---',
                      color: const Color(0xFF10B981),
                    ),
                  ],
                ),
              if (measuredAt != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '最終取得: ${measuredAt.substring(11, 19)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF10B981)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isLoadingHealth ? null : _refreshHealthData,
                  icon: const Icon(Icons.refresh_rounded, color: Color(0xFF10B981), size: 18),
                  label: const Text('データを更新', style: TextStyle(color: Color(0xFF10B981))),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 指標タイルウィジェット
  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // 1. ステータスパネルのUI構築
  Widget _buildStatusPanel() {
    final statusColor = _isStressActive ? Colors.redAccent : const Color(0xFF10B981);
    final statusText = _isStressActive ? 'ストレス上昇検出' : '通常 (リラックス状態)';

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _isStressActive ? _pulseAnimation.value : 1.0,
          child: child,
        );
      },
      child: Card(
        color: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: statusColor.withValues(alpha: 0.5),
            width: _isStressActive ? 2 : 1,
          ),
        ),
        elevation: _isStressActive ? 12 : 4,
        shadowColor: statusColor.withValues(alpha: 0.3),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '生体モニター状態',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _isFirebaseListening ? const Color(0xFF10B981) : Colors.amber,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_isFirebaseListening ? const Color(0xFF10B981) : Colors.amber).withValues(alpha: 0.5),
                          blurRadius: 6,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Icon(
                _isStressActive ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: statusColor,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isStressActive 
                  ? '心拍数平均が基準値(90)を超えました。音楽介入が必要です。'
                  : 'リアルタイムデータは正常です。',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              
              // シミュレーターボタン
              if (!_isFirebaseListening) ...[
                const Divider(color: Colors.white12, height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isStressActive ? Colors.grey[700] : Colors.redAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        _handleStressStatusChange(!_isStressActive, isSimulated: true);
                      },
                      icon: Icon(
                        _isStressActive ? Icons.thumb_up_alt_rounded : Icons.warning_rounded,
                        color: Colors.white,
                      ),
                      label: Text(
                        _isStressActive ? 'ストレス解消(シミュレート)' : 'ストレス上昇(シミュレート)',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                )
              ]
            ],
          ),
        ),
      ),
    );
  }

  // 2. 音楽プレイヤーのUI構築
  Widget _buildPlayerPanel() {
    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '音楽介入コントローラー',
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // 再生・停止ボタン
                GestureDetector(
                  onTap: _isPlayingMusic ? _stopMusic : _playMusic,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      _isPlayingMusic ? Icons.stop_rounded : Icons.play_arrow_rounded,
                      color: const Color(0xFF10B981),
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                // 再生状態と曲名
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isPlayingMusic ? 'リラックス音楽 再生中' : '音楽停止中',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'ヒーリングサウンド (アセット音源: C4 正弦倍音)',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // イコライザーのアニメーション表示
                if (_isPlayingMusic) _buildEqualizerWidget(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // イコライザーアニメーションバーの生成
  Widget _buildEqualizerWidget() {
    return Row(
      children: List.generate(4, (index) {
        return AnimatedBuilder(
          animation: _equalizerController,
          builder: (context, child) {
            double heightMultiplier = 1.0;
            switch (index) {
              case 0:
                heightMultiplier = 0.3 + 0.7 * _equalizerController.value;
                break;
              case 1:
                heightMultiplier = 0.5 + 0.5 * (1.0 - _equalizerController.value);
                break;
              case 2:
                heightMultiplier = 0.1 + 0.9 * _equalizerController.value;
                break;
              case 3:
                heightMultiplier = 0.6 + 0.4 * (1.0 - _equalizerController.value);
                break;
            }
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 4,
              height: 25 * heightMultiplier,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          },
        );
      }),
    );
  }

  // 3. 設定パネルのUI構築
  Widget _buildSettingsPanel() {
    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        collapsedIconColor: Colors.white70,
        iconColor: Colors.white,
        title: Row(
          children: const [
            Icon(Icons.settings, color: Colors.white70),
            SizedBox(width: 10),
            Text(
              '接続設定 (Firebase & Flask)',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.all(16.0),
        children: [
          // 参加者ID
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _participantIdController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: '参加者ID (例: participant_001)',
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                ),
                onPressed: _saveSettings,
                child: const Text('保存', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 定期送信 ON/OFF ボタン
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isSendingPeriodically ? Colors.orange : const Color(0xFF10B981),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _isSendingPeriodically ? _stopPeriodicHealthSend : _startPeriodicHealthSend,
            icon: Icon(
              _isSendingPeriodically ? Icons.stop_circle_outlined : Icons.send_rounded,
              color: Colors.white,
            ),
            label: Text(
              _isSendingPeriodically
                  ? '定期送信 停止中... ($_sendIntervalMinutes分ごと)'
                  : '定期送信 開始 ($_sendIntervalMinutes分ごと)',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          const SizedBox(height: 8),

          // 介入命令ポーリング ON/OFF ボタン
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isPollingActive ? Colors.deepPurple : const Color(0xFF334155),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _isPollingActive ? _stopPolling : _startPolling,
            icon: Icon(
              _isPollingActive ? Icons.sync_disabled_rounded : Icons.sync_rounded,
              color: Colors.white,
            ),
            label: Text(
              _isPollingActive
                  ? '介入命令ポーリング 停止 ($_pollIntervalSeconds秒ごと)'
                  : '介入命令ポーリング 開始 ($_pollIntervalSeconds秒ごと)',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          const Divider(color: Colors.white12, height: 24),

          // Firebase DB URL
          TextField(
            controller: _firebaseUrlController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Firebase Realtime DB URL',
              labelStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 12),
          
          // Firebase 監視キー
          TextField(
            controller: _firebasePathController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'ストレス検出の監視キーパス',
              labelStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 12),

          // Flask URL
          TextField(
            controller: _flaskUrlController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'FlaskサーバーのURL (MongoDB記録用)',
              labelStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 16),

          // Firebaseの監視切り替えボタン
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isFirebaseListening ? Colors.redAccent : const Color(0xFF10B981),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _toggleFirebaseListener,
            child: Text(
              _isFirebaseListening ? 'Firebase 監視を停止する' : 'Firebase 監視を開始する',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  // 4. イベントログパネルのUI構築
  Widget _buildLogsPanel() {
    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '通信・システムログ',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (_logs.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _logs.clear();
                      });
                    },
                    child: const Text('クリア', style: TextStyle(color: Colors.redAccent)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _logs.isEmpty
                ? const Center(
                    child: Text(
                      'ログはありません。\nFirebaseを起動するか、シミュレートしてください。',
                      style: TextStyle(color: Colors.white24, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8.0),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      final isSuccess = log['success'] as bool;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '[${log['time']}]',
                              style: const TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'monospace'),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${log['title']}:',
                              style: TextStyle(
                                color: isSuccess ? const Color(0xFF10B981) : Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                log['details'] as String,
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
