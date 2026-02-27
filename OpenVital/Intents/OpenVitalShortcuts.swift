import AppIntents

struct OpenVitalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ExportHealthDataIntent(),
            phrases: [
                "Export health data with \(.applicationName)",
                "Get all health data from \(.applicationName)"
            ],
            shortTitle: "Export Health Data",
            systemImageName: "heart.text.clipboard"
        )

        AppShortcut(
            intent: GetMetricIntent(),
            phrases: [
                "Get \(\.$metricType) from \(.applicationName)",
                "Check my \(\.$metricType) with \(.applicationName)"
            ],
            shortTitle: "Get Health Metric",
            systemImageName: "chart.bar"
        )
    }
}
