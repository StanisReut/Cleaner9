import SwiftUI
import Contacts
import EventKit
import Photos

struct HomeScreen: View {
    @Environment(MediaStore.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var capacity: Int64 = 0
    @State private var available: Int64 = 0
    @State private var contacts = ContactsStore()
    @State private var calendar = CalendarStore()
    private var used: Int64 { max(0, capacity - available) }
    private var fraction: Double { capacity > 0 ? Double(used)/Double(capacity) : 0 }
    private var cleanup: [MediaItem] {
        let duplicatePhotoBest = Set(library.groups(in: .duplicatePhotos).map(\.bestID))
        let similarPhotoBest = Set(library.groups(in: .similarPhotos).map(\.bestID))
        let duplicateVideoBest = Set(library.groups(in: .duplicateVideos).map(\.bestID))
        let similarVideoBest = Set(library.groups(in: .similarVideos).map(\.bestID))

        let photoCandidates = library.items(in: .duplicatePhotos).filter { !duplicatePhotoBest.contains($0.id) }
            + library.items(in: .similarPhotos).filter { !similarPhotoBest.contains($0.id) }
            + library.items(in: .screenshots)

        let videoCandidates = library.items(in: .duplicateVideos).filter { !duplicateVideoBest.contains($0.id) }
            + library.items(in: .similarVideos).filter { !similarVideoBest.contains($0.id) }
            + library.items(in: .screenRecordings)
            + library.items(in: .largeVideos)

        var seen: Set<String> = []
        return (photoCandidates + videoCandidates).filter { seen.insert($0.id).inserted }
    }
    private var photoBytes: Int64 { FidelityPreview.active ? 2_100_000_000 : cleanup.filter { !$0.isVideo }.reduce(0) { $0 + $1.bytes } }
    private var videoBytes: Int64 { FidelityPreview.active ? 6_400_000_000 : cleanup.filter(\.isVideo).reduce(0) { $0 + $1.bytes } }
    private var scanned: Bool { FidelityPreview.active || library.progress > 0 || !library.isScanning }
    private var premiumActive: Bool { FidelityPreview.active || PurchaseState.shared.active }
    private var adaptiveRow: AnyLayout {
        dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
    }
    var body: some View {
      ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("Cleaner").font(Palette.font(28, .bold)).lineLimit(1).minimumScaleFactor(0.6); Spacer()
                    NavigationLink { SettingsScreen() } label: {
                        Image("Settings").resizable().scaledToFit().frame(width: 32, height: 32).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(BackButtonStyle())
                    .accessibilityLabel("Settings").accessibilityIdentifier("qa/settings")
                }.frame(height: dynamicType.isAccessibilitySize ? nil : 40)
                if !PurchaseState.shared.active || FidelityPreview.active { PremiumBanner(source: .premiumBadge) }
                VStack(spacing: 16) {
                    adaptiveRow {
                        StorageRing(value: fraction).frame(width: 134, height: 134)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(FidelityPreview.active ? "115.2 GB" : capacity > 0 ? formattedBytes(used) : "—").font(Palette.font(28, .bold)).minimumScaleFactor(0.75).lineLimit(1).frame(minHeight: 38)
                            Text(FidelityPreview.active ? "of 128 GB used" : capacity > 0 ? "of \(formattedBytes(capacity)) used" : "Storage unavailable").font(Palette.font(16)).foregroundStyle(Color(hex: 0x62656B)).frame(minHeight: 24)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(minHeight: 136)
                    NavigationLink { FeatureGate(feature: "Smart Scan", premiumActive: premiumActive) { ScanScreen() } } label: {
                        HStack(spacing: 8) { Image("ScanIcon").resizable().scaledToFit().frame(width: 18, height: 18); Text("Smart Scan").font(Palette.font(16, .bold)) }.frame(maxWidth: .infinity).frame(height: 48)
                            .foregroundStyle(.white).background(Palette.blue, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("qa/smart_scan")
                }.cleanerCard().compositingGroup().shadow(color: Color(hex: 0x356CB6).opacity(0.12), radius: 8, y: 8)
                if !FidelityPreview.active && (library.authorization == .denied || library.authorization == .restricted) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Allow access to photos").font(Palette.font(18, .semibold))
                        Text("Cleaner needs access to scan your photo library.").font(Palette.font(15)).foregroundStyle(Palette.secondary)
                        PrimaryButton(title: "Go to Settings", action: openSettings)
                    }.cleanerCard()
                } else { VStack(spacing: 8) {
                    adaptiveRow {
                        Text("Media cleanup"); if !dynamicType.isAccessibilitySize { Spacer() }
                        if !FidelityPreview.active && library.isScanning {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(FidelityPreview.active ? "8.5 GB to clean" : "\(formattedBytes(photoBytes + videoBytes)) to clean")
                                .foregroundStyle(Color(hex: 0x62656B)).font(Palette.font(16, .medium))
                        }
                    }.font(Palette.font(16, .medium)).frame(minHeight: 24)
                    adaptiveRow {
                        NavigationLink { FeatureGate(feature: "Photos", premiumActive: premiumActive) { MediaCategoriesScreen(video: false) } } label: {
                            metricCard(
                                "Photos",
                                asset: "Photos",
                                value: formattedBytes(photoBytes),
                                detail: "to clean",
                                count: FidelityPreview.active ? 340 : cleanup.filter { !$0.isVideo }.count,
                                fraction: photoBytes + videoBytes > 0 ? Double(photoBytes)/Double(photoBytes+videoBytes) : 0,
                                loading: !FidelityPreview.active && library.isScanning
                            )
                        }
                        .buttonStyle(InteractiveCardButtonStyle())
                        NavigationLink { FeatureGate(feature: "Videos", premiumActive: premiumActive) { MediaCategoriesScreen(video: true) } } label: {
                            metricCard(
                                "Videos",
                                asset: "Videos",
                                value: formattedBytes(videoBytes),
                                detail: "to clean",
                                count: FidelityPreview.active ? 12 : cleanup.filter(\.isVideo).count,
                                fraction: photoBytes + videoBytes > 0 ? Double(videoBytes)/Double(photoBytes+videoBytes) : 0,
                                loading: !FidelityPreview.active && library.isScanning
                            )
                        }
                        .buttonStyle(InteractiveCardButtonStyle())
                    }
                }
                if library.authorization == .limited && !FidelityPreview.active {
                    HStack { Text("Limited access").font(Palette.font(14)).foregroundStyle(Palette.secondary); Spacer(); Button("Manage") { presentLimitedPhotoPicker() }.font(Palette.font(14, .semibold)) }
                } }
                adaptiveRow {
                    NavigationLink { FeatureGate(feature: "Contacts", premiumActive: premiumActive) { ContactsScreen(model: contacts) } } label: {
                        metricCard("Contacts", asset: "Contacts", value: contactValue, detail: "duplicates", loading: !FidelityPreview.active && contacts.loading)
                    }
                    .buttonStyle(InteractiveCardButtonStyle())
                    NavigationLink { FeatureGate(feature: "Calendar", premiumActive: premiumActive) { CalendarScreen(model: calendar) } } label: {
                        metricCard("Calendar", asset: "Calendar", value: calendarValue, detail: "old events", loading: !FidelityPreview.active && calendar.loading)
                    }
                    .buttonStyle(InteractiveCardButtonStyle())
                }
                NavigationLink { FeatureGate(feature: "Background Remover", premiumActive: premiumActive) { BackgroundRemoverScreen() } } label: { FeatureRow(title: "Background Remover", subtitle: "Erase backgrounds", asset: "BackgroundRemover") }
                    .buttonStyle(InteractiveCardButtonStyle())
                    .accessibilityIdentifier("qa/background")
                NavigationLink { FeatureGate(feature: "Security Center", premiumActive: premiumActive) { SecurityScreen() } } label: { FeatureRow(title: "Security Center", subtitle: "Check your security", asset: "SecurityCenter") }
                    .buttonStyle(InteractiveCardButtonStyle())
                    .accessibilityIdentifier("qa/security").id("home-bottom")
            }.padding(.leading, 16).padding(.trailing, 23).padding(.top, 8).padding(.bottom, 48)
        }.background(Palette.bg.ignoresSafeArea()).foregroundStyle(Color(hex: 0x28292C)).accessibilityIdentifier("qa/main")
            .toolbar(.hidden, for: .navigationBar).onAppear {
                updateStorage()
                Telemetry.shared.track(.mainShown, parameters: [
                    "storage_used_pct": "\(Int(fraction * 100))",
                    "media_to_clean_mb": "\((photoBytes + videoBytes) / 1_000_000)",
                    "subscription_status": premiumActive ? "active" : "none"
                ])
            }
            .task {
                if FidelityPreview.active { if FidelityPreview.bottom { try? await Task.sleep(for: .milliseconds(100)); proxy.scrollTo("home-bottom", anchor: .bottom) }; return }
                if library.progress == 0 && (library.authorization == .authorized || library.authorization == .limited) {
                    Task { await library.scan() }
                }
                let status = CNContactStore.authorizationStatus(for: .contacts)
                if status == .authorized || status.rawValue == 4 { await contacts.load() }
                if EKEventStore.authorizationStatus(for: .event) == .fullAccess { calendar.future = false; await calendar.load() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    updateStorage()
                    library.refreshAccess()
                    let status = CNContactStore.authorizationStatus(for: .contacts)
                    if status == .authorized || status.rawValue == 4 { Task { await contacts.load() } }
                    if EKEventStore.authorizationStatus(for: .event) == .fullAccess { Task { calendar.future = false; await calendar.load() } }
                }
            }
      }
    }
    private var contactValue: String {
        if FidelityPreview.active { return "12" }
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined { return "Tap to check" }
        if !contacts.allowed { return "No access" }
        return "\(contacts.duplicates.reduce(0) { $0 + $1.count })"
    }
    private var calendarValue: String {
        if FidelityPreview.active { return "340" }
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined { return "Tap to check" }
        if !calendar.allowed { return "No access" }
        return "\(calendar.events.filter { $0.endDate < Date() }.count)"
    }
    private func updateStorage() {
        if FidelityPreview.active { capacity = 128_000_000_000; available = 12_800_000_000; return }
        do {
            let v = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            capacity = Int64(v.volumeTotalCapacity ?? 0); available = v.volumeAvailableCapacityForImportantUsage ?? 0
        } catch { capacity = 0; available = 0 }
    }
    private func metricCard(_ title: String, asset: String, value: String, detail: String, count: Int? = nil, fraction: Double = 0, loading: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: count == nil ? 8 : 4) {
                HStack { Image(asset).resizable().scaledToFit().frame(width: 48, height: 48); Spacer(minLength: 0); Disclosure() }
                Text(title).font(Palette.font(16, .semibold)).foregroundStyle(Color(hex: 0x565C61)).frame(minHeight: 24)
            }
            VStack(alignment: .leading, spacing: count == nil ? 0 : 8) {
              VStack(alignment: .leading, spacing: 0) {
                if loading {
                    ProgressView().controlSize(.small).frame(height: 32)
                } else {
                    Text(value).font(Palette.font(20, .semibold)).frame(minHeight: 32)
                }
                Text(detail).font(Palette.font(16)).foregroundStyle(Color(hex: 0x62656B)).frame(minHeight: 24)
              }
            if let count {
                GeometryReader { geo in
                    Capsule().fill(Palette.track)
                    Capsule().fill(LinearGradient(colors: [Color(hex: 0xF99E91), Color(hex: 0xD93D49)], startPoint: .leading, endPoint: .trailing)).frame(width: geo.size.width * fraction)
                }.frame(height: 8)
                if loading {
                    ProgressView().controlSize(.small).frame(height: 24)
                } else {
                    Text("\(count) items").font(Palette.font(16)).foregroundStyle(Color(hex: 0x62656B)).frame(minHeight: 24)
                }
            }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 8)
            .background(.white, in: RoundedRectangle(cornerRadius: 16)).compositingGroup().shadow(color: Color(hex: 0x203E73).opacity(0.08), radius: 8, y: 8)
    }
}

