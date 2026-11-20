import AppTrackingTransparency
import AppsFlyerLib
import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import Foundation
import StoreKit
import UIKit

enum AnalyticsProvider: String, CaseIterable {
    case appsFlyer, firebase, userAcquisition
}

enum AnalyticsConfig {
    static let enabledProviders: Set<AnalyticsProvider> = []
    static let appsFlyerDevKey = "rSZWNFMUiEKq7NT64sWuRj"
    static let appleAppID = "6833933137"
    static let appStoreSharedSecret = "68421f4fe8de49c3816939a9066cf0c2"
    static let userAcquisitionAPIKey = "IH8u_wu5V9VB23KTovgv"
    static let userAcquisitionServerURL = "dash.qethar.com"
    static let googleServiceInfoName = "GoogleService-Info"
    static var activeProviders: Set<AnalyticsProvider> { enabledProviders.isEmpty ? Set(AnalyticsProvider.allCases) : enabledProviders }
}

enum AnalyticsEvent: String {
    case featureTutorialShown = "feature_tutorial_shown"
    case featureTutorialPassed = "feature_tutorial_passed"
    case selectionAllToggled = "selection_all_toggled"
    case sortChanged = "sort_changed"
    case deleteTapped = "delete_tapped"
    case deleteCancelled = "delete_cancelled"
    case contentDeleted = "content_deleted"
    case permissionCTATapped = "permission_cta_tapped"
    case restoreTapped = "restore_tapped"
    case restoreCompleted = "restore_completed"
    case legalLinkOpened = "legal_link_opened"
    case launchFirstTime = "launch_first_time"
    case sessionStart = "session_start"
    case splashShown = "splash_shown"
    case remoteConfigLoaded = "remote_config_loaded"
    case remoteConfigTimeout = "remote_config_timeout"
    case attShown = "att_shown"
    case attAnswered = "att_answered"
    case afConversionSuccess = "af_conversion_success"
    case afConversionFail = "af_conversion_fail"
    case onboardingStart = "onboarding_start"
    case onboardingScreenShown = "onboarding_screen_shown"
    case onboardingPassed = "onboarding_passed"
    case mediaPermissionShown = "media_permission_shown"
    case mediaPermissionAnswered = "media_permission_answered"
    case paywallShown = "paywall_shown"
    case paywallPlanSelected = "paywall_plan_selected"
    case paywallCheckoutInitiated = "paywall_checkout_initiated"
    case paywallCheckoutCancelled = "paywall_checkout_cancelled"
    case paywallCheckoutFailed = "paywall_checkout_failed"
    case paywallClosed = "paywall_closed"
    case trialStarted = "trial_started"
    case subscriptionStarted = "subscription_started"
    case mainShown = "main_shown"
    case ratePromptRequested = "rate_prompt_requested"
    case premiumBadgeTapped = "premium_badge_tapped"
    case settingsOpened = "settings_opened"
    case freeUpSpaceStarted = "free_up_space_started"
    case smartScanStarted = "smart_scan_started"
    case smartScanCompleted = "smart_scan_completed"
    case smartScanStopped = "smart_scan_stopped"
    case smartScanResultsShown = "smart_scan_results_shown"
    case smartScanCategoryOpened = "smart_scan_category_opened"
    case smartScanCleanupTapped = "smart_scan_cleanup_tapped"
    case manualPhotoOpened = "manual_photo_opened"
    case photoCategoryOpened = "photo_category_opened"
    case photoSwipeOpened = "photo_swipe_opened"
    case photoSwipeSessionEnded = "photo_swipe_session_ended"
    case photoSwipeCompleted = "photo_swipe_completed"
    case photoTrashOpened = "photo_trash_opened"
    case manualVideoOpened = "manual_video_opened"
    case videoCategoryOpened = "video_category_opened"
    case videoPreviewOpened = "video_preview_opened"
    case manualContactOpened = "manual_contact_opened"
    case contactsPermissionShown = "contacts_permission_shown"
    case contactsPermissionAnswered = "contacts_permission_answered"
    case contactsSectionOpened = "contacts_section_opened"
    case contactsMergePreview = "contacts_merge_preview"
    case contactsMerged = "contacts_merged"
    case contactsBackupCreated = "contacts_backup_created"
    case contactsBackupDeleted = "contacts_backup_deleted"
    case contactsRestoreStarted = "contacts_restore_started"
    case contactsRestoreCompleted = "contacts_restore_completed"
    case manualCalendarOpened = "manual_calendar_opened"
    case calendarPermissionShown = "calendar_permission_shown"
    case calendarPermissionAnswered = "calendar_permission_answered"
    case calendarTabSwitched = "calendar_tab_switched"
    case backgroundRemoverOpened = "background_remover_opened"
    case backgroundPhotoSelected = "bg_photo_selected"
    case backgroundPickerCancelled = "bg_picker_cancelled"
    case backgroundRemoved = "bg_removed"
    case backgroundRemoveFailed = "bg_remove_failed"
    case backgroundSelected = "bg_background_selected"
    case backgroundImageSaved = "bg_image_saved"
    case backgroundImageSaveFailed = "bg_image_save_failed"
    case backgroundImageShared = "bg_image_shared"
    case securityCenterOpened = "security_center_opened"
    case securityModuleOpened = "security_module_opened"
    case emailCheckCompleted = "email_check_completed"
    case passwordCheckCompleted = "password_check_completed"
    case deviceGuideOpened = "device_guide_opened"
    case deviceReviewCompleted = "device_review_completed"
    case settingsItemTapped = "settings_item_tapped"
    case subscriptionScreenShown = "subscription_screen_shown"
    case subscriptionStatusLoadFailed = "subscription_status_load_failed"
    case subscriptionManageTapped = "subscription_manage_tapped"
    case subscriptionManageClosed = "subscription_manage_closed"
    case subscriptionManageFailed = "subscription_manage_failed"
    case trialConverted = "trial_converted"
    case subscriptionRenewed = "subscription_renewed"
    case trialRenewalCancelled = "trial_renewal_cancelled"
    case subscriptionCanceled = "subscription_canceled"
    case subscriptionRenewalEnabled = "subscription_renewal_enabled"
    case subscriptionPlanChanged = "subscription_plan_changed"
    case subscriptionExpired = "subscription_expired"
    case subscriptionBillingIssue = "subscription_billing_issue"
    case subscriptionRefunded = "subscription_refunded"
}

