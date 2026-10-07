# CLAUDE.md — ストレス介入システム（Flutter アプリ）

## プロジェクト概要

研究テーマ「聴覚アプローチを用いたストレス介入システムの開発」の iOS クライアント。
HealthKit から生体データ（心拍数・歩数）を取得して Flask サーバーへ送信し、
Flask からのポーリングで介入命令を受け取ってリラックス音楽を再生する。

**GitHub:** `github.com/2232140/My_project_2026`
**対象プラットフォーム:** iOS（Fitbit → Apple Health → HealthKit 経由）
**Flutter SDK:** 3.x 系（Dart 3）

---

## ディレクトリ構成（主要ファイル）

```
stress_intervention_app/lib/
├── main.dart                        # エントリーポイント
├── screens/
│   └── dashboard_screen.dart        # メイン画面（唯一の画面）
└── services/
    ├── api_service.dart             # Flask との HTTP 通信
    ├── health_service.dart          # HealthKit データ取得
    ├── audio_service.dart           # 音楽再生（audioplayers）
    └── firebase_service.dart        # Firebase（現在未使用・将来のため保持）
```

---

## システムフロー

```
アプリ起動
  ↓（5秒後に自動開始）
┌─ 定期送信タイマー（_sendIntervalMinutes 分ごと）
│    HealthKit → fetchRecentData() → POST /api/health_data → MongoDB
│
├─ ポーリングタイマー（_pollIntervalSeconds 秒ごと）
│    GET /api/get_intervention → pending コマンドあれば処理
│    → stress_on 受信 → ダイアログ表示 → 音楽再生 or 拒否
│    → ACK POST /api/acknowledge_intervention
│
└─ UI リフレッシュタイマー（_uiRefreshIntervalSeconds 秒ごと）
     HealthKit から silent fetch して数値を表示更新（ログなし）
```

---

## タイミング定数（`dashboard_screen.dart` 冒頭）

```dart
static const int _sendIntervalMinutes    = 1;   // 本番: 5
static const int _pollIntervalSeconds    = 30;  // 本番: 30（変更不要）
static const int _uiRefreshIntervalSeconds = 30;
```

音楽の自動停止タイマー（`_playMusic()` 内）:
```dart
Timer(const Duration(seconds: 15), ...)  // テスト用。本番は数分に延ばす
```

---

## 主要サービス

### `ApiService`（シングルトン）

| メソッド | 説明 |
|---|---|
| `setBaseUrl(url)` | Flask の URL を設定（空文字・末尾スラッシュを考慮済み） |
| `sendHealthData(userId, healthData)` | POST /api/health_data |
| `checkIntervention(userId)` | GET /api/get_intervention（ポーリング） |
| `acknowledgeIntervention(commandId, userId)` | POST /api/acknowledge_intervention |
| `logStressEvent(eventType, extraData)` | POST /api/log_stress_event |

- `user_id` は全リクエストに含める（Flask 側の `is_stressed` 同期に必要）
- 接続 URL は SharedPreferences に保存・復元される

### `HealthService`（シングルトン）

- `requestPermissions()`: HealthKit アクセス許可を要求
- `fetchRecentData()`: 心拍数（直近4時間の最新値）と歩数（今日の合計）を返す
  - 歩数は `getTotalStepsInInterval` を使用（複数デバイスの重複を HealthKit 側で除去）
  - 心拍数のソースは `hrSource` フィールドで記録（Fitbit / Apple Watch / HealthKit など）
- **既知の課題**: Google Health 連携時に Google 側データが優先されることがある

### `AudioService`

- `playRelaxMusic()`: アセット音源を再生
- `setLoop(true)`: ループ再生設定
- `stop()`: 停止

---

## `DashboardScreen` の状態変数

| 変数 | 型 | 説明 |
|---|---|---|
| `_isStressActive` | bool | ストレス ON/OFF（UI の色・テキスト・アニメーションを制御） |
| `_isPlayingMusic` | bool | 音楽再生中フラグ（audioplayers のコールバックで更新） |
| `_isSendingPeriodically` | bool | 定期送信タイマー稼働中 |
| `_isPollingActive` | bool | ポーリングタイマー稼働中（インジケーター dot の色に使用） |
| `_healthData` | Map? | 直近の HealthKit データ |

---

## ストレス状態フロー（Flutter 側）

```
Flask から stress_on 受信
  ↓
_handleStressStatusChange(true)
  → _isStressActive = true（UI 赤色・アニメーション開始）
  → _sendEventToFlask('stress_received')
  → _showStressInterventionDialog()
      ├─ 「はい」→ _playMusic() → _sendEventToFlask('music_started')
      └─ 「いいえ」→ _sendEventToFlask('music_declined')
                     → Flask が is_stressed=False + クールダウン + pending 削除

音楽停止時（手動 or 15秒タイムアウト）
  → _stopMusic(reason: 'manual_user' | 'auto_timeout')
  → _isStressActive = false（常に setState、ガード条件なし）
  → _sendEventToFlask('music_stopped')
  → Flask が is_stressed=False + クールダウン + pending 削除 + auto_stress_recovered 記録
```

**重要な設計判断:**
- `_handleStressStatusChange` にはガード `if (isActive == _isStressActive) return` がある
  → `_stopMusic()` で必ず `_isStressActive = false` にリセットしないと次の通知が届かない
- `_stopMusic()` は `_isStressActive` の現在値に関わらず常に setState を実行する

---

## Firebase について

**現在未使用。ポーリング方式に完全移行済み。**

関連コードはコメントアウトで保持（削除しない）:
- `_toggleFirebaseListener()` メソッド
- `_isFirebaseListening` フィールド
- Firebase 関連 import
- `firebase_service.dart`（`dispose()` で使用中のため import は維持）
- 設定パネルの Firebase URL / path テキストフィールド（UI に表示したまま）

---

## 設定・接続情報の永続化

SharedPreferences に保存:
- `participant_id`: 参加者 ID（例: `participant_001`）
- `flask_url`: Flask サーバーの URL（例: `http://192.168.x.x:5000`）

アプリ起動 → `_loadSettings()` → 5秒後に自動で定期送信・ポーリング・UI リフレッシュを開始。

---

## コード規約

- **既存コードは削除せずコメントアウトで保持**（明示的な削除指示がない限り）
- `_sendEventToFlask()` を使う際は `user_id` を extraData に含める（Flask の状態同期に必須）
- HealthKit ログは `_refreshHealthData(silent: true)` で抑制済み（ログパネルに出さない）
- iOS 向けのみテスト実施。Android / macOS / Windows は未確認。

---

## ビルド・実行

```bash
cd stress_intervention_app
flutter pub get
flutter run  # iPhone を接続して実行
```

iOS の HealthKit 権限: `ios/Runner/Info.plist` に `NSHealthShareUsageDescription` が必要（設定済み）。

---

## 残タスク（優先順）

1. **E2E 動作確認**（実機で全自動フローを通す）
2. **本番パラメータへの切り替え**
   - `_sendIntervalMinutes = 5`
   - 音楽自動停止タイマーを 5〜10 分に変更
3. **ミニ PC デプロイ後に Flask URL をデフォルト値に設定**
4. **実験本番対応**（参加者 ID 管理・Flask URL の固定）

詳細は `../TODO.md`（Flask サーバー側リポジトリ）を参照。
