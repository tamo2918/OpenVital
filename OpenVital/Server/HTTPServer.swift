import Foundation

// MARK: - HTTP Types

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let pathComponents: [String]
    let queryParams: [String: String]
    let headers: [String: String]

    var bearerToken: String? {
        guard let auth = headers["authorization"] ?? headers["Authorization"] else { return nil }
        let prefix = "Bearer "
        guard auth.hasPrefix(prefix) else { return nil }
        return String(auth.dropFirst(prefix.count))
    }
}

struct HTTPResponse: Sendable {
    let statusCode: Int
    let statusText: String
    let contentType: String
    let body: Data

    static func json(_ data: Data, status: Int = 200, statusText: String = "OK") -> HTTPResponse {
        HTTPResponse(statusCode: status, statusText: statusText, contentType: "application/json; charset=utf-8", body: data)
    }

    static func error(code: String, message: String, status: Int) -> HTTPResponse {
        let error = APIError(error: APIErrorDetail(code: code, message: message, status: status))
        let data = (try? JSONCoders.encoder.encode(error)) ?? Data()
        let statusText: String
        switch status {
        case 400: statusText = "Bad Request"
        case 401: statusText = "Unauthorized"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 429: statusText = "Too Many Requests"
        case 503: statusText = "Service Unavailable"
        default: statusText = "Error"
        }
        return HTTPResponse(statusCode: status, statusText: statusText, contentType: "application/json; charset=utf-8", body: data)
    }

    static func noContent() -> HTTPResponse {
        HTTPResponse(statusCode: 204, statusText: "No Content", contentType: "", body: Data())
    }
}

// MARK: - HTTP Server

typealias RouteHandler = @Sendable (HTTPRequest) async -> HTTPResponse

final class HTTPServer: @unchecked Sendable {
    private var serverSocket: Int32 = -1
    private let queue = DispatchQueue(label: "dev.openvital.httpserver.accept")
    private let clientQueue = DispatchQueue(label: "dev.openvital.httpserver.clients", attributes: .concurrent)
    private var _isRunning = false
    private let lock = NSLock()
    private let routeHandler: RouteHandler
    private let logger: RequestLogger
    let startTime: Date

    var isRunning: Bool {
        lock.withLock { _isRunning }
    }

    nonisolated init(routeHandler: @escaping RouteHandler, logger: RequestLogger) {
        self.routeHandler = routeHandler
        self.logger = logger
        self.startTime = Date()
    }

    func start(port: UInt16, localhostOnly: Bool) throws {
        serverSocket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw ServerError.socketCreationFailed
        }

        var opt: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        let loopback: in_addr_t = 0x7f000001
        addr.sin_addr = in_addr(s_addr: localhostOnly ? loopback.bigEndian : in_addr_t(0))

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                Darwin.bind(serverSocket, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(serverSocket)
            throw ServerError.bindFailed(port: port)
        }

        guard Darwin.listen(serverSocket, 128) == 0 else {
            Darwin.close(serverSocket)
            throw ServerError.listenFailed
        }

