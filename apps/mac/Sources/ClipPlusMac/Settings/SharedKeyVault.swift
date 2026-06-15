import Foundation

protocol SharedKeyVault {
    func loadSharedKey() -> String
    func saveSharedKey(_ sharedKey: String) throws
}

enum SharedKeyVaultError: LocalizedError, Equatable {
    case executableDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .executableDirectoryUnavailable:
            return "无法定位 ClipPlus 进程目录"
        }
    }
}

final class FileSharedKeyVault: SharedKeyVault {
    private static let fileName = "clipplus.shared-key"
    private let fileURL: URL
    private let legacyFileURL: URL?

    init(fileURL: URL? = nil, legacyFileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.legacyFileURL = legacyFileURL ?? (fileURL == nil ? Self.legacyExecutableDirectoryFileURL() : nil)
    }

    func loadSharedKey() -> String {
        if let sharedKey = readSharedKey(from: fileURL), !sharedKey.isEmpty {
            return sharedKey
        }

        guard let legacyFileURL,
              legacyFileURL.standardizedFileURL != fileURL.standardizedFileURL,
              let legacySharedKey = readSharedKey(from: legacyFileURL),
              !legacySharedKey.isEmpty
        else {
            return ""
        }

        try? saveSharedKey(legacySharedKey)
        return legacySharedKey
    }

    func saveSharedKey(_ sharedKey: String) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try sharedKey.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func readSharedKey(from fileURL: URL) -> String? {
        guard let sharedKey = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        return sharedKey.trimmingCharacters(in: .newlines)
    }

    private static func defaultFileURL() -> URL {
        if let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            return applicationSupportURL
                .appendingPathComponent("ClipPlus", isDirectory: true)
                .appendingPathComponent(fileName, isDirectory: false)
        }

        return FileManager.default.currentDirectoryPathURL
            .appendingPathComponent("ClipPlus", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private static func legacyExecutableDirectoryFileURL() -> URL? {
        if let executableURL = Bundle.main.executableURL {
            return executableURL
                .deletingLastPathComponent()
                .appendingPathComponent(fileName, isDirectory: false)
        }

        if let executablePath = CommandLine.arguments.first, !executablePath.isEmpty {
            return URL(fileURLWithPath: executablePath)
                .deletingLastPathComponent()
                .appendingPathComponent(fileName, isDirectory: false)
        }

        return nil
    }
}

private extension FileManager {
    var currentDirectoryPathURL: URL {
        URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
    }
}
