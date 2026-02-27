@preconcurrency import HealthKit
import Foundation

actor HealthKitManager {
    private let healthStore = HKHealthStore()
    private let cache: HealthDataCache
    private var webhookManager: WebhookManager?
    private var anchors: [String: HKQueryAnchor] = [:]
    private var observerQueries: [HKObserverQuery] = []
    nonisolated let isAvailable: Bool

    init(cache: HealthDataCache, webhookManager: WebhookManager? = nil) {
        self.cache = cache
        self.webhookManager = webhookManager
        self.isAvailable = HKHealthStore.isHealthDataAvailable()
    }

    func setWebhookManager(_ manager: WebhookManager) {
        self.webhookManager = manager
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        let readTypes = HealthMetricType.allReadTypes
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    func authorizationStatus(for objectType: HKObjectType) -> HKAuthorizationStatus {
        healthStore.authorizationStatus(for: objectType)
    }

    func getPermissionStatuses() -> [String: String] {
        var statuses: [String: String] = [:]
        for metric in HealthMetricType.all {
            guard let objType = metric.objectType else { continue }
            let status = healthStore.authorizationStatus(for: objType)
            switch status {
            case .sharingAuthorized:
                statuses[metric.identifier] = "authorized"
            case .sharingDenied:
                statuses[metric.identifier] = "denied"
            case .notDetermined:
                statuses[metric.identifier] = "notDetermined"
            @unknown default:
                statuses[metric.identifier] = "unknown"
            }
        }
        // Workout type
        let workoutStatus = healthStore.authorizationStatus(for: .workoutType())
        statuses["workout"] = Self.statusString(workoutStatus)
        return statuses
    }

    private static func statusString(_ status: HKAuthorizationStatus) -> String {
        switch status {
        case .sharingAuthorized: "authorized"
        case .sharingDenied: "denied"
        case .notDetermined: "notDetermined"
        @unknown default: "unknown"
        }
    }

    // MARK: - Data Loading

    func loadAllData() async {
        guard isAvailable else { return }

        await withTaskGroup(of: Void.self) { group in
            // Load quantity samples
            for metric in HealthMetricType.all where metric.category != .sleep {
                group.addTask {
                    await self.loadQuantitySamples(for: metric)
                }
            }

            // Load sleep
            group.addTask { await self.loadSleepData() }

            // Load workouts
            group.addTask { await self.loadWorkouts() }

            // Load activity summaries
            group.addTask { await self.loadActivitySummaries() }
        }
    }

    private func loadQuantitySamples(for metric: HealthMetricType) async {
        guard let quantityType = metric.quantityTypeIdentifier.map({ HKQuantityType($0) }) else { return }

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: Date(), options: .strictStartDate)

        do {
            let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: quantityType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
                ) { _, results, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
                    }
                }
                healthStore.execute(query)
            }

            let healthSamples = samples.map { sample in
                HealthSample(
                    id: sample.uuid.uuidString,
                    type: metric.identifier,
                    value: sample.quantity.doubleValue(for: metric.unit),
                    unit: metric.unitString,
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    sourceName: sample.sourceRevision.source.name,
                    sourceBundle: sample.sourceRevision.source.bundleIdentifier
                )
            }

            await cache.setSamples(healthSamples, for: metric.identifier)
        } catch {
            // Permission denied or data not available - skip silently
        }
    }

    private func loadSleepData() async {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: Date(), options: .strictStartDate)

        do {
            let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: sleepType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
                ) { _, results, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
                    }
                }
                healthStore.execute(query)
            }

            let records = samples.map { sample -> SleepRecord in
                let stage: String
                if let sleepValue = HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                    switch sleepValue {
                    case .inBed: stage = "inBed"
                    case .asleepUnspecified: stage = "asleepUnspecified"
                    case .awake: stage = "awake"
                    case .asleepCore: stage = "asleepCore"
                    case .asleepDeep: stage = "asleepDeep"
                    case .asleepREM: stage = "asleepREM"
                    @unknown default: stage = "unknown"
                    }
                } else {
                    stage = "unknown"
                }

                return SleepRecord(
                    id: sample.uuid.uuidString,
                    stage: stage,
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    durationMinutes: sample.endDate.timeIntervalSince(sample.startDate) / 60.0,
                    sourceName: sample.sourceRevision.source.name
                )
            }

            await cache.setSleepRecords(records)
        } catch {
            // Skip silently
        }
    }

    private func loadWorkouts() async {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: Date(), options: .strictStartDate)

        do {
            let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: .workoutType(),
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
                ) { _, results, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (results as? [HKWorkout]) ?? [])
                    }
                }
                healthStore.execute(query)
            }

            let records = workouts.map { workout -> WorkoutRecord in
                let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()
                let distance = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()
                return WorkoutRecord(
                    id: workout.uuid.uuidString,
                    activityType: Self.workoutActivityName(workout.workoutActivityType),
                    activityTypeCode: UInt(workout.workoutActivityType.rawValue),
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    durationMinutes: workout.duration / 60.0,
                    totalEnergyBurned: energy?.doubleValue(for: .kilocalorie()),
                    totalEnergyBurnedUnit: energy != nil ? "kcal" : nil,
                    totalDistance: distance?.doubleValue(for: .meter()),
                    totalDistanceUnit: distance != nil ? "m" : nil,
                    sourceName: workout.sourceRevision.source.name,
                    sourceBundle: workout.sourceRevision.source.bundleIdentifier
                )
            }

            await cache.setWorkoutRecords(records)
        } catch {
            // Skip silently
        }
    }

    private func loadActivitySummaries() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today) else { return }

        var startComponents = calendar.dateComponents([.year, .month, .day, .era], from: thirtyDaysAgo)
        startComponents.calendar = calendar
        var endComponents = calendar.dateComponents([.year, .month, .day, .era], from: today)
        endComponents.calendar = calendar

        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: startComponents, end: endComponents)

        do {
            let summaries: [HKActivitySummary] = try await withCheckedThrowingContinuation { continuation in
                let query = HKActivitySummaryQuery(predicate: predicate) { _, results, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: results ?? [])
                    }
                }
                healthStore.execute(query)
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"

            let records = summaries.compactMap { summary -> ActivitySummaryRecord? in
                let dc = summary.dateComponents(for: calendar)
                guard let date = calendar.date(from: dc) else { return nil }
                let dateStr = formatter.string(from: date)

                return ActivitySummaryRecord(
                    date: dateStr,
                    activeEnergyBurned: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                    activeEnergyBurnedGoal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                    activeEnergyBurnedUnit: "kcal",
                    appleExerciseTime: summary.appleExerciseTime.doubleValue(for: .minute()),
                    appleExerciseTimeGoal: summary.exerciseTimeGoal?.doubleValue(for: .minute()) ?? 30,
                    appleStandHours: summary.appleStandHours.doubleValue(for: .count()),
                    appleStandHoursGoal: summary.standHoursGoal?.doubleValue(for: .count()) ?? 12
                )
            }

            await cache.setActivitySummaries(records.sorted { $0.date < $1.date })
        } catch {
            // Skip silently
        }
    }

    // MARK: - Observer Queries (Background Delivery)

    func setupObserverQueries() {
        guard isAvailable else { return }

        for metric in HealthMetricType.all {
            guard let sampleType = metric.sampleType else { continue }

            healthStore.enableBackgroundDelivery(for: sampleType, frequency: .hourly) { _, _ in }

            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
                guard error == nil, let self else {
                    completionHandler()
                    return
                }

                Task {
                    if metric.category == .sleep {
                        await self.loadSleepData()
                    } else {
                        await self.loadQuantitySamples(for: metric)
                    }
                    await self.notifyWebhook()
                    completionHandler()
                }
            }

            healthStore.execute(query)
            observerQueries.append(query)
        }

        // Workout observer
        healthStore.enableBackgroundDelivery(for: .workoutType(), frequency: .hourly) { _, _ in }
        let workoutObserver = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil, let self else {
                completionHandler()
                return
            }
            Task {
                await self.loadWorkouts()
                await self.notifyWebhook()
                completionHandler()
            }
        }
        healthStore.execute(workoutObserver)
        observerQueries.append(workoutObserver)
    }

    func stopObserverQueries() {
        for query in observerQueries {
            healthStore.stop(query)
        }
        observerQueries.removeAll()
    }

    // MARK: - Webhook

    private func notifyWebhook() async {
        guard let webhookManager else { return }
        let export = await cache.exportAllData(days: 7)
        await webhookManager.sendPayload(export)
    }

    // MARK: - Helpers

    private static func workoutActivityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "running"
        case .cycling: "cycling"
        case .walking: "walking"
        case .swimming: "swimming"
        case .hiking: "hiking"
        case .yoga: "yoga"
        case .functionalStrengthTraining: "functionalStrengthTraining"
        case .traditionalStrengthTraining: "traditionalStrengthTraining"
        case .dance: "dance"
        case .cooldown: "cooldown"
        case .coreTraining: "coreTraining"
        case .elliptical: "elliptical"
        case .rowing: "rowing"
        case .stairClimbing: "stairClimbing"
        case .highIntensityIntervalTraining: "highIntensityIntervalTraining"
        case .jumpRope: "jumpRope"
        case .pilates: "pilates"
        case .soccer: "soccer"
        case .basketball: "basketball"
        case .tennis: "tennis"
        case .badminton: "badminton"
        case .martialArts: "martialArts"
        case .golf: "golf"
        case .baseball: "baseball"
        case .tableTennis: "tableTennis"
        case .skatingSports: "skatingSports"
        case .snowSports: "snowSports"
        case .mixedCardio: "mixedCardio"
        case .other: "other"
        default: "activityType_\(type.rawValue)"
        }
    }
}
