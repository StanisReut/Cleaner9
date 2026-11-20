import AdSupport
import Foundation
import StoreKit
import SwiftyStoreKit

/// Service for tracking user acquisition and purchase analytics
final class UserAcquisitionService: NSObject, UserAcquisitionProtocol {
    
    var conversionInfo = UserAcquisitionService.Info()
    
    /// API endpoints for the user acquisition service
    enum Endpoints: String {
        case receipt = "/v2/receipt"
        case pushToken = "/v2/ios/push_token"
        case userInfo = "/v1/ios/user_info"
    }
    
    private let apiKey: String
    private let serverUrl: String
    private let sharedSecret: String
    private let appleReceiptValidator: AppleReceiptValidator.VerifyReceiptURLType

    init(
        apiKey: String,
        serverUrl: String,
        sharedSecret: String,
        appleReceiptValidator: AppleReceiptValidator.VerifyReceiptURLType
    ) {
        self.apiKey = apiKey
        self.serverUrl = serverUrl
        self.sharedSecret = sharedSecret
        self.appleReceiptValidator = appleReceiptValidator
    }
    
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }
    
    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }
    
    private var bundleId: String {
        Bundle.main.bundleIdentifier ?? "-"
    }
}

extension UserAcquisitionService {
    /// Processes a refund request with user consent
    /// - Parameter consented: Whether the user has consented to the refund
    func refund(consented: Bool) async {
        let appleReceiptValidator = AppleReceiptValidator(
            service: .production,
            sharedSecret: sharedSecret
        )
        do {
            let receipt = try await verifyReceipt(appleReceiptValidator: appleReceiptValidator)
            let params: [String: Any] = [
                "api_key": apiKey,
                "original_transaction_ids": extractOriginalTransactionIDs(from: receipt),
                "customer_consented": consented
            ]
            
            try await requestToServer(
                params: params,
                endPoint: .userInfo
            )
        } catch {
            print(error.localizedDescription)
        }
    }
    
    /// Logs push device token with original transaction ID
    /// - Parameters:
    ///   - pushDeviceToken: The device's push notification token
    ///   - originalTransactionID: The original transaction ID
    func log(
        pushDeviceToken: String,
        and originalTransactionID: String
    ) async {
        let params: [String: Any] = [
            "api_key": apiKey,
            "push_token": pushDeviceToken,
            "original_transaction_id": originalTransactionID,
        ]
        
        do {
            try await requestToServer(
                params: params,
                endPoint: .pushToken
            )
        } catch {
            print(error.localizedDescription)
        }
    }
    
    /// Logs a purchase of an SKProduct
    /// - Parameter product: The SKProduct that was purchased
    func logPurchase(of product: SKProduct) async {
        do {
            let receipt = try await fetchReceipt()
            self.logPurchase(
                info: self.conversionInfo,
                skProduct: product,
                receipt: receipt
            )
        } catch {
            print(error.localizedDescription)
        }
    }
    
    /// Logs a purchase of a StoreKit 2 Product
    /// - Parameter product: The Product that was purchased
    func logPurchase(of product: Product) async {
        do {
            let receipt = try await fetchReceipt()
            self.logPurchase(
                info: self.conversionInfo,
                product: product,
                receipt: receipt
            )
        } catch {
            print(error.localizedDescription)
        }
    }
    
    /// Sets an extra value for tracking purposes
    /// - Parameters:
    ///   - value: The value to store
    ///   - key: The key to associate with the value
    func setExtraValue(
        _ value: Any,
        forKey key: String
    ) {
        conversionInfo.extra[key] = value
    }
}

