//
//  BLELogger.swift
//  ClaudeDesktopBuddy
//
//  Created by Matt Whitaker on 18/05/2026.
//


import Foundation

@MainActor
class BLELogger: ObservableObject {
    static let shared = BLELogger()
    
    @Published var entries: [LogEntry] = []
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String
        
        enum Level { case info, success, warning, error }
        
        var prefix: String {
            switch level {
            case .info:    return "·"
            case .success: return "✓"
            case .warning: return "⚠"
            case .error:   return "✗"
            }
        }
        
        var timeString: String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            return f.string(from: timestamp)
        }
    }
    
    func log(_ message: String, level: LogEntry.Level = .info) {
        let entry = LogEntry(timestamp: .now, level: level, message: message)
        entries.insert(entry, at: 0)
        if entries.count > 200 { entries = Array(entries.prefix(200)) }
        print("[\(entry.timeString)] \(entry.prefix) \(message)")
    }
    
    func info(_ msg: String)    { log(msg, level: .info) }
    func success(_ msg: String) { log(msg, level: .success) }
    func warning(_ msg: String) { log(msg, level: .warning) }
    func error(_ msg: String)   { log(msg, level: .error) }
    func clear()                { entries = [] }
}