import SwiftUI

/// The same result card is used by media, contacts, calendar and settings.
struct CleanerModal: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    let title: String
    let message: String
    let asset: String
    var primaryTitle = "Continue"
    var secondaryTitle: String? = nil
    let onPrimary: () -> Void
    var onSecondary: (() -> Void)? = nil
    private var compact: Bool { asset.isEmpty || title == "Photo saved" }
    var body: some View {
      if dynamicType.isAccessibilitySize {
        ZStack {
            Color(hex: compact ? 0x182238 : 0x152039).opacity(compact ? 0.48 : 0.5).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    if !asset.isEmpty { Image(asset).resizable().scaledToFit().frame(width: 112, height: 112).accessibilityHidden(true) }
                    Text(title).font(CleanerStyle.font(20, .bold)).fixedSize(horizontal: false, vertical: true)
                    if !message.isEmpty { Text(message).font(CleanerStyle.font(16)).foregroundStyle(CleanerStyle.secondary).fixedSize(horizontal: false, vertical: true) }
                    PrimaryButton(title: primaryTitle, action: onPrimary)
                    if let secondaryTitle { Button(secondaryTitle) { onSecondary?() }.font(CleanerStyle.font(16, .semibold)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 44) }
                }.multilineTextAlignment(.center).foregroundStyle(CleanerStyle.ink).padding(16)
                    .frame(maxWidth: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 24)).padding(16)
            }.defaultScrollAnchor(.top)
        }.accessibilityAddTraits(.isModal)
      } else {
        GeometryReader { proxy in
            ZStack {
                Color(hex: compact ? 0x182238 : 0x152039).opacity(compact ? 0.48 : 0.5).ignoresSafeArea()
                VStack(spacing: 8) {
                    Text(title == "Couldn’t restore purchases" ? "Couldn’t restore\npurchases" : title).font(CleanerStyle.font(20, .bold)).foregroundStyle(Color(hex: 0x252A32)).frame(minHeight: compact ? 28 : 24).fixedSize(horizontal: false, vertical: true).accessibilityLabel(title)
                    if !message.isEmpty { Text(message).font(CleanerStyle.font(asset.isEmpty ? 16 : 18)).lineSpacing(asset.isEmpty ? 4 : 2).padding(.vertical, compact ? 2 : 1).foregroundStyle(CleanerStyle.secondary).frame(minHeight: title == "Photo saved" ? 26 : 24).fixedSize(horizontal: false, vertical: true) }
                    PrimaryButton(title: primaryTitle, height: compact ? 48 : 56, action: onPrimary).padding(.top, compact ? 0 : 16)
                    if let secondaryTitle { Button(secondaryTitle) { onSecondary?() }.font(CleanerStyle.font(16, .semibold)).frame(maxWidth: .infinity, minHeight: 24).padding(.bottom, 20).contentShape(Rectangle()).padding(.bottom, -20) }
                }.multilineTextAlignment(.center).padding(.horizontal, 24).padding(.top, asset.isEmpty ? 24 : 72).padding(.bottom, 24)
                    .frame(width: min(312, max(0, proxy.size.width - 48)))
                    .background(.white, in: RoundedRectangle(cornerRadius: 24))
                    .overlay(alignment: .top) {
                        if !asset.isEmpty { Image(asset).resizable().scaledToFit().frame(width: 112, height: 112)
                            .overlay(alignment: .bottomTrailing) {
                                if (asset == "Premium" && title == "Purchases restored") || asset == "PhotoSaved" || asset.contains("Success") {
                                    Circle().fill(LinearGradient(colors: [Color(hex: 0x779AC7), Color(hex: 0x315D95)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .overlay(Circle().stroke(CleanerStyle.bg, lineWidth: 4))
                                        .overlay(Image(systemName: "checkmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)).frame(width: 36, height: 36).padding(2)
                                }
                            }.offset(y: -48).accessibilityHidden(true) }
                    }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.ignoresSafeArea().accessibilityAddTraits(.isModal)
      }
    }
}
