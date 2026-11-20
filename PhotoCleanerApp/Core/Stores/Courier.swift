import Foundation

// MARK: - Courier Failure (setup-backend §2)

enum CourierFailure: LocalizedError, Sendable {
    case offline
    case unauthorized
    case server(statusCode: Int)
    case rateLimited
    case serviceUnavailable
    case invalidRequest(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .offline:
            return "No internet connection. Please check your network and try again."
        case .unauthorized:
            return "Authorization error. Please try again."
        case .server(let code):
            return "Server returned an error (\(code)). Please try again later."
        case .rateLimited:
            return "Too many requests. Please wait a few moments before trying again."
        case .serviceUnavailable:
            return "The security service is currently unavailable. Please try again later."
        case .invalidRequest(let message):
            return message
        case .decoding(let detail):
            return "Failed to process server response: \(detail)"
        }
    }
}

// MARK: - v9 Response Envelope

struct V9Envelope<T: Codable>: Codable {
    let pouch: V9Pouch<T>
    let wax: V9Wax?
    let digit: Int?
}

struct V9Pouch<T: Codable>: Codable {
    let filling: T?
    let shade: String // "bright" | "dim" | "dark"
    let crumbs: [String: [String]]?
}

struct V9Wax: Codable {
    let bead: String?
    let ms: Int?
    let who: String?
    let step: String?
    let trail: String?
}

// MARK: - Courier Protocol & Live Implementation

protocol CourierProtocol: Sendable {
    func checkEmail(_ email: String) async throws -> EmailCheckResponse
    func checkLink(_ urlString: String) async throws -> LinkCheckResponse
    func fetchSafariRules(file: SafariRuleFile, etag: String?) async throws -> SafariRulesResult
    func resolveDNSQuery(dnsMessage: Data) async throws -> Data
}

final class Courier: CourierProtocol, Sendable {
    static let shared = Courier()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private var defaultBaseURL: URL {
        RemoteConfiguration.shared.value.backend.baseURL ?? URL(string: "https://flint.dolightdev.org")!
    }

    private var linkCheckURL: URL {
        RemoteConfiguration.shared.value.backend.linkCheckApiURL ?? defaultBaseURL
    }

    private var rulesBaseURL: URL {
        RemoteConfiguration.shared.value.backend.safariBlockerRulesURL ?? defaultBaseURL.appendingPathComponent("rules")
    }

    private var dohURL: URL {
        RemoteConfiguration.shared.value.backend.webProtectionDoHURL ?? defaultBaseURL.appendingPathComponent("dns-query")
    }

    // MARK: - 1. Email Breach Check (POST /v1/email/check)

    func checkEmail(_ email: String) async throws -> EmailCheckResponse {
        let endpoint = defaultBaseURL.appendingPathComponent("v1/email/check")
        let requestBody = try JSONEncoder().encode(EmailCheckRequest(email: email))

        return try await executeWithRetry(
            url: endpoint,
            method: "POST",
            body: requestBody,
            timeout: 10.0
        )
    }

    // MARK: - 2. Link Check API (POST /v1/link-check)

    func checkLink(_ urlString: String) async throws -> LinkCheckResponse {
        let endpoint = linkCheckURL.appendingPathComponent("v1/link-check")
        let requestBody = try JSONEncoder().encode(LinkCheckRequest(url: urlString))

        return try await executeWithRetry(
            url: endpoint,
            method: "POST",
            body: requestBody,
            timeout: 5.0
        )
    }

    // MARK: - 3. Safari Blocker Rules (GET /rules/{file})

