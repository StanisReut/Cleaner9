import SwiftUI
import Photos
import AVFoundation
import CryptoKit
import Vision
import Observation

nonisolated enum MediaCategory: String, CaseIterable, Identifiable, Sendable {
    case duplicatePhotos, similarPhotos, screenshots, otherPhotos
    case duplicateVideos, similarVideos, screenRecordings, largeVideos, otherVideos
    var id: String { rawValue }
    var isVideo: Bool { [.duplicateVideos, .similarVideos, .screenRecordings, .largeVideos, .otherVideos].contains(self) }
    var title: String {
        switch self {
        case .duplicatePhotos: "Duplicate Photos"
        case .similarPhotos: "Similar Photos"
        case .screenshots: "Screenshots"
        case .otherPhotos: "Other Photos"
        case .duplicateVideos: "Duplicate Videos"
        case .similarVideos: "Similar Videos"
        case .screenRecordings: "Screen Recordings"
        case .largeVideos: "Large Videos"
        case .otherVideos: "Other Videos"
        }
    }
}

nonisolated struct MediaItem: Identifiable, Hashable, @unchecked Sendable {
    let id: String
    let asset: PHAsset
    /// Zero means size could not be measured locally. No estimated sizes are used.
    let bytes: Int64
    let fingerprint: String?
    var isVideo: Bool { asset.mediaType == .video }
    var duration: TimeInterval { asset.duration }
    var creationDate: Date? { asset.creationDate }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

nonisolated struct MediaGroup: Identifiable, Sendable {
    let id: String
    let category: MediaCategory
    let items: [MediaItem]
    let bestID: String
}

@MainActor @Observable final class MediaLibrary {
    var items: [MediaItem] = []
    var groups: [MediaGroup] = []
    var isScanning = false
    var progress = 0.0
    var error: String?
    var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var skippedCloudCount = 0
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    /// Call when the app becomes active after Settings or Photos. This never prompts.
    func refreshAccess() {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let changed = current != authorization
        authorization = current
        guard current == .authorized || current == .limited else {
            items = []; groups = []; skippedCloudCount = 0; progress = 0
            if current != .notDetermined { error = "Allow photo access in Settings to scan your library." }
            return
        }
        let available = PHAsset.fetchAssets(withLocalIdentifiers: items.map(\.id), options: nil)
        var availableIDs: Set<String> = []
        available.enumerateObjects { asset, _, _ in availableIDs.insert(asset.localIdentifier) }
        removeFromResults(Set(items.map(\.id)).subtracting(availableIDs))
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        let hasUnscannedItems = PHAsset.fetchAssets(with: options).count != items.count
        if changed || hasUnscannedItems { error = nil; progress = 0 }
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        error = nil
        progress = 0
        defer { isScanning = false }
        authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard authorization == .authorized || authorization == .limited else {
            items = []; groups = []; skippedCloudCount = 0
            error = "Allow photo access in Settings to scan your library."
            return
        }
        let worker = Task.detached(priority: .utility) {
            try await LibraryScanner.scan { value in
                await MainActor.run { self.progress = value }
            }
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            items = result.items
            groups = result.groups
            skippedCloudCount = result.skipped
            progress = 1
            refreshAccess()
        } catch is CancellationError {
            error = "Scan cancelled. You can scan again."
        } catch { self.error = error.localizedDescription }
    }

    func groups(in category: MediaCategory) -> [MediaGroup] { groups.filter { $0.category == category } }

    func items(in category: MediaCategory) -> [MediaItem] {
        let grouped = Set(groups(in: category).flatMap(\.items).map(\.id))
        switch category {
        case .duplicatePhotos, .similarPhotos, .duplicateVideos, .similarVideos:
            return items.filter { grouped.contains($0.id) }
        case .screenshots: return items.filter { !$0.isVideo && $0.asset.mediaSubtypes.contains(.photoScreenshot) }
        case .screenRecordings: return items.filter { $0.isVideo && $0.asset.mediaSubtypes.contains(.videoScreenRecording) }
        case .largeVideos: return items.filter { $0.isVideo && $0.bytes >= 1_000_000_000 }
        case .otherPhotos, .otherVideos:
            let assigned = Set(groups.flatMap(\.items).map(\.id))
            return items.filter {
                $0.isVideo == category.isVideo && !assigned.contains($0.id)
                && !$0.asset.mediaSubtypes.contains(.photoScreenshot)
                && !$0.asset.mediaSubtypes.contains(.videoScreenRecording)
                && (!$0.isVideo || $0.bytes < 1_000_000_000)
            }
        }
    }

    func delete(ids: Set<String>) async throws {
        guard !ids.isEmpty else { return }
        guard !isScanning else {
            throw NSError(domain: "MediaLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: "Wait for the scan to finish, then try deleting again."])
        }
        refreshAccess()
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        guard assets.count == ids.count else {
            throw NSError(domain: "MediaLibrary", code: 2, userInfo: [NSLocalizedDescriptionKey: "Some selected files are no longer available. Refresh your library and review your selection again."])
        }
        try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(assets) }
        removeFromResults(ids)
    }

    private func removeFromResults(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        skippedCloudCount = items.filter { $0.fingerprint == nil }.count
        groups = groups.compactMap { group in
            let remaining = group.items.filter { !ids.contains($0.id) }
            guard remaining.count > 1 else { return nil }
            return MediaGroup(id: group.id, category: group.category, items: remaining,
                              bestID: remaining.contains { $0.id == group.bestID } ? group.bestID : remaining[0].id)
        }
    }

    nonisolated static func playbackItem(for item: MediaItem) async -> AVPlayerItem? {
        let request = ImageRequest()
        let result: AVPlayerItem? = await withTaskCancellationHandler {
          await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            let id = PHImageManager.default().requestPlayerItem(forVideo: item.asset, options: options) { player, _ in
                continuation.resume(returning: player)
            }
            request.set(id)
          }
        } onCancel: { request.cancel() }
        return Task.isCancelled ? nil : result
    }
}

