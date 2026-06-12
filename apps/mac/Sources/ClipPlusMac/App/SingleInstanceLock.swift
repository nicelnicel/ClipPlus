import Darwin
import Foundation

final class SingleInstanceLock {
    private let fileDescriptor: Int32

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }

    static func acquireDefault() -> SingleInstanceLock? {
        let directoryURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ClipPlus", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("ClipPlus", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        return acquire(lockURL: directoryURL.appendingPathComponent("ClipPlus.lock"))
    }

    static func acquire(lockURL: URL) -> SingleInstanceLock? {
        let fileDescriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            return nil
        }

        guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(fileDescriptor)
            return nil
        }

        return SingleInstanceLock(fileDescriptor: fileDescriptor)
    }
}
