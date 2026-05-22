import 'dart:convert';
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
      print('Sending log event to Flask: $payload');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('Log success: ${response.body}');
        return true;
      } else {
        print('Log failed with status: ${response.statusCode}, body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error sending log to Flask: $e');
      return false;
    }
  }
}
