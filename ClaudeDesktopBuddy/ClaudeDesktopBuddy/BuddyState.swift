import Foundation

// MARK: - Heartbeat snapshot from desktop

struct HeartbeatSnapshot: Codable {
    let total: Int?
    let running: Int?
    let waiting: Int?
    let msg: String?
    let entries: [String]?
    let tokens: Int?
    let tokensToday: Int?
    let prompt: PendingPrompt?

    enum CodingKeys: String, CodingKey {
        case total, running, waiting, msg, entries, tokens
        case tokensToday = "tokens_today"
        case prompt
    }
}

struct PendingPrompt: Codable {
    let id: String
    let tool: String?
    let hint: String?
}

// MARK: - Turn event

struct TurnEvent: Codable {
    let evt: String
    let role: String?
    let content: [TurnContent]?
}

struct TurnContent: Codable {
    let type: String
    let text: String?
}

// MARK: - Commands from desktop

struct OwnerCommand: Codable {
    let cmd: String
    let name: String
}

struct TimeSync: Codable {
    let time: [Int]?
}

struct NameCommand: Codable {
    let cmd: String
    let name: String
}

// MARK: - Commands we send to desktop

struct PermissionDecision: Codable {
    let cmd: String = "permission"
    let id: String
    let decision: String  // "once" or "deny"
}

struct AckResponse: Codable {
    let ack: String
    let ok: Bool
    let n: Int?
    let error: String?

    init(ack: String, ok: Bool = true, n: Int? = nil, error: String? = nil) {
        self.ack = ack
        self.ok = ok
        self.n = n
        self.error = error
    }
}

struct StatusResponse: Codable {
    let ack: String = "status"
    let ok: Bool = true
    let data: StatusData
}

struct StatusData: Codable {
    let name: String
    let sec: Bool
    let sys: SysInfo

    struct SysInfo: Codable {
        let up: Int  // uptime seconds
        let heap: Int
    }
}

// MARK: - App-level buddy state

enum BuddyState {
    case disconnected
    case idle
    case busy(sessionCount: Int)
    case attention(prompt: PendingPrompt)
    case celebrate

    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .idle: return "Idle"
        case .busy(let n): return n == 1 ? "Working…" : "\(n) sessions running"
        case .attention: return "Approval needed"
        case .celebrate: return "Level up!"
        }
    }

    var emoji: String {
        switch self {
        case .disconnected: return "💤"
        case .idle: return "👀"
        case .busy: return "⚙️"
        case .attention: return "🔔"
        case .celebrate: return "🎉"
        }
    }
}

// MARK: - Observable app model

@MainActor
class BuddyModel: ObservableObject {
    @Published var state: BuddyState = .disconnected
    @Published var ownerName: String = "Claude"
    @Published var transcript: [String] = []
    @Published var tokens: Int = 0
    @Published var tokensToday: Int = 0
    @Published var lastMessage: String = "Waiting for connection…"
    @Published var pendingPrompt: PendingPrompt? = nil
    @Published var lastTurnText: String? = nil
    @Published var appStartTime: Date = .now

    var appUptime: Int {
        Int(Date.now.timeIntervalSince(appStartTime))
    }

    func apply(snapshot: HeartbeatSnapshot) {
        let total = snapshot.total ?? 0
        let running = snapshot.running ?? 0
        let waiting = snapshot.waiting ?? 0

        if let msg = snapshot.msg { lastMessage = msg }
        if let entries = snapshot.entries { transcript = entries }
        if let t = snapshot.tokens { tokens = t }
        if let tt = snapshot.tokensToday { tokensToday = tt }

        pendingPrompt = snapshot.prompt

        // Celebrate every 50k tokens
        let prevTokens = tokens
        if let t = snapshot.tokens, prevTokens > 0,
           (prevTokens / 50_000) < (t / 50_000) {
            state = .celebrate
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                updateState(total: total, running: running, waiting: waiting, prompt: snapshot.prompt)
            }
            return
        }

        updateState(total: total, running: running, waiting: waiting, prompt: snapshot.prompt)
    }

    private func updateState(total: Int, running: Int, waiting: Int, prompt: PendingPrompt?) {
        if let prompt = prompt, waiting > 0 {
            state = .attention(prompt: prompt)
        } else if running > 0 {
            state = .busy(sessionCount: running)
        } else if total > 0 || running == 0 {
            state = total == 0 ? .idle : .idle
        } else {
            state = .idle
        }
    }

    func markDisconnected() {
        state = .disconnected
        lastMessage = "Desktop disconnected"
        pendingPrompt = nil
    }

    func apply(turnEvent: TurnEvent) {
        let text = turnEvent.content?
            .filter { $0.type == "text" }
            .compactMap { $0.text }
            .joined(separator: " ")
        if let t = text, !t.isEmpty {
            lastTurnText = String(t.prefix(200))
        }
    }
}
