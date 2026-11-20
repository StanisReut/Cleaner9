import SwiftUI
import StoreKit
import Observation
import MessageUI
import SafariServices

/// Fill with the published product configuration; empty entries never simulate success.
enum ProductConfiguration {
    @MainActor static var subscriptionIDs: [String] {
        let configured = RemoteConfiguration.shared.value.paywall.plans.compactMap(\.productID)
        return configured.isEmpty ? ProductID.allCases.map(\.rawValue) : configured
    }
    @MainActor static var supportEmail: String? { RemoteConfiguration.shared.value.backend.supportEmail }
    @MainActor static var termsURL: URL? { RemoteConfiguration.shared.value.paywall.termsURL }
    @MainActor static var privacyURL: URL? { RemoteConfiguration.shared.value.paywall.privacyURL }
    @MainActor static var appStoreReviewURL: URL? { URL(string: "https://apps.apple.com/app/id6833933137?action=write-review") }
}

enum RestoreResult { case restored, none, failed }

@MainActor @Observable final class PurchaseState {
    static let shared = PurchaseState()
    private var entitled = false
    var active: Bool { entitled || externalEntitlement || Merchant.shared.isPremium }
    var activeProductID: String?
    var expiration: Date?
    var products: [Product] = []
    var busy = false
    var willRenew: Bool?
    private var externalEntitlement = false
    private var updates: Task<Void, Never>?
    private init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await self?.refresh(); await transaction.finish()
                }
            }
        }
    }
    func refresh() async {
        await Merchant.shared.refreshEntitlement()
        var expires: Date?
        var hasEntitled = false
        var productID: String?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  ProductConfiguration.subscriptionIDs.contains(transaction.productID),
                  transaction.revocationDate == nil, !transaction.isUpgraded,
                  transaction.expirationDate.map({ $0 > Date() }) ?? true else { continue }
            hasEntitled = true; productID = transaction.productID
            if let date = transaction.expirationDate, date > (expires ?? .distantPast) { expires = date }
        }
        entitled = hasEntitled; activeProductID = productID; expiration = expires; willRenew = nil
        guard !ProductConfiguration.subscriptionIDs.isEmpty else { return }
        do {
            products = try await Product.products(for: ProductConfiguration.subscriptionIDs)
            for product in products where product.id == activeProductID {
                for status in try await product.subscription?.status ?? [] {
                    if case .verified(let info) = status.renewalInfo { willRenew = info.willAutoRenew }
                }
            }
        } catch { Herald.shared.alert(title: "Subscription unavailable", message: "Check your connection and try again.", primary: HeraldAction(title: "OK", action: {})) }
    }
    func activateExternalEntitlement() { externalEntitlement = true }
    func restore() async -> RestoreResult {
        guard !busy else { return .failed }; busy = true; defer { busy = false }
        do { let restored = try await Merchant.shared.restore(); await refresh(); return restored ? .restored : .none }
        catch { return .failed }
    }
    func purchase(_ product: Product) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        guard let item = ProductID(rawValue: product.id) else { return }
        do { try await Merchant.shared.purchase(item); await refresh() }
        catch MerchantFailure.cancelled { }
        catch MerchantFailure.pending { Herald.shared.alert(title: "Purchase pending", message: "Your purchase is waiting for approval.", primary: HeraldAction(title: "OK", action: {})) }
        catch { Herald.shared.alert(title: "Purchase failed", message: "Something went wrong. Please try again.", primary: HeraldAction(title: "OK", action: {})) }
    }
}

private var settingsFixture: String { FidelityPreview.active ? FidelityPreview.name : "" }

