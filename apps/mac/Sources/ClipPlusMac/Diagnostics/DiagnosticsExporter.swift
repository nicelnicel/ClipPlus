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
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let exportURL = destinationDirectory
            .appendingPathComponent("ClipPlus-Diagnostics-\(Self.timestamp()).zip")

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

        let rawLog = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let logData = Data(redact(rawLog).utf8)

        try SimpleZipWriter.write(
            entries: [
                SimpleZipEntry(name: "status.json", data: statusData),
                SimpleZipEntry(name: "clipplus.log", data: logData)
            ],
            to: exportURL
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

private struct SimpleZipEntry {
    let name: String
    let data: Data
}

private enum SimpleZipWriter {
    static func write(entries: [SimpleZipEntry], to url: URL) throws {
        var archive = Data()
        var centralDirectory = Data()
        var centralDirectoryEntries = 0

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let localHeaderOffset = UInt32(archive.count)

            archive.appendUInt32LE(0x0403_4B50)
            archive.appendUInt16LE(20)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt32LE(crc)
            archive.appendUInt32LE(UInt32(entry.data.count))
            archive.appendUInt32LE(UInt32(entry.data.count))
            archive.appendUInt16LE(UInt16(nameData.count))
            archive.appendUInt16LE(0)
            archive.append(nameData)
            archive.append(entry.data)

            centralDirectory.appendUInt32LE(0x0201_4B50)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(crc)
            centralDirectory.appendUInt32LE(UInt32(entry.data.count))
            centralDirectory.appendUInt32LE(UInt32(entry.data.count))
            centralDirectory.appendUInt16LE(UInt16(nameData.count))
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(0)
            centralDirectory.appendUInt32LE(localHeaderOffset)
            centralDirectory.append(nameData)

            centralDirectoryEntries += 1
        }

        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        archive.appendUInt32LE(0x0605_4B50)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(UInt16(centralDirectoryEntries))
        archive.appendUInt16LE(UInt16(centralDirectoryEntries))
        archive.appendUInt32LE(UInt32(centralDirectory.count))
        archive.appendUInt32LE(centralDirectoryOffset)
        archive.appendUInt16LE(0)

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try archive.write(to: url, options: .atomic)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 == 1 {
                    crc = (crc >> 1) ^ 0xedb8_8320
                } else {
                    crc >>= 1
                }
            }
        }

        return crc ^ 0xffff_ffff
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