private extension UserAcquisitionService {
    func verifyReceipt(appleReceiptValidator: AppleReceiptValidator) async throws -> ReceiptInfo {
        try await withCheckedThrowingContinuation { (continuation) in
            SwiftyStoreKit.verifyReceipt(using: appleReceiptValidator) { (result) in
                switch result {
                case let .success(receipt):
                    continuation.resume(returning: receipt)
                case let .error(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func fetchReceipt() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation) in
            SwiftyStoreKit.fetchReceipt(forceRefresh: false) { result in
                switch result {
                case let .success(receiptData):
                    let receipt = receiptData.base64EncodedString()
                    continuation.resume(returning: receipt)
                case let .error(error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
    func logPurchase(
        info: Info,
        skProduct: SKProduct? = nil,
        product: Product? = nil,
        receipt: String
    ) {
        var acquisitionSource: String {
            switch info.acquisitionSource {
            case .facebook:
                return "Facebook"
            case .searchAds:
                return "Search Ads"
            case .organic:
                return "Organic"
            case let .custom(source):
                return source
            }
        }
        
        var afi: String {
            return ASIdentifierManager.shared().advertisingIdentifier.uuidString
        }
        
        var iap: [String: Any] = [:]
        
        if let skProduct {
            iap = [
                "product_id": skProduct.productIdentifier,
                "price": skProduct.price.stringValue,
                "currency": skProduct.priceLocale.currency?.identifier ?? ""
            ]
        } else if let product {
            iap = [
                "product_id": product.id,
                "price": NSDecimalNumber(decimal: product.price).stringValue,
                "currency": product.priceFormatStyle.locale.currency?.identifier ?? ""
            ]
        }
        
        var extra: [String: Any] = [
            "acquisition_source": acquisitionSource,
            "acquisition_date": Int(info.acquisitionDate.timeIntervalSince1970),
            "ad_campaign": info.adCampaign,
            "ad_group": info.adGroup,
            "ad_creative": info.adCreative,
            "vendor_id": UIDevice.current.identifierForVendor?.uuidString ?? "",
            "appsflyer_id": info.appsFlyerId,
            "appmetrica_device_id": info.appmetricaId,
            "amplitude_device_id": info.amplitudeId,
            "adjust_raw": info.adjustRaw,
            "appsflyer_raw": info.appsFlyerRaw,
            "searchads_raw": info.searchAdsRaw,
            "branch_raw": info.branchRaw,
            "fb_anonymous_id": info.fbAnonymousId,
            "version_app": appVersion,
            "build_app": appBuild
        ]
        
        for (field, value) in info.extra {
            extra[field] = value
        }
        
        let params: [String: Any?] = [
            "bundle_id": bundleId,
            "afi": afi,
            "receipt": receipt,
            "iap": iap,
            "country": skProduct?.priceLocale.region?.identifier ?? product?.priceFormatStyle.locale.region?.identifier ?? "",
            "extra": extra,
            "api_key": apiKey,
        ]
        
        Task {
            try await requestToServer(
                params: params,
                endPoint: .receipt
            )
        }
    }
    
    func extractOriginalTransactionIDs(from receipt: ReceiptInfo) -> [String] {
        var originalTransactionIDs = [String]()
        
        if let latestReceipts = receipt["latest_receipt_info"] as? [[String: Any]] {
            for receiptInfo in latestReceipts {
                if let originalID = receiptInfo["original_transaction_id"] as? String {
                    originalTransactionIDs.append(originalID)
                }
            }
        }
        
        return Array(Set(originalTransactionIDs))
    }
}

///TODO: - Request to server
extension UserAcquisitionService {
     func requestToServer(
        params: [String: Any?],
        endPoint: Endpoints
    ) async throws {
        let url = URL(string: "https://" + serverUrl + endPoint.rawValue)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try! JSONSerialization.data(withJSONObject: params)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data)
        print("UserAcquisitionService JSON: \(json)")
    }
}

private extension UserAcquisitionService {
    var isConversionUser: Bool {
        if case .organic = conversionInfo.acquisitionSource {
            return false
        } else {
            return true
        }
    }
}

extension UserAcquisitionService {
    struct Info {
        enum AcquisitionSource {
            case organic, facebook, searchAds, custom(String)
        }
        
        var userId: String?
        var acquisitionSource: AcquisitionSource = .organic
        var acquisitionDate = Date()
        var adCampaign = ""
        var adGroup = ""
        var adCreative = ""
        var appsFlyerId = ""
        var appmetricaId = ""
        var amplitudeId = ""
        var fbAnonymousId = ""
        var adjustRaw = ""
        var appsFlyerRaw = ""
        var searchAdsRaw = ""
        var branchRaw = ""
        var extra = [String: Any]()
        
        mutating func setAppsFlyerData(_ appsFlyerData: [String: Any]) {
            if let jsonData = try? JSONSerialization.data(withJSONObject: appsFlyerData, options: .prettyPrinted) {
                appsFlyerRaw = String(data: jsonData, encoding: .utf8) ?? ""
            }
            
            let status = appsFlyerData["af_status"] as? String ?? ""
            let source = appsFlyerData["media_source"] as? String ?? ""
            let campaign = appsFlyerData["campaign"] as? String ?? ""
            let campaignId = appsFlyerData["campaign_id"] as? String ?? ""
            let adSet = appsFlyerData["adset"] as? String ?? ""
            let adSetId = appsFlyerData["adset_id"] as? String ?? ""
            let ad = appsFlyerData["ad"] as? String ?? ""
            let adId = appsFlyerData["ad_id"] as? String ?? ""
            print(appsFlyerData)
            var acquisitionSource: UserAcquisitionService.Info.AcquisitionSource {
                switch status {
                case "Non-organic":
                    switch source {
                    case "Facebook Ads":
                        return .facebook
                    default:
                        return .custom(source)
                    }
                case "Organic":
                    return .organic
                default:
                    return .custom("Undefined")
                }
            }
            var acquisitionDate: Date {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-DD mm:HH:ss.SSS"
                return formatter.date(from: appsFlyerData["install_time"] as? String ?? "") ?? Date()
            }
            func merged(_ str1: String, _ str2: String) -> String {
                if str2 == "" {
                    return str1
                } else {
                    return "\(str1) (\(str2))"
                }
            }
            self.acquisitionSource = acquisitionSource
            self.acquisitionDate = acquisitionDate
            adCampaign = merged(campaign, campaignId)
            adGroup = merged(adSet, adSetId)
            adCreative = merged(ad, adId)
        }
    }
}
