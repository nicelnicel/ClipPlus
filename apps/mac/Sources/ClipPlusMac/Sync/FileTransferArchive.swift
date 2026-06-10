import Foundation

enum FileTransferArchive {
    static func writeZip(sourceURLs: [URL], to archiveURL: URL) throws {
        let written = CoreBridge().writeFileArchiveZip(
            sourcePaths: sourceURLs.map(\.path),
            archivePath: archiveURL.path
        )
        if !written {
            throw FileTransferArchiveError.writeFailed
        }
    }
}

enum FileTransferArchiveError: Error {
    case writeFailed
}