        lock.withLock { _isRunning = true }

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        lock.withLock { _isRunning = false }
        if serverSocket >= 0 {
            Darwin.close(serverSocket)
            serverSocket = -1
        }
    }

    // MARK: - Accept Loop

    private func acceptLoop() {
        while isRunning {
            var clientAddr = sockaddr_in()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    Darwin.accept(serverSocket, saPtr, &clientAddrLen)
                }
            }

            guard clientSocket >= 0 else {
                if isRunning {
                    continue
                }
                break
            }

            let handler = routeHandler
            let logger = self.logger

            clientQueue.async {
                let requestStart = Date()
                defer { Darwin.close(clientSocket) }

                guard let data = Self.readRequest(from: clientSocket) else { return }
                guard let request = Self.parseHTTPRequest(data) else {
                    let response = HTTPResponse.error(code: "bad_request", message: "Malformed request", status: 400)
                    Self.sendResponse(response, to: clientSocket)
                    return
                }

                // Handle CORS preflight
                if request.method == "OPTIONS" {
                    let response = HTTPResponse.noContent()
                    Self.sendResponse(response, to: clientSocket, includeCORS: true)
                    return
                }

                let semaphore = DispatchSemaphore(value: 0)
                var response = HTTPResponse.error(code: "internal_error", message: "Internal error", status: 500)

                Task.detached {
                    response = await handler(request)
                    semaphore.signal()
                }

                semaphore.wait()

                Self.sendResponse(response, to: clientSocket, includeCORS: true)

                let durationMs = Date().timeIntervalSince(requestStart) * 1000

                Task.detached {
                    await logger.log(
                        method: request.method,
                        path: request.path,
                        statusCode: response.statusCode,
                        durationMs: durationMs
                    )
                }
            }
        }
    }

    // MARK: - Request Parsing

    private static func readRequest(from socket: Int32) -> Data? {
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var buffer = [UInt8](repeating: 0, count: 8192)
        var data = Data()

        while true {
            let bytesRead = recv(socket, &buffer, buffer.count, 0)
            if bytesRead <= 0 { break }
            data.append(contentsOf: buffer[0..<bytesRead])

            if let str = String(data: data, encoding: .utf8), str.contains("\r\n\r\n") {
                break
            }
            if data.count > 65536 { break }
        }

        return data.isEmpty ? nil : data
    }

    static func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let fullPath = String(parts[1])

        // Parse path and query
        let pathAndQuery = fullPath.split(separator: "?", maxSplits: 1)
        let path = String(pathAndQuery[0])
        var queryParams: [String: String] = [:]

        if pathAndQuery.count > 1 {
            let queryString = String(pathAndQuery[1])
            for pair in queryString.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                    let value = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                    queryParams[key] = value
                }
            }
        }

        // Parse headers
        var headers: [String: String] = [:]
        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty { break }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        // Build path components (skip empty first component from leading /)
        let pathComponents = path.split(separator: "/").map(String.init)

        return HTTPRequest(
            method: method,
            path: path,
            pathComponents: pathComponents,
            queryParams: queryParams,
            headers: headers
        )
    }

    // MARK: - Response Sending

    private static func sendResponse(_ response: HTTPResponse, to socket: Int32, includeCORS: Bool = false) {
        var headerLines = [
            "HTTP/1.1 \(response.statusCode) \(response.statusText)",
            "Connection: close",
        ]

        if !response.contentType.isEmpty {
            headerLines.append("Content-Type: \(response.contentType)")
        }
        headerLines.append("Content-Length: \(response.body.count)")

        if includeCORS {
            headerLines.append("Access-Control-Allow-Origin: *")
            headerLines.append("Access-Control-Allow-Methods: GET, OPTIONS")
            headerLines.append("Access-Control-Allow-Headers: Authorization, Content-Type")
            headerLines.append("Access-Control-Max-Age: 86400")
        }

        let headerString = headerLines.joined(separator: "\r\n") + "\r\n\r\n"
        guard var headerData = headerString.data(using: .utf8) else { return }
        headerData.append(response.body)

        headerData.withUnsafeBytes { bufferPointer in
            guard let baseAddress = bufferPointer.baseAddress else { return }
            var totalSent = 0
            let totalBytes = headerData.count
            while totalSent < totalBytes {
                let sent = send(socket, baseAddress.advanced(by: totalSent), totalBytes - totalSent, 0)
                if sent <= 0 { break }
                totalSent += sent
            }
        }
    }

    // MARK: - Errors

    enum ServerError: Error, LocalizedError {
        case socketCreationFailed
        case bindFailed(port: UInt16)
        case listenFailed

        var errorDescription: String? {
            switch self {
            case .socketCreationFailed: "Failed to create socket"
            case .bindFailed(let port): "Failed to bind to port \(port). It may already be in use."
            case .listenFailed: "Failed to start listening for connections"
            }
        }
    }
}
