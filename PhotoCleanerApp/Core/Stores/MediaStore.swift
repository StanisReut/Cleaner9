import SwiftUI
import Photos
import PhotosUI
import AVFoundation
import CryptoKit
import Vision
import Observation
import UIKit
import CoreLocation

nonisolated final class VideoLocationResolver: @unchecked Sendable {
    static let shared = VideoLocationResolver()
    private let lock = NSLock()
    private var cache: [String: String] = [:]
    private let geocoder = CLGeocoder()
    private var pending = Set<String>()

    func title(for asset: PHAsset) -> String {
        if let location = asset.location {
            let key = String(format: "%.3f,%.3f", location.coordinate.latitude, location.coordinate.longitude)
            lock.lock()
            if let cached = cache[key] {
                lock.unlock()
                return cached
            }
            let shouldResolve = pending.insert(key).inserted
            lock.unlock()

            if shouldResolve {
                Task {
                    if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
                        let name = placemark.locality ?? placemark.name ?? placemark.administrativeArea
                        if let name, !name.isEmpty {
                            self.lock.lock()
                            self.cache[key] = name
                            self.pending.remove(key)
                            self.lock.unlock()
                        }
                    }
                }
            }
        }
        if let date = asset.creationDate {
            return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
        return "Video"
    }
}

@MainActor
func presentLimitedPhotoPicker() {
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
          let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
    var presenter = root
    while let presented = presenter.presentedViewController { presenter = presented }
    PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter)
}

