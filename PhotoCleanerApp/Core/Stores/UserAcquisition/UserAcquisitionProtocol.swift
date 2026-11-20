import Foundation
import StoreKit

/// Protocol for user acquisition tracking and analytics
protocol UserAcquisitionProtocol {
    var conversionInfo: UserAcquisitionService.Info { get set }
    
    /// Processes a refund request with user consent
    /// - Parameter consented: Whether the user has consented to the refund
    func refund(consented: Bool) async
    
    /// Logs push device token with original transaction ID
    /// - Parameters:
    ///   - pushDeviceToken: The device's push notification token
    ///   - originalTransactionID: The original transaction ID
    func log(
        pushDeviceToken: String,
        and originalTransactionID: String
    ) async
    
    /// Logs a purchase of an SKProduct
    /// - Parameter product: The SKProduct that was purchased
    func logPurchase(of product: SKProduct) async
    
    /// Logs a purchase of a StoreKit 2 Product
    /// - Parameter product: The Product that was purchased
    func logPurchase(of product: Product) async
    
    /// Sets an extra value for tracking purposes
    /// - Parameters:
    ///   - value: The value to store
    ///   - key: The key to associate with the value
    func setExtraValue(
        _ value: Any,
        forKey key: String
    )
}
