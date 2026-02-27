import SwiftUI

struct PermissionsView: View {
    @Bindable var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                if !appState.isHealthKitAvailable {
                    Section {
                        Label {
                            VStack(alignment: .leading) {
                                Text("HealthKit Not Available")
                                    .fontWeight(.semibold)
                                Text("This device does not support HealthKit.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    Section {
                        Button {
                            Task { await appState.requestPermissions() }
                        } label: {
                            Label("Request All Permissions", systemImage: "heart.text.square")
                        }

                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Open Health Settings", systemImage: "gear")
                        }
                    } header: {
                        Text("Actions")
                    } footer: {
                        Text("HealthKit does not reveal whether permission was denied or not requested. \"Unknown\" may mean either.")
                    }

                    permissionsSection(title: "Activity", category: .activity)
                    permissionsSection(title: "Vitals", category: .vitals)
                    permissionsSection(title: "Body", category: .body)
                    permissionsSection(title: "Sleep", category: .sleep)

                    Section("Other") {
                        permissionRow(identifier: "workout", name: "Workouts")
                    }
                }
            }
            .navigationTitle("Permissions")
            .refreshable {
                await appState.refreshPermissions()
            }
        }
    }

    private func permissionsSection(title: String, category: HealthMetricCategory) -> some View {
        let metrics = HealthMetricType.all.filter { $0.category == category }
        return Section(title) {
            ForEach(metrics, id: \.identifier) { metric in
                permissionRow(identifier: metric.identifier, name: metric.identifier)
            }
        }
    }

    private func permissionRow(identifier: String, name: String) -> some View {
        HStack {
            Text(name)
                .font(.system(.body, design: .monospaced))
            Spacer()
            permissionBadge(for: appState.permissionStatuses[identifier] ?? "unknown")
        }
    }

    private func permissionBadge(for status: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 8, height: 8)
            Text(statusLabel(status))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "authorized": .green
        case "denied": .red
        case "notDetermined": .orange
        default: .gray
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "authorized": "Authorized"
        case "denied": "Denied"
        case "notDetermined": "Not Set"
        default: "Unknown"
        }
    }
}
