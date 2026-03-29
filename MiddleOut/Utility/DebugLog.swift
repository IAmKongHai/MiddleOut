// DebugLog.swift
// Writes timestamped debug logs to a file in the project directory.
// Logs are saved to: ~/Code_local/Project/MiddleOut/debug.log

import Foundation

struct DebugLog {
    private static let logURL: URL = {
        // Write to project directory so developer can inspect
        let projectDir = URL(fileURLWithPath: "/Users/konghai/Code_local/Project/MiddleOut")
        return projectDir.appendingPathComponent("debug.log")
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// Append a line to the debug log file and also print to console
    static func log(_ message: String, function: String = #function, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let threadInfo = Thread.isMainThread ? "MAIN" : "BG"
        let entry = "[\(timestamp)] [\(threadInfo)] \(function):\(line) — \(message)\n"

        print("[DebugLog] \(entry)", terminator: "")

        // Append to file
        if let data = entry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    /// Clear the log file
    static func clear() {
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
    }
}
