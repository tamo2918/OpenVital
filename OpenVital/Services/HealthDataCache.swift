import Foundation

actor HealthDataCache {
    private var quantitySamples: [String: [HealthSample]] = [:]
    private var sleepRecords: [SleepRecord] = []
    private var workoutRecords: [WorkoutRecord] = []
    private var activitySummaries: [ActivitySummaryRecord] = []
    private(set) var lastUpdated: Date?

    // MARK: - Write Operations

    func setSamples(_ samples: [HealthSample], for type: String) {
        quantitySamples[type] = samples.sorted { $0.startDate > $1.startDate }
        lastUpdated = Date()
    }

    func appendSamples(_ samples: [HealthSample], for type: String) {
        var existing = quantitySamples[type] ?? []
        let existingIds = Set(existing.map(\.id))
        let newSamples = samples.filter { !existingIds.contains($0.id) }
        existing.append(contentsOf: newSamples)
        existing.sort { $0.startDate > $1.startDate }
        quantitySamples[type] = existing
        lastUpdated = Date()
    }

    func removeSamples(withIds ids: Set<String>, for type: String) {
        quantitySamples[type]?.removeAll { ids.contains($0.id) }
        lastUpdated = Date()
    }

    func setSleepRecords(_ records: [SleepRecord]) {
        sleepRecords = records.sorted { $0.startDate > $1.startDate }
        lastUpdated = Date()
    }

    func appendSleepRecords(_ records: [SleepRecord]) {
        let existingIds = Set(sleepRecords.map(\.id))
        let newRecords = records.filter { !existingIds.contains($0.id) }
        sleepRecords.append(contentsOf: newRecords)
        sleepRecords.sort { $0.startDate > $1.startDate }
        lastUpdated = Date()
    }

    func setWorkoutRecords(_ records: [WorkoutRecord]) {
        workoutRecords = records.sorted { $0.startDate > $1.startDate }
        lastUpdated = Date()
    }

    func appendWorkoutRecords(_ records: [WorkoutRecord]) {
        let existingIds = Set(workoutRecords.map(\.id))
        let newRecords = records.filter { !existingIds.contains($0.id) }
        workoutRecords.append(contentsOf: newRecords)
        workoutRecords.sort { $0.startDate > $1.startDate }
        lastUpdated = Date()
    }

    func setActivitySummaries(_ summaries: [ActivitySummaryRecord]) {
        activitySummaries = summaries
        lastUpdated = Date()
    }

    func clearAll() {
        quantitySamples.removeAll()
        sleepRecords.removeAll()
        workoutRecords.removeAll()
        activitySummaries.removeAll()
        lastUpdated = nil
    }

    // MARK: - Read Operations

    struct PagedResult<T: Sendable>: Sendable {
        let items: [T]
        let hasMore: Bool
        let nextCursor: String?
        let totalFiltered: Int
    }

    func getSamples(
        type: String,
        start: Date,
        end: Date,
        limit: Int,
        cursor: String?
    ) -> PagedResult<HealthSample> {
        guard let allSamples = quantitySamples[type] else {
            return PagedResult(items: [], hasMore: false, nextCursor: nil, totalFiltered: 0)
        }

        var filtered = allSamples.filter { $0.startDate >= start && $0.startDate <= end }

        if let cursor, let cursorInfo = decodeCursor(cursor) {
            filtered = filtered.filter {
                $0.startDate < cursorInfo.date || ($0.startDate == cursorInfo.date && $0.id > cursorInfo.id)
            }
        }

        let totalFiltered = filtered.count
        let hasMore = filtered.count > limit
        let page = Array(filtered.prefix(limit))
        var nextCursor: String?
        if hasMore, let last = page.last {
            nextCursor = encodeCursor(CursorInfo(date: last.startDate, id: last.id))
        }

        return PagedResult(items: page, hasMore: hasMore, nextCursor: nextCursor, totalFiltered: totalFiltered)
    }

    func getLatestSample(type: String) -> HealthSample? {
        quantitySamples[type]?.first
    }

    func getSleepRecords(start: Date, end: Date, limit: Int, cursor: String?) -> PagedResult<SleepRecord> {
        var filtered = sleepRecords.filter { $0.startDate >= start && $0.startDate <= end }

        if let cursor, let cursorInfo = decodeCursor(cursor) {
            filtered = filtered.filter {
                $0.startDate < cursorInfo.date || ($0.startDate == cursorInfo.date && $0.id > cursorInfo.id)
            }
        }

        let hasMore = filtered.count > limit
        let page = Array(filtered.prefix(limit))
        var nextCursor: String?
        if hasMore, let last = page.last {
            nextCursor = encodeCursor(CursorInfo(date: last.startDate, id: last.id))
        }

        return PagedResult(items: page, hasMore: hasMore, nextCursor: nextCursor, totalFiltered: filtered.count)
    }

    func getWorkoutRecords(start: Date, end: Date, limit: Int, cursor: String?) -> PagedResult<WorkoutRecord> {
        var filtered = workoutRecords.filter { $0.startDate >= start && $0.startDate <= end }

        if let cursor, let cursorInfo = decodeCursor(cursor) {
            filtered = filtered.filter {
                $0.startDate < cursorInfo.date || ($0.startDate == cursorInfo.date && $0.id > cursorInfo.id)
            }
        }

        let hasMore = filtered.count > limit
        let page = Array(filtered.prefix(limit))
        var nextCursor: String?
        if hasMore, let last = page.last {
            nextCursor = encodeCursor(CursorInfo(date: last.startDate, id: last.id))
        }

        return PagedResult(items: page, hasMore: hasMore, nextCursor: nextCursor, totalFiltered: filtered.count)
    }

    func getWorkoutRecord(id: String) -> WorkoutRecord? {
        workoutRecords.first { $0.id == id }
    }

    func getActivitySummaries(start: String, end: String) -> [ActivitySummaryRecord] {
        activitySummaries.filter { $0.date >= start && $0.date <= end }
    }

    func getDailyAggregates(type: String, start: Date, end: Date) -> [DailyAggregate] {
        guard let metric = HealthMetricType.find(type),
              let samples = quantitySamples[type] else { return [] }

        let filtered = samples.filter { $0.startDate >= start && $0.startDate <= end }

        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone

        var dailyValues: [String: [Double]] = [:]
        for sample in filtered {
            let key = formatter.string(from: sample.startDate)
            dailyValues[key, default: []].append(sample.value)
        }

        var aggregates: [DailyAggregate] = []
        for (dateString, values) in dailyValues {
            let aggregated: Double
            switch metric.aggregation {
            case .cumulativeSum:
                aggregated = values.reduce(0, +)
            case .discreteAverage:
                aggregated = values.reduce(0, +) / Double(values.count)
            }
            aggregates.append(DailyAggregate(date: dateString, value: aggregated, unit: metric.unitString))
        }

        return aggregates.sorted { $0.date < $1.date }
    }

    // MARK: - Export

    func exportAllData(days: Int) -> HealthDataExport {
        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.date(byAdding: .day, value: -days, to: now)!

        let formatter = ISO8601DateFormatter()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let startDateString = dateFormatter.string(from: startDate)

        // Aggregate metrics by day
        var metricsExport: [String: [DailyAggregate]] = [:]
        for metric in HealthMetricType.all where metric.category != .sleep {
            let aggregates = getDailyAggregates(type: metric.identifier, start: startDate, end: now)
            if !aggregates.isEmpty {
                metricsExport[metric.identifier] = aggregates
            }
        }

        // Filter sleep/workout/activity by date range
        let filteredSleep = sleepRecords.filter { $0.startDate >= startDate && $0.startDate <= now }
        let filteredWorkouts = workoutRecords.filter { $0.startDate >= startDate && $0.startDate <= now }
        let filteredActivity = activitySummaries.filter { $0.date >= startDateString }

        return HealthDataExport(
            exportDate: formatter.string(from: now),
            periodDays: days,
            metrics: metricsExport,
            sleepRecords: filteredSleep,
            workoutRecords: filteredWorkouts,
            activitySummaries: filteredActivity
        )
    }

    // MARK: - Cursor Helpers

    private func encodeCursor(_ info: CursorInfo) -> String? {
        guard let data = try? JSONCoders.encoder.encode(info) else { return nil }
        return data.base64EncodedString()
    }

    private func decodeCursor(_ cursor: String) -> CursorInfo? {
        guard let data = Data(base64Encoded: cursor) else { return nil }
        return try? JSONCoders.decoder.decode(CursorInfo.self, from: data)
    }
}

// MARK: - Shared JSON Coders

nonisolated enum JSONCoders {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
