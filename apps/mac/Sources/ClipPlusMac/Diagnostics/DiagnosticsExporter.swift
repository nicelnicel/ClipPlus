import Foundation

struct DiagnosticsExporter {
    private let logURL: URL
    private let destinationDirectory: URL
    private let sensitiveValues: [String]

    init(
        logURL: URL = ClipPlusLogger.defaultLogURL,
        destinationDirectory: URL = DiagnosticsExporter.defaultDestinationDirectory(),
        sensitiveValues: [String] = []
    ) {
        self.logURL = logURL
        self.destinationDirectory = destinationDirectory
        self.sensitiveValues = sensitiveValues
    }

    func export(state: SettingsState) throws -> URL {
        let exportURL = destinationDirectory
            .appendingPathComponent("ClipPlus-Diagnostics-\(Self.timestamp())", isDirectory: true)
        try FileManager.default.createDirectory(at: exportURL, withIntermediateDirectories: true)

        let status = DiagnosticsStatus(
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            platform: "macOS",
            sharedKeyConfigured: state.sharedKeyConfigured,
            sharingEnabled: state.sharingEnabled,
            startupEnabled: state.startupEnabled,
            pendingPeerCount: state.pendingPeerCount,
            trustedPeerCount: state.trustedPeerIds.count,
            lastStatusMessage: redact(state.lastStatusMessage)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let statusData = try encoder.encode(status)
        try statusData.write(to: exportURL.appendingPathComponent("status.json"))

        let rawLog = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        try redact(rawLog).write(
            to: exportURL.appendingPathComponent("clipplus.log"),
            atomically: true,
            encoding: .utf8
        )

        return exportURL
    }

    private func redact(_ value: String) -> String {
        let allValues = sensitiveValues
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        return allValues.reduce(value) { redacted, sensitiveValue in
            redacted.replacingOccurrences(of: sensitiveValue, with: "<redacted>")
        }
    }

    private static func defaultDestinationDirectory() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
    }
}

private struct DiagnosticsStatus: Encodable {
    let exportedAt: String
    let platform: String
    let sharedKeyConfigured: Bool
    let sharingEnabled: Bool
    let startupEnabled: Bool
    let pendingPeerCount: Int
    let trustedPeerCount: Int
    let lastStatusMessage: String
}
