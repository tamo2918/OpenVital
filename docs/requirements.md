# OpenVital 要件定義書

**バージョン:** 1.0.0
**作成日:** 2026-02-26
**ステータス:** Draft

---

## 目次

1. [プロジェクト概要](#1-プロジェクト概要)
2. [背景と課題](#2-背景と課題)
3. [ソリューション概要](#3-ソリューション概要)
4. [ステークホルダーとユーザー](#4-ステークホルダーとユーザー)
5. [機能要件](#5-機能要件)
6. [非機能要件](#6-非機能要件)
7. [技術スタック](#7-技術スタック)
8. [システムアーキテクチャ](#8-システムアーキテクチャ)
9. [HealthKit データモデル](#9-healthkit-データモデル)
10. [REST API 仕様](#10-rest-api-仕様)
11. [セキュリティ設計](#11-セキュリティ設計)
12. [バックグラウンド処理設計](#12-バックグラウンド処理設計)
13. [UI/UX 要件](#13-uiux-要件)
14. [開発フェーズ計画](#14-開発フェーズ計画)
15. [制約事項・既知の制限](#15-制約事項既知の制限)
16. [App Store 審査対応](#16-app-store-審査対応)
17. [用語集](#17-用語集)

---

## 1. プロジェクト概要

### 1.1 アプリ名

**OpenVital** — Open Vitals API for HealthKit

### 1.2 一言説明

iPhone の HealthKit データを、ユーザー自身のデバイス上でローカル HTTP API として安全に公開する iOS アプリ。

### 1.3 目的

Apple Health（HealthKit）が外部から直接アクセスできる公式 API を提供していないという制約を、デバイス上で動作するローカル HTTP サーバーによって解決する。これにより、LLM エージェント・ホームオートメーション・個人ダッシュボードなど、任意の外部ツールが健康データにアクセスできるようになる。

### 1.4 スコープ

| 対象 | 内容 |
|------|------|
| **IN** | HealthKit データの読み取りと REST API 提供 |
| **IN** | iOS アプリとしての UI（サーバー管理・権限・トークン） |
| **IN** | バックグラウンドでのデータ同期 |
| **OUT** | HealthKit への書き込み（将来フェーズ） |
| **OUT** | クラウドサービスへのデータ送信 |
| **OUT** | Android / ウェアラブル対応 |

---

## 2. 背景と課題

### 2.1 Apple Health の現状

Apple の Health アプリと HealthKit フレームワークは、iOS 8（2014年）より提供されているヘルスデータの中央集約リポジトリである。歩数・心拍数・睡眠・体重・血圧など 150 種類以上の健康指標を管理できる一方で、以下の重大な制約がある。

**公式 API の欠如:**
- Apple は 2026 年現在においても、外部サービスや PC・Mac から HealthKit データに直接アクセスするための公式 Web API や OAuth フローを提供していない
- データへのアクセスは iOS/watchOS アプリ内からのみ可能（HealthKit フレームワーク経由）
- macOS の Apple Health アプリ（2023年〜）は存在するが、外部 API は未提供

**ユーザーが直面する問題:**
- 個人の AI エージェント・LLM に健康データを参照させられない
- Home Assistant・Grafana 等のダッシュボードに健康データを取り込めない
- 自作スクリプト・ツールから健康データを取得できない
- XML エクスポート（手動）しか選択肢がなく、自動化できない

### 2.2 既存の回避策とその限界

| 手法 | 限界 |
|------|------|
| XML 手動エクスポート | 自動化不可、データが巨大になる |
| iOS Shortcuts + Webhook | リアルタイム性に欠ける、設定が複雑 |
| サードパーティアプリ（Health Auto Export 等） | クローズドソース、課金必須、データが外部サーバー経由 |
| React Native Bridge | アプリ内利用のみ、外部公開不可 |

### 2.3 OpenVital が解決するもの

OpenVital は、**iPhone デバイス上で動作するローカル HTTP サーバー**として機能することで、同一ネットワーク上の任意のクライアント（LLM・PC・スマートホームシステム等）が REST API を通じて健康データにアクセスできる仕組みを提供する。

---

## 3. ソリューション概要

### 3.1 動作概念図

```
┌─────────────────────────────────────────────────────────────┐
│                         iPhone                               │
│                                                              │
│  ┌─────────────┐    HealthKit     ┌──────────────────────┐  │
│  │  Apple      │ ←───────────── │   OpenVital App       │  │
│  │  Health     │                 │                        │  │
│  │  (HealthKit)│ ──────────────→ │  ┌────────────────┐  │  │
│  └─────────────┘   HKSampleQuery │  │  Local HTTP    │  │  │
│                                  │  │  Server        │  │  │
│                                  │  │  :8080         │  │  │
│                                  │  └────────┬───────┘  │  │
│                                  └───────────┼───────────┘  │
└──────────────────────────────────────────────┼──────────────┘
                                               │ localhost / LAN
                         ┌─────────────────────┼────────────────┐
                         │                     │                │
                  ┌──────▼──────┐    ┌─────────▼──────┐  ┌─────▼──────┐
                  │  LLM Agent  │    │  Grafana /      │  │  自作      │
                  │  (Claude等) │    │  Dashboard      │  │  スクリプト│
                  └─────────────┘    └─────────────────┘  └───────────┘
```

### 3.2 コアバリュープロポジション

1. **プライバシーファースト** - データはデバイスの外に出ない。クラウド経由なし
2. **簡単なセットアップ** - アプリを起動してトークンをコピーするだけ
3. **標準的な REST API** - curl / fetch / Python requests で即座に使える
4. **オープンソース** - 何をしているか完全に透明

---

## 4. ステークホルダーとユーザー

### 4.1 主要ユーザー

| ユーザー像 | ニーズ |
|-----------|--------|
| **開発者・エンジニア** | LLM エージェント・個人ツールに健康データを組み込みたい |
| **セルフトラッカー** | Grafana・Obsidian 等で健康データを可視化・分析したい |
| **AI パワーユーザー** | Claude・GPT 等に日々の健康状態を参照させたい |
| **ホームオートメーション愛好家** | Home Assistant や Node-RED に健康データを流したい |

### 4.2 技術要件の前提

- iOS 16.0 以上の iPhone を所有
- 同一 Wi-Fi ネットワーク上にクライアントデバイスが存在（または localhost 直接）
- HealthKit に蓄積されたデータが存在（Apple Watch や他のアプリによる記録）

---

## 5. 機能要件

### 5.1 HealthKit 権限管理

| ID | 要件 |
|----|------|
| HK-01 | アプリ初回起動時に HealthKit の読み取り権限をリクエストする |
| HK-02 | 対応する全データタイプの読み取り権限を一括リクエストできる |
| HK-03 | 個別のデータタイプごとに権限の付与状況を UI に表示する |
| HK-04 | 権限が拒否されたデータタイプへのリクエストは 403 を返す |
| HK-05 | 権限の再リクエストボタン（iOS 設定アプリへの誘導）を提供する |

### 5.2 ローカル HTTP サーバー

| ID | 要件 |
|----|------|
| SRV-01 | アプリ起動時に自動でローカル HTTP サーバーを起動する |
| SRV-02 | デフォルトポートは 8080 とし、8081〜8090 の範囲でユーザーが変更できる |
| SRV-03 | サーバーはデフォルトで `127.0.0.1`（loopback）にバインドする |
| SRV-04 | ユーザーが明示的に許可した場合のみ LAN（0.0.0.0）にバインドする |
| SRV-05 | サーバーの起動・停止状態をリアルタイムで UI に表示する |
| SRV-06 | アプリがフォアグラウンドにある間、サーバーは常時稼働する |
| SRV-07 | バックグラウンド移行時はサーバーを一時停止し、フォアグラウンド復帰時に再起動する |
| SRV-08 | サーバーへの全リクエスト・レスポンスをアプリ内ログとして最大 1000 件保持する |

### 5.3 認証・セキュリティ

| ID | 要件 |
|----|------|
| AUTH-01 | アプリ初回起動時に 32 バイトのランダム Bearer トークンを生成し Keychain に保存する |
| AUTH-02 | 全 API エンドポイントで `Authorization: Bearer {token}` ヘッダーを必須とする |
| AUTH-03 | 無効または欠如したトークンには HTTP 401 を返す |
| AUTH-04 | トークンを UI 上でコピーまたは QR コードとして表示する機能を提供する |
| AUTH-05 | ユーザーがトークンを再生成できる機能を提供する（既存トークンは無効化） |
| AUTH-06 | レート制限: 同一 IP から 60 リクエスト/分を超えた場合 HTTP 429 を返す |

### 5.4 API エンドポイント

#### 5.4.1 ステータス系

| ID | 要件 |
|----|------|
| API-01 | `GET /v1/status` — サーバー状態・バージョン・対応データタイプ一覧を返す |
| API-02 | `GET /v1/permissions` — 各データタイプの権限状態一覧を返す |

#### 5.4.2 健康データ系

| ID | 要件 |
|----|------|
| API-03 | `GET /v1/metrics/{type}` — 指定タイプの生サンプル一覧を返す |
| API-04 | `GET /v1/metrics/{type}/daily` — 指定タイプの日次集計を返す |
| API-05 | `GET /v1/metrics/{type}/latest` — 最新 1 件のサンプルを返す |
| API-06 | `GET /v1/workouts` — ワークアウト一覧を返す |
| API-07 | `GET /v1/workouts/{id}` — 特定ワークアウトの詳細を返す |
| API-08 | `GET /v1/summary/activity` — アクティビティリング（ムーブ・エクササイズ・スタンド）の集計を返す |
| API-09 | `GET /v1/sleep` — 睡眠ステージの一覧を返す（`/metrics/sleepAnalysis` のエイリアス） |

#### 5.4.3 クエリパラメータ

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| `start` | ISO 8601 | 取得開始日時（デフォルト: 7日前） |
| `end` | ISO 8601 | 取得終了日時（デフォルト: 現在） |
| `limit` | integer | 1ページあたり最大件数（デフォルト: 100、最大: 1000） |
| `cursor` | string | 次ページ取得用カーソル（前レスポンスの `meta.nextCursor`） |
| `interval` | string | `raw` / `hourly` / `daily` / `weekly`（集計粒度） |
| `aggregation` | string | `sum` / `avg` / `min` / `max`（interval 指定時） |
| `sources` | string | カンマ区切りのソース名フィルター（例: `Apple Watch,iPhone`） |

### 5.5 データキャッシュ・同期

| ID | 要件 |
|----|------|
| CACHE-01 | アプリ起動時に過去 30 日分のデータをメモリキャッシュに読み込む |
| CACHE-02 | `HKObserverQuery` + `enableBackgroundDelivery` でデータ変更を監視する |
| CACHE-03 | `HKAnchoredObjectQuery` を用いた差分更新でキャッシュを効率的に更新する |
| CACHE-04 | アンカー（HKQueryAnchor）を UserDefaults に永続化し、再起動後も差分取得を継続する |
| CACHE-05 | HTTP サーバーはキャッシュのみを参照し、HealthKit を直接クエリしない |
| CACHE-06 | キャッシュ最終更新日時を API レスポンスの `meta` に含める |

---

## 6. 非機能要件

### 6.1 パフォーマンス

| 要件 | 目標値 |
|------|--------|
| API 応答時間（キャッシュヒット時） | 100ms 以内 |
| アプリ起動からサーバー起動まで | 3秒以内 |
| 初回キャッシュ構築（30日分） | 10秒以内 |
| メモリ使用量（キャッシュ込み） | 100MB 以下 |
| 1リクエストあたりの最大レスポンスサイズ | 5MB 以下 |

### 6.2 信頼性・可用性

- アプリがフォアグラウンドの間、サーバーの稼働率 99% 以上
- クラッシュ後の自動再起動（次回起動時）
- HealthKit 権限エラー時も他のエンドポイントは正常稼働

### 6.3 プライバシー・データ保護

- 健康データは iOS デバイスの外部に送信しない
- ログ（リクエストログ）には健康データの値を含めない（URLとステータスコードのみ）
- アプリ削除時に Keychain のトークンも削除する
- 健康データをローカルストレージ（SQLite 等）に永続化しない（メモリキャッシュのみ）

### 6.4 互換性

- 最小 iOS バージョン: iOS 16.0
- 対応デバイス: iPhone（iPad は対象外）
- Xcode 16.0 以上でビルド可能
- Swift 5.10 以上

---

## 7. 技術スタック

### 7.1 プラットフォーム・言語

| 項目 | 選定内容 | 理由 |
|------|---------|------|
| 言語 | Swift 5.10+ | iOS 標準、HealthKit との親和性 |
| UI フレームワーク | SwiftUI | iOS 16+ 対象、宣言的 UI |
| 最小 iOS バージョン | iOS 16.0 | HKAnchoredObjectQuery async サポート、モダン API |
| アーキテクチャ | Clean Architecture + MVVM | テスタビリティ、関心分離 |

### 7.2 主要依存ライブラリ

| ライブラリ | バージョン | 用途 | 選定理由 |
|-----------|---------|------|---------|
| **Telegraph** | latest | HTTP/HTTPS ローカルサーバー | アクティブメンテナンス、TLS サポート、localhost バインド対応、Swift ネイティブ |
| （標準ライブラリのみ） | - | その他全般 | 外部依存を最小化 |

**Telegraph を選定した理由（比較）:**

| ライブラリ | メンテナンス | TLS | Swift | 選定 |
|-----------|------------|-----|-------|------|
| Telegraph | ○ 活発 | ○ ネイティブ | ○ | **採用** |
| Swifter | △ 停滞気味 | × なし | ○ | - |
| GCDWebServer | × アーカイブ済 | × なし | × (ObjC) | - |
| Embassy | △ 低頻度 | × なし | ○ | - |
| SwiftNIO | ○ Apple製 | ○ | ○ | 複雑すぎる |

### 7.3 パッケージ管理

Swift Package Manager (SPM) を使用。CocoaPods / Carthage は使用しない。

---

## 8. システムアーキテクチャ

### 8.1 レイヤー構成

```
┌──────────────────────────────────────────────────────────────┐
│                   Presentation Layer (SwiftUI)               │
│  ServerStatusView │ PermissionsView │ TokenView │ LogView    │
│           ViewModel (ObservableObject / @Observable)         │
└──────────────────────────┬───────────────────────────────────┘
                           │ Use Cases
┌──────────────────────────▼───────────────────────────────────┐
│                      Domain Layer                            │
│  ┌────────────────────┐  ┌──────────────────────────────┐   │
│  │ Use Cases          │  │ Domain Models                │   │
│  │ FetchMetricsUC     │  │ HealthSample                 │   │
│  │ FetchWorkoutsUC    │  │ DailyAggregate               │   │
│  │ FetchSleepUC       │  │ WorkoutRecord                │   │
│  │ FetchActivityUC    │  │ SleepRecord                  │   │
│  └────────────────────┘  │ ActivitySummary              │   │
│  ┌────────────────────┐  └──────────────────────────────┘   │
│  │ Repository Protocol│                                      │
│  │ HealthRepository   │                                      │
│  └────────────────────┘                                      │
└───────────┬──────────────────────────────┬───────────────────┘
            │                              │
┌───────────▼────────────┐  ┌─────────────▼──────────────────┐
│   Data Layer           │  │   Server Layer                 │
│ HealthKitRepository    │  │ HealthAPIServer (Telegraph)    │
│ HKHealthStore          │  │ RouteHandler                   │
│ HKSampleQuery          │  │ AuthMiddleware                 │
│ HKStatisticsQuery      │  │ RateLimitMiddleware            │
│ HKAnchoredObjectQuery  │  │ ResponseSerializer             │
│ HKObserverQuery        │  │ RequestLogger                  │
│ HealthDataCache        │  │                                │
│ (in-memory)            │  │                                │
└────────────────────────┘  └────────────────────────────────┘
            │
┌───────────▼────────────┐
│   Infrastructure       │
│ TokenManager (Keychain)│
│ SettingsManager        │
│ AnchorStorage          │
│ (UserDefaults)         │
└────────────────────────┘
```

### 8.2 データフロー

#### フォアグラウンド時

```
HTTP クライアント
    → HealthAPIServer (localhost:8080)
        → AuthMiddleware (Bearer token 検証)
            → RouteHandler
                → UseCase
                    → HealthDataCache (メモリ読み取り)
                        → JSON レスポンス生成
                            → HTTP クライアントへ返却
```

#### バックグラウンド更新フロー

```
HealthKit 新規データ書き込み
    → HKObserverQuery コールバック (システムがアプリを起動)
        → HKAnchoredObjectQuery (差分取得)
            → HealthDataCache 更新
                → 新しいアンカーを UserDefaults に保存
                    → completionHandler() 呼び出し (必須)
```

### 8.3 サーバーライフサイクル

```swift
// ScenePhase に応じたサーバー管理
.onChange(of: scenePhase) { _, newPhase in
    switch newPhase {
    case .active:   server.start()
    case .inactive: break          // 短時間の inactive は維持
    case .background: server.stop()
    }
}
```

---

## 9. HealthKit データモデル

### 9.1 対応データタイプ（フェーズ1）

#### 活動量・運動

| 識別子 | 単位 | 集計方法 | 優先度 |
|-------|------|---------|--------|
| `stepCount` | count | cumulativeSum | 最高 |
| `distanceWalkingRunning` | m | cumulativeSum | 高 |
| `activeEnergyBurned` | kcal | cumulativeSum | 高 |
| `basalEnergyBurned` | kcal | cumulativeSum | 中 |
| `flightsClimbed` | count | cumulativeSum | 中 |
| `appleExerciseTime` | min | cumulativeSum | 高 |
| `appleStandTime` | min | cumulativeSum | 中 |
| `distanceCycling` | m | cumulativeSum | 中 |

#### バイタルサイン

| 識別子 | 単位 | 集計方法 | 優先度 |
|-------|------|---------|--------|
| `heartRate` | count/min | discreteAverage | 最高 |
| `restingHeartRate` | count/min | discreteAverage | 最高 |
| `heartRateVariabilitySDNN` | ms | discreteAverage | 高 |
| `oxygenSaturation` | % | discreteAverage | 高 |
| `respiratoryRate` | count/min | discreteAverage | 中 |
| `bodyTemperature` | degC | discreteAverage | 中 |

#### 体格測定

| 識別子 | 単位 | 集計方法 | 優先度 |
|-------|------|---------|--------|
| `bodyMass` | kg | discreteAverage | 高 |
| `height` | m | discreteAverage | 中 |
| `bodyMassIndex` | count | discreteAverage | 中 |
| `bodyFatPercentage` | % | discreteAverage | 中 |

#### カテゴリ系

| 識別子 | 値の種類 | 優先度 |
|-------|---------|--------|
| `sleepAnalysis` | inBed / asleepCore / asleepDeep / asleepREM / awake | 最高 |
| `appleStandHour` | stood / idle | 中 |
| `mindfulSession` | duration | 低 |

#### ワークアウト

- `HKWorkoutType` — 全ワークアウトタイプ（100+種類）
- 記録項目: activityType, startDate, endDate, duration, totalEnergyBurned, totalDistance, sourceName

#### 血圧（Correlation）

| 識別子 | 内容 |
|-------|------|
| `bloodPressure` | systolic + diastolic のペア |

### 9.2 フェーズ2（将来対応）

- 血糖値（`bloodGlucose`）
- 栄養素（`dietaryEnergyConsumed`他）
- 心電図（`electrocardiogram`）
- VO2 Max（`vo2Max`）
- 生理サイクル関連
- 臨床記録（`HKClinicalType` — 特別な Entitlement 申請が必要）

---

## 10. REST API 仕様

### 10.1 ベース URL

```
http://localhost:8080
```

全エンドポイントは `/v1/` プレフィックスを持つ。

### 10.2 認証

全リクエストに以下のヘッダーが必要:

```
Authorization: Bearer {token}
```

### 10.3 共通レスポンス形式

#### 成功レスポンス

```json
{
  "data": [...],
  "meta": {
    "count": 100,
    "hasMore": true,
    "nextCursor": "eyJzdGFydERhdGUi...",
    "queryStart": "2026-02-19T00:00:00Z",
    "queryEnd": "2026-02-26T23:59:59Z",
    "cachedAt": "2026-02-26T10:30:00Z"
  }
}
```

#### エラーレスポンス

```json
{
  "error": {
    "code": "unauthorized",
    "message": "Invalid or missing Bearer token",
    "status": 401
  }
}
```

### 10.4 エンドポイント詳細

#### `GET /v1/status`

サーバーおよびアプリの状態を返す。認証不要。

```json
{
  "version": "1.0.0",
  "status": "running",
  "port": 8080,
  "uptime": 3600,
  "cacheLastUpdated": "2026-02-26T10:30:00Z",
  "supportedMetrics": [
    "stepCount",
    "heartRate",
    "sleepAnalysis",
    "..."
  ]
}
```

---

#### `GET /v1/permissions`

各データタイプの HealthKit 権限状態を返す。

```json
{
  "data": {
    "stepCount": "authorized",
    "heartRate": "authorized",
    "bodyMass": "notDetermined",
    "bloodGlucose": "denied"
  }
}
```

権限値: `"authorized"` / `"denied"` / `"notDetermined"`

---

#### `GET /v1/metrics/{type}`

生サンプル一覧を返す。

**パスパラメータ:**
- `type`: HealthKit 識別子（例: `stepCount`, `heartRate`, `bodyMass`）

**クエリパラメータ:**
- `start`: ISO 8601 日時（デフォルト: 7日前）
- `end`: ISO 8601 日時（デフォルト: 現在）
- `limit`: 整数（デフォルト: 100、最大: 1000）
- `cursor`: 次ページカーソル
- `sources`: カンマ区切りソース名フィルター

**レスポンス例（心拍数）:**
```json
{
  "data": [
    {
      "id": "3F2A-...",
      "type": "heartRate",
      "value": 72.0,
      "unit": "count/min",
      "startDate": "2026-02-26T08:30:00Z",
      "endDate": "2026-02-26T08:30:00Z",
      "sourceName": "Apple Watch",
      "sourceBundle": "com.apple.health"
    }
  ],
  "meta": {
    "count": 100,
    "hasMore": true,
    "nextCursor": "eyJzdGFydERhdGUi...",
    "unit": "count/min",
    "queryStart": "2026-02-19T00:00:00Z",
    "queryEnd": "2026-02-26T23:59:59Z"
  }
}
```

---

#### `GET /v1/metrics/{type}/daily`

日次集計を返す。

**クエリパラメータ:**
- `start`, `end`: 期間（デフォルト: 過去 30 日）
- `aggregation`: `sum` / `avg` / `min` / `max`（タイプのデフォルト集計が適用される）

**レスポンス例（歩数）:**
```json
{
  "data": [
    {
      "date": "2026-02-25",
      "value": 8432.0,
      "unit": "count"
    },
    {
      "date": "2026-02-26",
      "value": 3210.0,
      "unit": "count"
    }
  ],
  "meta": {
    "type": "stepCount",
    "aggregation": "sum",
    "queryStart": "2026-02-20",
    "queryEnd": "2026-02-26"
  }
}
```

---

#### `GET /v1/metrics/{type}/latest`

最新 1 件のサンプルを返す。

```json
{
  "data": {
    "id": "3F2A-...",
    "type": "bodyMass",
    "value": 68.5,
    "unit": "kg",
    "startDate": "2026-02-26T07:00:00Z",
    "endDate": "2026-02-26T07:00:00Z",
    "sourceName": "Withings Scale"
  }
}
```

---

#### `GET /v1/sleep`

睡眠ステージの一覧を返す。

**クエリパラメータ:** `start`, `end`, `limit`, `cursor`

```json
{
  "data": [
    {
      "id": "9B1C-...",
      "stage": "asleepREM",
      "startDate": "2026-02-25T23:15:00Z",
      "endDate": "2026-02-26T00:45:00Z",
      "durationMinutes": 90.0,
      "sourceName": "Apple Watch"
    },
    {
      "id": "8A0B-...",
      "stage": "asleepDeep",
      "startDate": "2026-02-26T00:45:00Z",
      "endDate": "2026-02-26T01:30:00Z",
      "durationMinutes": 45.0,
      "sourceName": "Apple Watch"
    }
  ],
  "meta": {
    "queryStart": "2026-02-25T20:00:00Z",
    "queryEnd": "2026-02-26T08:00:00Z",
    "count": 12
  }
}
```

睡眠ステージ値: `inBed` / `awake` / `asleepCore` / `asleepDeep` / `asleepREM` / `asleepUnspecified`

---

#### `GET /v1/workouts`

ワークアウト一覧を返す。

```json
{
  "data": [
    {
      "id": "W7E2-...",
      "activityType": "running",
      "activityTypeCode": 37,
      "startDate": "2026-02-26T06:00:00Z",
      "endDate": "2026-02-26T06:45:00Z",
      "durationMinutes": 45.0,
      "totalEnergyBurned": 420.0,
      "totalEnergyBurnedUnit": "kcal",
      "totalDistance": 7500.0,
      "totalDistanceUnit": "m",
      "sourceName": "Nike Run Club",
      "sourceBundle": "com.nike.runclub"
    }
  ],
  "meta": {
    "count": 7,
    "hasMore": false
  }
}
```

---

#### `GET /v1/summary/activity`

アクティビティリング（ムーブ・エクササイズ・スタンド）の集計を返す。

**クエリパラメータ:** `start`, `end`（日付形式、デフォルト: 過去 7 日）

```json
{
  "data": [
    {
      "date": "2026-02-26",
      "activeEnergyBurned": 380.0,
      "activeEnergyBurnedGoal": 500.0,
      "activeEnergyBurnedUnit": "kcal",
      "appleExerciseTime": 25.0,
      "appleExerciseTimeGoal": 30.0,
      "appleStandHours": 9.0,
      "appleStandHoursGoal": 12.0
    }
  ]
}
```

### 10.5 HTTP ステータスコード

| コード | 意味 | 発生条件 |
|-------|------|---------|
| 200 | OK | 正常応答 |
| 400 | Bad Request | パラメータ不正（日付フォーマット等） |
| 401 | Unauthorized | Bearer トークン不正・欠如 |
| 403 | Forbidden | HealthKit 権限が拒否されている |
| 404 | Not Found | 不明なメトリックタイプ |
| 429 | Too Many Requests | レート制限超過 |
| 503 | Service Unavailable | HealthKit 利用不可（デバイスロック中等） |

### 10.6 ページネーション仕様

カーソルベースのページネーションを採用する。

- カーソルは `{"startDate": "ISO8601", "id": "UUID"}` を Base64 エンコードした不透明文字列
- カーソルを復元して `HKQuery.predicateForSamples(withStart:end:)` に適用
- `meta.hasMore: false` のとき、`meta.nextCursor` は省略される

---

## 11. セキュリティ設計

### 11.1 脅威モデル

| 脅威 | 対策 |
|------|------|
| 同一 LAN 上の第三者によるデータアクセス | Bearer トークン認証 + localhost バインド |
| トークンの盗難 | Keychain 保存、画面表示は最小限 |
| ネットワーク盗聴 | localhost 限定（ループバック通信は外部に出ない） |
| ブルートフォース攻撃 | レート制限（60 req/min）、固定遅延応答 |
| アプリ内データ漏洩 | 健康データをログに記録しない |

### 11.2 トークン管理

```
生成: SecRandomCopyBytes(32バイト) → Base64エンコード → Keychain 保存
表示: UI 上でマスク表示 + コピーボタン + QR コード
更新: 新トークン生成 → 旧トークン即時無効化 → Keychain 上書き
削除: アプリ削除時に Keychain エントリ削除（kSecAttrSynchronizable: false）
```

### 11.3 ネットワークバインディング

```
デフォルト: 127.0.0.1:8080（loopback のみ、LAN 非公開）
LAN モード: 0.0.0.0:8080（ユーザーが明示的に有効化、警告表示必須）
LAN 有効化条件: NSLocalNetworkUsageDescription の表示 + ユーザー同意
```

### 11.4 App Transport Security

localhost への HTTP 接続に ATS 例外を設定する（Info.plist）:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>localhost</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

### 11.5 将来対応: HTTPS（フェーズ2）

Telegraph の TLS 機能を使って自己署名 CA + サーバー証明書によるローカル HTTPS を実装し、ATS 例外を不要にする。

---

## 12. バックグラウンド処理設計

### 12.1 HealthKit バックグラウンド配信

iOS の HealthKit バックグラウンド配信は以下の仕組みで動作する:

1. **`enableBackgroundDelivery(for:frequency:)`** — データタイプごとに登録（アプリ起動毎に呼び出し必須）
2. **`HKObserverQuery`** — 変更検知クエリを常時実行状態に置く
3. **システムが変更を検知するとアプリをバックグラウンド起動**
4. **`HKAnchoredObjectQuery` で差分取得** → キャッシュ更新
5. **`completionHandler()` を必ず呼び出す**（これを怠るとシステムが以降の配信を停止する）

```swift
// 必要な Entitlement
// com.apple.developer.healthkit (true)
// com.apple.developer.healthkit.background-delivery (true)

// 必要な Info.plist キー
// UIBackgroundModes: [processing, fetch]
```

### 12.2 フォアグラウンド / バックグラウンド動作の違い

| 状態 | HTTP サーバー | HealthKit | キャッシュ更新 |
|------|------------|-----------|------------|
| フォアグラウンド（アクティブ） | ○ 稼働 | ○ 直接クエリ可 | リアルタイム |
| バックグラウンド（通常） | × 停止 | ○ 変更通知受信可 | バックグラウンド配信経由 |
| バックグラウンド（ロック中） | × 停止 | △ 制限あり※ | 遅延あり |

※ デバイスがパスコードロック中は HealthKit ストアへのアクセスが制限される（プライバシー保護のための iOS 設計）。フォアグラウンド起動時に差分を取得する。

### 12.3 バックグラウンド配信の実装方針

バックグラウンド配信の主な目的は「アプリが次回フォアグラウンドになったときに最新データをすぐ返せる状態にすること」である。サーバーはフォアグラウンド専用として設計する。

---

## 13. UI/UX 要件

### 13.1 画面構成

```
タブバー
├── ホーム（サーバーステータス）
│   ├── サーバー ON/OFF スイッチ
│   ├── 現在のポート番号
│   ├── 接続 URL 表示 + コピーボタン
│   ├── 接続テストボタン（curl 例表示）
│   └── リクエストログ（最新 10 件）
├── 権限
│   ├── データタイプ一覧 + 権限状態アイコン
│   ├── 一括権限リクエストボタン
│   └── iOS 設定を開くボタン
├── API トークン
│   ├── トークン表示（マスク / 表示切り替え）
│   ├── コピーボタン
│   ├── QR コード表示
│   └── トークン再生成ボタン（確認ダイアログ付き）
└── 設定
    ├── ポート番号（8080〜8090）
    ├── LAN モード ON/OFF（警告付き）
    ├── キャッシュ期間（7 / 14 / 30 日）
    ├── キャッシュ手動更新ボタン
    └── バージョン情報
```

### 13.2 オンボーディング

1. HealthKit 権限の説明画面（初回のみ）
2. 権限リクエスト（システムダイアログ）
3. API トークン発行 + 使い方説明
4. 完了 → ホーム画面

### 13.3 UX 原則

- サーバーが起動中は常にインジケーターを表示（ステータスバーアイコン等）
- HealthKit 権限が不足している場合は、どのエンドポイントで何が使えないかを明確に表示
- curl コマンド例を表示してコピーできるようにする（開発者向け）

---

## 14. 開発フェーズ計画

### フェーズ 1: MVP（最優先）

**目標:** 基本的な健康データを API で取得できる状態

**実装内容:**
- [ ] プロジェクト設定（HealthKit Entitlement、Info.plist）
- [ ] HealthKit 権限マネージャー
- [ ] HealthDataCache（インメモリ）
- [ ] HKObserverQuery + HKAnchoredObjectQuery による差分同期
- [ ] Telegraph HTTP サーバー統合
- [ ] Bearer トークン認証ミドルウェア
- [ ] 以下エンドポイントの実装:
  - `GET /v1/status`
  - `GET /v1/metrics/stepCount`（日次集計）
  - `GET /v1/metrics/heartRate`（生サンプル）
  - `GET /v1/sleep`
  - `GET /v1/metrics/activeEnergyBurned`（日次集計）
- [ ] 基本 UI（ホーム + トークン画面）

### フェーズ 2: 完全対応

**目標:** 全対応データタイプ + 完成度の高い UI

**実装内容:**
- [ ] 全データタイプ（優先度「高」以上）の実装
- [ ] ワークアウトエンドポイント
- [ ] アクティビティサマリーエンドポイント
- [ ] ページネーション（カーソルベース）
- [ ] クエリパラメータ完全実装（sources フィルター等）
- [ ] 権限管理画面
- [ ] 設定画面（ポート変更・LAN モード）
- [ ] リクエストログ表示
- [ ] オンボーディング

### フェーズ 3: 品質向上

**目標:** 安定性・セキュリティ強化

**実装内容:**
- [ ] レート制限
- [ ] HTTPS（自己署名 TLS 証明書、Telegraph）
- [ ] エラーハンドリング改善
- [ ] Unit Tests（Repository、UseCase 層）
- [ ] LAN モード対応（警告 UI 付き）
- [ ] キャッシュ永続化オプション（CoreData、オプトイン）

### フェーズ 4: 拡張機能

- [ ] 血糖値・栄養素対応
- [ ] ショートカット（Shortcuts）連携
- [ ] Webhook プッシュ通知（逆方向: サーバー → クライアントへのプッシュ）
- [ ] OpenAPI (Swagger) ドキュメント自動生成エンドポイント
- [ ] Apple Watch コンパニオンアプリ

---

## 15. 制約事項・既知の制限

### 15.1 iOS プラットフォーム制約

| 制約 | 説明 | 対策 |
|------|------|------|
| バックグラウンド HTTP サーバー | iOS はバックグラウンドでのソケット待ち受けを許可しない | フォアグラウンド専用サーバーとして設計 |
| ロック中 HealthKit 制限 | デバイスがロックされると HealthKit ストアへのアクセスが制限される | インメモリキャッシュで対応（ロック中でも返せる） |
| バックグラウンド配信の遅延 | `.immediate` でも iOS の省電力制御により遅延する場合がある | ドキュメントで明示 |
| 権限の不透明性 | HealthKit は「拒否」と「未設定」を区別して返さない（プライバシー保護） | UI 上は "未設定" と表示 |
| Entitlement 申請 | 臨床記録（HKClinicalType）には Apple の審査・承認が必要 | フェーズ 1 では対象外 |

### 15.2 設計上の制約

| 制約 | 理由 |
|------|------|
| データの外部送信禁止 | HealthKit プライバシーポリシー・App Store ガイドライン準拠 |
| 書き込み API なし（フェーズ1） | 誤書き込みリスクを回避 |
| メモリキャッシュのみ（フェーズ1） | 健康データの永続化によるリスクを最小化 |

---

## 16. App Store 審査対応

### 16.1 必要な Info.plist キー

```xml
<!-- HealthKit 必須 -->
<key>NSHealthShareUsageDescription</key>
<string>
  OpenVital は、あなたの健康データを読み取り、このデバイス上でローカル API として提供します。
  データはこのデバイスの外部に送信されません。
</string>

<!-- LAN モード使用時（フェーズ2） -->
<key>NSLocalNetworkUsageDescription</key>
<string>
  LAN モードを有効にすると、同じネットワーク上の他のデバイスから健康データ API にアクセスできます。
</string>
```

### 16.2 必要な Entitlements

```xml
<key>com.apple.developer.healthkit</key>
<true/>
<key>com.apple.developer.healthkit.background-delivery</key>
<true/>
```

### 16.3 審査対応ポイント

- **§5.1.3 Health & Health Research**: 健康データを広告や第三者に提供しないことを Privacy Policy に明記
- **§2.5.4 Background Modes**: バックグラウンドモードを HealthKit データ同期のみに使用することを説明
- **ローカル HTTP サーバーの目的**: ユーザー自身のデータをユーザー自身のネットワーク内でのみ提供する個人用ツールであることを審査コメントに明記
- **プライバシーポリシー**: App Store Connect に URL 登録必須（HealthKit データを扱うアプリの要件）

---

## 17. 用語集

| 用語 | 説明 |
|------|------|
| HealthKit | Apple の健康データフレームワーク。iOS/watchOS 上でのみ利用可能 |
| HKHealthStore | HealthKit データへのアクセスを管理するシングルトン |
| HKQuantityType | 数値型の健康データ（歩数・心拍数等） |
| HKCategoryType | カテゴリ型の健康データ（睡眠ステージ等） |
| HKObserverQuery | HealthKit データの変更を監視するクエリ（バックグラウンド配信に使用） |
| HKAnchoredObjectQuery | アンカー（前回取得位置）以降の差分データを取得するクエリ |
| HKQueryAnchor | 差分取得の起点となるブックマーク。UserDefaults に永続化 |
| Bearer Token | HTTP Authorization ヘッダーで使用する認証トークン |
| loopback / localhost | `127.0.0.1` — 同一デバイス内のみアクセスできるネットワークアドレス |
| LAN モード | `0.0.0.0` バインド — 同一 Wi-Fi 上の全デバイスからアクセス可能 |
| Telegraph | iOS 向けの Swift 製 HTTP/HTTPS サーバーライブラリ |
| カーソルページネーション | オフセットではなくカーソル（最後に取得したレコードの位置）を使うページネーション手法 |
| インメモリキャッシュ | RAM 上に保持するデータキャッシュ。アプリ終了時に消える |
| ATS | App Transport Security — iOS の HTTPS 強制ポリシー |

---

*本ドキュメントは OpenVital の初期要件定義書です。実装を通じて判明した新たな制約・要件は随時更新してください。*
