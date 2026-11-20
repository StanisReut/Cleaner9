import StoreKit
import UIKit

@MainActor
enum ReviewRequester {
    private static var didRequestThisSession = false

    static func requestReviewIfAppropriate() {
        guard !didRequestThisSession else { return }
        didRequestThisSession = true
        
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                SKStoreReviewController.requestReview(in: windowScene)
            }
        }
    }
}
