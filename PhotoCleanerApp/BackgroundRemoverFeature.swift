import SwiftUI
import PhotosUI
import Photos
import Vision
import ImageIO
import UniformTypeIdentifiers

struct BackgroundRemoverScreen: View {
    @State private var picked: PhotosPickerItem?
    @State private var source: Data?
    @State private var cutout: Data?
    @State private var rendered: Data?
    @State private var mode = CutoutBackground.transparent
    @State private var busy = false
    @State private var status = ""
    @State private var error: String?
    @State private var needsSettings = false
    @State private var share: CutoutShareFile?
    @State private var shareURL: URL?
    @State private var operationID = UUID()
    @State private var saved = false
    @State private var fixtureLoaded = false
    @State private var nativePicker = false
    private let worker = CutoutProcessor.shared

    var body: some View {
        GeometryReader { geometry in
          VStack(spacing: 0) {
            CleanerHeader(title: "Background Remover")
            ScrollView {
              VStack(alignment: .leading, spacing: 16) {
            if let data = rendered, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity).frame(height: max(160, geometry.size.height - 216))
                    .background {
                        if mode == .transparent { Checkerboard() }
                        else if let asset = mode.asset { Image(asset).resizable().scaledToFill() }
                        else { LinearGradient(colors: mode.colors.map { Color(uiColor: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing) }
                    }.clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("Photo with selected background")
                backgroundControls
            } else if !busy && error == nil {
                VStack(spacing: 16) {
                    Image("BackgroundIntro").resizable().scaledToFit().frame(maxWidth: 328).frame(height: min(360, max(180, geometry.size.height - 276))).accessibilityHidden(true)
                    Text("Remove the background").font(CleanerStyle.font(24, .semibold)).multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 32)
                    Text("Keep your subject and choose a new background.").foregroundStyle(CleanerStyle.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 48).padding(.top, 0)
                }.frame(maxWidth: .infinity).frame(minHeight: max(0, geometry.size.height - 64))
            }
            if busy && rendered == nil && status == "Loading photo…" {
                VStack(spacing: 24) {
                    Group {
                        if FidelityPreview.active { Image("Coast").resizable().scaledToFill() }
                        else { Rectangle().fill(CleanerStyle.track).overlay(Image(systemName: "photo").font(.system(size: 48)).foregroundStyle(CleanerStyle.secondary)) }
                    }.frame(width: 280, height: 280).clipShape(RoundedRectangle(cornerRadius: 24))
                    Text(status).frame(minHeight: 24)
                }.frame(maxWidth: .infinity).frame(minHeight: max(0, geometry.size.height - 80))
            } else if busy && rendered == nil {
                VStack(spacing: 24) {
                    ZStack {
                        ZStack {
                            Image("BGProcessingBefore").resizable().scaledToFit().frame(width: 167.0931, height: 194.3281).offset(x: -76.4534, y: -63.8769)
                            Image("BGProcessingAfter").resizable().scaledToFit().frame(width: 167.0931, height: 194.3281).offset(x: 84.0521, y: 76.1641)
                        }.frame(width: 328, height: 344)
                        Circle().fill(.white.opacity(0.9)).frame(width: 160, height: 160)
                        if FidelityPreview.active && !FidelityPreview.name.contains("Loading") {
                            let progress = FidelityPreview.name.contains("2") ? 0.78 : 0.32
                            Circle().stroke(Color(hex: 0xE6ECF7), lineWidth: 12).frame(width: 140, height: 140)
                            Circle().trim(from: 0, to: progress).stroke(CleanerStyle.blue, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 140, height: 140)
                            Text(progress > 0.5 ? "78%" : "32%").font(CleanerStyle.font(32, .semibold)).dynamicTypeSize(...DynamicTypeSize.large)
                        } else { ProgressView().controlSize(.large) }
                    }
                    Text(status).font(CleanerStyle.font(16, .semibold)).foregroundStyle(CleanerStyle.ink).frame(minHeight: 24)
                }.frame(maxWidth: .infinity).frame(minHeight: max(0, geometry.size.height - 80))
            } else if busy { ProgressView(status).frame(maxWidth: .infinity) }
            if let error, !needsSettings {
                Text(error).foregroundStyle(CleanerStyle.secondary).multilineTextAlignment(.center)
                if needsSettings {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } else if source != nil && cutout == nil {
                    Button("Try again") { process() }.disabled(busy)
                }
            }
            if !busy && !status.isEmpty && error == nil {
                Text(status).foregroundStyle(CleanerStyle.secondary).accessibilityAddTraits(.updatesFrequently)
            }
              }.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 24)
            }
          }
        }
        .background(LinearGradient(stops: [.init(color: CleanerStyle.bg, location: 0.78), .init(color: .white, location: 1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .font(CleanerStyle.font(16)).foregroundStyle(CleanerStyle.ink).toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if rendered != nil {
                HStack(spacing: 23) {
                    Button("Share") { export(save: false) }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color(hex: 0xE7EEF8), in: RoundedRectangle(cornerRadius: 16))
                    Button("Save") { export(save: true) }
                        .frame(maxWidth: .infinity, minHeight: 56).foregroundStyle(.white)
                        .background(Color(hex: 0x1CB450), in: RoundedRectangle(cornerRadius: 16))
                }.font(CleanerStyle.font(16, .semibold)).disabled(busy).padding(16).background(CleanerStyle.bg)
            }
            if rendered == nil && !busy {
            PhotosPicker(selection: $picked, matching: .images) {
                Text(source == nil ? "Choose photo" : "Choose another photo")
                    .font(CleanerStyle.font(16, .semibold)).frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(source == nil ? .white : CleanerStyle.blue)
                    .background(source == nil ? CleanerStyle.blue : Color.white, in: RoundedRectangle(cornerRadius: 16))
            }.disabled(busy).padding(16).background(.white)
            }
        }
        .overlay {
            if needsSettings {
                CleanerModal(title: "Photos access is off", message: "Allow Cleaner to add photos in Settings to save your image.", asset: "", primaryTitle: "Back to editor", onPrimary: { needsSettings = false; error = nil })
            } else if saved {
                CleanerModal(title: "Photo saved", message: "Added to your photo library.", asset: "PhotoSaved", onPrimary: { saved = false })
            }
        }
        .onAppear { loadFixture() }
        .photosPicker(isPresented: $nativePicker, selection: $picked, matching: .images)
        .task {
            guard FidelityPreview.nativeHandoff else { return }
            if FidelityPreview.name.contains("Select a photo") { nativePicker = true }
            else if FidelityPreview.name.contains("Share image"), let rendered {
                do { let url = try await worker.shareFile(rendered); shareURL = url; share = CutoutShareFile(url: url) }
                catch { self.error = error.localizedDescription }
            } else if FidelityPreview.name.contains("Add Photos Only") || FidelityPreview.name.contains("iOS add-only") {
                // Native permission handoff only; fidelity mode never writes to Photos.
                _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            }
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            let operation = UUID(); operationID = operation
            busy = true; status = "Loading photo…"; error = nil; needsSettings = false
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw CutoutError.unreadable }
                    guard operationID == operation else { return }
                    source = data; cutout = nil; rendered = nil; mode = .transparent
                    process()
                } catch {
                    guard operationID == operation else { return }
                    self.error = error.localizedDescription; busy = false; status = ""
                }
            }
        }
        .onDisappear { operationID = UUID() }
        .task(id: mode) {
            guard let cutout else { return }
            busy = true; status = "Updating background…"; error = nil
            do {
                let result = try await worker.compose(cutout, background: mode)
                try Task.checkCancellation()
                rendered = result; busy = false; status = ""
            } catch is CancellationError { } catch { self.error = error.localizedDescription; busy = false }
        }
        .sheet(item: $share, onDismiss: {
            if let shareURL { try? FileManager.default.removeItem(at: shareURL) }
            shareURL = nil
        }) { file in
            CutoutActivity(url: file.url) { completed, message in
                status = completed ? "Shared successfully" : ""
                error = message
            }
        }
    }

    private var backgroundControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background").font(CleanerStyle.font(16, .semibold)).frame(minHeight: 24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CutoutBackground.categories, id: \.self) { option in
                        Button(option.category) { mode = option }
                            .font(CleanerStyle.font(16, mode.category == option.category ? .semibold : .regular))
                            .frame(minHeight: 24).padding(8).foregroundStyle(mode.category == option.category ? CleanerStyle.blue : CleanerStyle.secondary)
                            .background(mode.category == option.category ? Color(hex: 0xDFEBFE) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityAddTraits(mode.category == option.category ? .isSelected : [])
                    }
                }
            }
            if mode == .transparent {
                HStack { Checkerboard().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8)); Text("No background").fixedSize(horizontal: false, vertical: true) }.frame(minHeight: 56)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(CutoutBackground.allCases.filter { $0.category == mode.category }, id: \.self) { option in
                            Button { mode = option } label: {
                                Group {
                                    if let asset = option.asset { Image(asset).resizable().scaledToFill() }
                                    else { LinearGradient(colors: option.colors.map { Color(uiColor: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing) }
                                }.frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(mode == option ? CleanerStyle.blue : .clear, lineWidth: 2))
                            }.accessibilityLabel(option.rawValue).accessibilityAddTraits(mode == option ? .isSelected : [])
                        }
                        Text(mode.rawValue).font(CleanerStyle.font(16))
                    }.frame(minHeight: 56)

                }
            }
        }.disabled(busy).foregroundStyle(CleanerStyle.secondary)
    }

    private func loadFixture() {
        guard FidelityPreview.active, !fixtureLoaded else { return }; fixtureLoaded = true
        let name = FidelityPreview.name
        if name.contains("Choose photo") || name.contains("Select a photo") { return }
        if name.contains("Processing") || name.contains("Loading") {
            busy = true; status = name.contains("Loading") ? "Loading photo…" : "Removing background…"; return
        }
        let sample = (UIImage(named: "CutoutSubject") ?? UIImage(named: "BackgroundIntro"))?.pngData()
        source = sample; cutout = sample; rendered = sample
        if let selected = CutoutBackground.allCases.first(where: { name.hasSuffix($0.rawValue) }) { mode = selected }
        needsSettings = name.localizedCaseInsensitiveContains("access off")
        saved = name.localizedCaseInsensitiveContains("photo saved")
        // Native picker / add-only permission / share sheet are OS-owned; fixtures show editor,
        // then testers trigger the real control. They are never imitated with app chrome.
    }

    private func process() {
        guard let source else { return }
        let operation = UUID(); operationID = operation
        busy = true; error = nil; status = "Removing background…"
        Task {
            do {
                let data = try await worker.remove(source)
                guard operationID == operation else { return }
                cutout = data; rendered = data; status = ""
            } catch {
                guard operationID == operation else { return }
                self.error = error.localizedDescription; status = ""
            }
            busy = false
        }
    }

    private func export(save: Bool) {
        if FidelityPreview.active { if save { saved = true }; return }
        guard let rendered else { return }
        busy = true; error = nil; needsSettings = false; status = save ? "Saving…" : "Preparing share…"
        Task {
            do {
                if save {
                    let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                    guard authorization == .authorized || authorization == .limited else {
                        needsSettings = true; throw CutoutError.permission
                    }
                    try await PHPhotoLibrary.shared().performChanges {
                        let request = PHAssetCreationRequest.forAsset()
                        let options = PHAssetResourceCreationOptions()
                        options.uniformTypeIdentifier = UTType.png.identifier
                        request.addResource(with: .photo, data: rendered, options: options)
                    }
                    status = ""; saved = true
                } else {
                    let url = try await worker.shareFile(rendered)
                    shareURL = url; share = CutoutShareFile(url: url); status = ""
                }
            } catch { self.error = error.localizedDescription; status = "" }
            busy = false
        }
    }
}

