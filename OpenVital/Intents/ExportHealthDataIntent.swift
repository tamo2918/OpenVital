import AppIntents
import SwiftUI

struct ExportHealthDataIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Health Data"
    static let description: IntentDescription = "Export HealthKit data as JSON for the specified number of days."
    static let openAppWhenRun = true

    @Parameter(title: "Days", default: 7)
    var days: Int

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let cache = HealthDataCache()
        let manager = HealthKitManager(cache: cache)

        try await manager.requestAuthorization()
        await manager.loadAllData()

        let export = await cache.exportAllData(days: days)
        let data = try JSONCoders.encoder.encode(export)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        return .result(value: json)
    }
}