nonisolated private enum LibraryScanner {
    struct Result: Sendable { let items: [MediaItem]; let groups: [MediaGroup]; let skipped: Int }

    static func scan(progress: @escaping @Sendable (Double) async -> Void) async throws -> Result {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        let assets = PHAsset.fetchAssets(with: options)
        var items: [MediaItem] = []
        var skipped = 0
        for index in 0..<assets.count {
            try Task.checkCancellation()
            let asset = assets.object(at: index)
            let resources = PHAssetResource.assetResources(for: asset)
            var signatures: [String] = []
            var bytes: Int64 = 0
            var complete = !resources.isEmpty
            for resource in resources {
                try Task.checkCancellation()
                if let result = await measure(resource) {
                    bytes += result.0
                    signatures.append("\(resource.type.rawValue):\(result.0):\(result.1)")
                } else { complete = false }
            }
            // Include every resource, including paired Live Photo videos and edits.
            // Partial/cloud assets can never be labelled exact duplicates.
            if !complete { skipped += 1 }
            items.append(MediaItem(id: asset.localIdentifier, asset: asset, bytes: complete ? bytes : 0,
                                   fingerprint: complete ? signatures.sorted().joined(separator: "|") : nil))
            await progress(Double(index + 1) / Double(max(1, assets.count)) * 0.85)
        }
        var groups: [MediaGroup] = []
        let exact = Dictionary(grouping: items.filter { $0.fingerprint != nil }, by: { "\($0.isVideo):\($0.fingerprint!)" })
        for matches in exact.values where matches.count > 1 {
            groups.append(makeGroup(matches, category: matches[0].isVideo ? .duplicateVideos : .duplicatePhotos))
        }
        let duplicates = Set(groups.flatMap(\.items).map(\.id))
        // Photos are compared only within a day, with matching aspect ratio and a
        // conservative Vision threshold.
        let candidates = items.filter { !$0.isVideo && !duplicates.contains($0.id) && !$0.asset.mediaSubtypes.contains(.photoScreenshot) }
        let days = Dictionary(grouping: candidates) { Calendar.current.startOfDay(for: $0.creationDate ?? .distantPast) }
        for day in days.values where day.count > 1 {
            var clusters: [(MediaItem, VNFeaturePrintObservation, [MediaItem])] = []
            for item in day {
                try Task.checkCancellation()
                guard let feature = await feature(for: item.asset) else { continue }
                var matched = false
                for index in clusters.indices {
                    let reference = clusters[index].0.asset
                    let ratio = Double(item.asset.pixelWidth) / Double(max(1, item.asset.pixelHeight))
                    let referenceRatio = Double(reference.pixelWidth) / Double(max(1, reference.pixelHeight))
                    guard abs(ratio - referenceRatio) < 0.03 else { continue }
                    var distance: Float = 0
                    if (try? feature.computeDistance(&distance, to: clusters[index].1)) != nil, distance < 0.20 {
                        clusters[index].2.append(item); matched = true; break
                    }
                }
                if !matched { clusters.append((item, feature, [item])) }
            }
            groups += clusters.filter { $0.2.count > 1 }.map { makeGroup($0.2, category: .similarPhotos) }
        }
        let videos = items.filter { $0.isVideo && !duplicates.contains($0.id) }
        var videoClusters: [(MediaItem, [VNFeaturePrintObservation], [MediaItem])] = []
        for (offset, item) in videos.enumerated() {
            try Task.checkCancellation()
            guard let samples = await videoFeatures(for: item.asset) else { continue }
            var matched = false
            for index in videoClusters.indices {
                let reference = videoClusters[index].0
                guard MediaMatching.videoCandidate(duration: item.duration, otherDuration: reference.duration,
                    width: item.asset.pixelWidth, height: item.asset.pixelHeight,
                    otherWidth: reference.asset.pixelWidth, otherHeight: reference.asset.pixelHeight) else { continue }
                let distances = zip(samples, videoClusters[index].1).compactMap { left, right -> Float? in
                    var distance: Float = 0
                    guard (try? left.computeDistance(&distance, to: right)) != nil else { return nil }
                    return distance
                }
                if MediaMatching.videoSamplesMatch(distances) {
                    videoClusters[index].2.append(item); matched = true; break
                }
            }
            if !matched { videoClusters.append((item, samples, [item])) }
            await progress(0.9 + Double(offset + 1) / Double(max(1, videos.count)) * 0.09)
        }
        groups += videoClusters.filter { $0.2.count > 1 }.map { makeGroup($0.2, category: .similarVideos) }
        return Result(items: items, groups: groups.sorted { $0.id < $1.id }, skipped: skipped)
    }

    static func makeGroup(_ items: [MediaItem], category: MediaCategory) -> MediaGroup {
        let sorted = items.sorted {
            if $0.asset.isFavorite != $1.asset.isFavorite { return $0.asset.isFavorite }
            let left = $0.asset.pixelWidth * $0.asset.pixelHeight
            let right = $1.asset.pixelWidth * $1.asset.pixelHeight
            return left == right ? $0.id < $1.id : left > right
        }
        return MediaGroup(id: category.rawValue + sorted.map(\.id).sorted().joined(), category: category, items: sorted, bestID: sorted[0].id)
    }

    static func measure(_ resource: PHAssetResource) async -> (Int64, String)? {
        let accumulator = ResourceAccumulator()
        let request = ResourceRequest()
        return await withTaskCancellationHandler {
          await withCheckedContinuation { continuation in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = false
            let id = PHAssetResourceManager.default().requestData(for: resource, options: options, dataReceivedHandler: { data in
                accumulator.append(data)
            }, completionHandler: { error in
                continuation.resume(returning: error == nil ? accumulator.finish() : nil)
            })
            request.set(id)
          }
        } onCancel: {
            request.cancel()
        }
    }

    static func feature(for asset: PHAsset) async -> VNFeaturePrintObservation? {
        guard let image = await localImage(for: asset), let cgImage = image.cgImage else { return nil }
        return feature(cgImage)
    }

    static func feature(_ cgImage: CGImage) -> VNFeaturePrintObservation? {
        return autoreleasepool {
            let request = VNGenerateImageFeaturePrintRequest()
            request.revision = VNGenerateImageFeaturePrintRequestRevision2
            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
                return request.results?.first
            } catch { return nil }
        }
    }

    static func videoFeatures(for asset: PHAsset) async -> [VNFeaturePrintObservation]? {
        guard asset.duration.isFinite, asset.duration > 0, !Task.isCancelled else { return nil }
        let request = ImageRequest()
        let video: AVAsset? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let options = PHVideoRequestOptions()
                options.isNetworkAccessAllowed = false
                options.deliveryMode = .highQualityFormat
                let id = PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { video, _, _ in
                    continuation.resume(returning: video)
                }
                request.set(id)
            }
        } onCancel: { request.cancel() }
        guard let video, !Task.isCancelled else { return nil }
        let generator = AVAssetImageGenerator(asset: video)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 256, height: 256)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        var samples: [VNFeaturePrintObservation] = []
        // Interior start/end samples avoid container-edge decoding failures.
        for fraction in [0.05, 0.5, 0.95] {
            guard !Task.isCancelled else { generator.cancelAllCGImageGeneration(); return nil }
            do {
                let result = try await withTaskCancellationHandler {
                    try await generator.image(at: CMTime(seconds: asset.duration * fraction, preferredTimescale: 600))
                } onCancel: { generator.cancelAllCGImageGeneration() }
                guard let observation = feature(result.image) else { return nil }
                samples.append(observation)
            } catch { return nil }
        }
        return samples
    }

    static func localImage(for asset: PHAsset, preview: Bool = false) async -> UIImage? {
        let request = ImageRequest()
        return await withTaskCancellationHandler {
          await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = preview
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            let dimension = preview ? 2048 : 256
            let id = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: dimension, height: dimension), contentMode: .aspectFit, options: options) { image, info in
                guard (info?[PHImageResultIsDegradedKey] as? Bool) != true else { return }
                continuation.resume(returning: image)
            }
            request.set(id)
          }
        } onCancel: { request.cancel() }
    }
}

