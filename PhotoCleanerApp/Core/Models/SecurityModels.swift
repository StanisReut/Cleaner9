import Foundation

// MARK: - Screen Phase (setup-backend §7)

enum ScreenPhase<Content> {
    case loading
    case content(Content)
    case loadFailure(String)
    case offline
}

// MARK: - Email Breach Check Models (OpenAPI: /v1/email/check)

struct EmailCheckRequest: Codable, Sendable {
    let email: String
}

struct EmailBreach: Codable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let title: String?
    let domain: String?
    let breach_date: String?
    let added_date: String?
    let modified_date: String?
    let pwn_count: Int?
    let description_html: String?
    let logo_url: String?
    let data_classes: [String]?
    let data_class_keys: [String]?
    let is_verified: Bool?
    let is_sensitive: Bool?
    let risk: String? // "high", "medium", "low"
    let source: String?

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return name
    }

    var displayDate: String {
        guard let breach_date, !breach_date.isEmpty else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter.date(from: breach_date) {
            let out = DateFormatter()
            out.locale = Locale(identifier: "en_US_POSIX")
            out.dateFormat = "MMM d, yyyy"
            return out.string(from: date)
        }
        return breach_date
    }

    var displayFields: String {
        data_classes?.joined(separator: ", ") ?? ""
    }
}

struct BreachSummary: Codable, Sendable {
    let total: Int
    let high: Int
    let medium: Int
    let low: Int
}

struct MonitoringStatus: Codable, Sendable {
    let enabled: Bool
    let last_checked_at: String?
}

struct EmailCheckResponse: Codable, Sendable {
    let email_masked: String
    let checked_at: String
    let breaches: [EmailBreach]
    let summary: BreachSummary
    let monitoring: MonitoringStatus
}

// MARK: - Link Check Models (OpenAPI: /v1/link-check)

enum LinkCheckVerdict: String, Codable, Sendable {
    case safe
    case suspicious
    case unsafe
    case unknown
}

struct LinkCheckReason: Codable, Sendable, Identifiable {
    var id: String { code + (days.map { "-\($0)" } ?? "") }
    let code: String
    let days: Int?
    let message: String?
}

struct LinkCheckRequest: Codable, Sendable {
    let url: String
}

struct LinkCheckResponse: Codable, Sendable {
    let verdict: LinkCheckVerdict
    let reasons: [LinkCheckReason]?
    let source: String?
}

// MARK: - Safari Blocker Models

enum SafariRuleFile: String, CaseIterable, Sendable {
    case ads = "rules_ads.json"
    case trackers = "rules_trackers.json"
    case unsafeRules = "rules_unsafe.json"
    case exceptions = "rules_exceptions.json"

    var maxRuleBudget: Int {
        switch self {
        case .ads: return 50000
        case .trackers: return 50000
        case .unsafeRules: return 45000
        case .exceptions: return 1000
        }
    }
}

enum SafariRulesResult: Sendable {
    case modified(data: Data, etag: String?)
    case notModified
    case notFound
}
