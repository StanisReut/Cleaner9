import StoreKit
import SwiftUI
import Combine
import SafariServices

@MainActor
final class PurchaseCoordinator: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var loading = false
    @Published private(set) var premium = false
    @Published var alert: PurchaseAlert?
    var source: PaywallSource = .onboarding
    var paywallVersion: String = "a"
    private var task: Task<Void, Never>?

    func load(productIDs: [String], timeout: TimeInterval) {
        guard !productIDs.isEmpty else { products = []; loading = false; return }
        task?.cancel()
        loading = true
        task = Task {
            let result = await withTaskGroup(of: [Product].self) { group in
                group.addTask { (try? await Product.products(for: productIDs)) ?? [] }
                group.addTask {
                    try? await Task.sleep(for: .seconds(timeout))
                    return []
                }
                return await group.next() ?? []
            }
            guard !Task.isCancelled else { return }
            products = result
            loading = false
            #if !DEBUG
            if result.isEmpty && !productIDs.isEmpty { alert = .loadFailed }
            #endif
        }
    }

    func purchaseDebugPlan(id: String) {
        Veil.shared.show()
        let productID: ProductID = switch id {
        case "week": .weekly
        case "month": .monthly
        case "year": .yearly
        default: .primary
        }
        Telemetry.shared.track(.paywallCheckoutInitiated, parameters: ["paywall_version": paywallVersion, "source": source.rawValue, "product_id": productID.rawValue])
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            defer { Veil.shared.hide() }
            Merchant.shared.grantTestPurchase(productID)
            Tactile.success()
            premium = true
            await PurchaseState.shared.refresh()
            onPurchased?()
            showRefundConsentPrompt()
        }
    }

    func purchase(planID: String) {
        let item: ProductID = switch planID {
        case "week": .weekly
        case "month": .monthly
        case "year": .yearly
        default: .primary
        }
        Veil.shared.show()
        Telemetry.shared.track(.paywallCheckoutInitiated, parameters: ["paywall_version": paywallVersion, "source": source.rawValue, "product_id": item.rawValue])
        Task {
            defer { Veil.shared.hide() }
            do {
                try await Merchant.shared.purchase(item)
                Tactile.success(); premium = Merchant.shared.isPremium
                await PurchaseState.shared.refresh()
                onPurchased?()
                showRefundConsentPrompt()
            } catch MerchantFailure.cancelled {
                Telemetry.shared.track(.paywallCheckoutCancelled, parameters: ["paywall_version": paywallVersion, "source": source.rawValue, "product_id": item.rawValue])
            } catch MerchantFailure.pending {
                alert = .pending
            } catch {
                Tactile.failure()
                Telemetry.shared.track(.paywallCheckoutFailed, parameters: ["paywall_version": paywallVersion, "source": source.rawValue, "error_code": String(describing: error)])
                alert = .failed
            }
        }
    }

    func purchase(_ product: Product) {
        Veil.shared.show()
        Telemetry.shared.track(.paywallCheckoutInitiated, parameters: ["paywall_version": paywallVersion, "source": source.rawValue, "product_id": product.id])
        Task {
            defer { Veil.shared.hide() }
            guard let item = ProductID(rawValue: product.id) else { alert = .failed; return }
            do {
                try await Merchant.shared.purchase(item)
                Tactile.success(); premium = Merchant.shared.isPremium
                await PurchaseState.shared.refresh()
                onPurchased?()
                showRefundConsentPrompt()
            } catch MerchantFailure.cancelled {
                Telemetry.shared.track(.paywallCheckoutCancelled, parameters: ["paywall_version": paywallVersion, "source": source.rawValue, "product_id": product.id])
            } catch MerchantFailure.pending {
                alert = .pending
            } catch {
                Tactile.failure()
                Telemetry.shared.track(.paywallCheckoutFailed, parameters: ["paywall_version": paywallVersion, "source": source.rawValue, "error_code": String(describing: error)])
                alert = .failed
            }
        }
    }

    private func showRefundConsentPrompt() {
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if !UserDefaults.standard.bool(forKey: "user_acquisition.refund_consent_prompted") {
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
        }
    }

    func restore(productIDs: [String]) {
        Telemetry.shared.track(.restoreTapped, parameters: ["source": source.rawValue])
        guard !productIDs.isEmpty else { alert = .restoreNone; return }
        Veil.shared.show()
        Task {
            defer { Veil.shared.hide() }
            do {
                let found = try await Merchant.shared.restore()
                premium = Merchant.shared.isPremium
                await PurchaseState.shared.refresh()
                Telemetry.shared.track(.restoreCompleted, parameters: ["source": source.rawValue, "result": found ? "restored" : "not_found"])
                alert = found ? .restoreSuccess : .restoreNone
                if found { onPurchased?() }
            } catch {
                Telemetry.shared.track(.restoreCompleted, parameters: ["source": source.rawValue, "result": "failed"])
                alert = .restoreFailed
            }
        }
    }
    var onPurchased: (() -> Void)?
}

