//
//  ContentView.swift
//  PhotoCleanerApp
//
//  Created by Stanislau Reut on 09/11/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var library = MediaLibrary()
    @State private var showSplash = true
    @State private var path: [String] = []
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack(path: $path) {
            HomeScreen().navigationDestination(for: String.self) { name in
                #if DEBUG
                verificationScreen(name)
                #else
                HomeScreen()
                #endif
            }
        }
            .environment(library).tint(CleanerStyle.blue).preferredColorScheme(.light)
            .statusBarHidden(showSplash || FidelityPreview.contains("Splash") || (FidelityPreview.active && FidelityPreview.name.hasPrefix("Overlay")))
            .overlay { if showSplash { SplashScreen().transition(.opacity) } }
            .task {
                #if DEBUG
                if FidelityPreview.active { showSplash = false; path = ["fidelity"]; return }
                let args = ProcessInfo.processInfo.arguments
                if let index = args.firstIndex(of: "--qa-screen"), args.indices.contains(index + 1) {
                    showSplash = false; path = [args[index + 1]]; return
                }
                #endif
                try? await Task.sleep(for: .seconds(1.88))
                withAnimation(.easeOut(duration: 0.25)) { showSplash = false }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active && !FidelityPreview.active { library.refreshAccess() } }
    }
    #if DEBUG
    @ViewBuilder private func verificationScreen(_ name: String) -> some View {
        switch name {
        case "fidelity":
            Group {
                switch FidelityPreview.section {
                case "Main", "Smart Scan", "Photos", "Photo Swipe", "Videos": MediaFidelityScreen()
                case "Contacts & Backups": ContactsFidelityScreen()
                case "Calendar": CalendarFidelityScreen()
                default: ToolsFidelityScreen()
                }
            }.toolbar(.hidden, for: .navigationBar)
        case "scan": ScanScreen()
        case "photos": MediaCategoriesScreen(video: false)
        case "swipe": PhotoSwipeScreen().task { await library.scan() }
        case "videos": MediaCategoriesScreen(video: true)
        case "contacts": ContactsScreen()
        case "calendar": CalendarScreen()
        case "background": BackgroundRemoverScreen()
        case "security": SecurityScreen()
        case "settings": SettingsScreen()
        case "subscription": SubscriptionScreen()
        case "email": EmailCheckScreen()
        case "password": PasswordCheckScreen()
        case "device": DeviceSecurityScreen()
        case "splash": SplashScreen()
        default: HomeScreen()
        }
    }
    #endif
}

#Preview {
    ContentView()
}
