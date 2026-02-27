import AppIntents
import SwiftUI

nonisolated enum HealthMetricTypeEnum: String, AppEnum, Sendable {
    case stepCount
    case distanceWalkingRunning
    case activeEnergyBurned
    case basalEnergyBurned
    case flightsClimbed
    case appleExerciseTime
    case heartRate
    case restingHeartRate
    case heartRateVariabilitySDNN
    case oxygenSaturation
    case respiratoryRate
    case bodyTemperature
    case bodyMass
    case height
    case bodyMassIndex
    case bodyFatPercentage

    nonisolated static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Health Metric")

    nonisolated static let caseDisplayRepresentations: [HealthMetricTypeEnum: DisplayRepresentation] = [
        .stepCount: "Step Count",
        .distanceWalkingRunning: "Distance Walking/Running",
        .activeEnergyBurned: "Active Energy Burned",
        .basalEnergyBurned: "Basal Energy Burned",
        .flightsClimbed: "Flights Climbed",
        .appleExerciseTime: "Exercise Time",
        .heartRate: "Heart Rate",
        .restingHeartRate: "Resting Heart Rate",
        .heartRateVariabilitySDNN: "HRV (SDNN)",
        .oxygenSaturation: "Oxygen Saturation",
        .respiratoryRate: "Respiratory Rate",
        .bodyTemperature: "Body Temperature",
        .bodyMass: "Body Mass",
        .height: "Height",
        .bodyMassIndex: "BMI",
        .bodyFatPercentage: "Body Fat Percentage",
    ]
}

struct GetMetricIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Health Metric"
    static let description: IntentDescription = "Get a specific health metric's daily aggregates."
    static let openAppWhenRun = true

    @Parameter(title: "Metric")
    var metricType: HealthMetricTypeEnum

    @Parameter(title: "Days", default: 7)
    var days: Int

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let identifier = metricType.rawValue
        guard HealthMetricType.find(identifier) != nil else {
            return .result(value: "{\"error\": \"Unknown metric: \(identifier)\"}")
        }

        let cache = HealthDataCache()
        let manager = HealthKitManager(cache: cache)

        try await manager.requestAuthorization()
        await manager.loadAllData()

        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now)!
        let aggregates = await cache.getDailyAggregates(type: identifier, start: start, end: now)

        let data = try JSONCoders.encoder.encode(aggregates)
        let json = String(data: data, encoding: .utf8) ?? "[]"

        return .result(value: json)
    }
}
