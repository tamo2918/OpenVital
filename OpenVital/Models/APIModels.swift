import Foundation

nonisolated struct APISuccessResponse<T: Codable & Sendable>: Codable, Sendable {
    let data: T
    let meta: APIMetadata?
}

nonisolated struct APIMetadata: Codable, Sendable {
    var count: Int?
    var hasMore: Bool?
    var nextCursor: String?
    var unit: String?
    var type: String?
    var aggregation: String?
    var queryStart: String?
    var queryEnd: String?
    var cachedAt: String?
}

nonisolated struct APIError: Codable, Sendable {
    let error: APIErrorDetail
}

nonisolated struct APIErrorDetail: Codable, Sendable {
    let code: String
    let message: String
    let status: Int
}

nonisolated struct StatusResponse: Codable, Sendable {
    let version: String
    let status: String
    let port: UInt16
    let uptime: Int
    let cacheLastUpdated: String?
    let supportedMetrics: [String]
}

nonisolated struct PermissionsResponse: Codable, Sendable {
    let data: [String: String]
}

nonisolated struct WelcomeResponse: Codable, Sendable {
    let name: String
    let version: String
    let status: String
    let docs: EndpointDocs
}

nonisolated struct EndpointDocs: Codable, Sendable {
    let `public`: [String: String]
    let authenticated: [String: String]
    let authHeader: String
}

// MARK: - Webhook Models

nonisolated struct WebhookPayload: Codable, Sendable {
    let event: String
    let timestamp: String
    let data: HealthDataExport
}

nonisolated struct HealthDataExport: Codable, Sendable {
    let exportDate: String
    let periodDays: Int
    let metrics: [String: [DailyAggregate]]
    let sleepRecords: [SleepRecord]
    let workoutRecords: [WorkoutRecord]
    let activitySummaries: [ActivitySummaryRecord]
}

nonisolated struct WebhookStatus: Sendable {
    let success: Bool
    let statusCode: Int?
    let message: String
    let timestamp: Date
}
