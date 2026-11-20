import SwiftUI
import UIKit

@MainActor
final class Veil {
    static let shared = Veil()
    private var window: UIWindow?

    func show() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.rootViewController = UIHostingController(rootView: VeilView())
        window.rootViewController?.view.backgroundColor = .clear
        window.isHidden = false
        self.window = window
    }

    func hide() {
        window?.isHidden = true
        window = nil
    }
}

private struct VeilView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
            ProgressView().controlSize(.large).tint(.white)
                .padding(24).background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 18))
        }.environment(\.colorScheme, .dark)
    }
}