enum PurchaseAlert: Identifiable, Equatable {
    case failed, pending, loadFailed, restoreSuccess, restoreNone, restoreFailed
    var id: String { String(describing: self) }
    var title: String? { switch self { case .loadFailed: return "Couldn't load plans"; case .pending: return "Purchase pending"; case .restoreSuccess: return "Purchases restored"; case .restoreNone: return "No purchases found"; case .restoreFailed: return "Couldn't restore purchases"; case .failed: return "Purchase failed" } }
    var message: String { switch self { case .pending: return "Your purchase is waiting for approval."; case .failed: return "Something went wrong. Please try again."; case .loadFailed: return "Please try again."; case .restoreSuccess: return "Your Premium features are available."; case .restoreNone: return "No active subscription was found for this Apple Account."; case .restoreFailed: return "Check your connection and try again." } }
}

struct PaywallScreen: View {
    var variant: OnboardingVariant? = nil
    let source: PaywallSource
    var feature: String? = nil
    let configuration: PaywallConfiguration
    var onClose: (() -> Void)? = nil
    var onPurchased: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var purchases = PurchaseCoordinator()
    @State private var selectedPlan: String = {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--qa-plan-year") { return "year" }
        if args.contains("--qa-plan-month") { return "month" }
        if let idx = args.firstIndex(of: "--qa-plan"), args.indices.contains(idx + 1) {
            return args[idx + 1]
        }
        return "week"
    }()
    @State private var safariURL: URL?
    @State private var legalDocument: LegalDocument?
    @State private var openedAt = Date()
    @State private var pulse = false

    private var activeVariant: OnboardingVariant {
        if let variant { return variant }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--qa-paywall-b") || args.contains("--onboarding-b") || args.contains("--qa-onboarding-b") { return .b }
        if args.contains("--qa-paywall-a") || args.contains("--onboarding-a") || args.contains("--qa-onboarding-a") { return .a }
        if let idx = args.firstIndex(of: "--qa-paywall"), args.indices.contains(idx + 1) {
            let val = args[idx + 1]
            if val == "b" { return .b }
            if val == "a" { return .a }
        }
        if let idx = args.firstIndex(of: "--qa-onboarding"), args.indices.contains(idx + 1) {
            let val = args[idx + 1]
            if val == "b" { return .b }
            if val == "a" { return .a }
        }
        let rc = RemoteConfiguration.shared.value
        if rc.paywallVariant == .b || rc.onboardingVariant == .b { return .b }
        return rc.paywallVariant
    }

