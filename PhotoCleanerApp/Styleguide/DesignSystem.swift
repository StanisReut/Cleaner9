import SwiftUI
import UIKit
import CoreText

enum Palette {
    static let bg = Color(hex: 0xEFF3FF)
    static let ink = Color(hex: 0x26292F)
    static let secondary = Color(hex: 0x505E70)
    static let blue = Color(hex: 0x0048AE)
    static let track = Color(hex: 0xEAF0F8)
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Inter", size: size, relativeTo: .body).weight(weight) }
    static func registerFonts() {
        for name in ["Inter", "Poppins-SemiBold"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }
}
extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255, opacity: 1) }
}
extension View {
    func cleanerBodyLineHeight() -> some View { modifier(BodyLineHeight()) }
    func cleanerCard() -> some View {
        padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}
private struct BodyLineHeight: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var spacing = max(0, 24 - (UIFont(name: "Inter-Regular", size: 16)?.lineHeight ?? UIFont.systemFont(ofSize: 16).lineHeight))
    func body(content: Content) -> some View { content.lineSpacing(spacing) }
}
struct PageShell<Content: View>: View {
    let title: String
    var onBack: (() -> Void)? = nil
    var trailingPadding: CGFloat = 16
    var headerSpacing: CGFloat = 6
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            HeaderView(title: title, spacing: headerSpacing, onBack: onBack)
            ScrollView { VStack(alignment: .leading, spacing: 16, content: content).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16).padding(.leading, 16).padding(.trailing, trailingPadding).padding(.bottom, 20) }
        }
        .background(LinearGradient(stops: [.init(color: Palette.bg, location: 0), .init(color: Palette.bg, location: 0.78), .init(color: .white, location: 1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .background(SwipeBackEnabler())
        .foregroundStyle(Palette.ink)
        .font(Palette.font(16))
        .toolbar(.hidden, for: .navigationBar)
    }
}
struct SwipeBackEnabler: UIViewControllerRepresentable {
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var nav: UINavigationController?
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (nav?.viewControllers.count ?? 0) > 1
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        DispatchQueue.main.async {
            if let nav = vc.navigationController {
                context.coordinator.nav = nav
                nav.interactivePopGestureRecognizer?.isEnabled = true
                nav.interactivePopGestureRecognizer?.delegate = context.coordinator
            }
        }
        return vc
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
struct HeaderView: View {
    let title: String
    var spacing: CGFloat = 6
    var onBack: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        HStack(spacing: spacing) {
            Button { Tactile.tap(); (onBack ?? { dismiss() })() } label: { Image("BackIcon").resizable().scaledToFit().frame(width: 32, height: 32).frame(width: 44, height: 44).contentShape(Rectangle()) }
                .buttonStyle(BackButtonStyle())
                .accessibilityLabel("Back")
                .accessibilityIdentifier("qa/back")
            Text(title).font(Palette.font(24, .semibold)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }.foregroundStyle(Palette.ink).padding(.horizontal, 10).padding(.top, 10).padding(.bottom, -6)
    }
}
struct PrimaryButton: View {
    let title: String
    var disabled = false
    var height: CGFloat = 56
    var disabledFill = Color(hex: 0xDFE6F0)
    var disabledInk = Palette.secondary
    let action: () -> Void
    var body: some View {
        Button { Tactile.tap(); action() } label: {
            Text(title).font(Palette.font(16, .semibold)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 24).padding(.horizontal, 12).padding(.vertical, (height - 24) / 2)
                .background(disabled ? disabledFill : Palette.blue, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(disabled ? disabledInk : .white)
        }.disabled(disabled).buttonStyle(PrimaryButtonStyle())
    }
}
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
struct InteractiveCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.68), value: configuration.isPressed)
    }
}
struct BackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .opacity(configuration.isPressed ? 0.72 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
struct LoadingRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false
    var body: some View {
        Circle().trim(from: 0, to: 0.72).stroke(Palette.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: 16, height: 16)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .animation(FidelityPreview.active || reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false), value: rotating)
            .frame(width: 24, height: 24).accessibilityLabel("Loading…")
            .onAppear { if !FidelityPreview.active && !reduceMotion { rotating = true } }
    }
}
struct EmptyState: View {
    let title: String
    let message: String
    var systemImage = "tray"
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage).font(.system(size: 44)).foregroundStyle(Palette.blue)
            Text(title).font(Palette.font(22, .semibold))
            Text(message).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 32)
    }
}
struct Disclosure: View {
    var body: some View { Image("DisclosureIcon").resizable().scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true) }
}
struct FeatureRow: View {
    let title: String
    var subtitle: String? = nil
    var asset: String? = nil
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let asset { Image(asset).resizable().scaledToFit().frame(width: 32, height: 32) }
            if let symbol { Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(Palette.blue).frame(width: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Palette.font(16, .semibold)).foregroundStyle(Color(hex: 0x565C61))
                if let subtitle { Text(subtitle).font(Palette.font(16)).foregroundStyle(Color(hex: 0x62656B)).frame(minHeight: 24) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Disclosure()
        }.foregroundStyle(Palette.ink).frame(minHeight: 52).cleanerCard().compositingGroup().shadow(color: Color(hex: 0x203E73).opacity(0.08), radius: 8, y: 8).contentShape(Rectangle())
    }
}
func formattedBytes(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
func openSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
