import Foundation
import CryptoKit

enum ClipPlusMessageKind: String, Codable {
    case hello
    case text
    case image
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
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    static func text(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        text: String
    ) -> Self {
        Self(
            kind: .text,
            protocolVersion: 1,
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName,
            eventId: UUID().uuidString,
            text: text,
            imageBase64: nil,
            imageByteSize: nil,
            imageContentHash: nil,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
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
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}
