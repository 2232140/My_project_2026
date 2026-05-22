import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/firebase_service.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  // サービスインスタンス
  final FirebaseService _firebaseService = FirebaseService();
  final ApiService _apiService = ApiService();
  final AudioService _audioService = AudioService();

  // 設定用コントローラー
  final TextEditingController _firebaseUrlController = TextEditingController(
    text: 'https://your-project-id.firebaseio.com',
  );
  final TextEditingController _firebasePathController = TextEditingController(
    text: 'stress_control/active',
  );
  final TextEditingController _flaskUrlController = TextEditingController(
    text: 'http://localhost:5000',
  );

  // 状態管理
  bool _isStressActive = false;
  bool _isPlayingMusic = false;
  bool _isFirebaseListening = false;
  
  // 送信ログ履歴
  final List<Map<String, dynamic>> _logs = [];

  // アニメーション用
  late AnimationController _stressPulseController;
  late AnimationController _equalizerController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    
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
    _stressPulseController.dispose();
    _equalizerController.dispose();
    _firebaseUrlController.dispose();
    _firebasePathController.dispose();
    _flaskUrlController.dispose();
    _firebaseService.dispose();
    super.dispose();
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

  // ストレス状態の変化ハンドラ
  void _handleStressStatusChange(bool isActive, {required bool isSimulated}) {
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

    final source = isSimulated ? 'シミュレーション' : 'Firebase';
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
    await _audioService.setLoop(true);
    await _audioService.playRelaxMusic();
    _addLog('音楽再生', 'リラックス音楽の再生を開始しました', true);
  }

  // 音楽停止
  void _stopMusic() async {
    await _audioService.stop();
    _addLog('音楽再生', '音楽を停止しました', true);
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
            // 1. ストレスステータスパネル（アニメーション付き）
            _buildStatusPanel(),
            const SizedBox(height: 16),
            
            // 2. 音楽プレイヤー
            _buildPlayerPanel(),
            const SizedBox(height: 16),

            // 3. 設定パネル (Firebase & Flask)
            _buildSettingsPanel(),
            const SizedBox(height: 16),

            // 4. イベント・通信ログ
            _buildLogsPanel(),
          ],
        ),
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
            color: statusColor.withOpacity(0.5),
            width: _isStressActive ? 2 : 1,
          ),
        ),
        elevation: _isStressActive ? 12 : 4,
        shadowColor: statusColor.withOpacity(0.3),
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
                          color: (_isFirebaseListening ? const Color(0xFF10B981) : Colors.amber).withOpacity(0.5),
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
                        color: const Color(0xFF10B981).withOpacity(0.5),
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
