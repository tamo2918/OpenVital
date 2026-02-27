import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    @State private var selectedPort: UInt16 = 8080
    @State private var showLANWarning = false

    var body: some View {
        NavigationStack {
            List {
                serverSection
                networkSection
                webhookSection
                shortcutsSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .onAppear {
                selectedPort = appState.serverPort
            }
            .alert("Enable LAN Mode?", isPresented: $showLANWarning) {
                Button("Enable", role: .destructive) {
                    appState.updateLocalhostOnly(false)
                }
                Button("Cancel", role: .cancel) {
                    // Reset to localhost only
                }
            } message: {
                Text("LAN mode makes your health data API accessible to all devices on your Wi-Fi network. Only enable this on trusted networks.")
            }
        }
    }

    // MARK: - Server Settings

    private var serverSection: some View {
        Section {
            HStack {
                Text("Server")
                Spacer()
                Button(appState.isServerRunning ? "Stop" : "Start") {
                    if appState.isServerRunning {
                        appState.stopServer()
                    } else {
                        appState.startServer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.isServerRunning ? .red : .green)
            }

            Picker("Port", selection: $selectedPort) {
                ForEach(8080...8090, id: \.self) { port in
                    Text("\(port)").tag(UInt16(port))
                }
            }
            .onChange(of: selectedPort) { _, newPort in
                if newPort != appState.serverPort {
                    appState.updatePort(newPort)
                }
            }
        } header: {
            Text("Server")
        }
    }

    // MARK: - Network Settings

    private var networkSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { !appState.localhostOnly },
                set: { newValue in
                    if newValue {
                        showLANWarning = true
                    } else {
                        appState.updateLocalhostOnly(true)
                    }
                }
            )) {
                VStack(alignment: .leading) {
                    Text("LAN Mode")
                    Text(appState.localhostOnly ? "Only this device" : "All devices on network")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Network")
        } footer: {
            if !appState.localhostOnly {
                Text("LAN IP: \(getWiFiIP() ?? "Not connected")")
            }
        }
    }

    // MARK: - Data Settings

    private var dataSection: some View {
        Section {
            Button {
                Task { await appState.refreshData() }
            } label: {
                HStack {
                    Label("Refresh Health Data", systemImage: "arrow.triangle.2.circlepath")
                    if appState.isLoadingData {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(appState.isLoadingData)

        } header: {
            Text("Data")
        } footer: {
            if let lastUpdated = appState.recentLogs.first?.timestamp {
                Text("Cache covers the last 30 days. Last request: \(lastUpdated.formatted())")
            } else {
                Text("Cache covers the last 30 days of health data.")
            }
        }
    }

    // MARK: - Webhook

    private var webhookSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { appState.webhookEnabled },
                set: { newValue in
                    Task { await appState.updateWebhookEnabled(newValue) }
                }
            )) {
                VStack(alignment: .leading) {
                    Text("Webhook")
                    Text("POST health data to external URL on updates")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if appState.webhookEnabled {
                TextField("Webhook URL", text: Binding(
                    get: { appState.webhookURL },
                    set: { newValue in
                        Task { await appState.updateWebhookURL(newValue) }
                    }
                ))
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)

                TextField("Secret (optional, for HMAC signature)", text: Binding(
                    get: { appState.webhookSecret },
                    set: { newValue in
                        Task { await appState.updateWebhookSecret(newValue) }
                    }
                ))
                .autocapitalization(.none)
                .disableAutocorrection(true)

                Button {
                    Task { await appState.testWebhook() }
                } label: {
                    HStack {
                        Label("Send Test", systemImage: "paperplane")
                        if appState.isTestingWebhook {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(appState.webhookURL.isEmpty || appState.isTestingWebhook)

                if let status = appState.lastWebhookStatus {
                    HStack {
                        Image(systemName: status.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(status.success ? Color.green : Color.red)
                        VStack(alignment: .leading) {
                            Text(status.message)
                                .font(.caption)
                            Text(status.timestamp.formatted())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Webhook")
        } footer: {
            Text("When enabled, health data is POSTed to the URL whenever HealthKit detects changes.")
        }
    }

    // MARK: - Shortcuts

    private var shortcutsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Use the Shortcuts app to automate health data exports on a schedule.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Available actions: \"Export Health Data\", \"Get Health Metric\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                if let url = URL(string: "shortcuts://") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Shortcuts App", systemImage: "arrow.right.circle")
            }
        } header: {
            Text("Shortcuts")
        } footer: {
            Text("Create automations like \"Every day at 8 AM, export health data and send to my server\".")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("API Version")
                Spacer()
                Text("v1")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Supported Metrics")
                Spacer()
                Text("\(HealthMetricType.allIdentifiers.count)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("About")
        }
    }

    private func getWiFiIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil, 0,
                NI_NUMERICHOST
            )
            return String(cString: hostname)
        }
        return nil
    }
}
