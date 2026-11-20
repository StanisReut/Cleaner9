import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseRemoteConfig)
import FirebaseRemoteConfig
#endif

enum PaywallSource: String, Codable, Sendable {
    case onboarding
    case feature
    case premiumBadge = "premium_badge"
    case settings
}

enum OnboardingVariant: String, Codable, Sendable, CaseIterable {
    case a = "a"
    case b = "b"
    case privacyA = "privacy_a"
    case securityB = "security_b"
}

enum SecurityModule: String, Codable, Sendable, CaseIterable {
    case emailLeakage = "email_leakage"
    case passwordCheck = "password_check"
    case deviceSecurity = "device_security"
}

struct OnboardingPage: Identifiable, Codable, Sendable {
    let id: Int
    let title: String
    let message: String
    let illustration: String
}

struct PaywallPlan: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let detail: String
    let productID: String?
    let badge: String?
}

struct PaywallConfiguration: Codable, Sendable {
    var title: String
    var benefits: [String]
    var plans: [PaywallPlan]
    var termsURL: URL?
    var privacyURL: URL?
    var productLoadTimeout: TimeInterval
}

struct BackendConfiguration: Codable, Sendable {
    var baseURL: URL?
    var emailLeakagePath: String
    var emailLeakageToken: String
    var stripeCheckoutPath: String
    var stripeEntitlementPath: String
    var stripeToken: String
    var supportEmail: String?
    var linkCheckApiURL: URL?
    var safariBlockerRulesURL: URL?
    var webProtectionDoHURL: URL?
    var webProtectionDoHServers: [String]
    var webRiskApiKey: String
}

struct AppConfiguration: Sendable {
    var onboardingVariant: OnboardingVariant
    var onboardingPages: [OnboardingPage]
    var paywallVariant: OnboardingVariant
    var paywall: PaywallConfiguration
    var securityModules: [SecurityModule]
    var latestIOSVersion: String
    var appsFlyerDevKey: String
    var stripeToken: String
    var backend: BackendConfiguration

    static let fallback = AppConfiguration(
        onboardingVariant: .a,
        onboardingPages: [
            OnboardingPage(id: 1, title: "Free up space", message: "Find duplicate photos and large videos. Keep the memories that matter.", illustration: "Photos"),
            OnboardingPage(id: 2, title: "Clear the clutter", message: "Organize duplicate contacts and remove calendar events you don't need.", illustration: "Contacts"),
            OnboardingPage(id: 3, title: "Check your security", message: "Review email breaches, passwords and your device security settings.", illustration: "SecurityCenter")
        ],
        paywallVariant: .a,
        paywall: PaywallConfiguration(
            title: "Make room for more",
            benefits: ["Clean photos & videos", "Organize contacts & calendar", "Access security checks"],
            plans: [
                PaywallPlan(id: "week", title: "Week", detail: "3 days free · $9.99 / week", productID: ProductID.weekly.rawValue, badge: nil),
                PaywallPlan(id: "month", title: "Month", detail: "Billed monthly · $19.99 / month", productID: ProductID.monthly.rawValue, badge: nil),
                PaywallPlan(id: "year", title: "Year", detail: "$49.99 / year", productID: ProductID.yearly.rawValue, badge: "Save 79%")
            ], termsURL: URL(string: "https://dolightdev.org/terms.html"), privacyURL: URL(string: "https://dolightdev.org/privacy.html"), productLoadTimeout: 10
        ),
        securityModules: SecurityModule.allCases,
        latestIOSVersion: "18.0",
        appsFlyerDevKey: "",
        stripeToken: "",
        backend: BackendConfiguration(
            baseURL: URL(string: "https://flint.dolightdev.org"),
            emailLeakagePath: "/v1/email/check",
            emailLeakageToken: "",
            stripeCheckoutPath: "/v1/stripe/checkout",
            stripeEntitlementPath: "/v1/stripe/entitlement",
            stripeToken: "",
            supportEmail: "maxime@locaest.com",
            linkCheckApiURL: URL(string: "https://flint.dolightdev.org"),
            safariBlockerRulesURL: URL(string: "https://flint.dolightdev.org/rules"),
            webProtectionDoHURL: URL(string: "https://flint.dolightdev.org/dns-query"),
            webProtectionDoHServers: ["198.199.69.60"],
            webRiskApiKey: ""
        )
    )
}

@MainActor
final class RemoteConfiguration {
    static let shared = RemoteConfiguration()
    private(set) var value = AppConfiguration.fallback

