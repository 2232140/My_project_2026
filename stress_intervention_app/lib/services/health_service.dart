import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

class HealthService {
  static final HealthService _instance = HealthService._internal();
  factory HealthService() => _instance;
  HealthService._internal();

  final _health = Health();

  // 取得対象のデータ種別（心拍数・歩数）
  final _types = [
    HealthDataType.HEART_RATE,
    HealthDataType.STEPS,
  ];

  bool _isConfigured = false;
  bool _permissionsGranted = false;
  bool get permissionsGranted => _permissionsGranted;

  /// Health パッケージの初期化（初回のみ実行）
  Future<void> configure() async {
    if (_isConfigured) return;
    await _health.configure();
    _isConfigured = true;
    debugPrint('[HealthService] configured');
  }

  /// HealthKit / Health Connect へのアクセス許可を要求
  Future<bool> requestPermissions() async {
    await configure();
    try {
      final permissions = _types.map((_) => HealthDataAccess.READ).toList();
      _permissionsGranted = await _health.requestAuthorization(
        _types,
        permissions: permissions,
      );
      debugPrint('[HealthService] permissions granted: $_permissionsGranted');
      return _permissionsGranted;
    } catch (e) {
      debugPrint('[HealthService] permission request error: $e');
      return false;
    }
  }

  /// 歩数（今日の合計）と心拍数（直近4時間の最新値）を取得
  Future<Map<String, dynamic>> fetchRecentData() async {
    final now = DateTime.now();
    // 歩数: 今日の0時から現在まで（ヘルスケアアプリと同じ集計期間）
    final todayMidnight = DateTime(now.year, now.month, now.day);
    // 心拍数: 直近4時間（Fitbitの同期遅延を考慮して広めに）
    final fourHoursAgo = now.subtract(const Duration(hours: 4));

    try {
      // 歩数: getTotalStepsInInterval はHealthKitの統計APIを使うため
      // 複数デバイス（iPhone・Apple Watch・Fitbit）の重複を自動除去する
      final steps = await _health.getTotalStepsInInterval(todayMidnight, now) ?? 0;

      // 心拍数: 直近4時間のサンプルから最新値を取得
      final hrPoints = await _health.getHealthDataFromTypes(
        startTime: fourHoursAgo,
        endTime: now,
        types: [HealthDataType.HEART_RATE],
      );
      final deduped = _health.removeDuplicates(hrPoints);

      double? heartRate;
      String? hrSource;
      DateTime? hrTimestamp;

      for (final point in deduped) {
        if (hrTimestamp == null || point.dateFrom.isAfter(hrTimestamp)) {
          heartRate = (point.value as NumericHealthValue).numericValue.toDouble();
          hrTimestamp = point.dateFrom;
          hrSource = point.sourceName; // どのデバイスのデータか記録
        }
      }

      debugPrint('[HealthService] HR: $heartRate bpm (source: $hrSource), Steps today: $steps');
      return {
        'heart_rate': heartRate,
        'heart_rate_source': hrSource,
        'steps': steps,
        'measured_at': now.toIso8601String(),
        'steps_period': 'today',
        'hr_period_hours': 4,
      };
    } catch (e) {
      debugPrint('[HealthService] fetch error: $e');
      return {
        'heart_rate': null,
        'steps': null,
        'measured_at': now.toIso8601String(),
        'error': e.toString(),
      };
    }
  }
}
