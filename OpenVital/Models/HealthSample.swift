import Foundation

nonisolated struct HealthSample: Codable, Sendable {
    let id: String
    let type: String
    let value: Double
    let unit: String
    let startDate: Date
    let endDate: Date
    let sourceName: String
    let sourceBundle: String
}

nonisolated struct SleepRecord: Codable, Sendable {
    let id: String
    let stage: String
    let startDate: Date
    let endDate: Date
    let durationMinutes: Double
    let sourceName: String
}

nonisolated struct WorkoutRecord: Codable, Sendable {
    let id: String
    let activityType: String
    let activityTypeCode: UInt
    let startDate: Date
    let endDate: Date
    let durationMinutes: Double
    let totalEnergyBurned: Double?
    let totalEnergyBurnedUnit: String?
    let totalDistance: Double?
    let totalDistanceUnit: String?
    let sourceName: String
    let sourceBundle: String
}

nonisolated struct DailyAggregate: Codable, Sendable {
    let date: String
    let value: Double
    let unit: String
}

nonisolated struct ActivitySummaryRecord: Codable, Sendable {
    let date: String
    let activeEnergyBurned: Double
    let activeEnergyBurnedGoal: Double
    let activeEnergyBurnedUnit: String
    let appleExerciseTime: Double
    let appleExerciseTimeGoal: Double
    let appleStandHours: Double
    let appleStandHoursGoal: Double
}

nonisolated struct CursorInfo: Codable, Sendable {
    let date: Date
    let id: String
}
