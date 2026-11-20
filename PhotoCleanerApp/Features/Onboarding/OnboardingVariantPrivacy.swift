import SwiftUI

struct OnboardingVariantPrivacy: View {
    let configuration: AppConfiguration
    let onComplete: () -> Void
    @State private var step = 0
    @State private var progress: CGFloat = 0.0

    private let totalSteps = 4

    var body: some View {
        ZStack {
            Color(hex: 0x0A0F1D).ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Story Progress Bars
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.2))
                                if i < step {
                                    Capsule().fill(.white)
                                } else if i == step {
                                    Capsule().fill(.white)
                                }
                            }
                        }
                        .frame(height: 3)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer(minLength: 16)

                // Main card content with interactive swiping
                TabView(selection: $step) {
                    deviceRiskCard.tag(0)
                    storageCard.tag(1)
                    credentialCard.tag(2)
                    protectionCard.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .padding(.horizontal, 20)

                Spacer(minLength: 20)

                // Bottom CTA button
                Button(action: next) {
                    Text(step == totalSteps - 1 ? "Protect your data" : "Continue")
                        .font(Palette.font(17, .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: step == totalSteps - 1 ? [Color(hex: 0x0051C7), Color(hex: 0x4B8DE4)] : [Color(hex: 0x2A324B), Color(hex: 0x3E4A6F)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("qa/onboarding_continue")
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("Onboarding page \(step + 1)")
        .onAppear {
            Telemetry.shared.setUserProperty("privacy_a", .onboardingVersion)
            Telemetry.shared.track(.onboardingStart, parameters: ["onboarding_version": "privacy_a"])
            Telemetry.shared.track(.onboardingScreenShown, parameters: ["onboarding_version": "privacy_a", "screen_index": "\(step + 1)"])
        }
    }

    // Step 0: Device risk / phishing
    private var deviceRiskCard: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: 0xFF5C5C))
                    Text("Fake delivery page")
                        .font(Palette.font(14, .bold))
                        .foregroundStyle(Color(hex: 0xFF5C5C))
                    Spacer()
                    Text("Example phishing")
                        .font(Palette.font(12))
                        .foregroundStyle(.white.opacity(0.6))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("parcel-help.example")
                        .font(Palette.font(13))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Your parcel is on hold.")
                        .font(Palette.font(18, .semibold))
                        .foregroundStyle(.white)
                    Text("Confirm delivery  ↗")
                        .font(Palette.font(14, .medium))
                        .foregroundStyle(Color(hex: 0x58A6FF))
                }
                .padding(16)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

                HStack {
                    Image(systemName: "key.fill")
                        .foregroundStyle(Color(hex: 0xFFA154))
                    Text("Password requested")
                        .font(Palette.font(14, .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("••••••••")
                        .font(Palette.font(14))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(14)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(20)
            .background(Color(hex: 0x161D31), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(hex: 0xFF5C5C).opacity(0.3), lineWidth: 1.5))

            VStack(spacing: 8) {
                Text("Your device could\nbe at risk!")
                    .font(Palette.font(26, .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Phishing sites and malicious links try to steal passwords and personal info.")
                    .font(Palette.font(15))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    // Step 1: Storage
    private var storageCard: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color(hex: 0xFF5C5C))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iPhone Storage")
                            .font(Palette.font(16, .semibold))
                            .foregroundStyle(.white)
                        Text("120 GB used of 128 GB (94%)")
                            .font(Palette.font(13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(
                            LinearGradient(colors: [Color(hex: 0xFF5C5C), Color(hex: 0xFFA154)], startPoint: .leading, endPoint: .trailing)
                        ).frame(width: geo.size.width * 0.94)
                    }
                }
                .frame(height: 12)

                HStack {
                    Text("Only 8 GB free space remaining")
                        .font(Palette.font(13))
                        .foregroundStyle(Color(hex: 0xFFA154))
                    Spacer()
                }
            }
            .padding(20)
            .background(Color(hex: 0x161D31), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.12), lineWidth: 1))

            VStack(spacing: 8) {
                Text("Your iPhone is\nalmost full!")
                    .font(Palette.font(26, .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Duplicates and clutter slow down your device. Clean gigabytes in seconds.")
                    .font(Palette.font(15))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    // Step 2: Credential exposure
    private var credentialCard: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(hex: 0xFF5C5C))
                    Text("alex@example.com")
                        .font(Palette.font(15, .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("Found in leaks")
                        .font(Palette.font(11, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: 0xFF5C5C), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Password: ••••  ••••  •••• ••••")
                        .font(Palette.font(13))
                        .foregroundStyle(.white.opacity(0.8))
                    HStack(spacing: 6) {
                        Text("Strength:")
                            .font(Palette.font(12))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("Weak")
                            .font(Palette.font(12, .bold))
                            .foregroundStyle(Color(hex: 0xFF5C5C))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                Text("Change this password anywhere you reuse it.")
                    .font(Palette.font(13))
                    .foregroundStyle(Color(hex: 0xFFA154))
            }
            .padding(20)
            .background(Color(hex: 0x161D31), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.12), lineWidth: 1))

            VStack(spacing: 8) {
                Text("Possible email and\npassword leak!")
                    .font(Palette.font(26, .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Breached databases expose credentials online. Stay ahead of security issues.")
                    .font(Palette.font(15))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    // Step 3: Protection
    private var protectionCard: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color(hex: 0x1CB450))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Privacy & Storage Guard")
                            .font(Palette.font(17, .semibold))
                            .foregroundStyle(.white)
                        Text("Comprehensive device protection")
                            .font(Palette.font(13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                VStack(spacing: 10) {
                    protectionBenefit(title: "Smart Photo & Video Cleanup", icon: "photo.stack")
                    protectionBenefit(title: "Contacts & Calendar Clutter Shield", icon: "person.crop.circle.badge.checkmark")
                    protectionBenefit(title: "Email & Password Breach Monitor", icon: "lock.shield")
                }
            }
            .padding(20)
            .background(Color(hex: 0x161D31), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(hex: 0x1CB450).opacity(0.3), lineWidth: 1.5))

            VStack(spacing: 8) {
                Text("Keep your personal\ndata private.")
                    .font(Palette.font(26, .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Protect your photos, storage, and identity with Cleaner all-in-one suite.")
                    .font(Palette.font(15))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func protectionBenefit(title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Palette.blue)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            Text(title)
                .font(Palette.font(14, .medium))
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: 0x1CB450))
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func next() {
        Tactile.tap()
        if step < totalSteps - 1 {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                step += 1
            }
            Telemetry.shared.track(.onboardingScreenShown, parameters: ["onboarding_version": "privacy_a", "screen_index": "\(step + 1)"])
        } else {
            Telemetry.shared.track(.onboardingPassed, parameters: ["onboarding_version": "privacy_a"])
            onComplete()
        }
    }
}
