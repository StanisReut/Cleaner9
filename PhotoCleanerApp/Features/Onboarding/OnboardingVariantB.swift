import SwiftUI

struct OnboardingVariantB: View {
    let configuration: AppConfiguration
    let onComplete: () -> Void
    @State private var index: Int

    init(configuration: AppConfiguration, onComplete: @escaping () -> Void) {
        self.configuration = configuration
        self.onComplete = onComplete
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "--qa-onboarding-step"), args.indices.contains(idx + 1), let s = Int(args[idx + 1]) {
            _index = State(initialValue: min(max(s, 0), 2))
        } else {
            _index = State(initialValue: 0)
        }
    }

    private struct SlideB {
        let category: String
        let visualImageName: String
        let gradient: LinearGradient
        let title: String
        let subtitle: String
    }

    private let slides: [SlideB] = [
        SlideB(
            category: "Photos",
            visualImageName: "OnboardingBVisualPhotos",
            gradient: LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x78BAFF), location: 0.0),
                    .init(color: Color(hex: 0x0752CC), location: 0.60)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            ),
            title: "More space.\nMore possibilities.",
            subtitle: "Find duplicate photos and large videos. Keep what matters and make room for more."
        ),
        SlideB(
            category: "Contacts",
            visualImageName: "OnboardingBVisualContacts",
            gradient: LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x76D1F0), location: 0.0),
                    .init(color: Color(hex: 0x087AA8), location: 0.55)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            ),
            title: "Less clutter.\nMore clarity.",
            subtitle: "Bring contacts and calendar back in order. Review duplicates and events you no longer need."
        ),
        SlideB(
            category: "Security Center",
            visualImageName: "OnboardingBVisualSecurity",
            gradient: LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x71B8EF), location: 0.0),
                    .init(color: Color(hex: 0x163EAA), location: 0.65)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            ),
            title: "Your security.\nA clearer picture.",
            subtitle: "Explore email breach checks, password strength and device settings — all in one place."
        )
    ]

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top TabView with gradient cards
                TabView(selection: $index) {
                    ForEach(slides.indices, id: \.self) { i in
                        slideCard(slides[i])
                            .tag(i)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Bottom bar: Page indicator + Continue button
                VStack(spacing: 16) {
                    // Page indicator
                    HStack(spacing: 6) {
                        ForEach(slides.indices, id: \.self) { i in
                            if i == index {
                                Capsule()
                                    .fill(Color(hex: 0x0048AE))
                                    .frame(width: 24, height: 8)
                            } else {
                                Circle()
                                    .fill(Color(hex: 0xD0D7DE))
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: index)

                    // Pinned Continue button
                    Button(action: next) {
                        Text("Continue")
                            .font(Palette.font(17, .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color(hex: 0x0048AE), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("qa/onboarding_continue")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
                .padding(.top, 10)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("Onboarding page \(index + 1)")
        .onAppear {
            Telemetry.shared.setUserProperty("b", .onboardingVersion)
            Telemetry.shared.track(.onboardingStart, parameters: ["onboarding_version": "b"])
            Telemetry.shared.track(.onboardingScreenShown, parameters: ["onboarding_version": "b", "screen_index": "\(index + 1)"])
        }
        .onChange(of: index) { _, value in
            Telemetry.shared.track(.onboardingScreenShown, parameters: ["onboarding_version": "b", "screen_index": "\(value + 1)"])
        }
    }

    private func slideCard(_ slide: SlideB) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            // Visual with floating cards matching Figma (already includes category header)
            Image(slide.visualImageName)
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 16)

            Spacer(minLength: 16)

            // Titles inside gradient container
            VStack(spacing: 12) {
                Text(slide.title)
                    .font(Palette.font(28, .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(slide.subtitle)
                    .font(Palette.font(16, .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 12)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(slide.gradient, in: RoundedRectangle(cornerRadius: 24))
    }

    private func next() {
        Tactile.tap()
        if index < slides.count - 1 {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                index += 1
            }
        } else {
            Telemetry.shared.track(.onboardingPassed, parameters: ["onboarding_version": "b"])
            onComplete()
        }
    }
}
