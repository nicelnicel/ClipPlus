import Foundation

struct ClipPlusLogger {
    private let logURL: URL
    private let queue = DispatchQueue(label: "clipplus.mac.logger")

    init() {
        let directory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ClipPlus", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logURL = directory.appendingPathComponent("clipplus.log")
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
