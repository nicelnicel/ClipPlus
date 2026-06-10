import Foundation

struct ClipPlusLogger {
    static let defaultLogURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/ClipPlus/clipplus.log")

    let logURL: URL
    private let queue = DispatchQueue(label: "clipplus.mac.logger")

    init() {
        let directory = Self.defaultLogURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logURL = Self.defaultLogURL
    }

    func info(_ message: String) {
        write(level: "info", message: message)
    }

    func error(_ message: String) {
        write(level: "error", message: message)
    }

    private func write(level: String, message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(level)] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else {
                return
            }

            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}
