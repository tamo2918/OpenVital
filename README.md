# OpenVital

**Apple Health data as a local REST API.**

OpenVital is an iOS app that reads HealthKit data and serves it as a JSON REST API directly from your iPhone. No cloud, no third-party servers — your health data stays on your device.

## Why?

Apple Health has no official external API. If you want to use your health data in LLM agents, home automation, personal dashboards, or any external tool, there's no straightforward way to access it.

OpenVital solves this by running a lightweight HTTP server on your iPhone that exposes HealthKit data through a clean REST API accessible from your local network.

## Features

- **22+ Health Metrics** — Steps, heart rate, HRV, SpO2, blood pressure, body composition, sleep, workouts, activity rings, and more
- **Zero Dependencies** — Pure Swift implementation with POSIX sockets HTTP server (no external packages)
- **Secure by Default** — Bearer token authentication, Keychain storage, localhost-only by default
- **LAN Mode** — Optionally expose to your local network for access from other devices
- **Cursor-based Pagination** — Efficient data retrieval for large datasets
- **Daily Aggregates** — Pre-computed daily sums/averages for each metric
- **Background Delivery** — HealthKit observer queries keep data fresh
- **Webhook Push** — Automatically POST health data to an external URL when HealthKit detects changes
- **App Intents / Shortcuts** — Export health data or query specific metrics from the iOS Shortcuts app for scheduled automation
- **CORS Support** — Works with browser-based tools and web apps
- **Swift 6 Concurrency** — Actor-based architecture with full strict concurrency

## Requirements

- iOS 17.0+
- Xcode 16+
- Physical iPhone (HealthKit is not available in Simulator)

## Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/tamo2918/OpenVital.git
   ```
2. Open `OpenVital.xcodeproj` in Xcode
3. Select your development team in **Signing & Capabilities**
4. Build and run on a physical iPhone

## API Endpoints

All endpoints return JSON. Authenticated endpoints require the header:
```
Authorization: Bearer <token>
```

The token is displayed in the app's **Token** tab.

### Public

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | Welcome message and endpoint list |
| `GET` | `/v1/status` | Server status, uptime, supported metrics |

### Authenticated

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/metrics/{type}` | Raw health samples (e.g. `stepCount`, `heartRate`) |
| `GET` | `/v1/metrics/{type}/daily` | Daily aggregated values |
| `GET` | `/v1/metrics/{type}/latest` | Most recent sample |
| `GET` | `/v1/sleep` | Sleep stage records |
| `GET` | `/v1/workouts` | Workout list |
| `GET` | `/v1/workouts/{id}` | Workout detail |
| `GET` | `/v1/summary/activity` | Activity ring summaries |
| `GET` | `/v1/permissions` | HealthKit permission statuses |

### Query Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `start` | 7 days ago | Start date (ISO 8601 or `yyyy-MM-dd`) |
| `end` | now | End date |
| `limit` | 100 | Max results per page (1–1000) |
| `cursor` | — | Pagination cursor from previous response |

### Supported Metric Types

**Activity:** `stepCount`, `distanceWalkingRunning`, `activeEnergyBurned`, `basalEnergyBurned`, `flightsClimbed`, `appleExerciseTime`, `appleStandTime`, `distanceCycling`

**Vitals:** `heartRate`, `restingHeartRate`, `heartRateVariabilitySDNN`, `oxygenSaturation`, `respiratoryRate`, `bodyTemperature`, `bloodPressureSystolic`, `bloodPressureDiastolic`

**Body:** `bodyMass`, `height`, `bodyMassIndex`, `bodyFatPercentage`

**Sleep:** `sleepAnalysis`

## Usage Examples

### curl

```bash
# Server status (no auth required)
curl http://localhost:8080/v1/status

# Latest heart rate
curl -H 'Authorization: Bearer YOUR_TOKEN' \
  http://localhost:8080/v1/metrics/heartRate/latest

# Step count for the last 7 days
curl -H 'Authorization: Bearer YOUR_TOKEN' \
  'http://localhost:8080/v1/metrics/stepCount?limit=10'

# Daily step aggregates for the last 30 days
curl -H 'Authorization: Bearer YOUR_TOKEN' \
  'http://localhost:8080/v1/metrics/stepCount/daily?start=2026-01-01&end=2026-02-27'

# Workouts
curl -H 'Authorization: Bearer YOUR_TOKEN' \
  'http://localhost:8080/v1/workouts?limit=5'

# Activity rings
curl -H 'Authorization: Bearer YOUR_TOKEN' \
  http://localhost:8080/v1/summary/activity
```

### Python

```python
import requests

BASE = "http://192.168.x.x:8080"  # Your iPhone's IP in LAN mode
TOKEN = "YOUR_TOKEN"
headers = {"Authorization": f"Bearer {TOKEN}"}

# Get today's step count
resp = requests.get(f"{BASE}/v1/metrics/stepCount/latest", headers=headers)
print(resp.json())

# Get daily heart rate averages
resp = requests.get(f"{BASE}/v1/metrics/heartRate/daily", headers=headers)
for day in resp.json()["data"]:
    print(f"{day['date']}: {day['value']:.0f} bpm")
```

