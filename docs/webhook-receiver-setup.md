# Webhook Receiver Setup Guide

OpenVital の Webhook 機能は、HealthKit データが更新されたときに指定した URL へ JSON を POST 送信します。このガイドでは、受信側サーバーのセットアップ方法を説明します。

---

## 前提条件

- OpenVital アプリの Settings → Webhook が有効になっていること
- 受信サーバーが iPhone からネットワーク的に到達可能であること（同一 Wi-Fi、Tailscale 等）

> **ポート番号について:** OpenVital 自体がデフォルトでポート 8080 を使用します。受信サーバーを同じマシンで動かす場合は問題ありませんが、混同を避けるため **9090 など別のポート** の使用を推奨します。以降の例ではポート 9090 を使用します。

## クイックスタート（Python）

最もシンプルな受信サーバーです。Python 3 のみで動作します（外部ライブラリ不要）。

### 1. ファイルを作成

`webhook_server.py`:

```python
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
from datetime import datetime

PORT = 9090

class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        print(f"\n{'='*60}", flush=True)
        print(f"[{datetime.now().isoformat()}] Webhook received!", flush=True)
        print(f"Path: {self.path}", flush=True)
        print(f"Content-Length: {content_length} bytes", flush=True)

        # HMAC signature (if configured)
        signature = self.headers.get("X-OpenVital-Signature")
        if signature:
            print(f"Signature: {signature}", flush=True)

        # Parse and display payload
        try:
            data = json.loads(body)
            print(f"Event: {data.get('event')}", flush=True)
            print(f"Timestamp: {data.get('timestamp')}", flush=True)
            export = data.get("data", {})
            print(f"Period: {export.get('periodDays')} days", flush=True)
            metrics = export.get("metrics", {})
            print(f"Metrics ({len(metrics)}): {list(metrics.keys())}", flush=True)
            for key, values in metrics.items():
                if values:
                    print(f"  {key}: {len(values)} days, latest={values[-1]}", flush=True)
            print(f"Sleep records: {len(export.get('sleepRecords', []))}", flush=True)
            print(f"Workouts: {len(export.get('workoutRecords', []))}", flush=True)
            print(f"Activity summaries: {len(export.get('activitySummaries', []))}", flush=True)
        except json.JSONDecodeError:
            print(f"Body (raw): {body[:200]}", flush=True)

        print(f"{'='*60}", flush=True)

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

print(f"Webhook server listening on port {PORT}...", flush=True)
print(f"POST http://0.0.0.0:{PORT}/webhook", flush=True)
print("Ctrl+C to stop\n", flush=True)
HTTPServer(("0.0.0.0", PORT), WebhookHandler).serve_forever()
```

### 2. サーバーを起動

```bash
python3 -u webhook_server.py
```

> `-u` フラグを付けることで出力のバッファリングを無効にし、ログがリアルタイムで表示されます。

出力:
```
Webhook server listening on port 9090...
POST http://0.0.0.0:9090/webhook
Ctrl+C to stop
```

### 3. 動作確認（curl で手動テスト）

別のターミナルから:

```bash
# ヘルスチェック
curl http://localhost:9090/webhook

# POST テスト
curl -X POST http://localhost:9090/webhook \
  -H "Content-Type: application/json" \
  -d '{"event":"test","timestamp":"2026-01-01T00:00:00Z","data":{}}'
```

`Webhook received!` と表示されれば OK です。

### 4. OpenVital から送信

OpenVital の Settings → Webhook URL に以下を入力:

```
http://<サーバーのIP>:9090/webhook
```

**IP の確認方法:**

```bash
# Mac の場合
# Wi-Fi IP
ipconfig getifaddr en0

# Tailscale IP
tailscale ip -4
```

「Send Test」ボタンを押して、サーバーのターミナルに受信ログが表示されれば成功です。

---

## クイックスタート（Node.js）

```javascript
// webhook_server.js
const http = require("http");

const PORT = 9090;

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
        const metrics = Object.keys(data.data?.metrics || {});
        console.log(`Metrics (${metrics.length}): ${metrics.join(", ")}`);
        console.log(`Sleep records: ${data.data?.sleepRecords?.length || 0}`);
        console.log(`Workouts: ${data.data?.workoutRecords?.length || 0}`);
        console.log(`Activity summaries: ${data.data?.activitySummaries?.length || 0}`);
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
        print("Signature: VALID", flush=True)
    else:
        print("Signature: INVALID — rejecting request", flush=True)
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
   # 例: 100.88.49.82
   ```

