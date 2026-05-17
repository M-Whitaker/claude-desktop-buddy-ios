import SwiftUI

@main
struct ClaudeDesktopBuddyApp: App {
    @StateObject private var bleManager = BLEPeripheralManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
        }
    }
}
