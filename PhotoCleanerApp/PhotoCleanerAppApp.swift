//
//  PhotoCleanerAppApp.swift
//  PhotoCleanerApp
//
//  Created by Stanislau Reut on 09/11/2026.
//

import SwiftUI

@main
struct PhotoCleanerAppApp: App {
    init() { CleanerStyle.registerFonts() }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
