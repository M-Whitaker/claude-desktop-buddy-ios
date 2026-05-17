import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bleManager: BLEPeripheralManager

    var body: some View {
        Group {
            if bleManager.isConnected {
                BuddyDashboardView()
                    .environmentObject(bleManager.model)
                    .environmentObject(bleManager)
            } else {
                WaitingView()
                    .environmentObject(bleManager)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: bleManager.isConnected)
    }
}