/// Pure constraints, independently testable without a Photos library.
nonisolated enum MediaMatching {
    static func videoCandidate(duration: Double, otherDuration: Double, width: Int, height: Int, otherWidth: Int, otherHeight: Int) -> Bool {
        guard duration.isFinite, otherDuration.isFinite, duration > 0, otherDuration > 0,
              width > 0, height > 0, otherWidth > 0, otherHeight > 0 else { return false }
        return abs(duration - otherDuration) <= min(1, min(duration, otherDuration) * 0.02)
            && abs(Double(width) / Double(height) - Double(otherWidth) / Double(otherHeight)) < 0.03
    }
    static func videoSamplesMatch(_ distances: [Float]) -> Bool {
        distances.count == 3 && distances.allSatisfy { $0.isFinite && $0 >= 0 && $0 < 0.15 }
    }
}

nonisolated private final class ImageRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var id: PHImageRequestID?
    private var cancelled = false
    func set(_ value: PHImageRequestID) {
        lock.lock(); id = value; let shouldCancel = cancelled; lock.unlock()
        if shouldCancel { PHImageManager.default().cancelImageRequest(value) }
    }
    func cancel() {
        lock.lock(); cancelled = true; let value = id; lock.unlock()
        if let value { PHImageManager.default().cancelImageRequest(value) }
    }
}

