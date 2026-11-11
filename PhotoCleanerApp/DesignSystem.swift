import SwiftUI
import UIKit
import CoreText

enum CleanerStyle {
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
    func cleanerCard() -> some View {
        padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}
struct CleanerPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            CleanerHeader(title: title)
            ScrollView { VStack(alignment: .leading, spacing: 16, content: content).frame(maxWidth: .infinity, alignment: .leading).padding(16).padding(.bottom, 20) }
        }.background(LinearGradient(stops: [.init(color: CleanerStyle.bg, location: 0), .init(color: CleanerStyle.bg, location: 0.78), .init(color: .white, location: 1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()).foregroundStyle(CleanerStyle.ink).font(CleanerStyle.font(16)).toolbar(.hidden, for: .navigationBar)
    }
}
struct CleanerHeader: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        HStack(spacing: 6) {
            Button { dismiss() } label: { Image("BackIcon").resizable().scaledToFit().frame(width: 32, height: 32).frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Back")
            Text(title).font(CleanerStyle.font(24, .semibold)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }.foregroundStyle(CleanerStyle.ink).padding(.horizontal, 10).padding(.top, 10).padding(.bottom, -6)
    }
}
struct PrimaryButton: View {
    let title: String
    var disabled = false
    var height: CGFloat = 56
    var disabledFill = Color(hex: 0xDFE6F0)
    var disabledInk = CleanerStyle.secondary
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(CleanerStyle.font(16, .semibold)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 24).padding(.horizontal, 12).padding(.vertical, (height - 24) / 2)
                .background(disabled ? disabledFill : CleanerStyle.blue, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(disabled ? disabledInk : .white)
        }.disabled(disabled).buttonStyle(CleanerButtonStyle())
    }
}
struct CleanerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.opacity(configuration.isPressed ? 0.9 : 1) }
}
struct CleanerLoadingRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false
    var body: some View {
        Circle().trim(from: 0, to: 0.72).stroke(CleanerStyle.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: 16, height: 16)
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
            Image(systemName: systemImage).font(.system(size: 44)).foregroundStyle(CleanerStyle.blue)
            Text(title).font(CleanerStyle.font(22, .semibold))
            Text(message).foregroundStyle(CleanerStyle.secondary).multilineTextAlignment(.center)
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
            if let symbol { Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(CleanerStyle.blue).frame(width: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(CleanerStyle.font(16, .semibold))
                if let subtitle { Text(subtitle).font(CleanerStyle.font(16)).foregroundStyle(CleanerStyle.secondary).frame(minHeight: 24) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Disclosure()
        }.foregroundStyle(CleanerStyle.ink).frame(minHeight: 52).cleanerCard().contentShape(Rectangle())
    }
}
func formattedBytes(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
func openCleanerSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
