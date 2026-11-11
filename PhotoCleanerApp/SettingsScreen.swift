import SwiftUI
import StoreKit
import Observation

/// Fill with the published product configuration; empty entries never simulate success.
enum ProductConfiguration {
    static let subscriptionIDs: [String] = []
    static let supportEmail: String? = nil
    static let termsURL: URL? = nil
    static let privacyURL: URL? = nil
}

@MainActor @Observable final class PurchaseState {
    static let shared = PurchaseState()
    var active = false
    var activeProductID: String?
    var expiration: Date?
    var products: [Product] = []
    var busy = false
    var message: String?
    var willRenew: Bool?
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
        var expires: Date?
        var entitled = false
        var productID: String?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  ProductConfiguration.subscriptionIDs.contains(transaction.productID),
                  transaction.revocationDate == nil, !transaction.isUpgraded,
                  transaction.expirationDate.map({ $0 > Date() }) ?? true else { continue }
            entitled = true; productID = transaction.productID
            if let date = transaction.expirationDate, date > (expires ?? .distantPast) { expires = date }
        }
        active = entitled; activeProductID = productID; expiration = expires; willRenew = nil
        guard !ProductConfiguration.subscriptionIDs.isEmpty else { return }
        do {
            products = try await Product.products(for: ProductConfiguration.subscriptionIDs)
            for product in products where product.id == activeProductID {
                for status in try await product.subscription?.status ?? [] {
                    if case .verified(let info) = status.renewalInfo { willRenew = info.willAutoRenew }
                }
            }
        } catch { message = error.localizedDescription }
    }
    func restore() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        guard !ProductConfiguration.subscriptionIDs.isEmpty else { message = "Purchases are not available yet."; return }
        do { try await AppStore.sync(); await refresh(); message = active ? "Premium restored." : "No active subscription was found." }
        catch { message = "Unable to restore purchases. \(error.localizedDescription)" }
    }
    func purchase(_ product: Product) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else { message = "Purchase could not be verified."; return }
                await refresh(); await transaction.finish()
            case .pending: message = "Your purchase is pending approval."
            case .userCancelled: break
            @unknown default: message = "Purchase status is unavailable."
            }
        } catch { message = error.localizedDescription }
    }
}

private var settingsFixture: String { FidelityPreview.active ? FidelityPreview.name : "" }

