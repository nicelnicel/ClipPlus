import Foundation

final class RemoteClipboardReceiveGuard {
    private let lock = NSLock()
    private let imageFileSuppressionInterval: TimeInterval
    private var recentImageTimesByDeviceId: [String: Date] = [:]

    init(imageFileSuppressionInterval: TimeInterval = 15) {
        self.imageFileSuppressionInterval = imageFileSuppressionInterval
    }

    func recordRemoteImage(senderDeviceId: String, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }

        recentImageTimesByDeviceId[senderDeviceId] = now
    }

    func shouldSuppressFileOfferAfterRecentImage(
        senderDeviceId: String,
        files: [FileTransferItem],
        now: Date = Date()
    ) -> Bool {
        guard isSingleImageFileOffer(files) else {
            return false
        }

        lock.lock()
        defer { lock.unlock() }

        guard let imageTime = recentImageTimesByDeviceId[senderDeviceId] else {
            return false
        }

        return now.timeIntervalSince(imageTime) <= imageFileSuppressionInterval
    }

    private func isSingleImageFileOffer(_ files: [FileTransferItem]) -> Bool {
        guard files.count == 1,
              let file = files.first,
              !file.isDirectory,
              file.byteSize > 0 else {
            return false
        }

        let fileExtension = URL(fileURLWithPath: file.relativePath).pathExtension.lowercased()
        return Self.imageFileExtensions.contains(fileExtension)
    }

    private static let imageFileExtensions: Set<String> = [
        "png",
        "jpg",
        "jpeg",
        "gif",
        "bmp",
        "tif",
        "tiff",
        "webp",
        "heic",
        "heif"
    ]
}