struct PremiumBanner: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    var activeOverride: Bool? = nil
    var expanded = false
    var source: PaywallSource = .premiumBadge
    private var active: Bool { activeOverride ?? PurchaseState.shared.active }
    var body: some View {
        NavigationLink { PaywallScreen(source: source, configuration: RemoteConfiguration.shared.value.paywall, onClose: {}, onPurchased: {}) } label: {
            let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: expanded ? 16 : 8))
            layout {
                Image("Premium").resizable().scaledToFit().frame(width: expanded ? 48 : 40, height: expanded ? 48 : 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(active ? "Premium is active" : "Unlock all features").font(Palette.font(16, .semibold))
                    if expanded { Text("All features unlocked").font(Palette.font(16)) }
                }.foregroundStyle(expanded ? Palette.ink : .white).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                if !active { Text("Upgrade").font(.custom("Poppins-SemiBold", size: 14)).foregroundStyle(Palette.ink).padding(.horizontal, 12).padding(.vertical, 8).background(.white, in: Capsule()) }
                if active && !expanded { Image(systemName: "checkmark.circle.fill").font(.system(size: 32)).foregroundStyle(Color(hex: 0x1CB450)).background(.white, in: Circle()).frame(width: 40, height: 40) }
            }.padding(.horizontal, 16).padding(.vertical, expanded ? 16 : 6)
                .background(LinearGradient(stops: expanded ? [.init(color: Color(hex: 0xEAF0F8), location: 0), .init(color: Palette.blue, location: 1)] : [.init(color: Color(hex: 0xFE8301), location: 0.5776), .init(color: Color(hex: 0xFFB700), location: 1)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(InteractiveCardButtonStyle()).compositingGroup().shadow(color: Color(hex: 0x356CB6).opacity(0.12), radius: 8, y: 8)
    }
}
private enum RestoreOutcome { case restored, none, failed }
struct SettingsScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.requestReview) private var requestReview
    @AppStorage("rate_us_prompt_count") private var ratePromptCount = 0
    @State private var restoreOutcome: RestoreOutcome?
    @State private var mailComposer = false
    @State private var safariURL: URL?
    @State private var legalDocument: LegalDocument?
    @State private var unlockTaps = 0
    private var purchases: PurchaseState { .shared }
    private var active: Bool { FidelityPreview.active ? settingsFixture.contains("active") || settingsFixture.contains("Active") || settingsFixture.contains("restored") : purchases.active }
    private var busy: Bool { purchases.busy || settingsFixture.contains("checking") }
    var body: some View {
        PageShell(title: "Settings") {
            PremiumBanner(activeOverride: active, expanded: settingsFixture.contains("restored") || restoreOutcome == .restored, source: .settings)
            VStack(spacing: 8) {
                NavigationLink { SubscriptionScreen() } label: { SettingsRow(title: "Manage subscription", symbol: "creditcard") }
                    .buttonStyle(InteractiveCardButtonStyle())
                Button(action: restore) { SettingsRow(title: busy ? "Restoring purchases…" : "Restore Purchases", symbol: "arrow.clockwise", loading: busy) }.disabled(busy).buttonStyle(InteractiveCardButtonStyle())
            }
            VStack(spacing: 8) {
                Button { rateUs() } label: { SettingsRow(title: "Rate us", symbol: "star") }
                    .buttonStyle(InteractiveCardButtonStyle())
                Button {
                    guard let email = ProductConfiguration.supportEmail else { Herald.shared.alert(title: "Contact unavailable", message: "Support contact is not available yet.", primary: HeraldAction(title: "OK", action: {})); return }
                    if MFMailComposeViewController.canSendMail() { mailComposer = true }
                    else if let url = URL(string: "mailto:\(email)") { UIApplication.shared.open(url) }
                    else { Herald.shared.alert(title: "Contact unavailable", message: "Support contact is not available yet.", primary: HeraldAction(title: "OK", action: {})) }
                } label: { SettingsRow(title: "Contact us", symbol: "envelope") }
                    .buttonStyle(InteractiveCardButtonStyle())
            }
            VStack(spacing: 8) {
                Button { openDocument(.terms, url: ProductConfiguration.termsURL) } label: { SettingsRow(title: "Terms of Use", symbol: "doc.text") }
                    .buttonStyle(InteractiveCardButtonStyle())
                Button { openDocument(.privacy, url: ProductConfiguration.privacyURL) } label: { SettingsRow(title: "Privacy Policy", symbol: "hand.raised") }
                    .buttonStyle(InteractiveCardButtonStyle())
                Button { showManageConsentAlert() } label: { SettingsRow(title: "Manage Consent", symbol: "shield.lefthalf.filled") }
                    .buttonStyle(InteractiveCardButtonStyle())
            }
            #if DEBUG
            VStack(spacing: 8) {
                Button {
                    UserDefaults.standard.set(false, forKey: "onboarding.completed")
                    Tactile.success()
                    Herald.shared.alert(
                        title: "Onboarding Reset",
                        message: "Onboarding state reset. Close and reopen the app to see the current Remote Config onboarding.",
                        primary: HeraldAction(title: "OK", action: {})
                    )
                } label: { SettingsRow(title: "Reset Onboarding (A/B Test)", symbol: "arrow.counterclockwise") }

                Button {
                    Task {
                        Veil.shared.show()
                        let res = try? await TestDataSeeder.shared.seedAll()
                        Veil.shared.hide()
                        Tactile.success()
                        Herald.shared.alert(
                            title: "Test Data Seeded",
                            message: "Created \(res?.contactsCreated ?? 0) contacts and \(res?.eventsCreated ?? 0) calendar events.",
                            primary: HeraldAction(title: "OK", action: {})
                        )
                    }
                } label: { SettingsRow(title: "Generate Test Contacts & Calendar", symbol: "plus.circle") }
            }
            #endif
        }.buttonStyle(.plain).task {
            Telemetry.shared.track(.settingsOpened, parameters: ["subscription_status": active ? "active" : "none"])
            if !FidelityPreview.active { await purchases.refresh() }
        }
            .safeAreaInset(edge: .bottom) { Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")").font(Palette.font(16)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 12).background(Palette.bg).onTapGesture {
                unlockTaps += 1
                #if DEBUG
                print("💳 [Billing] test purchase toggle: tap \(unlockTaps)/3")
                #endif
                if unlockTaps >= 3 {
                    Merchant.shared.registerSecretUnlockTap()
                    unlockTaps = 0
                    Tactile.tap()
                    Task { await purchases.refresh() }
                }
            } }
            .overlay {
                if let restoreOutcome {
                    switch restoreOutcome {
                    case .restored: NoticeView(title: "Purchases restored", message: "Your Premium features are available.", asset: "Premium", onPrimary: { self.restoreOutcome = nil })
                    case .none: NoticeView(title: "No purchases found", message: "No active subscription was found for this Apple Account.", asset: "Premium", onPrimary: { self.restoreOutcome = nil })
                    case .failed: NoticeView(title: "Couldn’t restore purchases", message: "Check your connection and try again.", asset: "Premium", primaryTitle: "Try again", secondaryTitle: "Back to Settings", onPrimary: { self.restoreOutcome = nil; restore() }, onSecondary: { self.restoreOutcome = nil })
                    }
                }
            }
            .sheet(isPresented: $mailComposer) { MailView(recipient: ProductConfiguration.supportEmail ?? "") }
            .sheet(isPresented: Binding(get: { safariURL != nil }, set: { if !$0 { safariURL = nil } })) {
                if let safariURL { SafariView(url: safariURL) }
            }
            .sheet(item: $legalDocument) { doc in LegalDocumentSheet(document: doc) }
            .onAppear {
                guard FidelityPreview.active else { return }
                if settingsFixture.hasSuffix("/ restored") { restoreOutcome = .restored }
                if settingsFixture.hasSuffix("/ none") { restoreOutcome = RestoreOutcome.none }
                if settingsFixture.hasSuffix("/ error") { restoreOutcome = .failed }
            }
    }
    private func showManageConsentAlert() {
        Herald.shared.alert(
            title: "Manage Consent",
            message: "We will share your purchase details with Apple to process the refund. You can opt out or withdraw consent at any time in the settings.",
            primary: HeraldAction(title: "Allow", action: {
                Telemetry.shared.setRefundConsent(true)
            }),
            secondary: HeraldAction(title: "Don't Allow", action: {
                Telemetry.shared.setRefundConsent(false)
            })
        )
    }

    private func restore() {
        Telemetry.shared.track(.restoreTapped, parameters: ["source": "settings"])
        Veil.shared.show()
        Task {
            defer { Veil.shared.hide() }
            switch await purchases.restore() {
            case .restored:
                Telemetry.shared.track(.restoreCompleted, parameters: ["source": "settings", "result": "restored"])
                restoreOutcome = .restored
            case .none:
                Telemetry.shared.track(.restoreCompleted, parameters: ["source": "settings", "result": "not_found"])
                restoreOutcome = RestoreOutcome.none
            case .failed:
                Telemetry.shared.track(.restoreCompleted, parameters: ["source": "settings", "result": "failed"])
                restoreOutcome = .failed
            }
        }
    }
    private func rateUs() {
        if ratePromptCount < 3 {
            ratePromptCount += 1
            requestReview()
        } else if let url = ProductConfiguration.appStoreReviewURL {
            UIApplication.shared.open(url)
        } else {
            requestReview()
        }
    }
    private func openDocument(_ document: LegalDocument, url: URL?) {
        Telemetry.shared.track(.legalLinkOpened, parameters: ["link": document.rawValue, "source": "settings"])
        if let url { safariURL = url } else { legalDocument = document }
    }
}

