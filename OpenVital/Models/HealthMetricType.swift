import HealthKit

nonisolated enum HealthMetricCategory: String, Sendable, Codable, CaseIterable {
    case activity
    case vitals
    case body
    case sleep
    case workout
}

nonisolated enum AggregationMethod: Sendable {
    case cumulativeSum
    case discreteAverage
}

nonisolated struct HealthMetricType: Sendable {
    let identifier: String
    let quantityTypeIdentifier: HKQuantityTypeIdentifier?
    let categoryTypeIdentifier: HKCategoryTypeIdentifier?
    let unit: HKUnit
    let unitString: String
    let category: HealthMetricCategory
    let aggregation: AggregationMethod

    var sampleType: HKSampleType? {
        if let id = quantityTypeIdentifier {
            return HKQuantityType(id)
        }
        if let id = categoryTypeIdentifier {
            return HKCategoryType(id)
        }
        return nil
    }

    var objectType: HKObjectType? {
        sampleType
    }
}

nonisolated extension HealthMetricType {
    static let all: [HealthMetricType] = [
        // Activity
        .init(identifier: "stepCount",
              quantityTypeIdentifier: .stepCount,
              categoryTypeIdentifier: nil,
              unit: .count(),
              unitString: "count",
              category: .activity,
              aggregation: .cumulativeSum),
        .init(identifier: "distanceWalkingRunning",
              quantityTypeIdentifier: .distanceWalkingRunning,
              categoryTypeIdentifier: nil,
              unit: .meter(),
              unitString: "m",
              category: .activity,
              aggregation: .cumulativeSum),
        .init(identifier: "activeEnergyBurned",
              quantityTypeIdentifier: .activeEnergyBurned,
              categoryTypeIdentifier: nil,
              unit: .kilocalorie(),
              unitString: "kcal",
              category: .activity,
              aggregation: .cumulativeSum),
        .init(identifier: "basalEnergyBurned",
              quantityTypeIdentifier: .basalEnergyBurned,
              categoryTypeIdentifier: nil,
              unit: .kilocalorie(),
              unitString: "kcal",
              category: .activity,
              aggregation: .cumulativeSum),
        .init(identifier: "flightsClimbed",
              quantityTypeIdentifier: .flightsClimbed,
              categoryTypeIdentifier: nil,
              unit: .count(),
              unitString: "count",
              category: .activity,
              aggregation: .cumulativeSum),
        .init(identifier: "appleExerciseTime",
              quantityTypeIdentifier: .appleExerciseTime,
              categoryTypeIdentifier: nil,
              unit: .minute(),
              unitString: "min",
              category: .activity,
              aggregation: .cumulativeSum),
        .init(identifier: "appleStandTime",
              quantityTypeIdentifier: .appleStandTime,
              categoryTypeIdentifier: nil,
              unit: .minute(),
              unitString: "min",
              category: .activity,
              aggregation: .cumulativeSum),
        .init(identifier: "distanceCycling",
              quantityTypeIdentifier: .distanceCycling,
              categoryTypeIdentifier: nil,
              unit: .meter(),
              unitString: "m",
              category: .activity,
              aggregation: .cumulativeSum),

        // Vitals
        .init(identifier: "heartRate",
              quantityTypeIdentifier: .heartRate,
              categoryTypeIdentifier: nil,
              unit: .count().unitDivided(by: .minute()),
              unitString: "count/min",
              category: .vitals,
              aggregation: .discreteAverage),
        .init(identifier: "restingHeartRate",
              quantityTypeIdentifier: .restingHeartRate,
              categoryTypeIdentifier: nil,
              unit: .count().unitDivided(by: .minute()),
              unitString: "count/min",
              category: .vitals,
              aggregation: .discreteAverage),
        .init(identifier: "heartRateVariabilitySDNN",
              quantityTypeIdentifier: .heartRateVariabilitySDNN,
              categoryTypeIdentifier: nil,
              unit: .secondUnit(with: .milli),
              unitString: "ms",
              category: .vitals,
              aggregation: .discreteAverage),
        .init(identifier: "oxygenSaturation",
              quantityTypeIdentifier: .oxygenSaturation,
              categoryTypeIdentifier: nil,
              unit: .percent(),
              unitString: "%",
              category: .vitals,
              aggregation: .discreteAverage),
        .init(identifier: "respiratoryRate",
              quantityTypeIdentifier: .respiratoryRate,
              categoryTypeIdentifier: nil,
              unit: .count().unitDivided(by: .minute()),
              unitString: "count/min",
              category: .vitals,
              aggregation: .discreteAverage),
        .init(identifier: "bodyTemperature",
              quantityTypeIdentifier: .bodyTemperature,
              categoryTypeIdentifier: nil,
              unit: .degreeCelsius(),
              unitString: "degC",
              category: .vitals,
              aggregation: .discreteAverage),
        .init(identifier: "bloodPressureSystolic",
              quantityTypeIdentifier: .bloodPressureSystolic,
              categoryTypeIdentifier: nil,
              unit: .millimeterOfMercury(),
              unitString: "mmHg",
              category: .vitals,
              aggregation: .discreteAverage),
        .init(identifier: "bloodPressureDiastolic",
              quantityTypeIdentifier: .bloodPressureDiastolic,
              categoryTypeIdentifier: nil,
              unit: .millimeterOfMercury(),
              unitString: "mmHg",
              category: .vitals,
              aggregation: .discreteAverage),

        // Body
        .init(identifier: "bodyMass",
              quantityTypeIdentifier: .bodyMass,
              categoryTypeIdentifier: nil,
              unit: .gramUnit(with: .kilo),
              unitString: "kg",
              category: .body,
              aggregation: .discreteAverage),
        .init(identifier: "height",
              quantityTypeIdentifier: .height,
              categoryTypeIdentifier: nil,
              unit: .meter(),
              unitString: "m",
              category: .body,
              aggregation: .discreteAverage),
        .init(identifier: "bodyMassIndex",
              quantityTypeIdentifier: .bodyMassIndex,
              categoryTypeIdentifier: nil,
              unit: .count(),
              unitString: "count",
              category: .body,
              aggregation: .discreteAverage),
        .init(identifier: "bodyFatPercentage",
              quantityTypeIdentifier: .bodyFatPercentage,
              categoryTypeIdentifier: nil,
              unit: .percent(),
              unitString: "%",
              category: .body,
              aggregation: .discreteAverage),

        // Sleep (category type)
        .init(identifier: "sleepAnalysis",
              quantityTypeIdentifier: nil,
              categoryTypeIdentifier: .sleepAnalysis,
              unit: .second(),
              unitString: "category",
              category: .sleep,
              aggregation: .discreteAverage),
    ]

    static let byIdentifier: [String: HealthMetricType] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.identifier, $0) })
    }()

    static func find(_ identifier: String) -> HealthMetricType? {
        byIdentifier[identifier]
    }

    static var allReadTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for metric in all {
            if let t = metric.objectType {
                types.insert(t)
            }
        }
        types.insert(HKObjectType.workoutType())
        types.insert(HKObjectType.activitySummaryType())
        return types
    }

    static var allIdentifiers: [String] {
        all.map(\.identifier) + ["workout", "activitySummary"]
    }
}
