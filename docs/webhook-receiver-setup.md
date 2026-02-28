# Webhook Receiver Setup Guide

OpenVital の Webhook 機能は、HealthKit データが更新されたときに指定した URL へ JSON を POST 送信します。このガイドでは、受信側サーバーのセットアップ方法を説明します。

---

## 前提条件

- OpenVital アプリの Settings → Webhook が有効になっていること
- 受信サーバーが iPhone からネットワーク的に到達可能であること（同一 Wi-Fi、Tailscale 等）

## クイックスタート（Python）

最もシンプルな受信サーバーです。Python 3 のみで動作します（外部ライブラリ不要）。

### 1. ファイルを作成

`webhook_server.py`:

```python
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
from datetime import datetime

class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        print(f"\n{'='*60}")
        print(f"[{datetime.now().isoformat()}] Webhook received!")
        print(f"Path: {self.path}")
        print(f"Content-Length: {content_length} bytes")

        # HMAC signature (if configured)
        signature = self.headers.get("X-OpenVital-Signature")
        if signature:
            print(f"Signature: {signature}")

        # Parse and display payload
        try:
            data = json.loads(body)
            print(f"Event: {data.get('event')}")
            print(f"Timestamp: {data.get('timestamp')}")
            export = data.get("data", {})
            print(f"Period: {export.get('periodDays')} days")
            print(f"Metrics: {list(export.get('metrics', {}).keys())}")
            print(f"Sleep records: {len(export.get('sleepRecords', []))}")
            print(f"Workouts: {len(export.get('workoutRecords', []))}")
            print(f"Activity summaries: {len(export.get('activitySummaries', []))}")
        except json.JSONDecodeError:
            print(f"Body (raw): {body[:200]}")

        print(f"{'='*60}")

        # 200 OK を返す（これが重要）
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"status": "ok"}).encode())

    def do_GET(self):
        """ヘルスチェック用"""
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"status": "webhook server running"}).encode())

PORT = 8080

print(f"Webhook server listening on port {PORT}...")
print(f"POST http://0.0.0.0:{PORT}/webhook")
print("Ctrl+C to stop\n")
HTTPServer(("0.0.0.0", PORT), WebhookHandler).serve_forever()
```

### 2. サーバーを起動

```bash
python3 webhook_server.py
```

出力:
```
Webhook server listening on port 8080...
POST http://0.0.0.0:8080/webhook
Ctrl+C to stop
```

### 3. 動作確認（curl で手動テスト）

別のターミナルから:

```bash
# ヘルスチェック
curl http://localhost:8080/webhook

# POST テスト
curl -X POST http://localhost:8080/webhook \
  -H "Content-Type: application/json" \
  -d '{"event":"test","timestamp":"2026-01-01T00:00:00Z","data":{}}'
```

`Webhook received!` と表示されれば OK です。

### 4. OpenVital から送信

OpenVital の Settings → Webhook URL に以下を入力:

```
http://<サーバーのIP>:8080/webhook
```

**IP の確認方法:**

```bash
# Mac の場合
# Wi-Fi IP
ipconfig getifaddr en0

# Tailscale IP
tailscale ip -4
```

---

## クイックスタート（Node.js）

```javascript
// webhook_server.js
const http = require("http");

const PORT = 8080;

const server = http.createServer((req, res) => {
  if (req.method === "POST") {
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", () => {
      console.log(`\n${"=".repeat(60)}`);
      console.log(`[${new Date().toISOString()}] Webhook received!`);
      console.log(`Path: ${req.url}`);
      console.log(`Signature: ${req.headers["x-openvital-signature"] || "none"}`);

      try {
        const data = JSON.parse(body);
        console.log(`Event: ${data.event}`);
        console.log(`Metrics: ${Object.keys(data.data?.metrics || {}).join(", ")}`);
      } catch (e) {
        console.log(`Body: ${body.substring(0, 200)}`);
      }

      console.log(`${"=".repeat(60)}`);
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "ok" }));
    });
  } else {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "webhook server running" }));
  }
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`Webhook server listening on port ${PORT}...`);
  console.log(`POST http://0.0.0.0:${PORT}/webhook`);
});
```

```bash
node webhook_server.js
```

---

## HMAC 署名の検証

OpenVital で Secret を設定すると、リクエストヘッダーに `X-OpenVital-Signature` が付きます。

形式: `sha256=<hex-encoded HMAC-SHA256>`

### Python での検証例

```python
import hmac
import hashlib

