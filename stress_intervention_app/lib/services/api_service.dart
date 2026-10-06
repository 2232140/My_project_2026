import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  /// FlaskサーバーのベースURL (例: "http://10.0.2.2:5000" または "http://localhost:5000")
  String _baseUrl = 'http://localhost:5000';

  void setBaseUrl(String url) {
    if (url.endsWith('/')) {
      _baseUrl = url.substring(0, url.length - 1);
    } else {
      _baseUrl = url;
    }
  }

  String get baseUrl => _baseUrl;

  /// ヘルスデータを Flask サーバーに送信して MongoDB に保存する
  /// [userId] 研究参加者ID、[healthData] HealthService.fetchRecentData() の戻り値
  Future<bool> sendHealthData({
    required String userId,
    required Map<String, dynamic> healthData,
  }) async {
    final url = Uri.parse('$_baseUrl/api/health_data');
    final payload = {
      'user_id': userId,
      'timestamp': DateTime.now().toIso8601String(),
      'device': 'Flutter_App',
      'health_data': healthData,
    };

    try {
      debugPrint('[ApiService] Sending health data: $payload');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('[ApiService] Health data sent successfully');
        return true;
      } else {
        debugPrint('[ApiService] Health data send failed: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[ApiService] sendHealthData error: $e');
      return false;
    }
  }

  /// Flask にポーリングして未処理の介入命令を取得する
  /// 戻り値: {"has_command": false} または {"has_command": true, "command_id": "xxx", "command": "stress_on"}
  Future<Map<String, dynamic>> checkIntervention({required String userId}) async {
    final url = Uri.parse('$_baseUrl/api/get_intervention?user_id=$userId');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      debugPrint('[ApiService] checkIntervention failed: ${response.statusCode}');
      return {'has_command': false};
    } catch (e) {
      debugPrint('[ApiService] checkIntervention error: $e');
      return {'has_command': false};
    }
  }

  /// 介入命令の受理を Flask に通知する
  Future<bool> acknowledgeIntervention({
    required String commandId,
    required String userId,
  }) async {
    final url = Uri.parse('$_baseUrl/api/acknowledge_intervention');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'command_id': commandId, 'user_id': userId}),
      ).timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[ApiService] acknowledgeIntervention error: $e');
      return false;
    }
  }

  /// ストレスイベントをMongoDB（Flaskサーバー経由）にログとして記録
  /// [eventType] には 'stress_received' (通知受領), 'music_started' (音楽開始), 'music_declined' (拒否) などを指定
  Future<bool> logStressEvent({
    required String eventType,
    Map<String, dynamic>? extraData,
  }) async {
    final url = Uri.parse('$_baseUrl/api/log_stress_event');
    
    final payload = {
      'timestamp': DateTime.now().toIso8601String(),
      'event_type': eventType,
      'device': 'Flutter_App',
      if (extraData != null) ...extraData,
    };

    try {
      debugPrint('Sending log event to Flask: $payload');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('Log success: ${response.body}');
        return true;
      } else {
        debugPrint('Log failed with status: ${response.statusCode}, body: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error sending log to Flask: $e');
      return false;
    }
  }
}
