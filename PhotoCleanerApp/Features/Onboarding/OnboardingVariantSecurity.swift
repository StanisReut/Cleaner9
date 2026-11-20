import SwiftUI

struct OnboardingVariantSecurity: View {
    let configuration: AppConfiguration
    let onComplete: () -> Void
    @State private var step = 0
    @State private var beaconPulse = false

    private let totalSteps = 4

    var body: some View {
        ZStack {
            // Elegant dark blue background
            Color(hex: 0x0C1222).ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Progress indicator
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Capsule()
                            .fill(i == step ? Color(hex: 0x3882F6) : Color.white.opacity(0.18))
                            .frame(height: 4)
                            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: step)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer(minLength: 16)

                // Main card content with interactive swiping
                TabView(selection: $step) {
                    deviceSecurityCard.tag(0)
                    emailCheckCard.tag(1)
                    storageFreedCard.tag(2)
                    accountPrivacyCard.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .padding(.horizontal, 20)

                Spacer(minLength: 20)

                // Bottom CTA Button
                Button(action: next) {
                    Text(step == totalSteps - 1 ? "Protect your data" : "Continue")
                        .font(Palette.font(17, .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: 0x0051C7), Color(hex: 0x4B8DE4)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 16)
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
            beaconPulse = true
            Telemetry.shared.setUserProperty("security_b", .onboardingVersion)
            Telemetry.shared.track(.onboardingStart, parameters: ["onboarding_version": "security_b"])
            Telemetry.shared.track(.onboardingScreenShown, parameters: ["onboarding_version": "security_b", "screen_index": "\(step + 1)"])
        }
    }

    // Step 0: Device security
    private var deviceSecurityCard: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color(hex: 0xFF5C5C).opacity(beaconPulse ? 0.3 : 0.1))
                            .frame(width: 28, height: 28)
                            .scaleEffect(beaconPulse ? 1.25 : 1.0)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: beaconPulse)
                        Circle()
                            .fill(Color(hex: 0xFF5C5C))
                            .frame(width: 12, height: 12)
                    }
                    Text("iPhone security")
                        .font(Palette.font(16, .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("2 settings to review")
                        .font(Palette.font(12, .semibold))
                        .foregroundStyle(Color(hex: 0xFFA154))
                }

                VStack(spacing: 10) {
                    securityRow(icon: "lock.fill", title: "Device passcode", status: "Set", statusColor: Color(hex: 0x1CB450))
                    securityRow(icon: "person.badge.key.fill", title: "Apple Account", status: "Review 2FA", statusColor: Color(hex: 0xFFA154))
                    securityRow(icon: "arrow.triangle.2.circlepath", title: "iOS updates", status: "Review", statusColor: Color(hex: 0xFFA154))
                }
            }
            .padding(20)
            .background(Color(hex: 0x151C2F), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.12), lineWidth: 1))

            VStack(spacing: 8) {
                Text("Could someone\nsign in as you?")
                    .font(Palette.font(26, .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Review your essential device settings and verify who has access to your accounts.")
                    .font(Palette.font(15))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    // Step 1: Email check
    private var emailCheckCard: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(hex: 0xFF5C5C))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Email Leakage")
                            .font(Palette.font(16, .semibold))
                            .foregroundStyle(.white)
                        Text("maya@example.com")
                            .font(Palette.font(13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Text("2 reported breaches")
                        .font(Palette.font(11, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: 0xFF5C5C), in: Capsule())
                }

                VStack(spacing: 8) {
                    breachRow(name: "Northline Forum", date: "Mar 18, 2024", exposed: "Email address, username")
                    breachRow(name: "Juniper Club", date: "Sep 6, 2023", exposed: "Email address, password hash")
                }
            }
            .padding(20)
            .background(Color(hex: 0x151C2F), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(hex: 0xFF5C5C).opacity(0.3), lineWidth: 1.5))

            VStack(spacing: 8) {
                Text("Was your email in\na data breach?")
                    .font(Palette.font(26, .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Get instant alerts when your credentials appear in known public security breaches.")
                    .font(Palette.font(15))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    // Step 2: iPhone storage
    private var storageFreedCard: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(hex: 0x1CB450))
                    Text("32 GB freed")
                        .font(Palette.font(16, .bold))
                        .foregroundStyle(Color(hex: 0x1CB450))
                    Spacer()
                    Text("Storage cleaned")
                        .font(Palette.font(12))
                        .foregroundStyle(.white.opacity(0.6))
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Before")
                            .font(Palette.font(12, .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("126.7 GB")
                            .font(Palette.font(18, .bold))
                            .foregroundStyle(Color(hex: 0xFF5C5C))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("After")
                            .font(Palette.font(12, .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("94.7 GB")
                            .font(Palette.font(18, .bold))
                            .foregroundStyle(Color(hex: 0x1CB450))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(20)
            .background(Color(hex: 0x151C2F), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.12), lineWidth: 1))

            VStack(spacing: 8) {
                Text("Free up space\non your iPhone.")
                    .font(Palette.font(26, .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Remove duplicate files, large videos, and bloated cache with one simple scan.")
                    .font(Palette.font(15))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    // Step 3: Account privacy
    private var accountPrivacyCard: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("ACCOUNT PRIVACY")
                    .font(Palette.font(12, .bold))
                    .foregroundStyle(Palette.blue)
                    .tracking(1.2)

                VStack(spacing: 10) {
                    securityRow(icon: "applelogo", title: "Apple Account", status: "Protected", statusColor: Color(hex: 0x1CB450))
                    securityRow(icon: "shield.lefthalf.filled", title: "Sign-in settings", status: "Reviewed", statusColor: Color(hex: 0x1CB450))
                    securityRow(icon: "envelope.fill", title: "Email monitor", status: "Active", statusColor: Color(hex: 0x1CB450))
                }
            }
            .padding(20)
            .background(Color(hex: 0x151C2F), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(hex: 0x3882F6).opacity(0.4), lineWidth: 1.5))

            VStack(spacing: 8) {
                Text("Who can access\nyour accounts?")
                    .font(Palette.font(26, .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Review your sign-in settings and check your email for known leaks.")
                    .font(Palette.font(15))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func securityRow(icon: String, title: String, status: String, statusColor: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(Palette.font(14, .medium))
                .foregroundStyle(.white)

            Spacer()

            Text(status)
                .font(Palette.font(13, .semibold))
                .foregroundStyle(statusColor)
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    private func breachRow(name: String, date: String, exposed: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(Palette.font(14, .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(date)
                    .font(Palette.font(12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text(exposed)
                .font(Palette.font(12))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func next() {
        Tactile.tap()
        if step < totalSteps - 1 {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                step += 1
            }
            Telemetry.shared.track(.onboardingScreenShown, parameters: ["onboarding_version": "security_b", "screen_index": "\(step + 1)"])
        } else {
            Telemetry.shared.track(.onboardingPassed, parameters: ["onboarding_version": "security_b"])
            onComplete()
        }
    }
}
