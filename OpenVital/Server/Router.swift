import Foundation

struct Router: Sendable {
    let cache: HealthDataCache
    let tokenManager: TokenManager
    let logger: RequestLogger
    let serverPort: UInt16
    let serverStartTime: Date

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        // Public endpoints (no auth required)
        let c = request.pathComponents
        if c.isEmpty && request.method == "GET" {
            return await handleRoot()
        }
        if c == ["v1", "status"] && request.method == "GET" {
            return await handleStatus()
        }

        // All other endpoints require authentication
        guard await tokenManager.validate(request.bearerToken) else {
            return HTTPResponse.error(
                code: "unauthorized",
                message: "Invalid or missing Bearer token. Add header: Authorization: Bearer <token>",
                status: 401
            )
        }

        guard request.method == "GET" else {
            return HTTPResponse.error(
                code: "method_not_allowed",
                message: "Only GET method is supported",
                status: 400
            )
        }

        // Route matching (c already defined above)
        if c == ["v1", "permissions"] {
            return await handlePermissions()
        } else if c == ["v1", "sleep"] {
            return await handleSleep(params: request.queryParams)
        } else if c == ["v1", "workouts"] {
            return await handleWorkouts(params: request.queryParams)
        } else if c.count == 3, c[0] == "v1", c[1] == "workouts" {
            return await handleWorkoutDetail(id: c[2])
        } else if c == ["v1", "summary", "activity"] {
            return await handleActivitySummary(params: request.queryParams)
        } else if c.count == 3, c[0] == "v1", c[1] == "metrics" {
            return await handleMetrics(type: c[2], params: request.queryParams)
        } else if c.count == 4, c[0] == "v1", c[1] == "metrics", c[3] == "daily" {
            return await handleMetricsDaily(type: c[2], params: request.queryParams)
        } else if c.count == 4, c[0] == "v1", c[1] == "metrics", c[3] == "latest" {
            return await handleMetricsLatest(type: c[2])
        } else {
            return HTTPResponse.error(
                code: "not_found",
                message: "Endpoint not found: \(request.path)",
                status: 404
            )
        }
    }

    // MARK: - Query Param Helpers

    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        // Try date-only format
        let dateOnly = DateFormatter()
        dateOnly.dateFormat = "yyyy-MM-dd"
        dateOnly.timeZone = TimeZone.current
        return dateOnly.date(from: string)
    }

    static func dateRange(from params: [String: String], defaultDays: Int = 7) -> (start: Date, end: Date) {
        let end = parseDate(params["end"]) ?? Date()
        let start = parseDate(params["start"]) ?? Calendar.current.date(byAdding: .day, value: -defaultDays, to: end)!
        return (start, end)
    }

    static func limit(from params: [String: String]) -> Int {
        min(max(Int(params["limit"] ?? "100") ?? 100, 1), 1000)
    }

    static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func formatDateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    private func jsonResponse<T: Codable & Sendable>(_ value: T) -> HTTPResponse {
        guard let data = try? JSONCoders.encoder.encode(value) else {
            return HTTPResponse.error(code: "internal_error", message: "JSON encoding failed", status: 500)
        }
        return HTTPResponse.json(data)
    }

    // MARK: - Route Handlers

    private func handleRoot() async -> HTTPResponse {
        let welcome = WelcomeResponse(
            name: "OpenVital API",
            version: "1.0.0",
            status: "running",
            docs: EndpointDocs(
                public: [
                    "GET /" : "This welcome message",
                    "GET /v1/status" : "Server status and supported metrics",
                ],
                authenticated: [
                    "GET /v1/metrics/{type}" : "Raw health samples (e.g. stepCount, heartRate)",
                    "GET /v1/metrics/{type}/daily" : "Daily aggregates",
                    "GET /v1/metrics/{type}/latest" : "Most recent sample",
                    "GET /v1/sleep" : "Sleep stage records",
                    "GET /v1/workouts" : "Workout list",
                    "GET /v1/workouts/{id}" : "Workout detail",
                    "GET /v1/summary/activity" : "Activity ring summaries",
                    "GET /v1/permissions" : "HealthKit permission statuses",
                ],
                authHeader: "Authorization: Bearer <token>"
            )
        )
        return jsonResponse(welcome)
    }

    private func handleStatus() async -> HTTPResponse {
        let uptime = Int(Date().timeIntervalSince(serverStartTime))
        let lastUpdated = await cache.lastUpdated
        let response = StatusResponse(
            version: "1.0.0",
            status: "running",
            port: serverPort,
            uptime: uptime,
            cacheLastUpdated: lastUpdated.map { Self.formatDate($0) },
            supportedMetrics: HealthMetricType.allIdentifiers
        )
        return jsonResponse(response)
    }

    private func handlePermissions() async -> HTTPResponse {
        // Permission statuses require HealthKit access on MainActor
        // Return what we know from the cache availability
        var statuses: [String: String] = [:]
        for metric in HealthMetricType.all {
            let hasSamples = await cache.getLatestSample(type: metric.identifier) != nil
            statuses[metric.identifier] = hasSamples ? "authorized" : "unknown"
        }
        return jsonResponse(PermissionsResponse(data: statuses))
    }

    private func handleMetrics(type: String, params: [String: String]) async -> HTTPResponse {
        guard HealthMetricType.find(type) != nil else {
            return HTTPResponse.error(
                code: "not_found",
                message: "Unknown metric type: \(type). Use /v1/status for supported types.",
                status: 404
            )
        }

        let range = Self.dateRange(from: params)
        let limit = Self.limit(from: params)
        let cursor = params["cursor"]

        let result = await cache.getSamples(
            type: type,
            start: range.start,
            end: range.end,
            limit: limit,
            cursor: cursor
        )

        let metricUnit = HealthMetricType.find(type)?.unitString
        let meta = APIMetadata(
            count: result.items.count,
            hasMore: result.hasMore,
            nextCursor: result.nextCursor,
            unit: metricUnit,
            queryStart: Self.formatDate(range.start),
            queryEnd: Self.formatDate(range.end),
            cachedAt: await cache.lastUpdated.map { Self.formatDate($0) }
        )

        let response = APISuccessResponse(data: result.items, meta: meta)
        return jsonResponse(response)
    }

    private func handleMetricsDaily(type: String, params: [String: String]) async -> HTTPResponse {
        guard let metric = HealthMetricType.find(type) else {
            return HTTPResponse.error(code: "not_found", message: "Unknown metric type: \(type)", status: 404)
        }

        let range = Self.dateRange(from: params, defaultDays: 30)
        let aggregates = await cache.getDailyAggregates(type: type, start: range.start, end: range.end)

        let aggregationName: String
        switch metric.aggregation {
        case .cumulativeSum: aggregationName = "sum"
        case .discreteAverage: aggregationName = "avg"
        }

        let meta = APIMetadata(
            count: aggregates.count,
            type: type,
            aggregation: aggregationName,
            queryStart: Self.formatDateOnly(range.start),
            queryEnd: Self.formatDateOnly(range.end)
        )

        let response = APISuccessResponse(data: aggregates, meta: meta)
        return jsonResponse(response)
    }

    private func handleMetricsLatest(type: String) async -> HTTPResponse {
        guard HealthMetricType.find(type) != nil else {
            return HTTPResponse.error(code: "not_found", message: "Unknown metric type: \(type)", status: 404)
        }

        guard let sample = await cache.getLatestSample(type: type) else {
            return HTTPResponse.error(code: "not_found", message: "No data available for \(type)", status: 404)
        }

        let response = APISuccessResponse(data: sample, meta: nil as APIMetadata?)
        return jsonResponse(response)
    }

    private func handleSleep(params: [String: String]) async -> HTTPResponse {
        let range = Self.dateRange(from: params)
        let limit = Self.limit(from: params)
        let cursor = params["cursor"]

        let result = await cache.getSleepRecords(
            start: range.start,
            end: range.end,
            limit: limit,
            cursor: cursor
        )

        let meta = APIMetadata(
            count: result.items.count,
            hasMore: result.hasMore,
            nextCursor: result.nextCursor,
            queryStart: Self.formatDate(range.start),
            queryEnd: Self.formatDate(range.end)
        )

        let response = APISuccessResponse(data: result.items, meta: meta)
        return jsonResponse(response)
    }

    private func handleWorkouts(params: [String: String]) async -> HTTPResponse {
        let range = Self.dateRange(from: params, defaultDays: 30)
        let limit = Self.limit(from: params)
        let cursor = params["cursor"]

        let result = await cache.getWorkoutRecords(
            start: range.start,
            end: range.end,
            limit: limit,
            cursor: cursor
        )

        let meta = APIMetadata(
            count: result.items.count,
            hasMore: result.hasMore,
            nextCursor: result.nextCursor,
            queryStart: Self.formatDate(range.start),
            queryEnd: Self.formatDate(range.end)
        )

        let response = APISuccessResponse(data: result.items, meta: meta)
        return jsonResponse(response)
    }

    private func handleWorkoutDetail(id: String) async -> HTTPResponse {
        guard let workout = await cache.getWorkoutRecord(id: id) else {
            return HTTPResponse.error(code: "not_found", message: "Workout not found", status: 404)
        }

        let response = APISuccessResponse(data: workout, meta: nil as APIMetadata?)
        return jsonResponse(response)
    }

    private func handleActivitySummary(params: [String: String]) async -> HTTPResponse {
        let range = Self.dateRange(from: params)
        let startStr = Self.formatDateOnly(range.start)
        let endStr = Self.formatDateOnly(range.end)

        let summaries = await cache.getActivitySummaries(start: startStr, end: endStr)

        let response = APISuccessResponse(data: summaries, meta: nil as APIMetadata?)
        return jsonResponse(response)
    }
}
