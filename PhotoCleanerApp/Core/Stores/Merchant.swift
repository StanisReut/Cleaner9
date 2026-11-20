import Foundation
import StoreKit
import Network
import Observation

enum ProductID: String, CaseIterable, Sendable {
    case weekly = "com.locaest.cleanerapp.weektrial"
    case monthly = "com.locaest.cleanerapp.month"
    case yearly = "com.locaest.cleanerapp.year"
    static let primary: ProductID = .weekly
}

struct PlanDisplay: Sendable {
    let price: String
    let unit: String
    let trialDays: Int?
}

enum MerchantFailure: Error { case cancelled, pending, failed }

@MainActor @Observable
final class Merchant: PurchaseService {
    static let shared = Merchant()
    private(set) var isPremium = false
    private(set) var prices: [ProductID: String] = [:]
    private(set) var plans: [ProductID: PlanDisplay] = [:]
    private var products: [ProductID: Product] = [:]
    private var updatesTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var debugGrant: Bool {
        get { UserDefaults.standard.bool(forKey: "merchant.debugGrant") }
        set { UserDefaults.standard.set(newValue, forKey: "merchant.debugGrant") }
    }

    private init() {}

    func startObservingTransactions() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await self?.refreshEntitlement()
                    await transaction.finish()
                case .unverified(let transaction, let error):
                    Merchant.log("unverified transaction: \(error)")
                    await transaction.finish()
                }
            }
        }
    }

    func preloadProducts() {
        guard preloadTask == nil else { return }
        preloadTask = Task { [weak self] in
            guard let self else { return }
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "cleaner.merchant.reachability")
            monitor.start(queue: queue)
            defer { monitor.cancel(); preloadTask = nil }
            try? await Task.sleep(for: .milliseconds(150))
            var delay: UInt64 = 1
            var wasOffline = false
            while !Task.isCancelled && products.isEmpty {
                guard monitor.currentPath.status == .satisfied else {
                    wasOffline = true
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
                if wasOffline {
                    wasOffline = false
                    delay = 1
                }
                do {
                    let requestedIDs = ProductID.allCases.map(\.rawValue)
                    let loaded = try await Product.products(for: requestedIDs)
                    guard !loaded.isEmpty else {
                        Merchant.log("StoreKit returned 0 products for IDs: \(requestedIDs); retry in \(delay)s")
                        try? await Task.sleep(for: .seconds(delay))
                        delay = min(delay * 2, 60)
                        continue
                    }
                    products = Dictionary(uniqueKeysWithValues: loaded.compactMap { product in ProductID(rawValue: product.id).map { ($0, product) } })
                    prices = products.mapValues(\.displayPrice)
                    plans = products.mapValues { product in
                        let subscription = product.subscription?.subscriptionPeriod
                        let unit = subscription.map { Self.unit(for: $0) } ?? "—"
                        let trial = product.subscription?.introductoryOffer?.paymentMode == .freeTrial ? product.subscription?.introductoryOffer?.period.value : nil
                        return PlanDisplay(price: product.displayPrice, unit: unit, trialDays: trial)
                    }
                    Merchant.log("products loaded: \(prices)")
                    break
                } catch {
                    Merchant.log("products not loaded; retry in \(delay)s: \(error)")
                    try? await Task.sleep(for: .seconds(delay))
                    delay = min(delay * 2, 60)
                }
            }
        }
    }

    func refreshEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > Date() }) ?? true else { continue }
            if ProductID(rawValue: transaction.productID) != nil { active = true }
        }
        isPremium = active || debugGrant
    }

    func purchase(_ item: ProductID) async throws {
        let product: Product
        if let cached = products[item] {
            product = cached
        } else if let loaded = try? await Product.products(for: [item.rawValue]).first {
            product = loaded
        } else {
            throw MerchantFailure.failed
        }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { throw MerchantFailure.failed }
                await refreshEntitlement()
                await transaction.finish()
                Telemetry.shared.logPurchase(product)
                Merchant.log("purchase success: \(item.rawValue)")
            case .userCancelled:
                Merchant.log("purchase cancelled: \(item.rawValue)")
                throw MerchantFailure.cancelled
            case .pending:
                Merchant.log("purchase pending: \(item.rawValue)")
                throw MerchantFailure.pending
            @unknown default:
                throw MerchantFailure.failed
            }
        } catch MerchantFailure.cancelled { throw MerchantFailure.cancelled }
        catch MerchantFailure.pending { throw MerchantFailure.pending }
        catch { Merchant.log("purchase failed: \(error)"); throw MerchantFailure.failed }
    }

    func restore() async throws -> Bool {
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            Merchant.log(isPremium ? "restore success" : "nothing to restore")
            return isPremium
        } catch {
            #if DEBUG
            if debugGrant {
                isPremium = true
                Merchant.log("debug test purchase restored")
                return true
            }
            #endif
            Merchant.log("restore failed: \(error)")
            throw MerchantFailure.failed
        }
    }

    func grantTestPurchase(_ item: ProductID = .weekly) {
        debugGrant = true
        isPremium = true
        Merchant.log("test purchase granted: \(item.rawValue)")
    }

    func revokeTestPurchase() {
        debugGrant = false
        isPremium = false
        Merchant.log("test purchase revoked")
    }

    func registerSecretUnlockTap() {
        debugGrant.toggle(); isPremium = debugGrant || isPremium
        Merchant.log("secret unlock toggled: \(debugGrant)")
    }

    private static func unit(for period: Product.SubscriptionPeriod) -> String {
        switch period.unit { case .day: return "day"; case .week: return "week"; case .month: return "month"; case .year: return "year"; @unknown default: return "—" }
    }
    nonisolated private static func log(_ message: String) {
#if DEBUG
        print("💳 [Billing] \(message)")
#endif
    }
}

@MainActor protocol PurchaseService: AnyObject {
    var isPremium: Bool { get }
    var prices: [ProductID: String] { get }
    var plans: [ProductID: PlanDisplay] { get }
    func startObservingTransactions()
    func preloadProducts()
    func refreshEntitlement() async
    func purchase(_ item: ProductID) async throws
    func restore() async throws -> Bool
}
