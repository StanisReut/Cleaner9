import AppTrackingTransparency
import UIKit

enum Tracking {
    @MainActor
    static func request() async -> ATTrackingManager.AuthorizationStatus {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            return ATTrackingManager.trackingAuthorizationStatus
        }
        while UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(300))
        return await ATTrackingManager.requestTrackingAuthorization()
    }
}
