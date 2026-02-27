import SwiftUI
@preconcurrency import HealthKit

@Observable
final class AppState {
    // MARK: - Server State
    var isServerRunning = false
    var serverPort: UInt16 = 8080
    var localhostOnly = true
    var serverError: String?
    var recentLogs: [RequestLog] = []

    // MARK: - HealthKit State
    var isHealthKitAvailable = false
    var permissionStatuses: [String: String] = [:]
    var isLoadingData = false
    var dataLoadError: String?

    // MARK: - Token State
    var currentToken: String = ""

    // MARK: - Services
    let cache = HealthDataCache()
    let tokenManager = TokenManager()
    let requestLogger = RequestLogger()
    private(set) var healthKitManager: HealthKitManager!
    private var httpServer: HTTPServer?

    // MARK: - Settings (persisted)
    private let defaults = UserDefaults.standard

    init() {
        healthKitManager = HealthKitManager(cache: cache)
        isHealthKitAvailable = healthKitManager.isAvailable

        // Load persisted settings
        let savedPort = defaults.integer(forKey: "serverPort")
        if savedPort > 0 {
            serverPort = UInt16(savedPort)
        }
        localhostOnly = !defaults.bool(forKey: "lanModeEnabled")
    }

    // MARK: - Setup

    func setup() async {
        // Load token
        currentToken = await tokenManager.getToken()

        // Request permissions and load data if HealthKit is available
        if isHealthKitAvailable {
            do {
                try await healthKitManager.requestAuthorization()
            } catch {
                dataLoadError = error.localizedDescription
            }

            await refreshPermissions()
            await loadHealthData()

            // Setup observer queries for data changes
            await healthKitManager.setupObserverQueries()
        }

        // Start server
        startServer()
    }

    // MARK: - HealthKit

    func requestPermissions() async {
        guard isHealthKitAvailable else { return }
        do {
            try await healthKitManager.requestAuthorization()
            await refreshPermissions()
            await loadHealthData()
        } catch {
            dataLoadError = error.localizedDescription
        }
    }

    func refreshPermissions() async {
        permissionStatuses = await healthKitManager.getPermissionStatuses()
    }

    func loadHealthData() async {
        guard isHealthKitAvailable else { return }
        isLoadingData = true
        dataLoadError = nil

        await healthKitManager.loadAllData()

        isLoadingData = false
    }

    func refreshData() async {
        await loadHealthData()
    }

    // MARK: - Server

    func startServer() {
        guard httpServer == nil else { return }
        serverError = nil

        let router = Router(
            cache: cache,
            tokenManager: tokenManager,
            logger: requestLogger,
            serverPort: serverPort,
            serverStartTime: Date()
        )

        let server = HTTPServer(routeHandler: router.handle, logger: requestLogger)
        do {
            try server.start(port: serverPort, localhostOnly: localhostOnly)
            httpServer = server
            isServerRunning = true
        } catch {
            serverError = error.localizedDescription
            isServerRunning = false
        }
    }

    func stopServer() {
        httpServer?.stop()
        httpServer = nil
        isServerRunning = false
    }

    func restartServer() {
        stopServer()
        startServer()
    }

    // MARK: - Token

    func regenerateToken() async {
        currentToken = await tokenManager.regenerateToken()
    }

    // MARK: - Settings

    func updatePort(_ port: UInt16) {
        serverPort = port
        defaults.set(Int(port), forKey: "serverPort")
        restartServer()
    }

    func updateLocalhostOnly(_ value: Bool) {
        localhostOnly = value
        defaults.set(!value, forKey: "lanModeEnabled")
        restartServer()
    }

    // MARK: - Logs

    func refreshLogs() async {
        recentLogs = await requestLogger.getRecentLogs(count: 50)
    }

    func clearLogs() async {
        await requestLogger.clear()
        recentLogs = []
    }

    // MARK: - Lifecycle

    func handleSceneActive() {
        if !isServerRunning && httpServer == nil {
            startServer()
        }
    }

    func handleSceneBackground() {
        stopServer()
    }

    // MARK: - Computed Properties

    var serverURL: String {
        let host = localhostOnly ? "localhost" : getWiFiAddress() ?? "localhost"
        return "http://\(host):\(serverPort)"
    }

    var curlExample: String {
        "\(serverURL)/v1/status"
    }

    var curlWithAuthExample: String {
        "curl -H \"Authorization: Bearer \(currentToken)\" \(serverURL)/v1/metrics/stepCount"
    }
}

// MARK: - Network Helpers

private func getWiFiAddress() -> String? {
    var address: String?
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
        address = String(cString: hostname)
    }

    return address
}
