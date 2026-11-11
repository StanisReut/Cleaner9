import SwiftUI
import Photos
import AVKit

nonisolated struct MediaDisplayItem: Identifiable {
    let id: String
    var media: MediaItem?
    var title: String
    var bytes: Int64
    var duration: TimeInterval
    var date: Date?
    var video: Bool
    var artwork = "Coast"
    var sizeLabel: String?
    init(_ value: MediaItem) {
        id = value.id; media = value
        title = PHAssetResource.assetResources(for: value.asset).first?.originalFilename ?? (value.isVideo ? "Video" : "Photo")
        bytes = value.bytes; duration = value.duration; date = value.creationDate; video = value.isVideo
    }
    init(id: String, title: String, bytes: Int64, duration: TimeInterval = 0, video: Bool = false, artwork: String = "Coast") {
        self.id = id; self.title = title; self.bytes = bytes; self.duration = duration; self.video = video; self.artwork = artwork
    }
}
private struct DisplayGroup: Identifiable { let id: String; let title: String; let items: [MediaDisplayItem]; let bestID: String }
private struct DisplayThumbnail: View {
    let item: MediaDisplayItem
    var preview = false
    var body: some View {
        Group {
            if let media = item.media { MediaThumbnail(item: media, preview: preview) }
            else { Image(item.artwork).resizable().scaledToFill() }
        }.clipped().accessibilityLabel(item.title)
    }
}
private enum MediaFixture {
    static var active: Bool { FidelityPreview.active }
    static var texts: [String] { FidelityPreview.texts }
    static var name: String { FidelityPreview.name }
    static var noSelection: Bool { name.hasSuffix("n") || name.contains("none") || name.contains("No selection") }
    static var category: MediaCategory {
        if name.contains("playDup") || name.contains("/ dup") { return .duplicateVideos }
        if name.contains("playSim") || name.contains("/ sim") { return .similarVideos }
        if name.contains("large") { return .largeVideos }
        if name.contains("rec") { return .screenRecordings }
        if FidelityPreview.section == "Videos" { return .otherVideos }
        if name.contains("Duplicates") { return .duplicatePhotos }
        if name.contains("Similar") { return .similarPhotos }
        if name.contains("Screenshots") { return .screenshots }
        return .otherPhotos
    }
    static func amount(_ text: String) -> Int64 {
        let parts = text.split(separator: " "); guard let value = parts.first.flatMap({ Double($0) }) else { return 0 }
        let unit = parts.dropFirst().first ?? ""
        return Int64(value * (unit == "GB" ? 1_000_000_000 : unit == "MB" ? 1_000_000 : 1))
    }
    static func make(_ i: Int, bytes: Int64 = 5_000_000, video: Bool = false, title: String? = nil) -> MediaDisplayItem {
        var item = MediaDisplayItem(id: "fixture-\(i)", title: title ?? "Photo \(i + 1)", bytes: bytes, duration: 138, video: video, artwork: ["Coast", "Meadow", "Fountain"][i % 3])
        let ranks = ["Concert": 1, "Skate session": 2, "Morning surf": 3, "Editing session": 1, "Map walkthrough": 2, "Drawing replay": 3, "Afternoon ride": 1, "Wildflower walk": 2, "Shoreline": 3]
        item.date = Date(timeIntervalSince1970: Double(ranks[item.title] ?? i) * 86400)
        return item
    }
    static func groups(video: Bool) -> [DisplayGroup] {
        texts.filter { $0.hasPrefix("Group ") }.enumerated().map { index, label in
            let count = Int(label.components(separatedBy: " · ").last?.split(separator: " ").first ?? "3") ?? 3
            let items = (0..<count).map { offset in
                var item = make(index * 10 + offset, bytes: video ? (category == .duplicateVideos ? 400_000_000 : 150_000_000) : 5_000_000, video: video)
                if category == .similarVideos { item.duration = 68 }
                return item
            }
            return DisplayGroup(id: "group-\(index)", title: label, items: items, bestID: items[0].id)
        }
    }
    static func items(video: Bool) -> [MediaDisplayItem] {
        if video {
            var result: [MediaDisplayItem] = []
            for (i, text) in texts.enumerated() where (text.hasSuffix(" GB") || text.hasSuffix(" MB")) && !text.contains("·") && !text.hasPrefix("Delete") {
                guard i > 0 else { continue }
                var item = make(result.count, bytes: amount(text), video: true, title: texts[i-1])
                item.sizeLabel = text
                let durations: [String: TimeInterval] = ["Concert": 512, "Morning surf": 374, "Skate session": 261, "Editing session": 192, "Drawing replay": 126, "Map walkthrough": 84, "Afternoon ride": 48, "Shoreline": 37, "Wildflower walk": 22]
                item.duration = durations[item.title] ?? item.duration
                result.append(item)
            }
            return result
        }
        let count = name.hasPrefix("Trash") ? (name.contains("18") ? 18 : 17) : 60
        let total: Int64 = name.hasPrefix("Trash") ? (count == 18 ? 240_000_000 : 224_000_000) : 200_000_000
        return (0..<count).map { make($0, bytes: total / Int64(count)) }
    }
    static var playerItem: MediaDisplayItem {
        var item = make(0, bytes: amount(texts.last ?? "0 MB"), video: true, title: texts.first ?? "Video")
        let time = texts.first { $0.contains(":") && $0 != "00:00" } ?? "00:00"
        let parts = time.split(separator: ":").compactMap { Double($0) }
        item.duration = parts.count == 2 ? parts[0] * 60 + parts[1] : 0
        return item
    }
}
struct MediaFidelityScreen: View {
    @State private var playerSelected = !MediaFixture.noSelection
    var body: some View {
        Group {
            if FidelityPreview.section == "Main" { HomeScreen() }
            else if FidelityPreview.section == "Smart Scan" { ScanScreen() }
            else if MediaFixture.name.contains("Deleted") { MediaCategoriesScreen(video: FidelityPreview.section == "Videos") }
            else if MediaFixture.name.contains("play") { MediaPreviewScreen(display: MediaFixture.playerItem, selected: $playerSelected) }
            else if MediaFixture.name.hasPrefix("Photo Swipe") { PhotoSwipeScreen() }
            else if MediaFixture.name.hasPrefix("Trash") { MediaReviewScreen(category: .otherPhotos, screenTitle: "Trash") }
            else if MediaFixture.name.hasPrefix("Photos /") || MediaFixture.name == "Videos / cats" { MediaCategoriesScreen(video: FidelityPreview.section == "Videos") }
            else { MediaReviewScreen(category: MediaFixture.category) }
        }
    }
}
private extension MediaCategory {
    var shortTitle: String {
        switch self {
        case .duplicatePhotos, .duplicateVideos: "Duplicates"
        case .similarPhotos, .similarVideos: "Similar"
        case .otherPhotos, .otherVideos: "Other"
        case .screenRecordings: "Screen recordings"
        case .largeVideos: "Large videos"
        default: title
        }
    }
    var scanTitle: String {
        switch self {
        case .duplicatePhotos: "Duplicate photos"
        case .similarPhotos: "Similar photos"
        case .duplicateVideos: "Duplicate videos"
        default: shortTitle
        }
    }
    var scanColor: Color {
        switch self {
        case .duplicatePhotos: Color(hex: 0x627FDF)
        case .similarPhotos: Color(hex: 0x829CF0)
        case .screenshots: Color(hex: 0xB6A3DE)
        case .duplicateVideos, .similarVideos: Color(hex: 0xFF9189)
        case .screenRecordings: Color(hex: 0xEAC078)
        default: Color(hex: 0xE45C6C)
        }
    }
}
private let scanCategories: [MediaCategory] = [.duplicatePhotos, .similarPhotos, .screenshots, .duplicateVideos, .screenRecordings, .largeVideos]
struct ScanScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(MediaLibrary.self) private var library
    @State private var review = false
    private var scanning: Bool { MediaFixture.active ? MediaFixture.name.contains("Scanning") : library.isScanning }
    var body: some View {
        CleanerPage(title: "Smart Scan") {
            if scanning {
                GeometryReader { geometry in
                    let scale = min(1, geometry.size.width / 343, max(0.4, (geometry.size.height - 72) / 344))
                    VStack(spacing: 24) {
                    ZStack {
                        Image("ScanBeach").resizable().scaledToFit().frame(width: 150, height: 184).offset(x: -80, y: -65)
                        Image("ScanVideo").resizable().scaledToFit().frame(width: 147, height: 160).offset(x: 91, y: -75)
                        Image("ScanFlowers").resizable().scaledToFit().frame(width: 155, height: 162).offset(x: -72, y: 84)
                        Image("ScanCat").resizable().scaledToFit().frame(width: 157, height: 177).offset(x: 82, y: 88)
                        ZStack {
                            Circle().fill(.white)
                            Circle().stroke(Color(hex: 0xE6ECF7), lineWidth: 16).padding(12)
                            Circle().trim(from: 0, to: MediaFixture.active ? 0.64 : library.progress).rotation(.degrees(-90)).stroke(CleanerStyle.blue, style: StrokeStyle(lineWidth: 24, lineCap: .round)).padding(12)
                            Text("\(Int((MediaFixture.active ? 0.64 : library.progress) * 100))%").font(CleanerStyle.font(40, .bold)).dynamicTypeSize(...DynamicTypeSize.large)
                        }.frame(width: 200, height: 200)
                    }.frame(width: 343, height: 344).scaleEffect(scale).frame(height: 344 * scale)
                    Text("Scanning your photos and videos…").font(CleanerStyle.font(16)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }.frame(width: geometry.size.width, height: geometry.size.height)
                }.containerRelativeFrame(.vertical) { height, _ in max(dynamicType.isAccessibilitySize ? 560 : 260, height - 52) }
            } else if !MediaFixture.active, let error = library.error { MediaAccessError(message: error) }
            else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(MediaFixture.active ? "8.5 GB" : formattedBytes(reviewBytes)).font(CleanerStyle.font(40, .semibold)).fixedSize(horizontal: false, vertical: true).frame(minHeight: 48)
                    Text(MediaFixture.active ? "can be freed" : "available to review").foregroundStyle(CleanerStyle.secondary).fixedSize(horizontal: false, vertical: true).frame(minHeight: 24)
                    ScanCategoryBar().frame(height: 16)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
                MediaScanNotice()
                VStack(spacing: 8) {
                    ForEach(scanCategories) { category in
                        NavigationLink { MediaReviewScreen(category: category) } label: { MediaCategoryRow(category: category, scan: true) }
                    }
                }
            }
        }.safeAreaInset(edge: .bottom) {
            if !scanning && (MediaFixture.active || library.error == nil) {
                PrimaryButton(title: "Clean up") { review = true }.padding(16).background(CleanerStyle.bg)
            }
        }.buttonStyle(.plain).navigationDestination(isPresented: $review) {
            MediaReviewScreen(category: .otherPhotos, restrictedIDs: Set(scanCategories.flatMap { library.items(in: $0) }.map(\.id)).subtracting(library.groups.map(\.bestID)), screenTitle: "Smart Scan")
        }
            .task { if !MediaFixture.active && library.progress == 0 { await library.scan() } }
            .refreshable { if !MediaFixture.active { await library.scan() } }
    }
    private var reviewBytes: Int64 { Dictionary(scanCategories.flatMap { library.items(in: $0) }.map { ($0.id, $0.bytes) }, uniquingKeysWith: { first, _ in first }).values.reduce(0,+) }
}
private struct ScanCategoryBar: View {
    @Environment(MediaLibrary.self) private var library
    var body: some View {
        let sizes: [Double] = MediaFixture.active ? [32,40,32,48,32,127] : uniqueSizes
        let total = sizes.reduce(0,+)
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(scanCategories.enumerated()), id: \.element.id) { index, category in category.scanColor.frame(width: total > 0 ? geometry.size.width * sizes[index] / total : 0) }
            }
        }.background(CleanerStyle.track).clipShape(Capsule()).accessibilityHidden(true)
    }
    private var uniqueSizes: [Double] {
        var seen = Set<String>()
        return scanCategories.map { category in Double(library.items(in: category).reduce(Int64(0)) { $0 + (seen.insert($1.id).inserted ? $1.bytes : 0) }) }
    }
}
struct MediaAccessError: View {
    let message: String
    @Environment(MediaLibrary.self) private var library
    var body: some View {
        EmptyState(title: "Photo library", message: message, systemImage: "photo.on.rectangle")
        PrimaryButton(title: "Open Settings", action: openCleanerSettings)
        PrimaryButton(title: "Try again") { if !MediaFixture.active { Task { await library.scan() } } }
    }
}
struct MediaScanNotice: View {
    @Environment(MediaLibrary.self) private var library
    var body: some View {
        if !MediaFixture.active {
            if library.authorization == .limited {
                Text("Limited access: only selected photos are included. You can change access in Settings.").font(CleanerStyle.font(14)).foregroundStyle(CleanerStyle.secondary)
                Button("Manage photo access", action: openCleanerSettings)
            }
            if library.skippedCloudCount > 0 { Text("\(library.skippedCloudCount) files are not fully available on this device. Download originals in Photos, then scan again.").font(CleanerStyle.font(14)).foregroundStyle(CleanerStyle.secondary) }
        }
    }
}
struct MediaCategoriesScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    let video: Bool
    @Environment(MediaLibrary.self) private var library
    @AppStorage("photosIntroSeen") private var introSeen = false
    @State private var previewIntroDismissed = false
    @State private var resultDismissed = false
    private var intro: Bool { MediaFixture.active ? MediaFixture.name.contains("First visit") && !previewIntroDismissed : !video && !introSeen }
    private var counting: Bool { MediaFixture.active ? MediaFixture.name.contains("Counting") : library.isScanning }
    var body: some View {
        CleanerPage(title: video ? "Videos" : "Photos") {
            if intro { MediaIntro(artwork: "PhotosIntro", title: "Clean up your photos", message: "Find duplicates and similar shots, then choose what to keep.") }
            else if !MediaFixture.active, let error = library.error { MediaAccessError(message: error) }
            else {
                MediaScanNotice()
                ForEach(MediaCategory.allCases.filter { $0.isVideo == video }) { category in
                    NavigationLink {
                        if category == .otherPhotos { PhotoSwipeScreen() } else { MediaReviewScreen(category: category) }
                    } label: { MediaCategoryRow(category: category, counting: counting) }.allowsHitTesting(!counting)
                }
            }
        }.safeAreaInset(edge: .bottom) {
            if intro { PrimaryButton(title: "Let’s Go!") { if MediaFixture.active { previewIntroDismissed = true } else { introSeen = true } }.padding(16).background(dynamicType.isAccessibilitySize ? CleanerStyle.bg : .clear) }
        }.overlay {
            if MediaFixture.active && MediaFixture.name.contains("Deleted") && !resultDismissed {
                CleanerModal(title: MediaFixture.texts.first { $0.contains(" deleted") } ?? "Deleted", message: MediaFixture.texts.first { $0.contains(" freed") } ?? "", asset: video ? "VideoSuccess" : FidelityPreview.section == "Photo Swipe" ? "SwipeSuccess" : "PhotoSuccess", onPrimary: { resultDismissed = true })
            }
        }.buttonStyle(.plain).task { if !MediaFixture.active && library.progress == 0 { await library.scan() } }
            .refreshable { if !MediaFixture.active { await library.scan() } }
    }
}
private struct MediaIntro: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    let artwork: String; let title: String; let message: String
    var body: some View {
      if dynamicType.isAccessibilitySize {
        VStack(spacing: 16) {
            Image(artwork).resizable().scaledToFit().frame(maxWidth: 328).frame(height: 240).accessibilityHidden(true)
            Text(title).font(CleanerStyle.font(24, .semibold)).fixedSize(horizontal: false, vertical: true)
            Text(message).font(CleanerStyle.font(16)).foregroundStyle(CleanerStyle.secondary).fixedSize(horizontal: false, vertical: true)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 16)
      } else {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                Image(artwork).resizable().scaledToFit().frame(maxWidth: 328).frame(height: min(360, max(160, geometry.size.height * 360 / 588))).accessibilityHidden(true)
                Text(title).font(CleanerStyle.font(24, .semibold)).multilineTextAlignment(.center).frame(minHeight: 32)
                Text(message).font(CleanerStyle.font(16)).foregroundStyle(CleanerStyle.secondary).multilineTextAlignment(.center).frame(minHeight: 48)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.containerRelativeFrame(.vertical) { height, _ in max(340, height - 52) }
      }
    }
}
struct MediaCategoryRow: View {
    let category: MediaCategory
    var scan = false
    var counting = false
    @Environment(MediaLibrary.self) private var library
    private var items: [MediaDisplayItem] { MediaFixture.active ? (0..<3).map { MediaFixture.make($0, video: category.isVideo) } : library.items(in: category).prefix(3).map(MediaDisplayItem.init) }
    private var subtitle: String {
        if MediaFixture.active {
            let title = scan ? category.scanTitle : category.shortTitle
            if let i = MediaFixture.texts.firstIndex(of: title), MediaFixture.texts.indices.contains(i+1), MediaFixture.texts[i+1].contains("·") { return MediaFixture.texts[i+1] }
            return category.isVideo ? "3 videos · 720 MB" : "340 photos · 1.8 GB"
        }
        let all = library.items(in: category)
        return "\(all.count) \(scan ? "items" : category.isVideo ? "videos" : "photos") · \(formattedBytes(all.reduce(0) { $0 + $1.bytes }))"
    }
    var body: some View {
        HStack(spacing: 8) {
            if scan { RoundedRectangle(cornerRadius: 4).fill(category.scanColor).frame(width: 8, height: 32) }
            VStack(alignment: .leading, spacing: scan ? 0 : 8) {
                Text(scan ? category.scanTitle : category.shortTitle).font(CleanerStyle.font(16, .semibold)).frame(minHeight: 24)
                if counting { CleanerLoadingRing().accessibilityLabel("Counting…") }
                else { Text(subtitle).font(CleanerStyle.font(16)).foregroundStyle(CleanerStyle.secondary).frame(minHeight: 24) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            ZStack(alignment: .leading) {
                ForEach(Array(items.enumerated()).reversed(), id: \.element.id) { index, item in
                    DisplayThumbnail(item: item).frame(width: 56, height: scan ? 48 : 64).clipShape(RoundedRectangle(cornerRadius: 8)).offset(x: CGFloat(index) * 32)
                }
            }.frame(width: 104, height: scan ? 48 : 64, alignment: .leading).clipped()
        }.padding(.leading, scan ? 8 : 16).frame(minHeight: scan ? 72 : 96).background(.white, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(CleanerStyle.ink)
    }
}

private enum MediaSort: String, Identifiable, CaseIterable {
    case largest = "Largest", smallest = "Smallest", newest = "Newest", oldest = "Oldest"
    var id: String { rawValue }
}
struct MediaReviewScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    let category: MediaCategory
    var restrictedIDs: Set<String>? = nil
    var screenTitle: String? = nil
    var onCleanupComplete: (() -> Void)? = nil
    @Environment(MediaLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected = Set<String>()
    @State private var sort = MediaSort.newest
    @State private var initialized = false
    @State private var confirm = false
    @State private var busy = false
    @State private var error: String?
    @State private var result: (Int, Int64)?
    @State private var preview: MediaDisplayItem?
    private var groups: [DisplayGroup] {
        if MediaFixture.active { return MediaFixture.groups(video: category.isVideo) }
        if restrictedIDs != nil { return [] }
        return library.groups(in: category).enumerated().map { index, group in
            DisplayGroup(id: group.id, title: "Group \(index + 1) · \(group.items.count) \(category.isVideo ? "videos" : "photos")", items: group.items.map(MediaDisplayItem.init), bestID: group.bestID)
        }
    }
    private var items: [MediaDisplayItem] {
        if MediaFixture.active && !groups.isEmpty { return groups.flatMap(\.items) }
        let source = restrictedIDs.map { ids in library.items.filter { ids.contains($0.id) } } ?? library.items(in: category)
        let display = MediaFixture.active ? MediaFixture.items(video: category.isVideo) : source.map(MediaDisplayItem.init)
        return display.sorted { a,b in
            switch sort {
            case .largest: return a.bytes > b.bytes
            case .smallest: return a.bytes < b.bytes
            case .newest: return (a.date ?? .distantPast) > (b.date ?? .distantPast)
            case .oldest: return (a.date ?? .distantPast) < (b.date ?? .distantPast)
            }
        }
    }
    private var selectable: Set<String> { Set(items.map(\.id)).subtracting(groups.map(\.bestID)) }
    private var trash: Bool { screenTitle == "Trash" }
    private var selectedBytes: Int64 { items.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.bytes } }
    private var deleteTitle: String {
        if busy { return "Deleting…" }
        if selected.isEmpty { return category.isVideo ? "Delete videos" : "Delete photos" }
        if MediaFixture.active, selected == selectable, let text = MediaFixture.texts.last, text.hasPrefix("Delete ") { return text }
        return "Delete \(selected.count) \(screenTitle == "Smart Scan" ? "Items" : category.isVideo ? "Videos" : "Photos"), \(formattedBytes(selectedBytes))"
    }
    var body: some View {
        Group {
            if result != nil { MediaCategoriesScreen(video: category.isVideo) }
            else {
                VStack(spacing: 16) {
                    CleanerHeader(title: screenTitle ?? category.shortTitle)
                    if !MediaFixture.active && library.isScanning { ProgressView("Analysing your library…").frame(maxWidth: .infinity) }
                    else if !MediaFixture.active, let error = library.error { MediaAccessError(message: error) }
                    else if items.isEmpty { EmptyState(title: "Nothing here", message: "There are no files in this category.", systemImage: "photo.on.rectangle") }
                    else if dynamicType.isAccessibilitySize {
                        ScrollView {
                            VStack(spacing: 16) {
                                if category.isVideo && groups.isEmpty { sortTabs }
                                selectionRow
                                libraryContent
                            }.padding(.horizontal, 16).padding(.bottom, 8)
                        }
                    } else {
                        VStack(spacing: 16) {
                            if category.isVideo && groups.isEmpty { sortTabs }
                            selectionRow
                        }.padding(.horizontal, 16)
                        ScrollView { libraryContent.padding(.horizontal, 16).padding(.bottom, 8) }
                    }
                    if items.isEmpty { Spacer() }
                }.background(CleanerStyle.bg.ignoresSafeArea()).foregroundStyle(CleanerStyle.ink)
                .toolbar(.hidden, for: .navigationBar).safeAreaInset(edge: .bottom) {
                    if !items.isEmpty {
                        PrimaryButton(title: deleteTitle, disabled: selected.isEmpty || busy, disabledFill: category.isVideo ? Color(hex: 0xDFE6F0) : Color(hex: 0xDDE4F0), disabledInk: category.isVideo ? CleanerStyle.secondary : Color(hex: 0x626E80)) { confirm = true }.padding(16).background(CleanerStyle.bg)
                    }
                }
            }
        }
        .confirmationDialog("Delete \(selected.count) items?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Delete selected items", role: .destructive) { Task { await deleteSelected() } }
        } message: { Text("They will be removed from your photo library on all synced devices. Photos keeps them in Recently Deleted for recovery.") }
        .alert("Unable to delete", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .sheet(item: $preview) { item in
            MediaPreviewScreen(display: item, selected: Binding(get: { selected.contains(item.id) }, set: { value in if value { selected.insert(item.id) } else { selected.remove(item.id) } }))
        }
        .onAppear {
            guard !initialized else { return }; initialized = true
            selected = MediaFixture.active && MediaFixture.noSelection ? [] : selectable
            if MediaFixture.active {
                if MediaFixture.name.contains("Oldest") { sort = .oldest }
                else if category.isVideo {
                    let index = MediaFixture.name.dropLast().last.flatMap { Int(String($0)) } ?? 0
                    sort = [MediaSort.largest,.smallest,.newest,.oldest][min(index,3)]
                }
            } else { sort = category.isVideo ? .largest : .newest }
        }
        .onChange(of: items.map(\.id)) { _, ids in selected.formIntersection(Set(ids)) }
        .overlay {
            if let result {
                let noun = screenTitle == "Smart Scan" ? "item" : category.isVideo ? "video" : "photo"
                CleanerModal(title: "\(result.0) \(noun)\(result.0 == 1 ? "" : "s") deleted", message: MediaFixture.active ? "\(formattedBytes(result.1)) freed" : "\(formattedBytes(result.1)) in Recently Deleted", asset: category.isVideo ? "VideoSuccess" : trash ? "SwipeSuccess" : "PhotoSuccess", onPrimary: {
                    self.result = nil
                    if let onCleanupComplete { onCleanupComplete() } else { dismiss() }
                })
            }
        }
    }
    private var sortTabs: some View {
        let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            ForEach(MediaSort.allCases) { value in
                Button { sort = value } label: {
                    Text(value.rawValue).font(CleanerStyle.font(16, sort == value ? .semibold : .regular)).padding(8).frame(minHeight: 40).background(sort == value ? Color(hex: 0xDCE9FF) : .clear, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(sort == value ? CleanerStyle.blue : CleanerStyle.secondary)
                }.frame(maxWidth: .infinity)
            }
        }.buttonStyle(.plain)
    }
    private var selectionRow: some View {
        let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
        return layout {
            if !category.isVideo && groups.isEmpty && !trash {
                Menu {
                    Button("Newest") { sort = .newest }; Button("Oldest") { sort = .oldest }
                } label: { HStack(spacing: 8) { Text(sort.rawValue); Image(systemName: "chevron.down").font(.system(size: 12)) } }.foregroundStyle(CleanerStyle.blue)
            } else {
                Text(groups.isEmpty ? "\(items.count) \(category.isVideo ? "videos" : "photos")" : "\(groups.count) groups").foregroundStyle(CleanerStyle.secondary)
            }
            if !dynamicType.isAccessibilitySize { Spacer() }
            Button(selected.isEmpty ? "Select all" : "Deselect all") { selected = selected.isEmpty ? selectable : [] }.foregroundStyle(CleanerStyle.blue).font(CleanerStyle.font(16, .semibold))
        }.font(CleanerStyle.font(16)).frame(minHeight: 24).buttonStyle(.plain)
    }
    @ViewBuilder private var libraryContent: some View {
        if !groups.isEmpty {
            LazyVStack(spacing: 8) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title).font(CleanerStyle.font(16, .semibold)).frame(minHeight: 24)
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(group.items) { item in mediaCell(item, best: item.id == group.bestID).frame(width: category.isVideo ? 144 : 96, height: category.isVideo ? 144 : 96) }
                            }
                        }.scrollIndicators(.hidden)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        } else if category.isVideo {
            LazyVStack(spacing: 8) { ForEach(items) { item in videoRow(item) } }
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 3), alignment: .leading, spacing: 8) {
                ForEach(items) { item in mediaCell(item).aspectRatio(1, contentMode: .fit) }
            }.frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 328, alignment: .leading)
        }
    }
    private func toggle(_ item: MediaDisplayItem) { if !selected.insert(item.id).inserted { selected.remove(item.id) } }
    private func selectionButton(_ item: MediaDisplayItem) -> some View {
        Button { toggle(item) } label: {
            ZStack {
                Circle().fill(selected.contains(item.id) ? Color(hex: 0x1CB450) : Color(hex: 0xE2E8F2))
                if selected.contains(item.id) { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white) }
            }.frame(width: 24, height: 24).frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(selected.contains(item.id) ? "Deselect item" : "Select item")
    }
    private func mediaCell(_ item: MediaDisplayItem, best: Bool = false) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Button { preview = item } label: {
                    DisplayThumbnail(item: item).frame(width: geometry.size.width, height: geometry.size.height)
                }.buttonStyle(.plain).accessibilityLabel(item.video ? "Preview video" : "Preview photo").accessibilityValue(item.title)
                if !best { selectionButton(item).offset(x: 4, y: -4) }
                if best {
                    VStack { if !item.video { Spacer() }; HStack { Label("Best", systemImage: "star.fill").font(CleanerStyle.font(16, .semibold)).dynamicTypeSize(...DynamicTypeSize.large).foregroundStyle(.white).padding(.horizontal, 8).frame(height: 24).background(LinearGradient(colors: [Color(hex: 0xFE8301), Color(hex: 0xFFB700)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 8)); Spacer(minLength: 0) }; if item.video { Spacer() } }.dynamicTypeSize(...DynamicTypeSize.large).padding(item.video ? 8 : 6).allowsHitTesting(false)
                }
                if item.video {
                    VStack { Spacer(); HStack { VStack(alignment: .leading, spacing: 0) { Text(timeText(item.duration)).frame(height: 24); Text(formattedBytes(item.bytes)).frame(height: 24) }.font(CleanerStyle.font(16)).foregroundStyle(.white).padding(.horizontal, 8).background(Color(hex: 0x192335).opacity(0.9), in: RoundedRectangle(cornerRadius: 8)); Spacer(minLength: 0) } }.dynamicTypeSize(...DynamicTypeSize.large).padding(8).allowsHitTesting(false)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    private func videoRow(_ item: MediaDisplayItem) -> some View {
        HStack(spacing: 8) {
            Button { preview = item } label: {
                DisplayThumbnail(item: item).frame(width: 96, height: 72).overlay(alignment: .bottomLeading) {
                    Text(timeText(item.duration)).font(CleanerStyle.font(16, .semibold)).dynamicTypeSize(...DynamicTypeSize.large).foregroundStyle(.white).padding(.horizontal, 8).frame(height: 24).background(Color(hex: 0x23324A))
                }.clipShape(RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(CleanerStyle.font(16, .semibold)).lineLimit(dynamicType.isAccessibilitySize ? nil : 1).fixedSize(horizontal: false, vertical: true).frame(minHeight: 24)
                Text(item.sizeLabel ?? (item.bytes > 0 ? formattedBytes(item.bytes) : "Size unavailable")).font(CleanerStyle.font(16)).foregroundStyle(CleanerStyle.secondary).frame(minHeight: 24)
            }.frame(maxWidth: .infinity, alignment: .leading)
            selectionButton(item).frame(width: 24)
        }.padding(16).frame(minHeight: 104).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
    private func deleteSelected() async {
        guard !MediaFixture.active else { result = (selected.count, selectedBytes); selected = []; return }
        busy = true; defer { busy = false }
        let ids = selected.intersection(Set(items.compactMap { $0.media?.id }))
        guard !ids.isEmpty else { return }
        let bytes = items.filter { ids.contains($0.id) }.reduce(Int64(0)) { $0 + $1.bytes }
        do { try await library.delete(ids: ids); selected = []; result = (ids.count, bytes) }
        catch { self.error = error.localizedDescription }
    }
}
private func timeText(_ duration: TimeInterval) -> String {
    let seconds = max(0, Int(duration.isFinite ? duration : 0))
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

struct MediaPreviewScreen: View {
    let display: MediaDisplayItem
    @Binding var selected: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var elapsed = 0.0
    @State private var playing = false
    @State private var scrubbing = false
    @State private var reload = 0
    init(display: MediaDisplayItem, selected: Binding<Bool>) { self.display = display; _selected = selected }
    init(item: MediaItem) { display = MediaDisplayItem(item); _selected = .constant(false) }
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Button { dismiss() } label: { Image("BackIcon").resizable().scaledToFit().frame(width: 32, height: 32).frame(width: 44, height: 44).contentShape(Rectangle()).padding(-6) }.accessibilityLabel("Back")
                Text(display.title).font(CleanerStyle.font(24, .semibold)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Button { selected.toggle() } label: { ContactCheck(selected: selected).frame(width: 44, height: 44).contentShape(Rectangle()).padding(.horizontal, -10).padding(.vertical, -6) }.accessibilityLabel(selected ? "Deselect item" : "Select item")
            }.frame(minHeight: 32)
            GeometryReader { geometry in
                ZStack {
                    if let player { CleanerVideoSurface(player: player) }
                    else if failed { VStack { EmptyState(title: "Video unavailable", message: "Check your connection and try again.", systemImage: "video.slash"); PrimaryButton(title: "Try again") { reload += 1 } }.padding(16) }
                    else if MediaFixture.active || !display.video {
                        DisplayThumbnail(item: display, preview: true).frame(width: geometry.size.width, height: geometry.size.height)
                    } else { ProgressView("Loading video…") }
                    if display.video && !failed && (player != nil || MediaFixture.active) {
                        Button {
                            if playing { player?.pause(); playing = false }
                            else {
                                if elapsed >= max(0, display.duration - 0.1) { elapsed = 0; player?.seek(to: .zero) }
                                player?.play(); playing = true
                            }
                        } label: { Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 24)).foregroundStyle(.white).frame(width: 56, height: 56).background(CleanerStyle.blue, in: Circle()) }.accessibilityLabel(playing ? "Pause" : "Play")
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if display.video {
                VStack(spacing: 8) {
                    GeometryReader { proxy in
                        Capsule().fill(Color(hex: 0xDDE4F0))
                            .overlay(alignment: .leading) { Capsule().fill(CleanerStyle.blue).frame(width: proxy.size.width * min(1, max(0, elapsed / max(1, display.duration)))) }
                            .frame(height: 8).padding(.vertical, 18).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { value in scrubbing = true; elapsed = min(display.duration, max(0, value.location.x / max(1, proxy.size.width) * display.duration)) }.onEnded { _ in
                                let target = elapsed
                                if let player { player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in Task { @MainActor in scrubbing = false } } }
                                else { scrubbing = false }
                            }).padding(.vertical, -18)
                    }.frame(height: 8).accessibilityElement().accessibilityLabel("Playback position")
                        .accessibilityValue(timeText(elapsed)).accessibilityAdjustableAction { direction in
                            elapsed = min(display.duration, max(0, elapsed + (direction == .increment ? 5 : -5)))
                            player?.seek(to: CMTime(seconds: elapsed, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                        }
                    HStack { Text(timeText(elapsed)); Spacer(); Text(timeText(display.duration)) }.font(CleanerStyle.font(16)).frame(minHeight: 24)
                    Text(metadata).font(CleanerStyle.font(16)).foregroundStyle(CleanerStyle.secondary).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 24)
                }.frame(minHeight: 72)
            }
        }.padding(16).background(CleanerStyle.bg.ignoresSafeArea()).foregroundStyle(CleanerStyle.ink).toolbar(.hidden, for: .navigationBar)
        .task(id: reload) {
            guard !MediaFixture.active, let media = display.media, media.isVideo else { return }
            failed = false; elapsed = 0; playing = false
            if let playback = await MediaLibrary.playbackItem(for: media), !Task.isCancelled { player = AVPlayer(playerItem: playback) }
            else { failed = true }
        }
        .task(id: player != nil) {
            while !Task.isCancelled && player != nil {
                if player?.currentItem?.status == .failed { failed = true; playing = false; player = nil; break }
                if !scrubbing {
                    let seconds = player?.currentTime().seconds ?? 0
                    elapsed = seconds.isFinite ? max(0, seconds) : 0
                }
                playing = player?.timeControlStatus == .playing || player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .onDisappear { player?.pause() }
    }
    private var metadata: String {
        if MediaFixture.active { return MediaFixture.texts.last ?? "" }
        let size = display.bytes == 0 ? "Size unavailable" : formattedBytes(display.bytes)
        return display.date.map { size + " · " + $0.formatted(.dateTime.month(.abbreviated).day().year()) } ?? size
    }
}

private struct CleanerVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    func makeUIView(context: Context) -> Surface { let view = Surface(); view.videoLayer.player = player; view.videoLayer.videoGravity = .resizeAspect; return view }
    func updateUIView(_ view: Surface, context: Context) { view.videoLayer.player = player }
}

struct PhotoSwipeScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(MediaLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage("photoSwipeIntroSeen") private var introSeen = false
    @State private var previewIntroDismissed = false
    @State private var reviewed = Set<String>()
    @State private var trash = Set<String>()
    @State private var offset: CGFloat = 0
    @State private var history: [(String, Bool)] = []
    @State private var showTrash = false
    private var tutorial: Bool { MediaFixture.active ? MediaFixture.name.contains("Tutorial") && !previewIntroDismissed : !introSeen }
    private var allItems: [MediaDisplayItem] { MediaFixture.active ? (0..<340).map { MediaFixture.make($0) } : library.items(in: .otherPhotos).map(MediaDisplayItem.init) }
    private var remaining: [MediaDisplayItem] { allItems.filter { !reviewed.contains($0.id) } }
    private var previewIndex: Int { MediaFixture.name.contains("after") ? 12 : 11 }
    private var currentIndex: Int { MediaFixture.active ? previewIndex + reviewed.count : reviewed.count }
    private var displayed: [MediaDisplayItem] { MediaFixture.active ? Array(remaining.dropFirst(previewIndex)) : remaining }
    private var trashCount: Int { MediaFixture.active ? (MediaFixture.name.contains("afterDelete") ? 18 : 17) + trash.count : trash.intersection(Set(allItems.map(\.id))).count }
    private var gestureOffset: CGFloat {
        if offset != 0 { return offset }
        if MediaFixture.active && MediaFixture.name.hasSuffix("/ delete") { return -176 }
        if MediaFixture.active && MediaFixture.name.hasSuffix("/ keep") { return 179 }
        return 0
    }
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Button { dismiss() } label: { Image("BackIcon").resizable().scaledToFit().frame(width: 32, height: 32).frame(width: 44, height: 44).contentShape(Rectangle()).padding(-6) }.accessibilityLabel("Back")
                Text("Photo Swipe").font(CleanerStyle.font(24, .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                if !tutorial && !dynamicType.isAccessibilitySize { Button("Trash (\(trashCount))") { showTrash = true }.font(CleanerStyle.font(16, .semibold)).foregroundStyle(CleanerStyle.blue) }
            }.frame(minHeight: 32)
            if !tutorial && dynamicType.isAccessibilitySize { Button("Trash (\(trashCount))") { showTrash = true }.font(CleanerStyle.font(16, .semibold)).foregroundStyle(CleanerStyle.blue) }
            if tutorial {
                ScrollView { MediaIntro(artwork: "SwipeIntro", title: "Sort your photos", message: "Swipe right to keep a photo or left to move it to Trash.") }
                PrimaryButton(title: "Got it") { if MediaFixture.active { previewIntroDismissed = true } else { introSeen = true } }
            } else if let item = displayed.first {
                HStack {
                    Text("\(min(currentIndex + 1, allItems.count)) / \(allItems.count)").font(CleanerStyle.font(16)).dynamicTypeSize(...DynamicTypeSize.large).padding(.horizontal, 8).frame(height: 24).background(.white, in: Capsule())
                    Spacer()
                    if !history.isEmpty { Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }.accessibilityLabel("Undo last choice") }
                }
                GeometryReader { geo in
                    ZStack {
                        ForEach(Array(displayed.prefix(3).enumerated()).reversed(), id: \.element.id) { index, card in
                            DisplayThumbnail(item: card, preview: index == 0)
                                .frame(width: max(0, geo.size.width - 39), height: geo.size.height)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                                .overlay(alignment: gestureOffset < 0 ? .topTrailing : .topLeading) {
                                    if index == 0 && abs(gestureOffset) > 30 {
                                        Text(gestureOffset < 0 ? "Delete" : "Keep").font(CleanerStyle.font(24, .semibold)).dynamicTypeSize(...DynamicTypeSize.large).foregroundStyle(Color(hex: gestureOffset < 0 ? 0x9A3340 : 0x185D49)).padding(.horizontal, 16).padding(.vertical, 8).background(Color(hex: gestureOffset < 0 ? 0xFFE8EA : 0xDFF5E9), in: RoundedRectangle(cornerRadius: 16)).padding(16)
                                    }
                                }
                                .rotationEffect(.degrees(index == 0 ? (MediaFixture.active && offset == 0 ? (gestureOffset == 0 ? 0 : gestureOffset < 0 ? -8 : 8) : min(12, max(-12, Double(gestureOffset / 22)))) : index == 1 ? -8 : 8))
                                .offset(x: index == 0 ? gestureOffset : index == 1 ? -12 : 16, y: index == 0 ? -10 : CGFloat(index * 8))
                                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                        }
                    }.frame(width: geo.size.width, height: geo.size.height)
                    .gesture(DragGesture().onChanged { offset = $0.translation.width }.onEnded { value in
                        if abs(value.translation.width) > 80 { decide(item, deleting: value.translation.width < 0) }
                        withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
                    })
                }.padding(.top, 10)
                HStack(spacing: 8) {
                    Button { decide(item, deleting: true) } label: { Text("Delete").frame(maxWidth: .infinity).frame(height: 56).background(Color(hex: 0xCD0000).opacity(0.2), in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(Color(hex: 0xCD0000)) }
                    Button { decide(item, deleting: false) } label: { Text("Keep").frame(maxWidth: .infinity).frame(height: 56).background(Color(hex: 0x1CB450), in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.white) }
                }.font(CleanerStyle.font(16, .semibold)).padding(.horizontal, 7.5)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(allItems.dropFirst(max(0,currentIndex-2)).prefix(12).enumerated()), id: \.element.id) { index, thumb in
                            DisplayThumbnail(item: thumb).frame(width: index == 2 ? 64 : 48, height: index == 2 ? 64 : 48).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }.frame(height: 64)
                }.scrollIndicators(.hidden)
            } else { EmptyState(title: "You're all caught up", message: "Review Trash to finish, or undo your last choice.", systemImage: "checkmark.circle"); if !history.isEmpty { Button("Undo last choice", action: undo) }; Spacer() }
        }.padding(16).background(CleanerStyle.bg.ignoresSafeArea()).foregroundStyle(CleanerStyle.ink).buttonStyle(.plain).toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showTrash) { MediaReviewScreen(category: .otherPhotos, restrictedIDs: trash, screenTitle: "Trash", onCleanupComplete: { dismiss() }) }
        .onChange(of: library.items.map(\.id)) { _, ids in
            guard !MediaFixture.active else { return }; trash.formIntersection(Set(ids)); reviewed.formIntersection(Set(ids))
        }
    }
    private func decide(_ item: MediaDisplayItem, deleting: Bool) {
        reviewed.insert(item.id); if deleting { trash.insert(item.id) }; history.append((item.id, deleting))
    }
    private func undo() { guard let last = history.popLast() else { return }; reviewed.remove(last.0); trash.remove(last.0) }
}
