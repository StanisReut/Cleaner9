import SwiftUI
import Contacts
import EventKit

struct HomeScreen: View {
    @Environment(MediaLibrary.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var capacity: Int64 = 0
    @State private var available: Int64 = 0
    @State private var contacts = CleanerContactsStore()
    @State private var calendar = CleanerCalendarStore()
    private var used: Int64 { max(0, capacity - available) }
    private var fraction: Double { capacity > 0 ? Double(used)/Double(capacity) : 0 }
    private var cleanup: [MediaItem] {
        let candidates = library.groups.flatMap { g in g.items.filter { $0.id != g.bestID } } + library.items(in: .screenshots) + library.items(in: .largeVideos)
        var seen: Set<String> = []
        return candidates.filter { seen.insert($0.id).inserted }
    }
    private var photoBytes: Int64 { FidelityPreview.active ? 2_100_000_000 : cleanup.filter { !$0.isVideo }.reduce(0) { $0 + $1.bytes } }
    private var videoBytes: Int64 { FidelityPreview.active ? 6_400_000_000 : cleanup.filter(\.isVideo).reduce(0) { $0 + $1.bytes } }
    private var scanned: Bool { FidelityPreview.active || library.progress > 0 }
    private var adaptiveRow: AnyLayout {
        dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
    }
    var body: some View {
      ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("Cleaner").font(CleanerStyle.font(28, .bold)).lineLimit(1).minimumScaleFactor(0.6); Spacer()
                    NavigationLink { SettingsScreen() } label: {
                        Image("Settings").resizable().scaledToFit().frame(width: 32, height: 32).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.accessibilityLabel("Settings")
                }.frame(height: dynamicType.isAccessibilitySize ? nil : 40)
                PremiumBanner()
                VStack(spacing: 16) {
                    adaptiveRow {
                        StorageRing(value: fraction).frame(width: 134, height: 134)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(FidelityPreview.active ? "115.2 GB" : capacity > 0 ? formattedBytes(used) : "—").font(CleanerStyle.font(28, .bold)).minimumScaleFactor(0.75).lineLimit(1).frame(minHeight: 38)
                            Text(FidelityPreview.active ? "of 128 GB used" : capacity > 0 ? "of \(formattedBytes(capacity)) used" : "Storage unavailable").font(CleanerStyle.font(16)).foregroundStyle(Color(hex: 0x62656B)).frame(minHeight: 24)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(minHeight: 136)
                    NavigationLink { ScanScreen() } label: {
                        HStack(spacing: 8) { Image("ScanIcon").resizable().scaledToFit().frame(width: 18, height: 18); Text("Smart Scan").font(CleanerStyle.font(16, .bold)) }.frame(maxWidth: .infinity).frame(height: 48)
                            .foregroundStyle(.white).background(CleanerStyle.blue, in: RoundedRectangle(cornerRadius: 16))
                    }
                }.cleanerCard().compositingGroup().shadow(color: Color(hex: 0x356CB6).opacity(0.12), radius: 8, y: 8)
                VStack(spacing: 8) {
                    adaptiveRow {
                        Text("Media cleanup"); if !dynamicType.isAccessibilitySize { Spacer() }
                        Text(FidelityPreview.active ? "8.5 GB to clean" : scanned ? "\(formattedBytes(photoBytes + videoBytes)) to clean" : "Ready to scan")
                            .foregroundStyle(Color(hex: 0x62656B)).font(CleanerStyle.font(16, .medium))
                    }.font(CleanerStyle.font(16, .medium)).frame(minHeight: 24)
                    adaptiveRow {
                        NavigationLink { MediaCategoriesScreen(video: false) } label: {
                            metricCard("Photos", asset: "Photos", value: scanned ? formattedBytes(photoBytes) : "—", detail: "to clean", count: FidelityPreview.active ? 340 : cleanup.filter { !$0.isVideo }.count, fraction: photoBytes + videoBytes > 0 ? Double(photoBytes)/Double(photoBytes+videoBytes) : 0)
                        }
                        NavigationLink { MediaCategoriesScreen(video: true) } label: {
                            metricCard("Videos", asset: "Videos", value: scanned ? formattedBytes(videoBytes) : "—", detail: "to clean", count: FidelityPreview.active ? 12 : cleanup.filter(\.isVideo).count, fraction: photoBytes + videoBytes > 0 ? Double(videoBytes)/Double(photoBytes+videoBytes) : 0)
                        }
                    }
                }
                adaptiveRow {
                    NavigationLink { ContactsScreen(model: contacts) } label: { metricCard("Contacts", asset: "Contacts", value: FidelityPreview.active ? "12" : contacts.allowed ? "\(contacts.duplicates.reduce(0) { $0 + $1.count })" : "Review", detail: "duplicates") }
                    NavigationLink { CalendarScreen(model: calendar) } label: { metricCard("Calendar", asset: "Calendar", value: FidelityPreview.active ? "340" : calendar.allowed ? "\(calendar.events.filter { $0.endDate < Date() }.count)" : "Review", detail: "old events") }
                }
                NavigationLink { BackgroundRemoverScreen() } label: { FeatureRow(title: "Background Remover", subtitle: "Erase backgrounds", asset: "BackgroundRemover") }
                NavigationLink { SecurityScreen() } label: { FeatureRow(title: "Security Center", subtitle: "Check your security", asset: "SecurityCenter") }.id("home-bottom")
            }.padding(.leading, 16).padding(.trailing, 23).padding(.top, 8).padding(.bottom, 48)
        }.background(CleanerStyle.bg.ignoresSafeArea()).foregroundStyle(Color(hex: 0x28292C)).buttonStyle(.plain)
            .toolbar(.hidden, for: .navigationBar).onAppear(perform: updateStorage)
            .task {
                if FidelityPreview.active { if FidelityPreview.bottom { try? await Task.sleep(for: .milliseconds(100)); proxy.scrollTo("home-bottom", anchor: .bottom) }; return }
                let status = CNContactStore.authorizationStatus(for: .contacts)
                if status == .authorized || status.rawValue == 4 { await contacts.load() }
                if EKEventStore.authorizationStatus(for: .event) == .fullAccess { calendar.future = false; await calendar.load() }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { updateStorage() } }
      }
    }
    private func updateStorage() {
        if FidelityPreview.active { capacity = 128_000_000_000; available = 12_800_000_000; return }
        do {
            let v = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            capacity = Int64(v.volumeTotalCapacity ?? 0); available = v.volumeAvailableCapacityForImportantUsage ?? 0
        } catch { capacity = 0; available = 0 }
    }
    private func metricCard(_ title: String, asset: String, value: String, detail: String, count: Int? = nil, fraction: Double = 0) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: count == nil ? 8 : 4) {
                HStack { Image(asset).resizable().scaledToFit().frame(width: 48, height: 48); Spacer(minLength: 0); Disclosure() }
                Text(title).font(CleanerStyle.font(16, .semibold)).foregroundStyle(Color(hex: 0x565C61)).frame(minHeight: 24)
            }
            VStack(alignment: .leading, spacing: count == nil ? 0 : 8) {
              VStack(alignment: .leading, spacing: 0) {
                Text(value).font(CleanerStyle.font(20, .semibold)).frame(minHeight: 32)
                Text(detail).font(CleanerStyle.font(16)).foregroundStyle(Color(hex: 0x62656B)).frame(minHeight: 24)
              }
            if let count {
                GeometryReader { geo in
                    Capsule().fill(CleanerStyle.track)
                    Capsule().fill(LinearGradient(colors: [Color(hex: 0xF99E91), Color(hex: 0xD93D49)], startPoint: .leading, endPoint: .trailing)).frame(width: geo.size.width * fraction)
                }.frame(height: 8)
                Text(scanned ? "\(count) items" : "Not scanned").font(CleanerStyle.font(16)).foregroundStyle(Color(hex: 0x62656B)).frame(minHeight: 24)
            }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 8)
            .background(.white, in: RoundedRectangle(cornerRadius: 16)).compositingGroup().shadow(color: Color(hex: 0x203E73).opacity(0.08), radius: 8, y: 8)
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
            Text("\(Int(value * 100))%").font(CleanerStyle.font(29, .bold)).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Storage used, \(Int(value * 100)) percent")
    }
}