2. **サーバーが `0.0.0.0` でリッスンしていることを確認**（`127.0.0.1` だと Tailscale 経由のアクセスを受け付けない）

3. **ファイアウォールの確認**:
   ```bash
   # Mac: 指定ポートで何がリッスンしているか確認
   lsof -i :9090
   ```

4. **iPhone から到達可能か確認**:
   iPhone の Safari で `http://<Tailscale IP>:9090/webhook` にアクセスして `{"status": "webhook server running"}` が表示されれば OK

5. **OpenVital の Webhook URL に設定**:
   ```
   http://<Tailscale IP>:9090/webhook
   ```

> **注意:** Tailscale の IP（`100.x.x.x`）は iOS にとってローカルネットワークとして扱われません。OpenVital の Info.plist で `NSAllowsArbitraryLoads` が `true` に設定されている必要があります。

---

## トラブルシューティング

### `Could not connect to the server` (error -1004, errno 61)

TCP 接続が拒否（RST）されています。

- 受信サーバーが**起動していない** → `python3 -u webhook_server.py` で起動
- サーバーが `127.0.0.1` でリッスンしている → `0.0.0.0` に変更
- ポートが間違っている → URL とサーバーのポート番号を一致させる
- ファイアウォールでブロックされている → `lsof -i :<ポート>` で確認

### `App Transport Security policy` (error -1022)

iOS が `http://` の通信をブロックしています。

- Info.plist に `NSAllowsArbitraryLoads` が `true` であることを確認
- 変更後はアプリを**再ビルドしてインストール**し直す必要がある

### テストボタンが「ぐるぐる」のまま止まらない

- URLSession の `waitsForConnectivity` が `true` だと、接続できない場合にタイムアウトまで無限に待ち続けます。`false` にすることで即座にエラーを返すようになります（現在のバージョンでは修正済み）

### Webhook が大量に送信される

- HealthKit の Observer Query がメトリクスごとに発火するため、短時間に複数回呼ばれることがあります
- アプリ側で 5 秒のデバウンスを実装済みですが、初回ロード時は多く発火する場合があります

### レスポンスが 200 以外

- サーバーが `200`〜`299` を返さないと OpenVital はエラーとして記録します
- 必ず `200 OK` を返すようにしてください

### Python サーバーにログが表示されない

- Python の stdout はデフォルトでバッファリングされます
- `python3 -u webhook_server.py` で起動するか、`print()` に `flush=True` を付けてください

---

## ペイロード例

実際の送信データ（約 7KB）の構造:

```json
{
  "event": "health_data_updated",
  "timestamp": "2026-02-28T13:26:43Z",
  "data": {
    "exportDate": "2026-02-28T13:26:43Z",
    "periodDays": 7,
    "metrics": {
      "stepCount": [
        { "date": "2026-02-22", "value": 8432.0, "unit": "count" },
        { "date": "2026-02-28", "value": 13014.0, "unit": "count" }
      ],
      "heartRate": [
        { "date": "2026-02-22", "value": 72.5, "unit": "count/min" },
        { "date": "2026-02-28", "value": 127.58, "unit": "count/min" }
      ],
      "activeEnergyBurned": [
        { "date": "2026-02-28", "value": 470.17, "unit": "kcal" }
      ],
      "restingHeartRate": [
        { "date": "2026-02-28", "value": 70.0, "unit": "count/min" }
      ],
      "bodyMass": [
        { "date": "2026-02-23", "value": 58.5, "unit": "kg" }
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

> **メトリクス一覧:** `stepCount`, `distanceWalkingRunning`, `distanceCycling`, `activeEnergyBurned`, `basalEnergyBurned`, `flightsClimbed`, `appleExerciseTime`, `appleStandTime`, `heartRate`, `restingHeartRate`, `heartRateVariabilitySDNN`, `oxygenSaturation`, `bodyMass`, `bodyMassIndex`, `bodyFatPercentage`, `height`
>
> 各メトリクスは日別集計値（DailyAggregate）の配列として送信されます。データが存在しないメトリクスは省略されます。