## Webhook

OpenVital can automatically POST health data to an external URL whenever HealthKit detects new data (e.g. new step count, heart rate reading, or workout).

### Setup

1. Open the app → **Settings** tab
2. Enable the **Webhook** toggle
3. Enter your destination URL
4. (Optional) Enter a **Secret** for HMAC-SHA256 request signing
5. Tap **Send Test** to verify

### Payload

```json
{
  "event": "health_data_updated",
  "timestamp": "2026-02-28T08:00:00Z",
  "data": {
    "exportDate": "2026-02-28T08:00:00Z",
    "periodDays": 7,
    "metrics": {
      "stepCount": [
        { "date": "2026-02-27", "value": 8432, "unit": "count" }
      ],
      "heartRate": [
        { "date": "2026-02-27", "value": 72.5, "unit": "count/min" }
      ]
    },
    "sleepRecords": [],
    "workoutRecords": [],
    "activitySummaries": []
  }
}
```

### Signature Verification

When a secret is configured, every request includes an `X-OpenVital-Signature` header containing an HMAC-SHA256 signature of the request body:

```
X-OpenVital-Signature: sha256=abcdef1234567890...
```

Verify on your server by computing `HMAC-SHA256(secret, request_body)` and comparing.

## Shortcuts (App Intents)

OpenVital provides two actions for the iOS **Shortcuts** app, enabling scheduled automation without keeping the app in the foreground.

| Action | Description | Parameters |
|--------|-------------|------------|
| **Export Health Data** | Export all metrics, sleep, workouts, and activity as JSON | `days` (default: 7) |
| **Get Health Metric** | Get daily aggregates for a specific metric | `metric`, `days` (default: 7) |

### Automation Examples

- **Daily health report**: Create a Shortcut that runs "Export Health Data" at 8 AM every day and sends the result to your server via an HTTP POST action.
- **Step count notification**: Run "Get Health Metric" (stepCount) each evening and show a notification with your daily total.
- **Weekly data backup**: Export 7 days of data every Monday and save to iCloud Drive or Google Sheets.

## Example Response

```json
{
  "data": [
    {
      "id": "ABC123",
      "type": "heartRate",
      "value": 76,
      "unit": "count/min",
      "startDate": "2026-02-27T10:30:00Z",
      "endDate": "2026-02-27T10:30:00Z",
      "sourceName": "Apple Watch",
      "sourceBundle": "com.apple.health.D3A1B2C3"
    }
  ],
  "meta": {
    "count": 1,
    "hasMore": false,
    "unit": "count/min",
    "queryStart": "2026-02-20T00:00:00Z",
    "queryEnd": "2026-02-27T15:00:00Z"
  }
}
```

## Architecture

```
OpenVital/
├── Models/
│   ├── HealthMetricType.swift    # 22 metric definitions with HKUnit mappings
│   ├── HealthSample.swift        # Domain models (samples, sleep, workouts)
│   └── APIModels.swift           # Response DTOs
├── Services/
│   ├── HealthKitManager.swift    # HealthKit queries (actor)
│   ├── HealthDataCache.swift     # In-memory cache with pagination (actor)
│   ├── TokenManager.swift        # Keychain-backed token management (actor)
│   ├── RequestLogger.swift       # Ring-buffer request logger (actor)
│   └── WebhookManager.swift     # Webhook delivery with HMAC signing (actor)
├── Server/
│   ├── HTTPServer.swift          # POSIX sockets HTTP/1.1 server
│   └── Router.swift              # Route matching and handlers
├── Intents/
│   ├── ExportHealthDataIntent.swift  # App Intent: export all data as JSON
│   ├── GetMetricIntent.swift         # App Intent: query a specific metric
│   └── OpenVitalShortcuts.swift      # AppShortcutsProvider registration
├── Views/
│   ├── HomeView.swift            # Server status and logs
│   ├── PermissionsView.swift     # HealthKit permission management
│   ├── TokenView.swift           # Token display, QR code, copy
│   └── SettingsView.swift        # Port, LAN mode, webhook, shortcuts
├── AppState.swift                # @Observable app state
├── ContentView.swift             # Tab container
└── OpenVitalApp.swift            # Entry point
```

## Security

- **Bearer token** authentication on all data endpoints
- Tokens are **cryptographically random** (32 bytes) stored in **iOS Keychain**
- Server binds to **localhost only** by default (127.0.0.1)
- LAN mode (0.0.0.0) requires explicit opt-in with warning
- Webhook requests signed with **HMAC-SHA256** when a secret is configured
- No data leaves the device unless you explicitly enable Webhook or LAN mode
- CORS headers included for browser-based clients

## License

MIT
