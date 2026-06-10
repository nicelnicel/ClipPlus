import Foundation

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
        guard let json = CoreBridge().createHelloMessageJSON(
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName
        ) else {
            preconditionFailure("Rust 核心库不可用，无法创建 hello 消息")
        }

        return decodeCoreMessageJSON(json)
    }

    static func trust(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        approvedDeviceId: String
    ) -> Self {
        guard let json = CoreBridge().createTrustMessageJSON(
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName,
            approvedDeviceId: approvedDeviceId
        ) else {
            preconditionFailure("Rust 核心库不可用，无法创建 trust 消息")
        }

        return decodeCoreMessageJSON(json)
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
        ) else {
            preconditionFailure("Rust 核心库不可用，无法创建文本剪贴板消息")
        }

        return decodeCoreMessageJSON(json)
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

        guard let json = CoreBridge().createImageMessageJSON(
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName,
            pngData: pngData
        ) else {
            preconditionFailure("Rust 核心库不可用，无法创建图片剪贴板消息")
        }

        return decodeCoreMessageJSON(json)
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

    private static func decodeCoreMessageJSON(_ json: String) -> Self {
        guard let data = json.data(using: .utf8),
              let message = try? JSONDecoder().decode(Self.self, from: data) else {
            preconditionFailure("Rust 核心库返回了无法解析的消息 JSON")
        }

        return message
    }
}
