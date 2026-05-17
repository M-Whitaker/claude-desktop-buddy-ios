import SwiftUI

struct WaitingView: View {
    @EnvironmentObject var bleManager: BLEPeripheralManager
    @State private var pulse = false
    @State private var dotCount = 1

    let timer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Background
            Color(hex: "#0D0D0D")
                .ignoresSafeArea()

            // Subtle radial glow
            RadialGradient(
                colors: [Color(hex: "#E8620020"), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: 300
            )
            .ignoresSafeArea()
            .scaleEffect(pulse ? 1.2 : 0.9)
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)

            VStack(spacing: 0) {
                Spacer()

                // Claude logo mark
                ZStack {
                    Circle()
                        .stroke(Color(hex: "#E86200").opacity(0.2), lineWidth: 1)
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulse ? 1.4 : 1.0)
                        .opacity(pulse ? 0 : 1)
                        .animation(.easeOut(duration: 2).repeatForever(autoreverses: false), value: pulse)

                    Circle()
                        .stroke(Color(hex: "#E86200").opacity(0.15), lineWidth: 1)
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulse ? 1.8 : 1.0)
                        .opacity(pulse ? 0 : 0.6)
                        .animation(.easeOut(duration: 2).delay(0.4).repeatForever(autoreverses: false), value: pulse)

                    Circle()
                        .fill(Color(hex: "#1A1A1A"))
                        .frame(width: 96, height: 96)
                        .overlay(
                            Circle()
                                .stroke(Color(hex: "#E86200").opacity(0.6), lineWidth: 1.5)
                        )

                    Text("◆")
                        .font(.system(size: 36))
                        .foregroundColor(Color(hex: "#E86200"))
                }

                Spacer().frame(height: 48)

                Text("Claude Desktop Buddy")
                    .font(.custom("Georgia", size: 22))
                    .fontWeight(.regular)
                    .foregroundColor(.white)
                    .tracking(0.5)

                Spacer().frame(height: 12)

                // Status
                if bleManager.isAdvertising {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: "#E86200"))
                            .frame(width: 6, height: 6)
                            .opacity(pulse ? 1 : 0.3)
                            .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulse)

                        Text("Waiting for desktop" + String(repeating: ".", count: dotCount))
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                } else {
                    Text(bleManager.connectionError ?? "Starting Bluetooth…")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Color(hex: "#E86200").opacity(0.8))
                }

                Spacer().frame(height: 48)

                // Instructions card
                InstructionsCard()

                Spacer()

                // BT status pill
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11))
                    Text(bleManager.isAdvertising ? "Advertising as \"\(deviceName)\"" : "Bluetooth initialising")
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundColor(Color.white.opacity(0.25))
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            pulse = true
            bleManager.startAdvertising()
        }
        .onReceive(timer) { _ in
            dotCount = (dotCount % 3) + 1
        }
    }

    private var deviceName: String {
        "Claude \(UIDevice.current.name)"
    }
}

struct InstructionsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("HOW TO CONNECT")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(hex: "#E86200").opacity(0.7))
                .tracking(2)

            VStack(alignment: .leading, spacing: 10) {
                InstructionRow(number: "1", text: "Open Claude for macOS or Windows")
                InstructionRow(number: "2", text: "Help → Troubleshooting → Enable Developer Mode")
                InstructionRow(number: "3", text: "Developer → Open Hardware Buddy…")
                InstructionRow(number: "4", text: "Click Connect and pick your iPhone")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

struct InstructionRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#E86200"))
                .frame(width: 16)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Hex color extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