    var body: some View {
        Group {
            if activeVariant == .b {
                paywallBodyB
            } else {
                paywallBodyA
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            openedAt = Date()
            purchases.onPurchased = {
                onPurchased?()
                if source != .feature && source != .onboarding {
                    dismiss()
                }
            }
            purchases.source = source
            purchases.paywallVersion = activeVariant == .b ? "b" : "a"
            var params: [String: String] = ["paywall_version": purchases.paywallVersion, "source": source.rawValue]
            if let feature, !feature.isEmpty { params["feature"] = feature }
            Telemetry.shared.track(.paywallShown, parameters: params)
            purchases.load(productIDs: configuration.plans.compactMap(\.productID), timeout: configuration.productLoadTimeout)
        }
        .alert(item: $purchases.alert) { alert in
            switch alert {
            case .loadFailed:
                return Alert(
                    title: Text("Couldn't load plans"),
                    message: Text(""),
                    dismissButton: .default(Text("Try again")) {
                        purchases.load(productIDs: configuration.plans.compactMap(\.productID), timeout: configuration.productLoadTimeout)
                    }
                )
            case .pending:
                return Alert(
                    title: Text("Purchase pending"),
                    message: Text("Your purchase is waiting for approval."),
                    dismissButton: .default(Text("OK"))
                )
            case .failed:
                return Alert(
                    title: Text("Purchase failed"),
                    message: Text("Something went wrong. Please try again."),
                    dismissButton: .default(Text("OK"))
                )
            case .restoreSuccess:
                return Alert(
                    title: Text("Purchases restored"),
                    message: Text("Your Premium features are available."),
                    dismissButton: .default(Text("OK"))
                )
            case .restoreNone:
                return Alert(
                    title: Text("No purchases found"),
                    message: Text("No active subscription was found for this Apple Account."),
                    dismissButton: .default(Text("OK"))
                )
            case .restoreFailed:
                return Alert(
                    title: Text("Couldn't restore purchases"),
                    message: Text("Check your connection and try again."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .sheet(isPresented: Binding(get: { safariURL != nil }, set: { if !$0 { safariURL = nil } })) {
            if let safariURL { SafariView(url: safariURL) }
        }
        .sheet(item: $legalDocument) { doc in LegalDocumentSheet(document: doc) }
    }

    private var paywallBodyA: some View {
        ZStack {
            // Background deep blue gradient from Figma A
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x327ED7), location: 0.0),
                    .init(color: Color(hex: 0x092B61), location: 0.45),
                    .init(color: Color(hex: 0x06172F), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top close button
                HStack {
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(BackButtonStyle())
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Top 3D floating collage
                        Image("PaywallCollage")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 336, maxHeight: 176)
                            .padding(.top, -6)

                        // Headline
                        Text(configuration.title.isEmpty ? "Make room for more" : configuration.title)
                            .font(Palette.font(26, .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)

                        // Three benefits with cyan checkmark
                        VStack(alignment: .leading, spacing: 8) {
                            benefitRow("Clean photos & videos")
                            benefitRow("Organize contacts & calendar")
                            benefitRow("Access security checks")
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 4)

                        // Plans list
                        VStack(spacing: 10) {
                            planRow(id: "week", title: "Week", subtitle: "3 days free", price: "$9.99", unit: "/ week", badge: nil)
                            planRow(id: "month", title: "Month", subtitle: "Billed monthly", price: "$19.99", unit: "/ month", badge: nil)
                            planRow(id: "year", title: "Year", subtitle: nil, price: "$49.99", unit: "/ year", badge: "Save 79%")
                        }
                        .padding(.horizontal, 20)

                        // Billing disclosure
                        Text(disclosureText)
                            .font(Palette.font(13))
                            .foregroundStyle(Color(hex: 0xB4CCE8))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 24)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                    }
                }

                // Fixed bottom CTA container: always in the same place + pulsating
                VStack(spacing: 12) {
                    Button(action: handlePurchase) {
                        Text(isTrialSelected ? "Start free trial" : "Continue")
                            .font(Palette.font(17, .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: 0x0051C7), Color(hex: 0x4B8DE4)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                            .shadow(color: Color(hex: 0x0051C7).opacity(pulse ? 0.6 : 0.25), radius: pulse ? 14 : 6, y: 4)
                            .scaleEffect(pulse ? 1.025 : 1.0)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityLabel(isTrialSelected ? "Start free trial" : "Continue")
                    .accessibilityIdentifier("Paywall CTA")
                    .padding(.horizontal, 20)
                    .onAppear { pulse = true }

                    // Footer links
                    HStack(spacing: 20) {
                        Button("Terms of Use") { legalLink("terms", configuration.termsURL) }
                        Button("Privacy Policy") { legalLink("privacy", configuration.privacyURL) }
                        Button("Restore") { purchases.restore(productIDs: configuration.plans.compactMap(\.productID)) }
                    }
                    .font(Palette.font(13))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private var paywallBodyB: some View {
        ZStack {
            // Light sky pastel gradient from Figma B
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0xBBDFFF), location: 0.0),
                    .init(color: Color(hex: 0xEFF5FF), location: 0.35),
                    .init(color: Color(hex: 0xF7FAFF), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top close button
                HStack {
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: 0x505E70))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.85), in: Circle())
                            .overlay(Circle().stroke(Color(hex: 0x0048AE).opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(BackButtonStyle())
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Top 3D illustration from Figma
                        Image("PaywallIllustrationB")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 336, maxHeight: 136)
                            .padding(.top, -6)

                        // Value Headline
                        VStack(spacing: 6) {
                            Text("Unlock more")
                                .font(Palette.font(28, .bold))
                                .foregroundStyle(Color(hex: 0x0048AE))

                            Text("with Cleaner Premium")
                                .font(Palette.font(16))
                                .foregroundStyle(Color(hex: 0x505E70))
                        }
                        .multilineTextAlignment(.center)

                        // Premium benefits
                        VStack(spacing: 10) {
                            Text("Premium benefits")
                                .font(Palette.font(16, .semibold))
                                .foregroundStyle(Color(hex: 0x0048AE))

                            VStack(alignment: .leading, spacing: 8) {
                                benefitRowB("Clean photos & videos")
                                benefitRowB("Organize contacts & calendar")
                                benefitRowB("Access security checks")
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 2)

                        // Plans (3 cards horizontal: Week, Year, Month)
                        HStack(spacing: 8) {
                            planCardB(
                                id: "week",
                                title: "Week",
                                price: livePriceDetail(for: "week")?.price ?? "$9.99",
                                unit: "/ week",
                                detail: "3-day\nfree trial",
                                isBadge: false
                            )
                            planCardB(
                                id: "year",
                                title: "Year",
                                price: livePriceDetail(for: "year")?.price ?? "$49.99",
                                unit: "/ year",
                                detail: "Save 79%",
                                isBadge: true
                            )
                            planCardB(
                                id: "month",
                                title: "Month",
                                price: livePriceDetail(for: "month")?.price ?? "$19.99",
                                unit: "/ month",
                                detail: "Billed\nmonthly",
                                isBadge: false
                            )
                        }
                        .padding(.horizontal, 20)

                        // Billing disclosure
                        Text(disclosureTextB)
                            .font(Palette.font(13))
                            .foregroundStyle(Color(hex: 0x505E70))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 24)
                            .padding(.top, 4)
                            .padding(.bottom, 6)
                    }
                }

                // Fixed bottom CTA container: always in the same place + pulsating
                VStack(spacing: 12) {
                    Button(action: handlePurchase) {
                        Text(isTrialSelected ? "Start free trial" : "Continue")
                            .font(Palette.font(17, .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color(hex: 0x0048AE), in: RoundedRectangle(cornerRadius: 16))
                            .shadow(color: Color(hex: 0x0048AE).opacity(pulse ? 0.45 : 0.2), radius: pulse ? 12 : 6, y: 4)
                            .scaleEffect(pulse ? 1.025 : 1.0)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityLabel(isTrialSelected ? "Start free trial" : "Continue")
                    .accessibilityIdentifier("Paywall CTA")
                    .padding(.horizontal, 20)
                    .onAppear { pulse = true }

                    // Footer links
                    HStack(spacing: 24) {
                        Button("Terms of Use") { legalLink("terms", configuration.termsURL) }
                        Button("Restore") { purchases.restore(productIDs: configuration.plans.compactMap(\.productID)) }
                        Button("Privacy Policy") { legalLink("privacy", configuration.privacyURL) }
                    }
                    .font(Palette.font(13))
                    .foregroundStyle(Color(hex: 0x718096))
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private func benefitRowB(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: 0x0048AE))
            Text(text)
                .font(Palette.font(15))
                .foregroundStyle(Color(hex: 0x172B4D))
            Spacer()
        }
    }

    private func planCardB(id: String, title: String, price: String, unit: String, detail: String, isBadge: Bool) -> some View {
        let isSelected = selectedPlan == id
        return Button(action: {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                selectedPlan = id
            }
            Tactile.select()
            Telemetry.shared.track(.paywallPlanSelected, parameters: ["paywall_version": "b", "source": source.rawValue, "subscription_period": subscriptionPeriod(for: id)])
            handlePurchase()
        }) {
            VStack(spacing: 0) {
                Text(title)
                    .font(Palette.font(16, .semibold))
                    .foregroundStyle(isSelected ? Color(hex: 0x0048AE) : Color(hex: 0x1A202C))
                    .padding(.top, 16)

                Spacer(minLength: 4)

                Text(price)
                    .font(Palette.font(24, .bold))
                    .foregroundStyle(isSelected ? Color(hex: 0x0048AE) : Color(hex: 0x1A202C))
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)

                Text(unit)
                    .font(Palette.font(15))
                    .foregroundStyle(isSelected ? Color(hex: 0x0048AE) : Color(hex: 0x718096))
                    .padding(.top, 2)

                Spacer(minLength: 6)

                Text(detail)
                    .font(Palette.font(14, (isBadge || isSelected) ? .semibold : .regular))
                    .foregroundStyle(isBadge || isSelected ? Color(hex: 0x0048AE) : Color(hex: 0x5C6E8A))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 184)
            .background(
                isSelected ? Color(hex: 0xEEF5FF) : Color.white,
                in: RoundedRectangle(cornerRadius: 18)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? Color(hex: 0x0048AE) : Color(hex: 0xDCE4EE), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? Color(hex: 0x0048AE).opacity(0.12) : Color.black.opacity(0.04), radius: isSelected ? 8 : 4, y: 3)
        }
        .buttonStyle(InteractiveCardButtonStyle())
        .accessibilityIdentifier("Paywall plan \(id)")
    }

    private var disclosureTextB: String {
        let weekPrice = livePriceDetail(for: "week")?.price ?? "$9.99"
        let monthPrice = livePriceDetail(for: "month")?.price ?? "$19.99"
        let yearPrice = livePriceDetail(for: "year")?.price ?? "$49.99"
        switch selectedPlan {
        case "week":
            return "3 days free, then \(weekPrice) / week.\nAuto-renews until canceled."
        case "month":
            return "\(monthPrice) billed monthly.\nAuto-renews until canceled."
        case "year":
            return "\(yearPrice) billed yearly.\nAuto-renews until canceled."
        default:
            return "Auto-renews until canceled."
        }
    }

    private func benefitRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            Text("✓")
                .font(Palette.font(16, .bold))
                .foregroundStyle(Color(hex: 0x83C5FF))
            Text(text)
                .font(Palette.font(16))
                .foregroundStyle(.white)
            Spacer()
        }
    }

