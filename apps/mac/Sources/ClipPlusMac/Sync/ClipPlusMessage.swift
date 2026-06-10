import Foundation
import CryptoKit

enum ClipPlusMessageKind: String, Codable {
    case hello
    case trust
    case text
    case image
    case fileOffer
}

struct FileTransferItem: Codable, Equatable {
    let relativePath: String
    let byteSize: Int64
    let isDirectory: Bool
}

struct ClipPlusMessage: Codable, Equatable {
    static let maxInlineImageBytes = 32 * 1024

    let kind: ClipPlusMessageKind
    let protocolVersion: Int
    let groupId: String
    let senderDeviceId: String
    let senderDeviceName: String
    let eventId: String
    let text: String?
    let imageBase64: String?
    let imageByteSize: Int?
    let imageContentHash: String?
    let approvedDeviceId: String?
    let transferId: String?
    let files: [FileTransferItem]?
    let archivePort: Int?
    let createdAt: String

    var decodedImageData: Data? {
        guard let imageBase64 else {
            return nil
        }

        return Data(base64Encoded: imageBase64)
    }

    static func hello(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String
    ) -> Self {
        Self(
            kind: .hello,
            protocolVersion: 1,
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName,
            eventId: UUID().uuidString,
            text: nil,
            imageBase64: nil,
            imageByteSize: nil,
            imageContentHash: nil,
            approvedDeviceId: nil,
            transferId: nil,
            files: nil,
            archivePort: nil,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    static func trust(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        approvedDeviceId: String
    ) -> Self {
        Self(
            kind: .trust,
            protocolVersion: 1,
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName,
            eventId: UUID().uuidString,
            text: nil,
            imageBase64: nil,
            imageByteSize: nil,
            imageContentHash: nil,
            approvedDeviceId: approvedDeviceId,
            transferId: nil,
            files: nil,
            archivePort: nil,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    static func text(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        text: String
    ) -> Self {
        guard let json = CoreBridge().createTextMessageJSON(
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName,
            text: text
        ),
              let data = json.data(using: .utf8),
              let message = try? JSONDecoder().decode(Self.self, from: data) else {
            preconditionFailure("Rust 核心库不可用，无法创建文本剪贴板消息")
        }

        return message
    }

    static func image(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        pngData: Data
    ) -> Self? {
        guard !pngData.isEmpty, pngData.count <= maxInlineImageBytes else {
            return nil
        }

        return Self(
            kind: .image,
            protocolVersion: 1,
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName,
            eventId: UUID().uuidString,
            text: nil,
            imageBase64: pngData.base64EncodedString(),
            imageByteSize: pngData.count,
            imageContentHash: SHA256.hash(data: pngData)
                .map { String(format: "%02x", $0) }
                .joined(),
            approvedDeviceId: nil,
            transferId: nil,
            files: nil,
            archivePort: nil,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    static func fileOffer(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        transferId: String,
        files: [FileTransferItem],
        archivePort: Int
    ) -> Self {
        Self(
            kind: .fileOffer,
            protocolVersion: 1,
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName,
            eventId: UUID().uuidString,
            text: nil,
            imageBase64: nil,
            imageByteSize: nil,
            imageContentHash: nil,
            approvedDeviceId: nil,
            transferId: transferId,
            files: files,
            archivePort: archivePort,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}
