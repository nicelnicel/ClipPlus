import Foundation

enum ClipPlusMessageKind: String, Codable {
    case hello
    case trust
    case text
    case image
    case imageOffer
    case fileOffer
}

struct FileTransferItem: Codable, Equatable {
    let relativePath: String
    let byteSize: Int64
    let isDirectory: Bool
}

enum FileTransferFormat: String, Codable {
    case directTree
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
    let transferFormat: FileTransferFormat?
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
    ) -> Self? {
        guard let json = CoreBridge().createHelloMessageJSON(
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName
        ) else {
            return nil
        }

        return decodeCoreMessageJSON(json)
    }

    static func trust(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        approvedDeviceId: String
    ) -> Self? {
        guard let json = CoreBridge().createTrustMessageJSON(
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName,
            approvedDeviceId: approvedDeviceId
        ) else {
            return nil
        }

        return decodeCoreMessageJSON(json)
    }

    static func text(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        text: String
    ) -> Self? {
        guard let json = CoreBridge().createTextMessageJSON(
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName,
            text: text
        ) else {
            return nil
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
            return nil
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
    ) -> Self? {
        guard let json = CoreBridge().createFileOfferMessageJSON(
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName,
            transferId: transferId,
            files: files,
            archivePort: archivePort
        ) else {
            return nil
        }

        return decodeCoreMessageJSON(json)
    }

    static func imageOffer(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        transferId: String,
        pngData: Data,
        archivePort: Int
    ) -> Self? {
        guard let json = CoreBridge().createImageOfferMessageJSON(
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName,
            transferId: transferId,
            pngData: pngData,
            archivePort: archivePort
        ) else {
            return nil
        }

        return decodeCoreMessageJSON(json)
    }

    private static func decodeCoreMessageJSON(_ json: String) -> Self? {
        guard let data = json.data(using: .utf8),
              let message = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }

        return message
    }
}
