import SwiftUI

struct OnboardingFlow: View {
    let configuration: AppConfiguration
    let onComplete: () -> Void

    private var activeVariant: OnboardingVariant {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--qa-onboarding-b") { return .b }
        if args.contains("--qa-onboarding-privacy") || args.contains("--qa-onboarding-new-a") { return .privacyA }
        if args.contains("--qa-onboarding-security") || args.contains("--qa-onboarding-new-b") { return .securityB }
        if let idx = args.firstIndex(of: "--qa-onboarding"), args.indices.contains(idx + 1) {
            let val = args[idx + 1]
            return OnboardingVariant(rawValue: val) ?? configuration.onboardingVariant
        }
        return configuration.onboardingVariant
    }

    var body: some View {
        switch activeVariant {
        case .a:
            OnboardingVariantA(configuration: configuration, onComplete: onComplete)
        case .b:
            OnboardingVariantB(configuration: configuration, onComplete: onComplete)
        case .privacyA:
            OnboardingVariantPrivacy(configuration: configuration, onComplete: onComplete)
        case .securityB:
            OnboardingVariantSecurity(configuration: configuration, onComplete: onComplete)
        }
    }
}
