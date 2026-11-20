//
//  Stage.swift
//  PhotoCleanerApp
//
//  Created by Stanislau Reut on 09/11/2026.
//

import SwiftUI
import Photos
import SafariServices

struct Stage: View {
    @State private var library = MediaStore()
    @State private var showSplash = true
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @State private var showOnboarding = true
    @State private var showOnboardingPaywall = ProcessInfo.processInfo.arguments.contains("--qa-paywall")
    @State private var configuration = AppConfiguration.fallback
    @State private var path: [String] = []
    @State private var marketingURL: URL?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if showOnboarding {
                OnboardingFlow(configuration: configuration, onComplete: completeOnboarding)
                    .id(configuration.onboardingVariant.rawValue)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else if showOnboardingPaywall {
                PaywallScreen(variant: configuration.paywallVariant, source: .onboarding, configuration: configuration.paywall, onClose: {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { showOnboardingPaywall = false }
                }, onPurchased: {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { showOnboardingPaywall = false }
                })
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
            } else {
                NavigationStack(path: $path) {
                    HomeScreen().navigationDestination(for: String.self) { name in
                        #if DEBUG
                        verificationScreen(name)
                        #else
                        HomeScreen()
                        #endif
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showOnboarding)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showOnboardingPaywall)
            .environment(library).tint(Palette.blue).preferredColorScheme(.light)
            .statusBarHidden(showSplash || FidelityPreview.contains("Splash") || (FidelityPreview.active && FidelityPreview.name.hasPrefix("Overlay")))
            .overlay { if showSplash { SplashScreen().transition(.opacity) } }
            .task {
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if FidelityPreview.active { showOnboarding = false; showSplash = false; path = ["fidelity"]; return }
                if let index = args.firstIndex(of: "--qa-screen"), args.indices.contains(index + 1) {
                    showOnboarding = false; showSplash = false; path = [args[index + 1]]; return
                }
                if args.contains("--qa-paywall") {
                    await RemoteConfiguration.shared.refresh()
                    configuration = RemoteConfiguration.shared.value
                    showOnboarding = false
                    showOnboardingPaywall = true
                    showSplash = false
                    return
                }
                if args.contains("--seed-data") {
                    Task { _ = try? await TestDataSeeder.shared.seedAll() }
                }
                if args.contains("--reset-onboarding") {
                    onboardingCompleted = false
                }
                #endif
                Telemetry.shared.track(.splashShown)
                async let attTask: Void = Telemetry.shared.requestATTAndEnableCollection()
                let refreshStarted = Date()
                let refreshed = await withTaskGroup(of: Bool.self) { group in
                    group.addTask {
                        await RemoteConfiguration.shared.refresh()
                        return true
                    }
                    group.addTask {
                        try? await Task.sleep(for: .seconds(5))
                        return false
                    }
                    let result = await group.next() ?? false
                    group.cancelAll()
                    return result
                }
                _ = await attTask
                configuration = RemoteConfiguration.shared.value
                #if DEBUG
                fputs("🔥 [Stage] updated configuration.onboardingVariant: \(configuration.onboardingVariant.rawValue)\n", stderr)
                fflush(stderr)
                #endif
                if refreshed {
                    Telemetry.shared.track(.remoteConfigLoaded, parameters: ["source": "remote", "duration_ms": "\(Int(Date().timeIntervalSince(refreshStarted) * 1000))"])
                } else {
                    Telemetry.shared.track(.remoteConfigTimeout, parameters: ["duration_ms": "3000"])
                }
                #if DEBUG
                let forceOnboarding = args.contains("--qa-onboarding") || args.contains("--onboarding")
                showOnboarding = forceOnboarding || !onboardingCompleted
                #else
                showOnboarding = !onboardingCompleted
                #endif
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeOut(duration: 0.25)) { showSplash = false }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && !FidelityPreview.active {
                    library.refreshAccess()
                    Task { await Merchant.shared.refreshEntitlement() }
                }
            }
            .onOpenURL { url in handleMarketingURL(url) }
            .sheet(isPresented: Binding(get: { marketingURL != nil }, set: { if !$0 { marketingURL = nil } })) { if let marketingURL { StageSafariView(url: marketingURL) } }
    }
    private func completeOnboarding() {
        Task {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            onboardingCompleted = true
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                showOnboarding = false
                showOnboardingPaywall = true
            }
        }
    }
    private func handleMarketingURL(_ url: URL) {
        let marker = (url.host ?? "") + url.path + (url.query ?? "")
        if url.query?.contains("premium=success") == true || url.query?.contains("checkout=success") == true {
            Task {
                do {
                    let active = try await SecurityGateway.live(configuration: configuration.backend).verifyStripeEntitlement(url)
                    if active { await PurchaseState.shared.activateExternalEntitlement() }
                    else { Herald.shared.alert(title: "Purchase verification", message: "Stripe purchase could not be verified yet.", primary: HeraldAction(title: "OK", action: {})) }
                } catch { Herald.shared.alert(title: "Stripe unavailable", message: "Stripe purchase confirmation is unavailable. Please try again later.", primary: HeraldAction(title: "OK", action: {})) }
            }
            return
        }
        guard marker.localizedCaseInsensitiveContains("stripe") || marker.localizedCaseInsensitiveContains("marketing") || url.query?.contains("source=") == true else { return }
        Task {
            do {
                marketingURL = try await SecurityGateway.live(configuration: configuration.backend).createStripeCheckout(url)
            } catch {
                if url.scheme == "https" { marketingURL = url }
                else { Herald.shared.alert(title: "Stripe unavailable", message: "Stripe checkout is not available yet.", primary: HeraldAction(title: "OK", action: {})) }
            }
        }
    }
    #if DEBUG
    @ViewBuilder private func verificationScreen(_ name: String) -> some View {
        switch name {
        case "fidelity":
            Group {
                switch FidelityPreview.section {
                case "Main", "Smart Scan", "Photos", "Photo Swipe", "Videos": MediaFidelityScreen()
                case "Contacts & Backups": ContactsFidelityScreen()
                case "Calendar": CalendarFidelityScreen()
                default: ToolsFidelityScreen()
                }
            }.toolbar(.hidden, for: .navigationBar)
        case "scan": ScanScreen()
        case "photos": MediaCategoriesScreen(video: false)
        case "swipe": PhotoSwipeScreen().task { await library.scan() }
        case "videos": MediaCategoriesScreen(video: true)
        case "contacts": ContactsScreen()
        case "calendar": CalendarScreen()
        case "background": BackgroundRemoverScreen()
        case "security": SecurityScreen()
        case "settings": SettingsScreen()
        case "subscription": SubscriptionScreen()
        case "paywall": PaywallScreen(source: .onboarding, configuration: RemoteConfiguration.shared.value.paywall, onPurchased: { path = [] })
        case "email": EmailCheckScreen()
        case "password": PasswordCheckScreen()
        case "device": DeviceSecurityScreen()
        case "splash": SplashScreen()
        default: HomeScreen()
        }
    }
    #endif
}

private struct StageSafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

#Preview {
    Stage()
}
