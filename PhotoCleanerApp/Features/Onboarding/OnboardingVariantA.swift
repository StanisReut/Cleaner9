//
//  OnboardingVariantA.swift
//  PhotoCleanerApp
//
//  Created by Stanislau Reut on 09/11/2026.
//

import SwiftUI

struct OnboardingVariantA: View {
    let configuration: AppConfiguration
    let onComplete: () -> Void
    @State private var index: Int = {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "--qa-onboarding-step"), args.indices.contains(idx + 1) {
            return Int(args[idx + 1]) ?? 0
        }
        return 0
    }()

    private struct PageData {
        let artImage: String
        let sectionHeader: String?
        let title: String
        let subtitle: String
    }

    private let pages: [PageData] = [
        PageData(
            artImage: "Onboarding3DPhotos",
            sectionHeader: "Photos",
            title: "Free up space",
            subtitle: "Find duplicate photos and large videos. Keep the memories that matter."
        ),
        PageData(
            artImage: "Onboarding3DContacts",
            sectionHeader: "Contacts",
            title: "Clear the clutter",
            subtitle: "Organize duplicate contacts and remove calendar events you don't need."
        ),
        PageData(
            artImage: "Onboarding3DSecurity",
            sectionHeader: nil,
            title: "Check your security",
            subtitle: "Review email breaches, passwords and your device security settings."
        )
    ]

    var body: some View {
        ZStack {
            // Figma Background: Smooth sky gradient fading to clean light surface
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x95C7FF), location: 0.0),
                    .init(color: Color(hex: 0xC4E0FF), location: 0.32),
                    .init(color: Color(hex: 0xEAF4FF), location: 0.60),
                    .init(color: Color(hex: 0xF3F8FF), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Interactive Swipeable Page Container
                TabView(selection: $index) {
                    ForEach(pages.indices, id: \.self) { i in
                        pageContent(pages[i], at: i)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Bottom Controls: Page Dots + Continue Button
                VStack(spacing: 20) {
                    // Page indicator dots
                    HStack(spacing: 8) {
                        ForEach(pages.indices, id: \.self) { dot in
                            Capsule()
                                .fill(dot == index ? Color(hex: 0x0048AE) : Color(hex: 0xB9D5F4))
                                .frame(width: dot == index ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: index)
                        }
                    }

                    // Primary Continue CTA
                    Button(action: next) {
                        Text("Continue")
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
                            .shadow(color: Color(hex: 0x0051C7).opacity(0.28), radius: 12, y: 6)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("qa/onboarding_continue")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Onboarding page \(index + 1)")
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if let idx = args.firstIndex(of: "--qa-onboarding-step"), args.indices.contains(idx + 1), let val = Int(args[idx + 1]) {
                index = val
            }
            let version = "a"
            Telemetry.shared.setUserProperty(version, .onboardingVersion)
            Telemetry.shared.track(.onboardingStart, parameters: ["onboarding_version": version])
            Telemetry.shared.track(.onboardingScreenShown, parameters: ["onboarding_version": version, "screen_index": "\(index + 1)"])
        }
        .onChange(of: index) { _, value in
            Telemetry.shared.track(.onboardingScreenShown, parameters: ["onboarding_version": "a", "screen_index": "\(value + 1)"])
        }
    }

    // MARK: - Slide Content View
    @ViewBuilder
    private func pageContent(_ page: PageData, at pageIndex: Int) -> some View {
        VStack(spacing: 0) {
            // 3D Floating Illustration
            Image(page.artImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 320, maxHeight: 260)
                .padding(.top, 8)

            Spacer(minLength: 8)

            // Live Native App Interface Card
            nativePreviewCard(for: pageIndex)
                .padding(.horizontal, 20)

            Spacer(minLength: 16)

            // Title & Description
            VStack(spacing: 8) {
                Text(page.title)
                    .font(Palette.font(28, .semibold))
                    .foregroundStyle(Color(hex: 0x122640))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(page.subtitle)
                    .font(Palette.font(16))
                    .foregroundStyle(Color(hex: 0x3B5269))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Native Preview Cards (Figma Pixel-Perfect)
    @ViewBuilder
    private func nativePreviewCard(for pageIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if pageIndex == 0 {
                // Section Header
                Text("Photos")
                    .font(Palette.font(14, .semibold))
                    .foregroundStyle(Color(hex: 0x0051C7))
                    .padding(.leading, 4)

                // White Duplicates Card with cats photo
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Duplicates")
                            .font(Palette.font(17, .bold))
                            .foregroundStyle(Color(hex: 0x122640))

                        Text("88 photos · 800 MB")
                            .font(Palette.font(14))
                            .foregroundStyle(Color(hex: 0x738294))
                    }

                    Spacer()

                    Image("ScanCat")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.06), radius: 16, y: 8)
                )
            } else if pageIndex == 1 {
                // Section Header
                Text("Contacts")
                    .font(Palette.font(14, .semibold))
                    .foregroundStyle(Color(hex: 0x0051C7))
                    .padding(.leading, 4)

                // White Contacts Duplicates Card
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: 0xEAF2FD))
                            .frame(width: 44, height: 44)

                        Image(systemName: "person.2.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0051C7))
                    }

                    Text("Duplicates")
                        .font(Palette.font(17, .bold))
                        .foregroundStyle(Color(hex: 0x122640))

                    Spacer()

                    Text("12")
                        .font(Palette.font(17, .bold))
                        .foregroundStyle(Color(hex: 0x0051C7))

                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: 0xC2D4EB))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.06), radius: 16, y: 8)
                )
            } else {
                // White Security Card
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: 0xEAF2FD))
                            .frame(width: 44, height: 44)

                        Image(systemName: "envelope.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x0051C7))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email Leakage")
                            .font(Palette.font(17, .bold))
                            .foregroundStyle(Color(hex: 0x122640))

                        Text("Check for reported breaches.")
                            .font(Palette.font(13))
                            .foregroundStyle(Color(hex: 0x738294))

                        // Red/Salmon Badge: Issues found
                        HStack(spacing: 4) {
                            Text("Issues found")
                                .font(Palette.font(12, .semibold))
                                .foregroundStyle(Color(hex: 0xE53935))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: 0xFDECEE), in: RoundedRectangle(cornerRadius: 6))
                    }

                    Spacer()

                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: 0xC2D4EB))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.06), radius: 16, y: 8)
                )
            }
        }
    }

    private func next() {
        Tactile.tap()
        if index < pages.count - 1 {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                index += 1
            }
        } else {
            Telemetry.shared.track(.onboardingPassed, parameters: ["onboarding_version": "a"])
            onComplete()
        }
    }
}