    func fetchSafariRules(file: SafariRuleFile, etag: String?) async throws -> SafariRulesResult {
        let fileURL = rulesBaseURL.appendingPathComponent(file.rawValue)
        var request = URLRequest(url: fileURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15.0)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .networkConnectionLost {
                (data, response) = try await session.data(for: request)
            } else if urlError.code == .notConnectedToInternet || urlError.code == .cannotConnectToHost {
                throw CourierFailure.offline
            } else {
                throw urlError
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw CourierFailure.server(statusCode: 0)
        }

        if http.statusCode == 304 {
            return .notModified
        }

        if http.statusCode == 404 {
            return .notFound
        }

        guard (200..<300).contains(http.statusCode) else {
            throw CourierFailure.server(statusCode: http.statusCode)
        }

        let newETag = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "etag")
        return .modified(data: data, etag: newETag)
    }

    // MARK: - 4. Web Protection DNS-over-HTTPS (RFC 8484)

    func resolveDNSQuery(dnsMessage: Data) async throws -> Data {
        var request = URLRequest(url: dohURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5.0)
        request.httpMethod = "POST"
        request.setValue("application/dns-message", forHTTPHeaderField: "Content-Type")
        request.setValue("application/dns-message", forHTTPHeaderField: "Accept")
        request.httpBody = dnsMessage

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CourierFailure.server(statusCode: 0)
        }

        if (200..<300).contains(http.statusCode) {
            return data
        } else if http.statusCode == 400 {
            throw CourierFailure.invalidRequest("Malformed DNS message")
        } else {
            throw CourierFailure.server(statusCode: http.statusCode)
        }
    }

    // MARK: - Centralized v9 Request Executor (setup-backend §4)

    private func executeWithRetry<T: Codable>(
        url: URL,
        method: String,
        body: Data?,
        timeout: TimeInterval
    ) async throws -> T {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-App-Bundle-Id")
        }
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            request.setValue(version, forHTTPHeaderField: "X-App-Version")
        }
        request.httpBody = body

        // Resilience: retry once on .networkConnectionLost (setup-backend §4)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .networkConnectionLost {
                (data, response) = try await session.data(for: request)
            } else if urlError.code == .notConnectedToInternet || urlError.code == .cannotConnectToHost {
                throw CourierFailure.offline
            } else if urlError.code == .timedOut {
                throw CourierFailure.offline
            } else {
                throw urlError
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw CourierFailure.server(statusCode: 0)
        }

        return try decodeV9Payload(from: data, statusCode: http.statusCode)
    }

    // MARK: - Envelope Decoding & Error Unwrapping (IOS_INTEGRATION_CLEANER_9.md §2)

    private func decodeV9Payload<T: Codable>(from data: Data, statusCode: Int) throws -> T {
        let decoder = JSONDecoder()

        // 1. Attempt to decode standard v9 Envelope
        if let envelope = try? decoder.decode(V9Envelope<T>.self, from: data) {
            let shade = envelope.pouch.shade
            let digit = envelope.digit ?? statusCode

            if shade == "bright", let filling = envelope.pouch.filling {
                return filling
            }

            // Error responses inside envelope
            let validationMessage = formatCrumbs(envelope.pouch.crumbs)
            if digit == 429 {
                throw CourierFailure.rateLimited
            } else if digit == 503 {
                throw CourierFailure.serviceUnavailable
            } else if digit == 400 {
                throw CourierFailure.invalidRequest(validationMessage ?? "Invalid request.")
            } else {
                throw CourierFailure.server(statusCode: digit)
            }
        }

        // 2. Fallback: Check for error envelope without generic filling
        if let errorEnvelope = try? decoder.decode(V9Envelope<EmptyFilling>.self, from: data) {
            let digit = errorEnvelope.digit ?? statusCode
            let validationMessage = formatCrumbs(errorEnvelope.pouch.crumbs)

            if digit == 429 {
                throw CourierFailure.rateLimited
            } else if digit == 503 {
                throw CourierFailure.serviceUnavailable
            } else if digit == 400 {
                throw CourierFailure.invalidRequest(validationMessage ?? "Invalid input.")
            } else {
                throw CourierFailure.server(statusCode: digit)
            }
        }

        // 3. Fallback: Direct bare model (Cleaner 3 / legacy)
        if (200..<300).contains(statusCode), let direct = try? decoder.decode(T.self, from: data) {
            return direct
        }

        // 4. HTTP status error fallback
        if statusCode == 429 {
            throw CourierFailure.rateLimited
        } else if statusCode == 503 {
            throw CourierFailure.serviceUnavailable
        } else if !(200..<300).contains(statusCode) {
            throw CourierFailure.server(statusCode: statusCode)
        }

        throw CourierFailure.decoding("Unable to parse response.")
    }

    private func formatCrumbs(_ crumbs: [String: [String]]?) -> String? {
        guard let crumbs, !crumbs.isEmpty else { return nil }
        var messages: [String] = []
        for (_, errors) in crumbs {
            messages.append(contentsOf: errors)
        }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }
}

private struct EmptyFilling: Codable {}