enum AnalyticsUserProperty: String {
    case subscriptionStatus = "subscription_status"
    case autoRenew = "auto_renew"
    case onboardingVersion = "onboarding_version"
    case paywallVersion = "paywall_version"
    case attStatus = "att_status"
    case appsFlyerID = "appsflyer_id"
    case mediaPermission = "media_permission"
    case contactsPermission = "contacts_permission"
    case calendarPermission = "calendar_permission"
    case photoAddPermission = "photo_add_permission"
    case photoDuplicatesRemoved = "photo_duplicates_removed"
    case videoDuplicatesRemoved = "video_duplicates_removed"
    case contactDupesRemoved = "contact_dupes_removed"
}

protocol AnalyticsSink: AnyObject {
    func start()
    func track(_ name: String, parameters: [String: String])
    func logPurchase(id: String, price: Decimal, currency: String, name: String)
}

private func filled(_ value: String, placeholder: String) -> Bool {
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value != placeholder
}

final class AppsFlyerAnalyticsSink: NSObject, AnalyticsSink, AppsFlyerLibDelegate {
    private(set) var isStarted = false
    var onConversionData: (([String: String]) -> Void)?
    var onConversionStatus: ((Bool, [String: String]) -> Void)?
    func start() {
        guard filled(AnalyticsConfig.appsFlyerDevKey, placeholder: "APPSFLYER_DEV_KEY") else { warn("AppsFlyer skipped — dev key missing"); return }
        AppsFlyerLib.shared().initialize(devKey: AnalyticsConfig.appsFlyerDevKey, appId: AnalyticsConfig.appleAppID)
        AppsFlyerLib.shared().delegate = self
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
        isStarted = true
        AppsFlyerLib.shared().registerSessionReadyListener {
            AppsFlyerLib.shared().start()
        }
    }
    func track(_ name: String, parameters: [String: String]) {
        guard isStarted else { return }
        AppsFlyerLib.shared().logEvent(name, withValues: parameters)
    }
    func logPurchase(id: String, price: Decimal, currency: String, name: String) {
        guard isStarted else { return }
        AppsFlyerLib.shared().logEvent(AFEventPurchase, withValues: ["eventValue": ""])
        AppsFlyerLib.shared().logEvent(id, withValues: ["price": price, "currency": currency])
    }
    func registerUninstall(deviceToken: Data) {
        guard isStarted else { return }
        AppsFlyerLib.shared().registerUninstall(deviceToken)
    }
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        let stringified = conversionInfo.reduce(into: [String: String]()) { result, pair in result[String(describing: pair.key)] = String(describing: pair.value) }
        onConversionData?(stringified)
        onConversionStatus?(true, stringified)
    }
    func onConversionDataFail(_ error: Error) {
        onConversionStatus?(false, ["error": error.localizedDescription])
    }
    func onAppOpenAttribution(_ attributionData: [AnyHashable: Any]) {}
    func onAppOpenAttributionFailure(_ error: Error) {}
}

