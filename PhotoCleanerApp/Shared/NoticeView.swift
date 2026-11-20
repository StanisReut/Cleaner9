import SwiftUI

/// The same result card is used by media, contacts, calendar and settings.
struct NoticeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    let title: String
    let message: String
    let asset: String
    var primaryTitle = "Continue"
    var secondaryTitle: String? = nil
    let onPrimary: () -> Void
    var onSecondary: (() -> Void)? = nil
    @State private var appeared = false
    private var compact: Bool { asset.isEmpty || title == "Photo saved" }
    private var standardMessage: String {
        switch message {
        case "No incomplete contacts remain.": return "No incomplete contacts\nremain."
        case "Your Premium features are available.": return "Your Premium features are\navailable."
        case "Check your connection and try again.": return "Check your connection and try\nagain."
        case "Each pair is now a single contact.": return "Each pair is now a single\ncontact."
        case "Your backup has been restored.": return "Your backup has been\nrestored."
        default: return message
        }
    }
    var body: some View {
      if dynamicType.isAccessibilitySize {
        ZStack {
            Color(hex: compact ? 0x182238 : 0x152039).opacity(compact ? 0.48 : 0.5).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    if !asset.isEmpty { Image(asset).resizable().scaledToFit().frame(width: 112, height: 112).accessibilityHidden(true) }
                    Text(title).font(Palette.font(20, .bold)).fixedSize(horizontal: false, vertical: true)
                    if !message.isEmpty { Text(message).font(Palette.font(16)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true) }
                    PrimaryButton(title: primaryTitle, action: onPrimary)
                    if let secondaryTitle { Button(secondaryTitle) { onSecondary?() }.font(Palette.font(16, .semibold)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 44) }
                }.multilineTextAlignment(.center).foregroundStyle(Palette.ink).padding(16)
                    .frame(maxWidth: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 24))
                    .shadow(color: compact ? .clear : Color(.sRGB, red: 0.05, green: 0.1, blue: 0.2, opacity: 0.22), radius: 12, y: 8).padding(16)
            }.defaultScrollAnchor(.top)
        }.accessibilityAddTraits(.isModal)
      } else {
        GeometryReader { proxy in
            ZStack {
                Color(hex: compact ? 0x182238 : 0x152039).opacity(appeared ? (compact ? 0.48 : 0.5) : 0.0).ignoresSafeArea()
                    .animation(.easeOut(duration: 0.22), value: appeared)
                VStack(spacing: 8) {
                    Text(title == "Couldn’t restore purchases" ? "Couldn’t restore\npurchases" : title).font(Palette.font(20, .bold)).foregroundStyle(Color(hex: 0x252A32)).frame(minHeight: compact ? 28 : 24).fixedSize(horizontal: false, vertical: true).accessibilityLabel(title)
                    if !message.isEmpty { Text(standardMessage).font(Palette.font(asset.isEmpty ? 16 : 18)).lineSpacing(asset.isEmpty ? 4 : 2).padding(.vertical, compact ? 2 : 1).foregroundStyle(Palette.secondary).frame(minHeight: title == "Photo saved" ? 26 : 24).fixedSize(horizontal: false, vertical: true).accessibilityLabel(message) }
                    PrimaryButton(title: primaryTitle, height: compact ? 48 : 56, action: onPrimary).padding(.top, compact ? 0 : 16)
                    if let secondaryTitle { Button(secondaryTitle) { onSecondary?() }.font(Palette.font(16, .semibold)).frame(maxWidth: .infinity, minHeight: 24).padding(.bottom, 20).contentShape(Rectangle()).padding(.bottom, -20) }
                }.multilineTextAlignment(.center).padding(.horizontal, 24).padding(.top, asset.isEmpty ? 24 : 72).padding(.bottom, 24)
                    .frame(width: min(312, max(0, proxy.size.width - 48)))
                    .background(.white, in: RoundedRectangle(cornerRadius: 24))
                    .shadow(color: compact ? .clear : Color(.sRGB, red: 0.05, green: 0.1, blue: 0.2, opacity: 0.22), radius: 12, y: 8)
                    .overlay(alignment: .top) {
                        if !asset.isEmpty { Image(asset).resizable().scaledToFit().frame(width: 112, height: 112)
                            .overlay(alignment: .bottomTrailing) {
                                if (asset == "Premium" && title == "Purchases restored") || asset == "PhotoSaved" || asset.contains("Success") {
                                    Circle().fill(LinearGradient(colors: [Color(hex: 0x779AC7), Color(hex: 0x315D95)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .overlay(Circle().stroke(Palette.bg, lineWidth: 4))
                                        .overlay(Image(systemName: "checkmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)).frame(width: 36, height: 36).padding(2)
                                }
                            }.offset(y: -48).accessibilityHidden(true) }
                    }
                    .scaleEffect(appeared ? 1.0 : 0.92)
                    .opacity(appeared ? 1.0 : 0.0)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.ignoresSafeArea().accessibilityAddTraits(.isModal)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                appeared = true
            }
        }
      }
    }
}
