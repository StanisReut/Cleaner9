//
//  Liftoff.swift
//  PhotoCleanerApp
//
//  Created by Stanislau Reut on 09/11/2026.
//

import SwiftUI
import UIKit
import StoreKit

final class CleanerAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Telemetry.shared.start(launchOptions: launchOptions)
        application.registerForRemoteNotifications()
        Task { @MainActor in
            Merchant.shared.startObservingTransactions()
            Merchant.shared.preloadProducts()
            await Merchant.shared.refreshEntitlement()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Telemetry.shared.registerUninstallToken(deviceToken)
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task {
            for await result in StoreKit.Transaction.currentEntitlements {
                if case .verified(let transaction) = result {
                    UserAcquisition.shared.log(pushDeviceToken: tokenString, and: "\(transaction.originalID)")
                    break
                }
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("⚠️ Remote notification registration error: \(error.localizedDescription)")
        #endif
    }
}

@main
struct Liftoff: App {
    @UIApplicationDelegateAdaptor(CleanerAppDelegate.self) private var appDelegate
    init() {
        Palette.registerFonts()
    }
    var body: some Scene {
        WindowGroup {
            Stage()
        }
    }
}
