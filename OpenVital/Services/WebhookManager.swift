import Foundation
import CryptoKit

actor WebhookManager {
    // MARK: - Configuration

    private let defaults = UserDefaults.standard
    private let urlSession: URLSession

    private(set) var webhookURL: String {
        didSet { defaults.set(webhookURL, forKey: "webhookURL") }
    }

    private(set) var webhookEnabled: Bool {
        didSet { defaults.set(webhookEnabled, forKey: "webhookEnabled") }
    }

    private(set) var webhookSecret: String? {
        didSet { defaults.set(webhookSecret, forKey: "webhookSecret") }
    }

    private(set) var lastStatus: WebhookStatus?

    init() {
        self.webhookURL = UserDefaults.standard.string(forKey: "webhookURL") ?? ""
        self.webhookEnabled = UserDefaults.standard.bool(forKey: "webhookEnabled")
        self.webhookSecret = UserDefaults.standard.string(forKey: "webhookSecret")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Configuration Updates

    func setURL(_ url: String) {
        webhookURL = url
    }

    func setEnabled(_ enabled: Bool) {
        webhookEnabled = enabled
    }

    func setSecret(_ secret: String?) {
        webhookSecret = secret
    }

    // MARK: - Send

    func sendPayload(_ export: HealthDataExport) async {
        guard webhookEnabled, !webhookURL.isEmpty, let url = URL(string: webhookURL) else {
            return
        }

        let formatter = ISO8601DateFormatter()
        let payload = WebhookPayload(
            event: "health_data_updated",
            timestamp: formatter.string(from: Date()),
            data: export
        )

        do {
            let body = try JSONCoders.encoder.encode(payload)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("OpenVital/1.0", forHTTPHeaderField: "User-Agent")
            request.httpBody = body

            if let secret = webhookSecret, !secret.isEmpty {
                let signature = computeHMAC(data: body, key: secret)
                request.setValue(signature, forHTTPHeaderField: "X-OpenVital-Signature")
            }

            let (_, response) = try await urlSession.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0
            let success = (200..<300).contains(statusCode)

            lastStatus = WebhookStatus(
                success: success,
                statusCode: statusCode,
                message: success ? "OK" : "HTTP \(statusCode)",
                timestamp: Date()
            )
        } catch {
            lastStatus = WebhookStatus(
                success: false,
                statusCode: nil,
                message: error.localizedDescription,
                timestamp: Date()
            )
        }
    }

    func sendTestPayload(_ export: HealthDataExport) async -> WebhookStatus {
        await sendPayload(export)
        return lastStatus ?? WebhookStatus(
            success: false,
            statusCode: nil,
            message: "No result",
            timestamp: Date()
        )
    }

    // MARK: - HMAC

    private nonisolated func computeHMAC(data: Data, key: String) -> String {
        let keyData = SymmetricKey(data: Data(key.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: keyData)
        return "sha256=" + signature.map { String(format: "%02x", $0) }.joined()
    }
}
