import SwiftUI

struct BuddyDashboardView: View {
    @EnvironmentObject var model: BuddyModel
    @EnvironmentObject var bleManager: BLEPeripheralManager
    @State private var selectedTab: Tab = .status

    enum Tab { case status, transcript, stats }

    var body: some View {
        ZStack {
            // Background based on state
            backgroundView
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: stateKey)

            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.top, 8)

                // State hero
                BuddyStateHero()
                    .environmentObject(model)
                    .environmentObject(bleManager)
                    .padding(.vertical, 8)

                // Approval prompt (if waiting)
                if case .attention(let prompt) = model.state {
                    ApprovalCard(prompt: prompt)
                        .environmentObject(bleManager)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Tab bar
                tabBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                // Tab content
                tabContent
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                Spacer()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.state.displayName)
    }

    // MARK: - Background

    private var backgroundView: some View {
        ZStack {
            Color(hex: "#0A0A0A")

            switch model.state {
            case .attention:
                RadialGradient(
                    colors: [Color(hex: "#E8620018"), Color.clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 500
                )
            case .busy:
                RadialGradient(
                    colors: [Color(hex: "#0052CC18"), Color.clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 500
                )
            case .celebrate:
                RadialGradient(
                    colors: [Color(hex: "#00875A22"), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 400
                )
            default:
                Color.clear
            }
        }
    }

    private var stateKey: String { model.state.displayName }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.ownerName + "'s Claude")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.3))
                    .tracking(1)

                Text("Desktop Buddy")
                    .font(.custom("Georgia", size: 18))
                    .foregroundColor(.white)
            }

            Spacer()

            // Connection dot
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: "#00875A"))
                    .frame(width: 6, height: 6)
                Text("Connected")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach([Tab.status, .transcript, .stats], id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.label)
                        .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular, design: .monospaced))
                        .foregroundColor(selectedTab == tab ? .white : Color.white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .status:
            StatusTabView()
                .environmentObject(model)
        case .transcript:
            TranscriptTabView()
                .environmentObject(model)
        case .stats:
            StatsTabView()
                .environmentObject(model)
        }
    }
}

extension BuddyDashboardView.Tab {
    var label: String {
        switch self {
        case .status: return "STATUS"
        case .transcript: return "TRANSCRIPT"
        case .stats: return "STATS"
        }
    }
}

// MARK: - State Hero

struct BuddyStateHero: View {
    @EnvironmentObject var model: BuddyModel
    @State private var celebrating = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(stateColour.opacity(0.15), lineWidth: 1)
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(Color(hex: "#141414"))
                    .frame(width: 84, height: 84)
                    .overlay(
                        Circle()
                            .stroke(stateColour.opacity(0.4), lineWidth: 1.5)
                    )

                Text(model.state.emoji)
                    .font(.system(size: 38))
                    .scaleEffect(celebrating ? 1.3 : 1.0)
            }
            .frame(height: 110)

            Text(model.state.displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            if !model.lastMessage.isEmpty {
                Text(model.lastMessage)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.4))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .onChange(of: model.state.displayName) { _, new in
            if new == "Level up!" {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                    celebrating = true
                }
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    celebrating = false
                }
            }
        }
    }

    private var stateColour: Color {
        switch model.state {
        case .disconnected: return Color.white.opacity(0.2)
        case .idle: return Color(hex: "#4A90D9")
        case .busy: return Color(hex: "#0052CC")
        case .attention: return Color(hex: "#E86200")
        case .celebrate: return Color(hex: "#00875A")
        }
    }
}

// MARK: - Approval Card

struct ApprovalCard: View {
    let prompt: PendingPrompt
    @EnvironmentObject var bleManager: BLEPeripheralManager
    @State private var deciding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(hex: "#E86200"))
                    .font(.system(size: 13))
                Text("PERMISSION REQUEST")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#E86200"))
                    .tracking(1.5)
                Spacer()
            }

            if let tool = prompt.tool {
                Text(tool)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }

            if let hint = prompt.hint {
                Text(hint)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.55))
                    .lineLimit(3)
                    .padding(10)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(6)
            }

            HStack(spacing: 10) {
                Button {
                    guard !deciding else { return }
                    deciding = true
                    bleManager.sendPermissionDecision(id: prompt.id, approve: false)
                } label: {
                    Label("Deny", systemImage: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#E86200"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "#E86200").opacity(0.12))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: "#E86200").opacity(0.3), lineWidth: 1)
                        )
                }

                Button {
                    guard !deciding else { return }
                    deciding = true
                    bleManager.sendPermissionDecision(id: prompt.id, approve: true)
                } label: {
                    Label("Approve", systemImage: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "#00875A").opacity(0.8))
                        .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "#1A0E00"))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "#E86200").opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - Tab Views

struct StatusTabView: View {
    @EnvironmentObject var model: BuddyModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let lastTurn = model.lastTurnText {
                InfoRow(label: "Last response", value: lastTurn)
            }
            InfoRow(label: "Active sessions", value: "\(model.tokens > 0 ? "connected" : "none")")
        }
    }
}

struct TranscriptTabView: View {
    @EnvironmentObject var model: BuddyModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if model.transcript.isEmpty {
                    Text("No transcript yet")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.25))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                } else {
                    ForEach(Array(model.transcript.enumerated()), id: \.offset) { idx, entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(model.transcript.count - idx)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.2))
                                .frame(width: 16, alignment: .trailing)
                                .padding(.top, 2)

                            Text(entry)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.65))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .frame(maxHeight: 240)
    }
}

struct StatsTabView: View {
    @EnvironmentObject var model: BuddyModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                StatTile(label: "TOKENS\nTODAY", value: formatTokens(model.tokensToday))
                StatTile(label: "TOKENS\nTOTAL", value: formatTokens(model.tokens))
            }
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

struct StatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.3))
                .tracking(1.5)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.3))
                .tracking(1.5)
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.7))
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }
}