private struct MailView: UIViewControllerRepresentable {
    let recipient: String
    func makeUIViewController(context: Context) -> MFMailComposeViewController { let vc = MFMailComposeViewController(); vc.setToRecipients([recipient]); vc.setSubject("Cleaner support"); vc.mailComposeDelegate = context.coordinator; return vc }
    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate { func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) { controller.dismiss(animated: true) } }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
private struct SettingsRow: View {
    let title: String
    let symbol: String
    var loading = false
    var body: some View {
        HStack(spacing: 8) {
            Image(["creditcard": "SettingsManage", "arrow.clockwise": "SettingsRestore", "star": "SettingsRate", "envelope": "SettingsContact", "doc.text": "SettingsTerms", "hand.raised": "SettingsPrivacy"][symbol] ?? "SettingsManage").resizable().scaledToFit().frame(width: 24, height: 24).frame(width: 40, height: 40).background(Palette.track, in: RoundedRectangle(cornerRadius: 16))
            Text(title).font(Palette.font(16, .semibold)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            if loading { LoadingRing() } else { Disclosure() }
        }.padding(.horizontal, 16).padding(.vertical, 12).background(.white, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(Palette.ink)
    }
}
struct SubscriptionScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var purchases: PurchaseState { .shared }
    @State private var manage = false
    @State private var safariURL: URL?
    @State private var legalDocument: LegalDocument?
    private var fixture: Bool { FidelityPreview.active && settingsFixture.contains("My subscription") }
    private var active: Bool { fixture ? !settingsFixture.contains("No subscription") : purchases.active }
    private var renewalOff: Bool { fixture ? settingsFixture.contains("Renewal off") : purchases.willRenew == false }
    private var product: Product? { purchases.products.first { $0.id == purchases.activeProductID } }
    private var longDate: String { fixture ? "November 13, 2026" : purchases.expiration?.formatted(date: .long, time: .omitted) ?? "the end of your current period" }
    private var date: String { fixture ? "Nov 13, 2026" : purchases.expiration?.formatted(date: .abbreviated, time: .omitted) ?? "Unavailable" }
    private var period: String {
        if fixture { return "Weekly" }
        guard let value = product?.subscription?.subscriptionPeriod else { return "Subscription" }
        switch value.unit { case .day: return "Every \(value.value) day(s)"; case .week: return "Every \(value.value) week(s)"; case .month: return "Every \(value.value) month(s)"; case .year: return "Every \(value.value) year(s)"; @unknown default: return "Subscription" }
    }
    private var plan: String { fixture ? "Week · $9.99 / week" : product.map { "\($0.displayName) · \($0.displayPrice)" } ?? "Premium subscription" }
    var body: some View {
      GeometryReader { geometry in
        PageShell(title: "My subscription", trailingPadding: 23, headerSpacing: 2) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) { Image("Premium").resizable().scaledToFit().frame(width: 40, height: 40); Text("Cleaner Premium").font(Palette.font(24, .semibold)) }
                    Text(active ? plan : "No active subscription").font(Palette.font(16, .semibold))
                    HStack(spacing: 0) {
                        if active { Text("●").font(Palette.font(16, .medium)).foregroundStyle(Color(hex: 0x21C75A)) }
                        Text(active ? (renewalOff ? "  Auto-renewal off" : "  Active") : "Available with a subscription").font(Palette.font(16, active ? .medium : .regular))
                    }.frame(minHeight: 24)
                }.padding(16).frame(maxWidth: .infinity, minHeight: 144, alignment: .leading).foregroundStyle(.white).background(LinearGradient(colors: [Color(hex: 0xFE8301), Color(hex: 0xFFB700)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
                if active {
                    VStack(spacing: 8) { detail("Plan", period); detail(renewalOff ? "Access until" : purchases.willRenew == true || fixture ? "Renews on" : "Current period ends", date) }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 24))
                    Text(paragraph(renewalOff ? "You won’t be charged again.\nPremium stays available until\n\(longDate)." : purchases.willRenew == true || fixture ? "Your plan renews automatically.\nYou can change your plan or cancel\nrenewal without leaving Cleaner." : "Manage your subscription with Apple to review renewal details.")).cleanerBodyLineHeight().foregroundStyle(Color(hex: 0x526580)).frame(minHeight: max(72, min(136, geometry.size.height - 604)), alignment: .topLeading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nothing to cancel").font(Palette.font(24, .semibold))
                        Text(paragraph("There is no active subscription\nfor this Apple Account. Restore\npurchases if you subscribed before.")).cleanerBodyLineHeight().foregroundStyle(Color(hex: 0x526580))
                    }.padding(16).frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading).background(.white, in: RoundedRectangle(cornerRadius: 24))
                    Text(paragraph("Check your purchases or restore\nan existing subscription using\nyour Apple Account.")).cleanerBodyLineHeight().foregroundStyle(Color(hex: 0x526580)).frame(minHeight: 72, alignment: .topLeading)
                }
                subscriptionButton(active ? "Manage plan" : "Manage purchases", primary: true) { manage = true }
                subscriptionButton(active ? (renewalOff ? "Back to Settings" : "Cancel subscription") : "Restore Purchases", destructive: active && !renewalOff) {
                    if active { if renewalOff { dismiss() } else { manage = true } }
                    else { Task { await purchases.restore() } }
                }
                Text(active ? (renewalOff ? "You can turn renewal back on at any time." : "Apple will ask you to confirm.") : "Purchases are linked to your Apple Account.").foregroundStyle(Color(hex: 0x526580)).frame(minHeight: 48, alignment: .topLeading)
                if !active {
                    ForEach(purchases.products) { product in PrimaryButton(title: "\(product.displayName) · \(product.displayPrice)", disabled: purchases.busy) { Task { await purchases.purchase(product) } } }
                }
                HStack(spacing: 24) {
                    Button("Terms of Use") { openDocument(.terms, url: ProductConfiguration.termsURL) }
                    Button("Privacy Policy") { openDocument(.privacy, url: ProductConfiguration.privacyURL) }
                }
                .font(Palette.font(13))
                .foregroundStyle(Color(hex: 0x526580))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.manageSubscriptionsSheet(isPresented: $manage).task { if !fixture { await purchases.refresh() } }
            .onChange(of: manage) { _, shown in if !shown && !fixture { Task { await purchases.refresh() } } }
            .sheet(isPresented: Binding(get: { safariURL != nil }, set: { if !$0 { safariURL = nil } })) {
                if let safariURL { SafariView(url: safariURL) }
            }
            .sheet(item: $legalDocument) { doc in LegalDocumentSheet(document: doc) }
      }
    }
    private func openDocument(_ document: LegalDocument, url: URL?) {
        Telemetry.shared.track(.legalLinkOpened, parameters: ["link": document.rawValue, "source": "subscription"])
        if let url { safariURL = url } else { legalDocument = document }
    }
    private func paragraph(_ text: String) -> String { dynamicType.isAccessibilitySize ? text.replacingOccurrences(of: "\n", with: " ") : text }
    private func detail(_ key: String, _ value: String) -> some View { HStack { Text(key).foregroundStyle(Color(hex: 0x526580)); Spacer(); Text(value).font(Palette.font(16, .semibold)) }.frame(minHeight: 40) }
    private func subscriptionButton(_ title: String, primary: Bool = false, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(Palette.font(16, .semibold)).frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(primary ? .white : destructive ? Color(hex: 0xB53B3B) : Palette.blue).background(primary ? Palette.blue : .white, in: RoundedRectangle(cornerRadius: 16)) }.disabled(purchases.busy)
    }
}
