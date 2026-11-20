import SwiftUI
import UIKit

struct HeraldAction {
    let title: LocalizedStringKey
    let action: () -> Void
}

@MainActor protocol Notifier {
    func toast(_ message: LocalizedStringKey)
    func alert(title: LocalizedStringKey, message: LocalizedStringKey, primary: HeraldAction, secondary: HeraldAction?)
}

@MainActor
final class Herald: Notifier {
    static let shared = Herald()
    private var window: UIWindow?
    private var dismissTask: Task<Void, Never>?

    func toast(_ message: LocalizedStringKey) { present(.toast(message)) }
    func alert(title: LocalizedStringKey, message: LocalizedStringKey, primary: HeraldAction, secondary: HeraldAction? = nil) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            present(.alert(title: title, message: message, primary: primary, secondary: secondary))
            return
        }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let alert = UIAlertController(title: "Cleaner", message: extractString(message), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: extractString(primary.title), style: .default) { _ in primary.action() })
        if let secondary {
            alert.addAction(UIAlertAction(title: extractString(secondary.title), style: .cancel) { _ in secondary.action() })
        }
        top.present(alert, animated: true)
    }

    private func extractString(_ key: LocalizedStringKey) -> String {
        let mirror = Mirror(reflecting: key)
        if let str = mirror.children.first(where: { $0.label == "key" })?.value as? String {
            return str
        }
        return String(describing: key)
    }

    fileprivate enum Payload {
        case toast(LocalizedStringKey)
        case alert(title: LocalizedStringKey, message: LocalizedStringKey, primary: HeraldAction, secondary: HeraldAction?)
    }

    private func present(_ payload: Payload) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else { return }
        dismissTask?.cancel()
        let window = self.window ?? UIWindow(windowScene: scene)
        window.windowLevel = .alert + 2
        window.backgroundColor = .clear
        window.rootViewController = UIHostingController(rootView: HeraldView(payload: payload, dismiss: { [weak self] in self?.dismiss() }))
        window.rootViewController?.view.backgroundColor = .clear
        window.isHidden = false
        self.window = window
        if case .toast = payload {
            dismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.dismiss()
            }
        }
    }

    private func dismiss() { dismissTask?.cancel(); window?.isHidden = true; window = nil }
}

private struct HeraldView: View {
    let payload: Herald.Payload
    let dismiss: () -> Void
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear.ignoresSafeArea()
            switch payload {
            case .toast(let message): Text(message).font(Palette.font(16, .semibold)).foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 12).background(.black.opacity(0.82), in: Capsule()).padding(.bottom, 28)
            case .alert(let title, let message, let primary, let secondary):
                VStack(spacing: 12) {
                    Text(title).font(Palette.font(20, .bold))
                    Text(message).font(Palette.font(16)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                    Button { dismiss(); primary.action() } label: {
                        Text(primary.title).font(Palette.font(16, .semibold)).frame(maxWidth: .infinity, minHeight: 56).background(Palette.blue, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.white)
                    }
                    if let secondary { Button(secondary.title) { dismiss(); secondary.action() }.font(Palette.font(16, .semibold)).frame(minHeight: 44) }
                }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 24)).padding(16)
            }
        }.ignoresSafeArea().accessibilityAddTraits(.isModal)
    }
}
