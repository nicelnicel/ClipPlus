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

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    func loadSharedKey() -> String {
        guard let sharedKey = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return ""
        }

        return sharedKey.trimmingCharacters(in: .newlines)
    }

    func saveSharedKey(_ sharedKey: String) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try sharedKey.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func defaultFileURL() -> URL {
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

        return FileManager.default.currentDirectoryPathURL
            .appendingPathComponent(fileName, isDirectory: false)
    }
}

private extension FileManager {
    var currentDirectoryPathURL: URL {
        URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
    }
}
