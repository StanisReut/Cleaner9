import Foundation
import StoreKit
import SwiftyStoreKit
import AppsFlyerLib

protocol UserAcquisitionProviding: AnyObject {
    func start()
    func logPurchase(productID: String, price: Decimal, currency: String)
    func setAttribution(_ values: [String: String])
    func refund(consented: Bool)
}

/// Global interface for UserAcquisition per specification:
/// UserAcquisition.shared.configure(withAPIKey: "...")
final class UserAcquisition: NSObject {
    static let shared = UserAcquisition()

    private(set) var service: UserAcquisitionService?

    var conversionInfo: UserAcquisitionService.Info {
        get { service?.conversionInfo ?? UserAcquisitionService.Info() }
        set { service?.conversionInfo = newValue }
    }

    func configure(
        withAPIKey apiKey: String = AnalyticsConfig.userAcquisitionAPIKey,
        serverUrl: String = AnalyticsConfig.userAcquisitionServerURL,
        sharedSecret: String = AnalyticsConfig.appStoreSharedSecret
    ) {
        service = UserAcquisitionService(
            apiKey: apiKey,
            serverUrl: serverUrl,
            sharedSecret: sharedSecret,
            appleReceiptValidator: .production
        )
        #if DEBUG
        print("📊 [UserAcquisition] configured with API key: \(apiKey.prefix(6))..., server: \(serverUrl)")
        #endif
    }

    func logPurchase(of product: Product) {
        guard let service else {
            #if DEBUG
            print("⚠️ [UserAcquisition] logPurchase skipped — service not configured")
            #endif
            return
        }
        Task {
            await service.logPurchase(of: product)
        }
    }

    func logPurchase(of product: SKProduct) {
        guard let service else { return }
        Task {
            await service.logPurchase(of: product)
        }
    }

    func log(pushDeviceToken: String, and originalTransactionID: String) {
        guard let service else { return }
        Task {
            await service.log(pushDeviceToken: pushDeviceToken, and: originalTransactionID)
        }
    }

    func refund(consented: Bool) {
        guard let service else { return }
        Task {
            await service.refund(consented: consented)
        }
    }
}

final class UserAcquisitionAdapter: UserAcquisitionProviding {
    func start() {
        UserAcquisition.shared.configure(
            withAPIKey: AnalyticsConfig.userAcquisitionAPIKey,
            serverUrl: AnalyticsConfig.userAcquisitionServerURL,
            sharedSecret: AnalyticsConfig.appStoreSharedSecret
        )
    }

    func logPurchase(productID: String, price: Decimal, currency: String) {
        #if DEBUG
        print("📊 [UserAcquisition] purchase receipt flow active for \(productID) \(price) \(currency)")
        #endif
    }

    func setAttribution(_ values: [String: String]) {
        UserAcquisition.shared.conversionInfo.setAppsFlyerData(values)
        UserAcquisition.shared.conversionInfo.appsFlyerId = AppsFlyerLib.shared().getAppsFlyerUID()
    }

    func refund(consented: Bool) {
        UserAcquisition.shared.refund(consented: consented)
    }
}
