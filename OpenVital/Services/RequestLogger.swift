import Foundation

nonisolated struct RequestLog: Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let method: String
    let path: String
    let statusCode: Int
    let durationMs: Double
}

actor RequestLogger {
    private var logs: [RequestLog] = []
    private let maxLogs = 1000

    func log(method: String, path: String, statusCode: Int, durationMs: Double) {
        let entry = RequestLog(
            id: UUID(),
            timestamp: Date(),
            method: method,
            path: path,
            statusCode: statusCode,
            durationMs: durationMs
        )
        logs.append(entry)
        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }
    }

    func getRecentLogs(count: Int = 50) -> [RequestLog] {
        Array(logs.suffix(count).reversed())
    }

    func clear() {
        logs.removeAll()
    }
}