nonisolated enum MediaCategory: String, CaseIterable, Identifiable, Codable, Sendable {
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

@MainActor @Observable final class MediaStore {
    var items: [MediaItem] = []
    var groups: [MediaGroup] = []
    var isScanning = false
    var progress = 0.0
    var error: String?
    var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var skippedCloudCount = 0
    var lastDeletedCount: Int?
    var lastDeletedBytes: Int64?
    var lastDeletedSection: String?
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    func publishDeletion(count: Int, bytes: Int64, section: String? = nil) {
        lastDeletedCount = count
        lastDeletedBytes = bytes
        lastDeletedSection = section
    }

    func clearDeletion() {
        lastDeletedCount = nil
        lastDeletedBytes = nil
        lastDeletedSection = nil
    }

    func cancelScan() {
        scanTask?.cancel()
    }

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
        if restoreCachedResultsIfCurrentLibraryMatches() {
            progress = 1
            return
        }
        let worker = Task.detached(priority: .utility) {
            try await LibraryScanner.scan { value in
                await MainActor.run { self.progress = value }
            }
        }
        scanTask = worker
        do {
            let result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            items = result.items
            groups = result.groups
            persistCachedResults()
            skippedCloudCount = result.skipped
            progress = 1
            refreshAccess()
        } catch is CancellationError {
            error = nil
            if !items.isEmpty {
                persistCachedResults()
            }
        } catch { self.error = error.localizedDescription }
        scanTask = nil
    }

    private var scanTask: Task<LibraryScanner.Result, Error>?

    private struct CachedItem: Codable { let id: String; let bytes: Int64; let fingerprint: String?; let category: MediaCategory?; let groupID: String?; let best: Bool }
    private func persistCachedResults() {
        let cache = items.map { item in
            let group = groups.first { $0.items.contains(item) }
            return CachedItem(id: item.id, bytes: item.bytes, fingerprint: item.fingerprint, category: group?.category, groupID: group?.id, best: group?.bestID == item.id)
        }
        let ids = items.map(\.id).sorted().joined(separator: "|")
        UserDefaults.standard.set(ids, forKey: "media.scan.signature")
        UserDefaults.standard.set(try? JSONEncoder().encode(cache), forKey: "media.scan.cache")
    }
    private func restoreCachedResultsIfCurrentLibraryMatches() -> Bool {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        var ids: [String] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        guard ids.sorted().joined(separator: "|") == UserDefaults.standard.string(forKey: "media.scan.signature"),
              let data = UserDefaults.standard.data(forKey: "media.scan.cache"),
              let cached = try? JSONDecoder().decode([CachedItem].self, from: data) else { return false }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: cached.map(\.id), options: nil)
        var byID: [String: PHAsset] = [:]
        assets.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        items = cached.compactMap { item in byID[item.id].map { MediaItem(id: item.id, asset: $0, bytes: item.bytes, fingerprint: item.fingerprint) } }
        let grouped = Dictionary(grouping: cached.compactMap { item -> CachedItem? in item.groupID == nil ? nil : item }, by: { $0.groupID! })
        groups = grouped.compactMap { id, values in
            let members = values.compactMap { item in items.first { $0.id == item.id } }
            guard members.count > 1, let best = values.first(where: { $0.best }) else { return nil }
            return MediaGroup(id: id, category: values.first?.category ?? .otherPhotos, items: members, bestID: best.id)
        }
        return items.count == cached.count
    }

    func groups(in category: MediaCategory) -> [MediaGroup] { groups.filter { $0.category == category } }

    func items(in category: MediaCategory) -> [MediaItem] {
        let grouped = Set(groups(in: category).flatMap(\.items).map(\.id))
        switch category {
        case .duplicatePhotos, .similarPhotos, .duplicateVideos, .similarVideos:
            return items.filter { grouped.contains($0.id) }
        case .screenshots: return items.filter { !$0.isVideo && $0.asset.mediaSubtypes.contains(.photoScreenshot) }
        case .screenRecordings: return items.filter { $0.isVideo && isScreenRecording($0.asset) }
        case .largeVideos: return items.filter { $0.isVideo && $0.bytes >= 1_000_000_000 }
        case .otherPhotos, .otherVideos:
            let assigned = Set(groups.flatMap(\.items).map(\.id))
            return items.filter {
                $0.isVideo == category.isVideo && !assigned.contains($0.id)
                && !$0.asset.mediaSubtypes.contains(.photoScreenshot)
                && !($0.isVideo && isScreenRecording($0.asset))
                && (!$0.isVideo || $0.bytes < 1_000_000_000)
            }
        }
    }

    private func isScreenRecording(_ asset: PHAsset) -> Bool {
        if asset.mediaSubtypes.contains(.videoScreenRecording) { return true }
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.contains { resource in
            let uti = resource.uniformTypeIdentifier.lowercased()
            return uti.contains("screenrecord") || uti.contains("screencapture")
        }
    }

    func delete(ids: Set<String>) async throws {
        guard !ids.isEmpty else { return }
        guard !isScanning else {
            throw NSError(domain: "MediaStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Wait for the scan to finish, then try deleting again."])
        }
        refreshAccess()
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        guard assets.count == ids.count else {
            throw NSError(domain: "MediaStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Some selected files are no longer available. Refresh your library and review your selection again."])
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
        // Some exports lose their resource signature. Treat images with the
        // same dimensions captured within one second as duplicates as well.
        let duplicateIDs = Set(groups.flatMap(\.items).map(\.id))
        let dimensionCandidates = items.filter { !$0.isVideo && !duplicateIDs.contains($0.id) }
        var dimensionGroups: [[MediaItem]] = []
        for item in dimensionCandidates {
            guard let date = item.creationDate else { continue }
            if let index = dimensionGroups.firstIndex(where: { group in
                guard let reference = group.first, let referenceDate = reference.creationDate else { return false }
                return reference.asset.pixelWidth == item.asset.pixelWidth &&
                    reference.asset.pixelHeight == item.asset.pixelHeight &&
                    abs(date.timeIntervalSince(referenceDate)) <= 1
            }) { dimensionGroups[index].append(item) }
            else { dimensionGroups.append([item]) }
        }
        for matches in dimensionGroups where matches.count > 1 { groups.append(makeGroup(matches, category: .duplicatePhotos)) }

        // Perceptual dHash matches (distance 0)
        let currentDuplicateIDs = Set(groups.flatMap(\.items).map(\.id))
        let dHashCandidates = items.filter { !$0.isVideo && !currentDuplicateIDs.contains($0.id) }
        var dHashGroups: [UInt64: [MediaItem]] = [:]
        for item in dHashCandidates {
            if let img = await localImage(for: item.asset), let cg = img.cgImage, let hash = dHash(for: cg) {
                dHashGroups[hash, default: []].append(item)
            }
        }
        for matches in dHashGroups.values where matches.count > 1 {
            groups.append(makeGroup(matches, category: .duplicatePhotos))
        }
        let duplicates = Set(groups.flatMap(\.items).map(\.id))
        // Similar photos are compared within a ten-minute capture window,
        // matching aspect ratio and the Vision feature-print threshold.
        let candidates = items.filter { !$0.isVideo && !duplicates.contains($0.id) && !$0.asset.mediaSubtypes.contains(.photoScreenshot) }
        if candidates.count > 1 {
            let window = candidates
            var clusters: [(MediaItem, VNFeaturePrintObservation, [MediaItem])] = []
            for item in window {
                try Task.checkCancellation()
                guard let feature = await feature(for: item.asset) else { continue }
                var matched = false
                for index in clusters.indices {
                    let reference = clusters[index].0.asset
                    let ratio = Double(item.asset.pixelWidth) / Double(max(1, item.asset.pixelHeight))
                    let referenceRatio = Double(reference.pixelWidth) / Double(max(1, reference.pixelHeight))
                    guard abs(ratio - referenceRatio) < 0.03 else { continue }
                    var distance: Float = 0
                    guard abs((item.creationDate ?? .distantPast).timeIntervalSince(reference.creationDate ?? .distantPast)) <= 600 else { continue }
                    if (try? feature.computeDistance(&distance, to: clusters[index].1)) != nil, distance <= 0.35 {
                        clusters[index].2.append(item); matched = true; break
                    }
                }
                if !matched { clusters.append((item, feature, [item])) }
            }
            groups += clusters.filter { $0.2.count > 1 }.map { makeGroup($0.2, category: .similarPhotos) }
        }
        let videos = items.filter { $0.isVideo && !duplicates.contains($0.id) }
        var videoFeaturesCache: [(MediaItem, [VNFeaturePrintObservation])] = []
        for (offset, item) in videos.enumerated() {
            try Task.checkCancellation()
            if let samples = await videoFeatures(for: item.asset) {
                videoFeaturesCache.append((item, samples))
            }
            await progress(0.9 + Double(offset + 1) / Double(max(1, videos.count)) * 0.05)
        }

        // 1. Duplicate videos:
        // duration ± 0.5s + match of feature print of first, middle, last frame
        var duplicateVideoClusters: [(MediaItem, [VNFeaturePrintObservation], [MediaItem])] = []
        for (item, samples) in videoFeaturesCache {
            var matched = false
            for index in duplicateVideoClusters.indices {
                let reference = duplicateVideoClusters[index].0
                guard MediaMatching.videoDuplicateCandidate(duration: item.duration, otherDuration: reference.duration) else { continue }
                let distances = zip(samples, duplicateVideoClusters[index].1).compactMap { left, right -> Float? in
                    var distance: Float = 0
                    guard (try? left.computeDistance(&distance, to: right)) != nil else { return nil }
                    return distance
                }
                if MediaMatching.videoSamplesMatch(distances) {
                    duplicateVideoClusters[index].2.append(item)
                    matched = true
                    break
                }
            }
            if !matched {
                duplicateVideoClusters.append((item, samples, [item]))
            }
        }
        for cluster in duplicateVideoClusters where cluster.2.count > 1 {
            groups.append(makeGroup(cluster.2, category: .duplicateVideos))
        }

        let allDuplicateIDs = Set(groups.flatMap(\.items).map(\.id))
        let remainingVideos = videoFeaturesCache.filter { !allDuplicateIDs.contains($0.0.id) }

        // 2. Similar videos:
        // duration ± 10%, captured within 10 min, keyframes distance <= 0.35; not in Duplicates
        var similarVideoClusters: [(MediaItem, [VNFeaturePrintObservation], [MediaItem])] = []
        for (offset, (item, samples)) in remainingVideos.enumerated() {
            try Task.checkCancellation()
            var matched = false
            for index in similarVideoClusters.indices {
                let reference = similarVideoClusters[index].0
                guard MediaMatching.videoSimilarCandidate(duration: item.duration, otherDuration: reference.duration, date: item.creationDate, otherDate: reference.creationDate) else { continue }
                let distances = zip(samples, similarVideoClusters[index].1).compactMap { left, right -> Float? in
                    var distance: Float = 0
                    guard (try? left.computeDistance(&distance, to: right)) != nil else { return nil }
                    return distance
                }
                if MediaMatching.videoSimilarSamplesMatch(distances) {
                    similarVideoClusters[index].2.append(item)
                    matched = true
                    break
                }
            }
            if !matched {
                similarVideoClusters.append((item, samples, [item]))
            }
            await progress(0.95 + Double(offset + 1) / Double(max(1, remainingVideos.count)) * 0.04)
        }
        groups += similarVideoClusters.filter { $0.2.count > 1 }.map { makeGroup($0.2, category: .similarVideos) }
        return Result(items: items, groups: groups.sorted { $0.id < $1.id }, skipped: skipped)
    }

    static func makeGroup(_ items: [MediaItem], category: MediaCategory) -> MediaGroup {
        let sorted = items.sorted {
            let left = $0.asset.pixelWidth * $0.asset.pixelHeight
            let right = $1.asset.pixelWidth * $1.asset.pixelHeight
            if left != right { return left > right }
            if $0.asset.isFavorite != $1.asset.isFavorite { return $0.asset.isFavorite }
            let leftDate = $0.creationDate ?? .distantPast
            let rightDate = $1.creationDate ?? .distantPast
            return leftDate == rightDate ? $0.id < $1.id : leftDate > rightDate
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

    static func dHash(for cgImage: CGImage) -> UInt64? {
        let width = 9
        let height = 8
        var bytes = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var hash: UInt64 = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                let left = bytes[y * width + x]
                let right = bytes[y * width + x + 1]
                hash = (hash << 1) | (left > right ? 1 : 0)
            }
        }
        return hash
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
        distances.count == 3 && distances.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 0.15 }
    }
    static func videoDuplicateCandidate(duration: Double, otherDuration: Double) -> Bool {
        guard duration.isFinite, otherDuration.isFinite, duration > 0, otherDuration > 0 else { return false }
        return abs(duration - otherDuration) <= 0.5
    }
    static func videoSimilarCandidate(duration: Double, otherDuration: Double, date: Date?, otherDate: Date?) -> Bool {
        guard duration.isFinite, otherDuration.isFinite, duration > 0, otherDuration > 0 else { return false }
        guard abs(duration - otherDuration) <= max(duration, otherDuration) * 0.10 else { return false }
        guard let date, let otherDate, abs(date.timeIntervalSince(otherDate)) <= 600 else { return false }
        return true
    }
    static func videoSimilarSamplesMatch(_ distances: [Float]) -> Bool {
        distances.count == 3 && distances.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 0.35 }
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