    private func planRow(id: String, title: String, subtitle: String?, price: String, unit: String, badge: String?) -> some View {
        let isSelected = selectedPlan == id
        let liveDetail = livePriceDetail(for: id)

        return Button(action: {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                selectedPlan = id
            }
            Tactile.select()
            Telemetry.shared.track(.paywallPlanSelected, parameters: ["paywall_version": "a", "source": source.rawValue, "subscription_period": subscriptionPeriod(for: id)])
            handlePurchase()
        }) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(Palette.font(18, .semibold))
                            .foregroundStyle(.white)
                        if let badge {
                            Text(badge)
                                .font(Palette.font(11, .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    LinearGradient(
                                        colors: [Color(hex: 0xFE8301), Color(hex: 0xFFB700)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                        }
                    }
                    if let sub = subtitle {
                        Text(sub)
                            .font(Palette.font(13))
                            .foregroundStyle(id == "week" ? Color(hex: 0x83C5FF) : Color.white.opacity(0.7))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(liveDetail?.price ?? price)
                        .font(Palette.font(18, .semibold))
                        .foregroundStyle(.white)
                    Text(liveDetail?.unit ?? unit)
                        .font(Palette.font(13))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                isSelected ? Color(hex: 0x4A9BFA).opacity(0.64) : Color.white.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.white : Color.white.opacity(0.12), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(InteractiveCardButtonStyle())
        .accessibilityIdentifier("Paywall plan \(id)")
    }

    private var isTrialSelected: Bool {
        selectedPlan == "week"
    }

    private var disclosureText: String {
        let weekPrice = livePriceDetail(for: "week")?.price ?? "$9.99"
        let monthPrice = livePriceDetail(for: "month")?.price ?? "$19.99"
        let yearPrice = livePriceDetail(for: "year")?.price ?? "$49.99"
        switch selectedPlan {
        case "week":
            return "3 days free, then \(weekPrice) / week.\nAuto-renews until canceled."
        case "month":
            return "Billed monthly at \(monthPrice) / month.\nAuto-renews until canceled."
        case "year":
            return "Billed annually at \(yearPrice) / year.\nAuto-renews until canceled."
        default:
            return "Auto-renews until canceled."
        }
    }

    private func livePriceDetail(for planID: String) -> (price: String, unit: String)? {
        let productID: ProductID? = switch planID {
        case "week": .weekly
        case "month": .monthly
        case "year": .yearly
        default: nil
        }
        if let productID, let detail = Merchant.shared.plans[productID] {
            let formattedUnit = detail.unit.hasPrefix("/") ? detail.unit : "/ \(detail.unit)"
            return (detail.price, formattedUnit)
        }
        if let productID, let price = Merchant.shared.prices[productID] {
            let unit: String = switch productID {
            case .weekly: "/ week"
            case .monthly: "/ month"
            case .yearly: "/ year"
            }
            return (price, unit)
        }
        if let target = purchases.products.first(where: {
            if let pid = productID?.rawValue { return $0.id == pid }
            return $0.id.contains(planID)
        }) {
            let fallbackUnit = planID == "week" ? "/ week" : (planID == "month" ? "/ month" : "/ year")
            let unit: String
            if let period = target.subscription?.subscriptionPeriod {
                switch period.unit {
                case .day: unit = "/ day"
                case .week: unit = "/ week"
                case .month: unit = "/ month"
                case .year: unit = "/ year"
                @unknown default: unit = fallbackUnit
                }
            } else {
                unit = fallbackUnit
            }
            return (target.displayPrice, unit)
        }
        return nil
    }

    private func handlePurchase() {
        if let product = selectedProduct {
            purchases.purchase(product)
        } else {
            purchases.purchase(planID: selectedPlan)
        }
    }

    private var selectedProduct: Product? {
        if let plan = configuration.plans.first(where: { $0.id == selectedPlan }),
           let productID = plan.productID,
           let match = purchases.products.first(where: { $0.id == productID }) {
            return match
        }
        let targetID: String = switch selectedPlan {
        case "week": ProductID.weekly.rawValue
        case "month": ProductID.monthly.rawValue
        case "year": ProductID.yearly.rawValue
        default: ""
        }
        return purchases.products.first(where: { $0.id == targetID || $0.id.contains(selectedPlan) })
    }

    private func close() {
        Telemetry.shared.track(.paywallClosed, parameters: ["paywall_version": activeVariant == .b ? "b" : "a", "source": source.rawValue, "time_on_screen_ms": "\(Int(Date().timeIntervalSince(openedAt) * 1000))"])
        onClose?()
        dismiss()
    }

    private func legalLink(_ link: String, _ url: URL?) {
        Telemetry.shared.track(.legalLinkOpened, parameters: ["link": link, "source": source.rawValue])
        if let url {
            safariURL = url
        } else {
            legalDocument = (link == "terms") ? .terms : .privacy
        }
    }

    private func subscriptionPeriod(for planID: String) -> String {
        switch planID {
        case "week": return "weekly"
        case "month": return "monthly"
        case "year": return "yearly"
        default: return planID
        }
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