struct PremiumBanner: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    var activeOverride: Bool? = nil
    var expanded = false
    private var active: Bool { activeOverride ?? PurchaseState.shared.active }
    var body: some View {
        NavigationLink { SubscriptionScreen() } label: {
            let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: expanded ? 16 : 8))
            layout {
                Image("Premium").resizable().scaledToFit().frame(width: expanded ? 48 : 40, height: expanded ? 48 : 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(active ? "Premium is active" : "Unlock all features").font(CleanerStyle.font(16, .semibold))
                    if expanded { Text("All features unlocked").font(CleanerStyle.font(16)) }
                }.foregroundStyle(expanded ? CleanerStyle.ink : .white).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                if !active { Text("Upgrade").font(.custom("Poppins-SemiBold", size: 14)).foregroundStyle(CleanerStyle.ink).padding(.horizontal, 12).padding(.vertical, 8).background(.white, in: Capsule()) }
                if active && !expanded { Image(systemName: "checkmark.circle.fill").font(.system(size: 32)).foregroundStyle(Color(hex: 0x1CB450)).background(.white, in: Circle()).frame(width: 40, height: 40) }
            }.padding(.horizontal, 16).padding(.vertical, expanded ? 16 : 6)
                .background(LinearGradient(stops: expanded ? [.init(color: Color(hex: 0xEAF0F8), location: 0), .init(color: CleanerStyle.blue, location: 1)] : [.init(color: Color(hex: 0xFE8301), location: 0.5776), .init(color: Color(hex: 0xFFB700), location: 1)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
}
private enum RestoreOutcome { case restored, none, failed }
struct SettingsScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.requestReview) private var requestReview
    @State private var message: String?
    @State private var restoreOutcome: RestoreOutcome?
    private var purchases: PurchaseState { .shared }
    private var active: Bool { FidelityPreview.active ? settingsFixture.contains("active") || settingsFixture.contains("Active") || settingsFixture.contains("restored") : purchases.active }
    private var busy: Bool { purchases.busy || settingsFixture.contains("checking") }
    var body: some View {
        CleanerPage(title: "Settings") {
            PremiumBanner(activeOverride: active, expanded: settingsFixture.contains("restored") || restoreOutcome == .restored)
            VStack(spacing: 8) {
                NavigationLink { SubscriptionScreen() } label: { SettingsRow(title: "Manage subscription", symbol: "creditcard") }
                Button(action: restore) { SettingsRow(title: busy ? "Restoring purchases…" : "Restore Purchases", symbol: "arrow.clockwise", loading: busy) }.disabled(busy).buttonStyle(CleanerButtonStyle())
            }
            VStack(spacing: 8) {
                Button { requestReview() } label: { SettingsRow(title: "Rate us", symbol: "star") }
                Button {
                    guard let email = ProductConfiguration.supportEmail, let url = URL(string: "mailto:\(email)"), UIApplication.shared.canOpenURL(url) else { message = "Support contact is not available yet."; return }
                    UIApplication.shared.open(url)
                } label: { SettingsRow(title: "Contact us", symbol: "envelope") }
            }
            VStack(spacing: 8) {
                Button { openDocument(ProductConfiguration.termsURL) } label: { SettingsRow(title: "Terms of Use", symbol: "doc.text") }
                Button { openDocument(ProductConfiguration.privacyURL) } label: { SettingsRow(title: "Privacy Policy", symbol: "hand.raised") }
            }
        }.buttonStyle(.plain).task { if !FidelityPreview.active { await purchases.refresh() } }
            .safeAreaInset(edge: .bottom) { Text("Version \(FidelityPreview.active ? "1.0.0" : Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")").font(CleanerStyle.font(16)).foregroundStyle(CleanerStyle.secondary).frame(maxWidth: .infinity, alignment: .center).padding(16).background(dynamicType.isAccessibilitySize ? CleanerStyle.bg : .clear) }
            .overlay {
                if let restoreOutcome {
                    switch restoreOutcome {
                    case .restored: CleanerModal(title: "Purchases restored", message: "Your Premium features are available.", asset: "Premium", onPrimary: { self.restoreOutcome = nil })
                    case .none: CleanerModal(title: "No purchases found", message: "No active subscription was found for this Apple Account.", asset: "Premium", onPrimary: { self.restoreOutcome = nil })
                    case .failed: CleanerModal(title: "Couldn’t restore purchases", message: "Check your connection and try again.", asset: "Premium", primaryTitle: "Try again", secondaryTitle: "Back to Settings", onPrimary: { self.restoreOutcome = nil; restore() }, onSecondary: { self.restoreOutcome = nil })
                    }
                }
            }
            .alert("Cleaner", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
            .onAppear {
                guard FidelityPreview.active else { return }
                if settingsFixture.hasSuffix("/ restored") { restoreOutcome = .restored }
                if settingsFixture.hasSuffix("/ none") { restoreOutcome = RestoreOutcome.none }
                if settingsFixture.hasSuffix("/ error") { restoreOutcome = .failed }
            }
    }
    private func restore() {
        Task {
            await purchases.restore()
            if ProductConfiguration.subscriptionIDs.isEmpty { message = purchases.message; return }
            if purchases.message == "Premium restored." { restoreOutcome = .restored }
            else if purchases.message == "No active subscription was found." { restoreOutcome = RestoreOutcome.none }
            else { restoreOutcome = .failed }
        }
    }
    private func openDocument(_ url: URL?) { if let url { UIApplication.shared.open(url) } else { message = "This document is not available yet." } }
}
private struct SettingsRow: View {
    let title: String
    let symbol: String
    var loading = false
    var body: some View {
        HStack(spacing: 8) {
            Image(["creditcard": "SettingsManage", "arrow.clockwise": "SettingsRestore", "star": "SettingsRate", "envelope": "SettingsContact", "doc.text": "SettingsTerms", "hand.raised": "SettingsPrivacy"][symbol] ?? "SettingsManage").resizable().scaledToFit().frame(width: 24, height: 24).frame(width: 40, height: 40).background(CleanerStyle.track, in: RoundedRectangle(cornerRadius: 16))
            Text(title).font(CleanerStyle.font(16, .semibold)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            if loading { CleanerLoadingRing() } else { Disclosure() }
        }.padding(.horizontal, 16).padding(.vertical, 12).background(.white, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(CleanerStyle.ink)
    }
}
struct SubscriptionScreen: View {
    @Environment(\.dismiss) private var dismiss
    private var purchases: PurchaseState { .shared }
    @State private var manage = false
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
        CleanerPage(title: "My subscription") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) { Image("Premium").resizable().scaledToFit().frame(width: 40, height: 40); Text("Cleaner Premium").font(CleanerStyle.font(24, .semibold)) }
                    Text(active ? plan : "No active subscription").font(CleanerStyle.font(16, .semibold))
                    HStack(spacing: 6) { if active { Circle().fill(Color(hex: 0x21C75A)).frame(width: 8, height: 8) }; Text(active ? (renewalOff ? "Auto-renewal off" : "Active") : "Available with a subscription") }
                }.padding(16).frame(maxWidth: .infinity, minHeight: 144, alignment: .leading).foregroundStyle(.white).background(LinearGradient(colors: [Color(hex: 0xFE8301), Color(hex: 0xFFB700)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
                if active {
                    VStack(spacing: 8) { detail("Plan", period); detail(renewalOff ? "Access until" : purchases.willRenew == true || fixture ? "Renews on" : "Current period ends", date) }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 24))
                    Text(renewalOff ? "You won’t be charged again. Premium stays available until \(longDate)." : purchases.willRenew == true || fixture ? "Your plan renews automatically. You can change your plan or cancel renewal without leaving Cleaner." : "Manage your subscription with Apple to review renewal details.").foregroundStyle(Color(hex: 0x526580)).frame(minHeight: max(72, min(136, geometry.size.height - 604)), alignment: .topLeading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nothing to cancel").font(CleanerStyle.font(24, .semibold))
                        Text("There is no active subscription for this Apple Account. Restore purchases if you subscribed before.").foregroundStyle(Color(hex: 0x526580))
                    }.padding(16).frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading).background(.white, in: RoundedRectangle(cornerRadius: 24))
                    Text("Check your purchases or restore an existing subscription using your Apple Account.").foregroundStyle(Color(hex: 0x526580)).frame(minHeight: 72, alignment: .topLeading)
                }
                subscriptionButton(active ? "Manage plan" : "Manage purchases", primary: true) { manage = true }
                subscriptionButton(active ? (renewalOff ? "Back to Settings" : "Cancel subscription") : "Restore Purchases", destructive: active && !renewalOff) {
                    if active { if renewalOff { dismiss() } else { manage = true } }
                    else { Task { await purchases.restore() } }
                }
                Text(active ? (renewalOff ? "You can turn renewal back on at any time." : "Apple will ask you to confirm.") : "Purchases are linked to your Apple Account.").foregroundStyle(Color(hex: 0x526580)).frame(minHeight: 48, alignment: .topLeading)
                if !fixture {
                    if ProductConfiguration.subscriptionIDs.isEmpty { Text("Premium purchases are not available yet. You can use the available cleaning tools.").foregroundStyle(CleanerStyle.secondary) }
                    ForEach(purchases.products) { product in PrimaryButton(title: "\(product.displayName) · \(product.displayPrice)", disabled: purchases.busy) { Task { await purchases.purchase(product) } } }
                    if let message = purchases.message { Text(message).foregroundStyle(CleanerStyle.secondary) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.manageSubscriptionsSheet(isPresented: $manage).task { if !fixture { await purchases.refresh() } }
            .onChange(of: manage) { _, shown in if !shown && !fixture { Task { await purchases.refresh() } } }
      }
    }
    private func detail(_ key: String, _ value: String) -> some View { HStack { Text(key).foregroundStyle(Color(hex: 0x526580)); Spacer(); Text(value).font(CleanerStyle.font(16, .semibold)) }.frame(minHeight: 40) }
    private func subscriptionButton(_ title: String, primary: Bool = false, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(CleanerStyle.font(16, .semibold)).frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(primary ? .white : destructive ? Color(hex: 0xB53B3B) : CleanerStyle.blue).background(primary ? CleanerStyle.blue : .white, in: RoundedRectangle(cornerRadius: 16)) }.disabled(purchases.busy)
    }
}