private struct FeatureGate<Content: View>: View {
    let feature: String
    let premiumActive: Bool
    private let content: () -> Content
    @State private var unlocked = false

    init(feature: String, premiumActive: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.feature = feature
        self.premiumActive = premiumActive
        self.content = content
    }

    var body: some View {
        Group {
            if premiumActive || PurchaseState.shared.active || unlocked {
                content()
            } else {
                PaywallScreen(source: .feature, feature: feature, configuration: RemoteConfiguration.shared.value.paywall, onPurchased: { unlocked = true })
            }
        }
        .onAppear {
            ReviewRequester.requestReviewIfAppropriate()
        }
    }
}
struct StorageRing: View {
    let value: Double
    var body: some View {
        ZStack {
            Circle().fill(.white).shadow(color: .black.opacity(0.13), radius: 10, y: 10)
            Circle().stroke(Color(hex: 0xEFF0F2), lineWidth: 9.5714).padding(14.3571)
            Circle().trim(from: 0, to: min(max(value, 0), 1)).rotation(.degrees(-90))
                .stroke(LinearGradient(colors: [Color(hex: 0xD7243F), Color(hex: 0xFF9583)], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .padding(14.3571).shadow(color: Color(hex: 0xF36163).opacity(0.22), radius: 4.7857)
            Text("\(Int(value * 100))%").font(Palette.font(29, .bold)).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Storage used, \(Int(value * 100)) percent")
    }
}
