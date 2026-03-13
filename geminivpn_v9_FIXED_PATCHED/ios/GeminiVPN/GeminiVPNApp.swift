import SwiftUI

@main
struct GeminiVPNApp: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var vpnManager = VPNManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(vpnManager)
                .preferredColorScheme(.dark)
                .onAppear {
                    Task { await appState.initialise() }
                }
        }
    }
}