final class FirebaseAnalyticsSink: AnalyticsSink {
    private var started = false
    private var collectionEnabled = false
    private var pending: [(String, [String: String])] = []
    func start() {
        guard Bundle.main.path(forResource: AnalyticsConfig.googleServiceInfoName, ofType: "plist") != nil else { warn("Firebase skipped — GoogleService-Info.plist missing"); return }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        started = true
    }
    func enableCollection() {
        guard started else { return }
        Analytics.setAnalyticsCollectionEnabled(true); collectionEnabled = true
        pending.forEach { Analytics.logEvent($0.0, parameters: $0.1) }; pending.removeAll()
    }
    func track(_ name: String, parameters: [String: String]) {
        guard collectionEnabled else { if pending.count < 20 { pending.append((name, parameters)) }; return }
        Analytics.logEvent(name, parameters: parameters)
    }
    func setUserProperty(_ value: String?, forName name: String) {
        guard started else { return }
        Analytics.setUserProperty(value, forName: name)
    }
    func logPurchase(id: String, price: Decimal, currency: String, name: String) { track(name, parameters: ["price": NSDecimalNumber(decimal: price).stringValue, "currency": currency]) }
}

@MainActor
final class Telemetry {
    static let shared = Telemetry()
    private let appsFlyer: AppsFlyerAnalyticsSink?
    private let firebase: FirebaseAnalyticsSink?
    private let userAcquisition: UserAcquisitionProviding?
    private var started = false

    private init() {
        let providers = AnalyticsConfig.activeProviders
        appsFlyer = providers.contains(.appsFlyer) ? AppsFlyerAnalyticsSink() : nil
        firebase = providers.contains(.firebase) ? FirebaseAnalyticsSink() : nil
        userAcquisition = providers.contains(.userAcquisition) ? UserAcquisitionAdapter() : nil
        appsFlyer?.onConversionData = { [weak self] values in
            self?.userAcquisition?.setAttribution(values)
        }
        appsFlyer?.onConversionStatus = { [weak self] success, payload in
            Task { @MainActor [weak self] in
                self?.track(success ? .afConversionSuccess : .afConversionFail, parameters: payload)
            }
        }
    }
    func start(launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) {
        guard !started else { return }; started = true
        appsFlyer?.start(); firebase?.start(); userAcquisition?.start()
        if appsFlyer?.isStarted == true {
            UserAcquisition.shared.conversionInfo.appsFlyerId = AppsFlyerLib.shared().getAppsFlyerUID()
        }
        debug("started providers: \(AnalyticsConfig.activeProviders.map(\.rawValue).sorted().joined(separator: ", "))")
        track(.sessionStart)
        if !UserDefaults.standard.bool(forKey: "telemetry.first_launch_recorded") {
            UserDefaults.standard.set(true, forKey: "telemetry.first_launch_recorded")
            track(.launchFirstTime)
        }
    }
    func requestATTAndEnableCollection() async {
        track(.attShown)
        let status = await Tracking.request()
        let value: String
        switch status {
        case .authorized: value = "authorized"
        case .restricted: value = "restricted"
        case .denied: value = "denied"
        case .notDetermined: value = "not_determined"
        @unknown default: value = "unknown"
        }
        track(.attAnswered, parameters: ["status": value])
        setUserProperty(value, .attStatus)
        firebase?.enableCollection()
    }
    func registerUninstallToken(_ deviceToken: Data) {
        appsFlyer?.registerUninstall(deviceToken: deviceToken)
        debug("registered device token for uninstall tracking (\(deviceToken.count) bytes)")
    }
    func setRefundConsent(_ consented: Bool) {
        userAcquisition?.refund(consented: consented)
        UserDefaults.standard.set(consented, forKey: "user_acquisition.refund_consented")
        UserDefaults.standard.set(true, forKey: "user_acquisition.refund_consent_prompted")
        debug("refund consent updated: consented=\(consented)")
    }
    func track(_ event: AnalyticsEvent, parameters: [String: String] = [:]) {
        track(name: event.rawValue, parameters: parameters)
    }
    func track(name: String, parameters: [String: String] = [:]) {
        appsFlyer?.track(name, parameters: parameters); firebase?.track(name, parameters: parameters)
        debug("event: \(name) \(parameters)")
    }
    func setUserProperty(_ value: String?, forName name: String) {
        firebase?.setUserProperty(value, forName: name)
        debug("user property: \(name)=\(value ?? "nil")")
    }
    func setUserProperty(_ value: String?, _ property: AnalyticsUserProperty) {
        setUserProperty(value, forName: property.rawValue)
    }
    func logPurchase(_ product: Product, name: AnalyticsEvent = .subscriptionStarted) {
        let price = product.price; let currency = product.priceFormatStyle.currencyCode
        appsFlyer?.logPurchase(id: product.id, price: price, currency: currency, name: name.rawValue); firebase?.logPurchase(id: product.id, price: price, currency: currency, name: name.rawValue)
        userAcquisition?.logPurchase(productID: product.id, price: price, currency: currency)
        UserAcquisition.shared.logPurchase(of: product)
        debug("purchase: \(name.rawValue) — \(product.id) \(price) \(currency)")
    }
    private func debug(_ message: String) {
        #if DEBUG
        print("📊 [Telemetry] \(message)")
        #endif
    }
}

private func warn(_ message: String) {
    #if DEBUG
    print("⚠️ [Telemetry] \(message)")
    #endif
}