def verify_signature(body: bytes, secret: str, signature_header: str) -> bool:
    """
    body: リクエストボディの生バイト列
    secret: OpenVital に設定した Secret 文字列
    signature_header: X-OpenVital-Signature ヘッダーの値
    """
    expected = "sha256=" + hmac.new(
        secret.encode("utf-8"),
        body,
        hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature_header)
```

検証付きサーバーの例（do_POST 内）:

```python
signature = self.headers.get("X-OpenVital-Signature")
if signature:
    SECRET = "your-secret-here"  # OpenVital に設定したものと同じ値
    if verify_signature(body, SECRET, signature):
        print("Signature: VALID")
    else:
        print("Signature: INVALID — rejecting request")
        self.send_response(401)
        self.end_headers()
        return
```

---

## Tailscale 環境での設定

Tailscale を使用している場合:

1. **受信サーバーの Tailscale IP を確認**:
   ```bash
   tailscale ip -4
   # 例: 100.124.110.2
   ```

2. **サーバーが 0.0.0.0 でリッスンしていることを確認**（127.0.0.1 だと Tailscale 経由のアクセスを受け付けない）

3. **ファイアウォールの確認**:
   ```bash
   # Mac: ポート 8080 が開いているか確認
   lsof -i :8080
   ```

4. **iPhone から到達可能か確認**:
   iPhone の Safari で `http://100.124.110.2:8080/webhook` にアクセスして `{"status": "webhook server running"}` が表示されれば OK

5. **OpenVital の Webhook URL に設定**:
   ```
   http://100.124.110.2:8080/webhook
   ```

---

## トラブルシューティング

### `Could not connect to the server` (error -1004)

- 受信サーバーが**起動していない** → `python3 webhook_server.py` で起動
- サーバーが `127.0.0.1` でリッスンしている → `0.0.0.0` に変更
- ポートが間違っている → URL とサーバーのポート番号を一致させる
- ファイアウォールでブロックされている → `lsof -i :8080` で確認

### `The resource could not be loaded because the App Transport Security policy` (error -1022)

- `http://` を使用している → Info.plist に `NSAllowsArbitraryLoads` が `true` であることを確認
- アプリを再ビルドしてインストールし直す

### `Connection refused` (errno 61, TCP RST)

- サーバーのポートで何もリッスンしていない → サーバーを起動する
- 別のポートでリッスンしている → ポート番号を確認

### Webhook が大量に送信される

- HealthKit の Observer Query がメトリクスごとに発火するため、短時間に複数回呼ばれることがあります
- アプリ側で 5 秒のデバウンスを実装済みですが、初回ロード時は多く発火する場合があります

### レスポンスが 200 以外

- サーバーが `200`〜`299` を返さないと OpenVital はエラーとして記録します
- 必ず `200 OK` を返すようにしてください

---

## ペイロード例

```json
{
  "event": "health_data_updated",
  "timestamp": "2026-02-28T08:00:00Z",
  "data": {
    "exportDate": "2026-02-28T08:00:00Z",
    "periodDays": 7,
    "metrics": {
      "stepCount": [
        { "date": "2026-02-21", "value": 8432.0, "unit": "count" },
        { "date": "2026-02-22", "value": 10241.0, "unit": "count" }
      ],
      "heartRate": [
        { "date": "2026-02-21", "value": 72.5, "unit": "count/min" }
      ],
      "activeEnergyBurned": [
        { "date": "2026-02-21", "value": 450.3, "unit": "kcal" }
      ]
    },
    "sleepRecords": [
      {
        "id": "ABC-123",
        "stage": "asleepDeep",
        "startDate": "2026-02-27T23:30:00Z",
        "endDate": "2026-02-28T01:15:00Z",
        "durationMinutes": 105.0,
        "sourceName": "Apple Watch"
      }
    ],
    "workoutRecords": [
      {
        "id": "DEF-456",
        "activityType": "running",
        "activityTypeCode": 37,
        "startDate": "2026-02-27T07:00:00Z",
        "endDate": "2026-02-27T07:35:00Z",
        "durationMinutes": 35.0,
        "totalEnergyBurned": 320.5,
        "totalEnergyBurnedUnit": "kcal",
        "totalDistance": 5200.0,
        "totalDistanceUnit": "m",
        "sourceName": "Apple Watch",
        "sourceBundle": "com.apple.health"
      }
    ],
    "activitySummaries": [
      {
        "date": "2026-02-27",
        "activeEnergyBurned": 450.3,
        "activeEnergyBurnedGoal": 500.0,
        "activeEnergyBurnedUnit": "kcal",
        "appleExerciseTime": 32.0,
        "appleExerciseTimeGoal": 30.0,
        "appleStandHours": 10.0,
        "appleStandHoursGoal": 12.0
      }
    ]
  }
}
```
