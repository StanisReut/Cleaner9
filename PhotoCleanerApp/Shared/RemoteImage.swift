import SwiftUI
import UIKit

/// Asynchronous remote image loader with retries and shimmer highlight (setup-backend §5.1).
struct RemoteImage: View {
    let urlString: String?
    var cornerRadius: CGFloat = 12
    var contentMode: ContentMode = .fill

    @State private var image: Image?
    @State private var failed = false
    private var hasURL: Bool { !(urlString?.isEmpty ?? true) }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Palette.track)
            .overlay {
                if let image {
                    image.resizable().aspectRatio(contentMode: contentMode)
                } else if hasURL && !failed {
                    ShimmerFill(cornerRadius: cornerRadius)
                } else {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(Palette.secondary.opacity(0.4))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .task(id: urlString) { await load() }
    }

    @MainActor private func load() async {
        image = nil
        failed = false
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else { return }
        for attempt in 0..<3 {
            if Task.isCancelled { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let ui = UIImage(data: data) else { failed = true; return }
                withAnimation(.easeInOut(duration: 0.2)) { image = Image(uiImage: ui) }
                return
            } catch is CancellationError {
                return
            } catch let e as URLError where e.code == .cancelled {
                return
            } catch {
                if attempt == 2 { failed = true; return }
                try? await Task.sleep(for: .milliseconds(300 * (attempt + 1)))
            }
        }
    }
}

/// Animated loading skeleton: a running light highlight across the backing.
private struct ShimmerFill: View {
    let cornerRadius: CGFloat
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            Palette.track
                .overlay(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.35), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: w * 0.55)
                    .offset(x: -w + phase * (2 * w))
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .onAppear {
                    withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
    }
}
