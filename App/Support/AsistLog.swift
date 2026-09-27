// FILE: App/Support/AsistLog.swift
import Foundation
import os

enum LogCategory: String {
    case app, store, notif, voice, intents, smart, location, widget, ui
}

/// Thread-safe ring buffer shown in Ayarlar > Tanılama (there is no Mac console).
final class LogBuffer: @unchecked Sendable {
    static let shared = LogBuffer()
    private let lock = NSLock()
    private var lines: [String] = []
    private let capacity = 300

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

/// Callable from any thread/isolation.
enum AsistLog {
    static let subsystem = "com.gokhanbudak.asist"

    static func info(_ message: String, _ category: LogCategory = .app) {
        write(message, category, .info)
    }

    static func error(_ message: String, _ category: LogCategory = .app) {
        write("HATA: " + message, category, .error)
    }

    static func recentLines() -> [String] {
        LogBuffer.shared.snapshot()
    }

    private static func write(_ message: String, _ category: LogCategory, _ level: OSLogType) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        logger.log(level: level, "\(message, privacy: .public)")
        let stamp = Date().formatted(date: .numeric, time: .standard)
        LogBuffer.shared.append(stamp + " [" + category.rawValue + "] " + message)
    }
}