    func refresh() async {
        var next = AppConfiguration.fallback
#if canImport(FirebaseRemoteConfig)
        if FirebaseApp.app() == nil {
            #if DEBUG
            NSLog("🔥 [RemoteConfig] FirebaseApp was nil, configuring...")
            #endif
            FirebaseApp.configure()
        }
        let remote = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        #if DEBUG
        settings.minimumFetchInterval = 0
        #else
        settings.minimumFetchInterval = 3600
        #endif
        settings.fetchTimeout = 5
        remote.configSettings = settings
        #if DEBUG
        fputs("🔥 [RemoteConfig] starting refresh...\n", stderr)
        fflush(stderr)
        #endif
        do {
            let status = try await remote.fetchAndActivate()
            #if DEBUG
            fputs("🔥 [RemoteConfig] fetch status: \(status.rawValue)\n", stderr)
            fflush(stderr)
            #else
            _ = status
            #endif
        } catch {
            #if DEBUG
            fputs("🔥 [RemoteConfig] fetch error: \(error.localizedDescription)\n", stderr)
            fflush(stderr)
            #endif
        }
        let rawEntryVariant = remote.configValue(forKey: "entry_variant").stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawLegacyOnboarding = remote.configValue(forKey: "onboarding_variant").stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let unifiedVariantRaw = (rawEntryVariant.isEmpty ? rawLegacyOnboarding : rawEntryVariant).lowercased()
        #if DEBUG
        fputs("🔥 [RemoteConfig] fetched entry_variant: '\(rawEntryVariant)' (resolved: '\(unifiedVariantRaw)')\n", stderr)
        fflush(stderr)
        #endif
        let securityModules = remote.configValue(forKey: "security_modules").stringValue
        let backendBaseURL = remote.configValue(forKey: "backend_base_url").stringValue
        let emailLeakagePath = remote.configValue(forKey: "email_leakage_path").stringValue
        let emailLeakageToken = remote.configValue(forKey: "email_leakage_token").stringValue
        let stripeCheckoutPath = remote.configValue(forKey: "stripe_checkout_path").stringValue
        let stripeEntitlementPath = remote.configValue(forKey: "stripe_entitlement_path").stringValue
        let stripeToken = remote.configValue(forKey: "stripe_token").stringValue
        let supportEmail = remote.configValue(forKey: "support_email").stringValue
        let linkCheckApiURL = remote.configValue(forKey: "link_check_api_url").stringValue
        let safariBlockerRulesURL = remote.configValue(forKey: "safari_blocker_rules_url").stringValue
        let webProtectionDoHURL = remote.configValue(forKey: "web_protection_doh_url").stringValue
        let webProtectionDoHServers = remote.configValue(forKey: "web_protection_doh_servers").stringValue
        let webRiskApiKey = remote.configValue(forKey: "web_risk_api_key").stringValue
        let emailCheckApiURL = remote.configValue(forKey: "email_check_api_url").stringValue
        let latestIOSVersion = remote.configValue(forKey: "latest_ios_version").stringValue
        if !latestIOSVersion.isEmpty { next.latestIOSVersion = latestIOSVersion }
        if !securityModules.isEmpty {
            let parsed = securityModules.split(separator: ",").compactMap { SecurityModule(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if !parsed.isEmpty { next.securityModules = parsed }
        }
        next.onboardingVariant = OnboardingVariant(rawValue: unifiedVariantRaw) ?? .a
        // Unified A/B entry_variant controls both Onboarding and Paywall
        next.paywallVariant = next.onboardingVariant == .b ? .b : .a
        next.onboardingPages = next.onboardingPages.enumerated().map { index, page in
            let suffix = index + 1
            let titleKey = "onboarding_\(suffix)_title_\(next.onboardingVariant.rawValue)"
            let messageKey = "onboarding_\(suffix)_message_\(next.onboardingVariant.rawValue)"
            let title = remote.configValue(forKey: titleKey).stringValue
            let message = remote.configValue(forKey: messageKey).stringValue
            let fallback = variantOnboardingPage(index: index, variant: next.onboardingVariant, original: page)
            return OnboardingPage(id: page.id, title: title.isEmpty ? fallback.title : title, message: message.isEmpty ? fallback.message : message, illustration: page.illustration)
        }
        let paywallSuffix = next.paywallVariant.rawValue
        let title = remote.configValue(forKey: "paywall_title_\(paywallSuffix)").stringValue
        let benefits = remote.configValue(forKey: "paywall_benefits_\(paywallSuffix)").stringValue
        let order = remote.configValue(forKey: "paywall_plan_order_\(paywallSuffix)").stringValue
        let weekDetail = remote.configValue(forKey: "paywall_week_detail_\(paywallSuffix)").stringValue
        let monthDetail = remote.configValue(forKey: "paywall_month_detail_\(paywallSuffix)").stringValue
        let yearDetail = remote.configValue(forKey: "paywall_year_detail_\(paywallSuffix)").stringValue
        let weekProductID = remote.configValue(forKey: "paywall_week_product_id").stringValue
        let monthProductID = remote.configValue(forKey: "paywall_month_product_id").stringValue
        let yearProductID = remote.configValue(forKey: "paywall_year_product_id").stringValue
        let fallbackPaywall = variantPaywall(variant: next.paywallVariant, original: next.paywall)
        next.paywall.title = title.isEmpty ? fallbackPaywall.title : title
        next.paywall.benefits = benefits.isEmpty ? fallbackPaywall.benefits : benefits.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let details = ["week": weekDetail.isEmpty ? fallbackPaywall.plans.first(where: { $0.id == "week" })?.detail : weekDetail,
                       "month": monthDetail.isEmpty ? fallbackPaywall.plans.first(where: { $0.id == "month" })?.detail : monthDetail,
                       "year": yearDetail.isEmpty ? fallbackPaywall.plans.first(where: { $0.id == "year" })?.detail : yearDetail]
        let updatedPlans = next.paywall.plans.map { plan in
            let configuredProductID: String? = switch plan.id {
            case "week": weekProductID.isEmpty ? plan.productID : weekProductID
            case "month": monthProductID.isEmpty ? plan.productID : monthProductID
            case "year": yearProductID.isEmpty ? plan.productID : yearProductID
            default: plan.productID
            }
            return PaywallPlan(id: plan.id, title: plan.title, detail: (details[plan.id] ?? nil) ?? plan.detail, productID: configuredProductID, badge: plan.badge)
        }
        if !order.isEmpty {
            let positions = order.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            next.paywall.plans = positions.compactMap { id in updatedPlans.first(where: { $0.id == id }) } + updatedPlans.filter { !positions.contains($0.id) }
        } else {
            next.paywall.plans = variantPaywall(variant: next.paywallVariant, original: PaywallConfiguration(title: next.paywall.title, benefits: next.paywall.benefits, plans: updatedPlans, termsURL: next.paywall.termsURL, privacyURL: next.paywall.privacyURL, productLoadTimeout: next.paywall.productLoadTimeout)).plans
        }
        let terms = remote.configValue(forKey: "paywall_terms_url").stringValue
        let privacy = remote.configValue(forKey: "paywall_privacy_url").stringValue
        if let url = URL(string: terms), !terms.isEmpty { next.paywall.termsURL = url }
        if let url = URL(string: privacy), !privacy.isEmpty { next.paywall.privacyURL = url }
        if let url = URL(string: backendBaseURL), !backendBaseURL.isEmpty { next.backend.baseURL = url }
        if !emailLeakagePath.isEmpty { next.backend.emailLeakagePath = emailLeakagePath }
        if !emailLeakageToken.isEmpty { next.backend.emailLeakageToken = emailLeakageToken }
        if !stripeCheckoutPath.isEmpty { next.backend.stripeCheckoutPath = stripeCheckoutPath }
        if !stripeEntitlementPath.isEmpty { next.backend.stripeEntitlementPath = stripeEntitlementPath }
        if !stripeToken.isEmpty { next.backend.stripeToken = stripeToken; next.stripeToken = stripeToken }
        if !supportEmail.isEmpty { next.backend.supportEmail = supportEmail }
        if let url = URL(string: linkCheckApiURL), !linkCheckApiURL.isEmpty { next.backend.linkCheckApiURL = url }
        if let url = URL(string: safariBlockerRulesURL), !safariBlockerRulesURL.isEmpty { next.backend.safariBlockerRulesURL = url }
        if let url = URL(string: webProtectionDoHURL), !webProtectionDoHURL.isEmpty { next.backend.webProtectionDoHURL = url }
        if !webProtectionDoHServers.isEmpty {
            next.backend.webProtectionDoHServers = webProtectionDoHServers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        next.backend.webRiskApiKey = webRiskApiKey
        if let url = URL(string: emailCheckApiURL), !emailCheckApiURL.isEmpty { next.backend.baseURL = url }
#endif
        value = next
    }

    private func variantOnboardingPage(index: Int, variant: OnboardingVariant, original: OnboardingPage) -> OnboardingPage {
        guard variant == .b else { return original }
        let values = [
            ("More space. More possibilities.", "Find duplicate photos and large videos. Keep what matters and make room for more."),
            ("Less clutter. More clarity.", "Bring contacts and calendar back in order. Review duplicates and events you no longer need."),
            ("Your security. A clearer picture.", "Explore email breach checks, password strength and device settings — all in one place.")
        ]
        let value = values.indices.contains(index) ? values[index] : (original.title, original.message)
        return OnboardingPage(id: original.id, title: value.0, message: value.1, illustration: original.illustration)
    }

    private func variantPaywall(variant: OnboardingVariant, original: PaywallConfiguration) -> PaywallConfiguration {
        guard variant == .b else { return original }
        let plans = original.plans.map { plan in
            switch plan.id {
            case "week": return PaywallPlan(id: plan.id, title: plan.title, detail: "$9.99 / week · 3-day free trial", productID: plan.productID, badge: plan.badge)
            case "month": return PaywallPlan(id: plan.id, title: plan.title, detail: "$19.99 / month · Billed monthly", productID: plan.productID, badge: plan.badge)
            default: return plan
            }
        }
        let ordered = ["week", "year", "month"].compactMap { id in plans.first(where: { $0.id == id }) }
        return PaywallConfiguration(title: "Unlock more with Cleaner Premium", benefits: original.benefits, plans: ordered, termsURL: original.termsURL, privacyURL: original.privacyURL, productLoadTimeout: original.productLoadTimeout)
    }
}
