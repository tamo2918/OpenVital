import SwiftUI

struct HomeView: View {
    @Bindable var appState: AppState
    @State private var logRefreshTimer: Timer?

    var body: some View {
        NavigationStack {
            List {
                serverStatusSection
                connectionSection
                curlSection
                logsSection
            }
            .navigationTitle("OpenVital")
            .refreshable {
                await appState.refreshData()
                await appState.refreshLogs()
            }
            .onAppear {
                startLogRefresh()
            }
            .onDisappear {
                stopLogRefresh()
            }
        }
    }

    // MARK: - Server Status

    private var serverStatusSection: some View {
        Section {
            HStack {
                Label {
                    Text("API Server")
                } icon: {
                    Image(systemName: appState.isServerRunning ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(appState.isServerRunning ? .green : .red)
                }
                Spacer()
                Text(appState.isServerRunning ? "Running" : "Stopped")
                    .foregroundStyle(.secondary)
            }

            if let error = appState.serverError {
                Label {
                    Text(error)
                        .foregroundStyle(.red)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            HStack {
                Label("Port", systemImage: "network")
                Spacer()
                Text("\(appState.serverPort)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack {
                Label("Mode", systemImage: appState.localhostOnly ? "lock.fill" : "globe")
                Spacer()
                Text(appState.localhostOnly ? "Localhost Only" : "LAN")
                    .foregroundStyle(.secondary)
            }

            if appState.isLoadingData {
                HStack {
                    Label("Data", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    ProgressView()
                }
            }
        } header: {
            Text("Status")
        }
    }

    // MARK: - Connection Info

    private var connectionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Base URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(appState.serverURL)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Button {
                        UIPasteboard.general.string = appState.serverURL
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        } header: {
            Text("Connection")
        }
    }

    // MARK: - cURL Examples

    private var curlSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Status (no auth)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("curl \(appState.curlExample)")
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = "curl \(appState.curlExample)"
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Steps (with auth)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(appState.curlWithAuthExample)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(3)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = appState.curlWithAuthExample
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        } header: {
            Text("Quick Start")
        }
    }

    // MARK: - Request Logs

    private var displayLogs: [RequestLog] {
        Array(appState.recentLogs.prefix(10))
    }

    private var logsSection: some View {
        Section {
            if appState.recentLogs.isEmpty {
                Text("No requests yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayLogs) { log in
                    logRow(log)
                }
            }

            if !appState.recentLogs.isEmpty {
                Button("Clear Logs") {
                    Task { await appState.clearLogs() }
                }
                .foregroundStyle(.red)
            }
        } header: {
            Text("Recent Requests")
        }
    }

    private func logRow(_ log: RequestLog) -> some View {
        HStack {
            Text(log.method)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(log.statusCode < 400 ? .green : .red)
            Text(log.path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
            Spacer()
            Text("\(log.statusCode)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(log.statusCode < 400 ? Color.secondary : Color.red)
            Text(String(format: "%.0fms", log.durationMs))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Log Refresh

    private func startLogRefresh() {
        logRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                await appState.refreshLogs()
            }
        }
    }

    private func stopLogRefresh() {
        logRefreshTimer?.invalidate()
        logRefreshTimer = nil
    }
}