nonisolated private final class ResourceRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var id: PHAssetResourceDataRequestID?
    private var cancelled = false
    func set(_ value: PHAssetResourceDataRequestID) {
        lock.lock(); id = value; let shouldCancel = cancelled; lock.unlock()
        if shouldCancel { PHAssetResourceManager.default().cancelDataRequest(value) }
    }
    func cancel() {
        lock.lock(); cancelled = true; let value = id; lock.unlock()
        if let value { PHAssetResourceManager.default().cancelDataRequest(value) }
    }
}

nonisolated private final class ResourceAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var hash = SHA256()
    private var bytes: Int64 = 0
    func append(_ data: Data) { lock.lock(); defer { lock.unlock() }; hash.update(data: data); bytes += Int64(data.count) }
    func finish() -> (Int64, String) {
        lock.lock(); defer { lock.unlock() }
        return (bytes, hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
}

struct MediaThumbnail: View {
    let item: MediaItem
    var preview = false
    @State private var image: UIImage?
    @State private var finished = false
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.secondary.opacity(0.12)
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: preview ? .fit : .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                } else if preview && !finished { ProgressView("Loading photo…") }
                else if preview { Text("Photo unavailable. Check your connection and reopen the preview.").multilineTextAlignment(.center).padding() }
                else { Image(systemName: item.isVideo ? "video" : "photo").foregroundStyle(.secondary) }
            }
        }
        .clipped()
        .task(id: item.id) {
            image = nil
            finished = false
            let loaded = await LibraryScanner.localImage(for: item.asset, preview: preview)
            guard !Task.isCancelled else { return }
            image = loaded
            finished = true
        }
        .accessibilityLabel(item.isVideo ? "Video thumbnail" : "Photo thumbnail")
    }
}
