"""
ストレス介入システム - Flaskサーバー拡張実装例
このスクリプトは、Flutterアプリから送信されるイベント（ストレス通知受領や音楽再生開始などの履歴）を
受け取り、ローカルのMongoDBに保存するためのFlask用エンドポイントの実装例です。

現在お使いのFlaskサーバーのコードに、以下のように組み込んでご使用ください。
"""

from flask import Flask, request, jsonify
from flask_cors import CORS  # Flutterからの通信を許可するためにCORSが必要な場合があります
from pymongo import MongoClient
from datetime import datetime

app = Flask(__name__)
CORS(app)  # 全てのエンドポイントでCORSを有効化（開発用）

# ----------------------------------------------------
# MongoDB 接続設定
# ----------------------------------------------------
# 必要に応じて、接続文字列やDB名、コレクション名を変更してください。
MONGO_URI = "mongodb://localhost:27017/"
DB_NAME = "stress_intervention_db"
COLLECTION_NAME = "event_logs"

try:
    client = MongoClient(MONGO_URI)
    db = client[DB_NAME]
    collection = db[COLLECTION_NAME]
    print(f"Successfully connected to MongoDB: {DB_NAME} -> {COLLECTION_NAME}")
except Exception as e:
    print(f"Failed to connect to MongoDB: {e}")

# ----------------------------------------------------
# API エンドポイント: ストレスイベントの記録
# ----------------------------------------------------
@app.route('/api/log_stress_event', methods=['POST'])
def log_stress_event():
    try:
        # リクエストからJSONデータを取得
        data = request.get_json()
        if not data:
            return jsonify({"status": "error", "message": "No JSON payload received"}), 400

        # 必要不可欠なフィールド
        event_type = data.get('event_type')
        timestamp_str = data.get('timestamp')
        
        if not event_type:
            return jsonify({"status": "error", "message": "Missing required field: event_type"}), 400

        # タイムスタンプのパース（省略された場合は現在時刻）
        if timestamp_str:
            try:
                timestamp = datetime.fromisoformat(timestamp_str)
            except ValueError:
                timestamp = datetime.utcnow()
        else:
            timestamp = datetime.utcnow()

        # MongoDBに保存するドキュメントの構築
        log_document = {
            "timestamp": timestamp,
            "event_type": event_type,
            "device": data.get('device', 'Flutter_App'),
            "received_at": datetime.utcnow(),  # サーバー側での受領時刻
            # 追加データ（source, 心拍数等）があればまとめて格納
            "extra_data": {k: v for k, v in data.items() if k not in ['event_type', 'timestamp', 'device']}
        }

        # MongoDBへの書き込み
        result = collection.insert_one(log_document)
        
        print(f"Logged event in MongoDB: {event_type} (ID: {result.inserted_id})")
        
        return jsonify({
            "status": "success",
            "message": "Event logged successfully",
            "id": str(result.inserted_id)
        }), 201

    except Exception as e:
        print(f"Error handling event log: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

# ----------------------------------------------------
# (参考) 既存の心拍数データ受領およびストレス判定エンドポイントの例
# ----------------------------------------------------
# ※ ユーザー様がすでに作成されている仕組みのイメージです。
@app.route('/api/heart_rate', methods=['POST'])
def heart_rate():
    # Garmin等から送られてきた心拍数を処理してMongoDBに保存
    # 平均値が90を超えたら Firebase 上のコントロールをONにするロジック
    pass

if __name__ == '__main__':
    # ローカルネットワーク上のスマホやエミュレータからアクセス可能にするため、
    # host='0.0.0.0' で起動することをお勧めします。
    app.run(host='0.0.0.0', port=5000, debug=True)
