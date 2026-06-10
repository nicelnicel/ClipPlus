import Foundation

enum FileTransferArchive {
    static func writeZip(sourceURLs: [URL], to archiveURL: URL) throws {
        let entries = try sourceURLs.flatMap { sourceURL in
            try entriesForSourceURL(sourceURL)
        }

        try SimpleFileTransferZipWriter.write(entries: entries, to: archiveURL)
    }

    private static func entriesForSourceURL(_ sourceURL: URL) throws -> [SimpleFileTransferZipEntry] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            return []
        }

        if !isDirectory.boolValue {
            return [
                SimpleFileTransferZipEntry(
                    name: sourceURL.lastPathComponent,
                    data: try Data(contentsOf: sourceURL)
                )
            ]
        }

        let baseURL = sourceURL.deletingLastPathComponent()
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey]
        let childURLs = FileManager.default.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? []

        return try childURLs.compactMap { childURL in
            let values = try childURL.resourceValues(forKeys: Set(resourceKeys))
            guard values.isDirectory != true else {
                return nil
            }

            return SimpleFileTransferZipEntry(
                name: relativePath(from: baseURL, to: childURL),
                data: try Data(contentsOf: childURL)
            )
        }
    }

    private static func relativePath(from baseURL: URL, to fileURL: URL) -> String {
        let basePath = baseURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let prefix = basePath.hasSuffix("/") ? basePath : "\(basePath)/"

        guard filePath.hasPrefix(prefix) else {
            return fileURL.lastPathComponent
        }

        return String(filePath.dropFirst(prefix.count))
    }
}

private struct SimpleFileTransferZipEntry {
    let name: String
    let data: Data
}

private enum SimpleFileTransferZipWriter {
    static func write(entries: [SimpleFileTransferZipEntry], to url: URL) throws {
        var archive = Data()
        var centralDirectory = Data()
        var centralDirectoryEntries = 0

        for entry in entries {
            let nameData = Data(entry.name.replacingOccurrences(of: "\\", with: "/").utf8)
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