nonisolated private enum CutoutBackground: String, CaseIterable, Sendable {
    case transparent = "Transparent", mist = "Mist", peach = "Peach", sage = "Sage", paper = "Paper"
    case sky = "Sky", dawn = "Dawn", mint = "Mint"
    case coast = "Coast", meadow = "Meadow", fountain = "Fountain"
    static let categories: [Self] = [.transparent, .mist, .sky, .coast]
    var category: String {
        switch self { case .transparent: return "Transparent"; case .mist, .peach, .sage, .paper: return "Color"; case .sky, .dawn, .mint: return "Gradient"; default: return "Image" }
    }
    var asset: String? { category == "Image" ? rawValue : nil }
    var colors: [UIColor] {
        func color(_ hex: UInt32) -> UIColor { UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1) }
        switch self {
        case .mist: return [color(0xC5D7E6), color(0xC5D7E6)]
        case .peach: return [color(0xEDC9B6), color(0xEDC9B6)]
        case .sage: return [color(0xBDD5C1), color(0xBDD5C1)]
        case .paper: return [color(0xF6ECDD), color(0xF6ECDD)]
        case .sky: return [color(0xA7CBEB), color(0xE1E5F5)]
        case .dawn: return [color(0xF6CCAE), color(0xCFBBDC)]
        case .mint: return [color(0xBDDFCB), color(0xBCD4EA)]
        default: return [.clear, .clear]
        }
    }
}

