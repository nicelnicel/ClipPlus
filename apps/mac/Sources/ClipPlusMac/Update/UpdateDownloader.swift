import CryptoKit
import Foundation

struct UpdateDownloader {
    let cachesDirectory: URL

    init(cachesDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]) {
        self.cachesDirectory = cachesDirectory
    }

    func download(
        asset: SelectedUpdateAsset,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> DownloadedUpdate {
        let updateDirectory = cachesDirectory
            .appendingPathComponent("ClipPlus", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
            .appendingPathComponent("v\(asset.version.description)", isDirectory: true)
        try FileManager.default.createDirectory(at: updateDirectory, withIntermediateDirectories: true)

        let finalURL = updateDirectory.appendingPathComponent(asset.name, isDirectory: false)
        let partialURL = updateDirectory.appendingPathComponent("\(asset.name).partial", isDirectory: false)
        try? FileManager.default.removeItem(at: partialURL)
        try? FileManager.default.removeItem(at: finalURL)

        let (temporaryURL, response) = try await URLSession.shared.download(from: asset.downloadURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateError.downloadFailed
        }

        try FileManager.default.moveItem(at: temporaryURL, to: partialURL)
        try Self.verifySha256(fileURL: partialURL, expectedHex: asset.sha256Hex)
        try FileManager.default.moveItem(at: partialURL, to: finalURL)
        await progress(1)
        return DownloadedUpdate(version: asset.version, assetName: asset.name, fileURL: finalURL)
    }

    static func verifySha256(fileURL: URL, expectedHex: String) throws {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest.caseInsensitiveCompare(expectedHex) == .orderedSame else {
            throw UpdateError.sha256Mismatch
        }
    }
}
