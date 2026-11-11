import SwiftUI

/// Static Figma splash. The parent controls the 1.88-second presentation and fade.
struct SplashScreen: View {
    var body: some View {
        GeometryReader { geometry in
            let sx = geometry.size.width / 375
            let sy = geometry.size.height / 812
            ZStack {
                LinearGradient(stops: [
                    .init(color: Color(hex: 0x84B6E8), location: 0),
                    .init(color: Color(hex: 0x0048AE), location: 0.5),
                    .init(color: Color(hex: 0x76A9DF), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                Circle().fill(.white.opacity(0.22)).frame(width: 384 * sx, height: 384 * sx)
                    .blur(radius: 80).position(x: 0, y: 96 * sy)
                Circle().fill(Color(hex: 0x99C9F2).opacity(0.45)).frame(width: 320 * sx, height: 320 * sx)
                    .blur(radius: 80).position(x: 324 * sx, y: 272 * sy)
                Circle().fill(Color(hex: 0x0048AE).opacity(0.4)).frame(width: 448 * sx, height: 448 * sx)
                    .blur(radius: 80).position(x: -12 * sx, y: 757 * sy)
                Circle().fill(.white.opacity(0.22)).frame(width: 256 * sx, height: 256 * sx)
                    .blur(radius: 80).position(x: 312 * sx, y: 752 * sy)
                VStack(spacing: 24) {
                    Image("SplashBrand").resizable().scaledToFit().frame(width: 263.0769, height: 263.0769).offset(y: 14.6154).frame(width: 190, height: 190)
                        .accessibilityHidden(true)
                    Text("Cleaner").font(CleanerStyle.font(32, .semibold)).dynamicTypeSize(...DynamicTypeSize.large).foregroundStyle(.white).frame(width: 208, height: 40)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.clipped()
        }.ignoresSafeArea().accessibilityElement(children: .combine)
    }
}