nonisolated private enum CutoutError: LocalizedError {
    case unreadable, noSubject, export, permission
    var errorDescription: String? {
        switch self {
        case .unreadable: return "This photo couldn’t be opened. Choose another photo and try again."
        case .noSubject: return "No clear subject was found. Try a photo with a distinct person, pet, or object."
        case .export: return "The image couldn’t be created. Please try again."
        case .permission: return "Allow Cleaner to add photos in Settings, then tap Save again."
        }
    }
}

// ImageIO applies EXIF orientation before Vision. Keep native dimensions up to
// 4096 pixels on the longest edge to bound mask/compositing memory for large photos.
private actor CutoutProcessor {
    static let shared = CutoutProcessor()
    func remove(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096
              ] as CFDictionary) else { throw CutoutError.unreadable }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else { throw CutoutError.noSubject }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cg = CIContext().createCGImage(ci, from: ci.extent), let png = UIImage(cgImage: cg).pngData() else { throw CutoutError.export }
        return png
    }

    func compose(_ data: Data, background: CutoutBackground) throws -> Data {
        if background == .transparent { return data }
        guard let image = UIImage(data: data) else { throw CutoutError.unreadable }
        let size = image.size
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let backgroundImage = background.asset.flatMap { UIImage(named: $0) }
        if background.asset != nil && backgroundImage == nil { throw CutoutError.export }
        let output = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let rect = CGRect(origin: .zero, size: size)
            if let backgroundImage {
                let ratio = max(size.width / backgroundImage.size.width, size.height / backgroundImage.size.height)
                let width = backgroundImage.size.width * ratio, height = backgroundImage.size.height * ratio
                backgroundImage.draw(in: CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height))
            } else if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: background.colors.map(\.cgColor) as CFArray, locations: [0, 1]) {
                renderer.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            image.draw(in: rect)
        }
        guard let result = output.pngData() else { throw CutoutError.export }
        return result
    }
    func shareFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Cleaner-\(UUID().uuidString).png")
        try data.write(to: url, options: .atomic)
        return url
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for row in 0..<Int(ceil(size.height / 8)) {
                for column in 0..<Int(ceil(size.width / 8)) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * 8, y: CGFloat(row) * 8, width: 8, height: 8)), with: .color(Color(white: 0.87)))
                }
            }
        }.accessibilityHidden(true)
    }
}
private struct CutoutShareFile: Identifiable { let id = UUID(); let url: URL }
private struct CutoutActivity: UIViewControllerRepresentable {
    let url: URL
    let completion: (Bool, String?) -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            DispatchQueue.main.async { completion(completed, error?.localizedDescription) }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
