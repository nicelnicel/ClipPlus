import Foundation

enum ClipPlusMessageKind: String, Codable {
    case hello
    case text
}

struct ClipPlusMessage: Codable, Equatable {
    let kind: ClipPlusMessageKind
    let protocolVersion: Int
    let groupId: String
    let senderDeviceId: String
    let senderDeviceName: String
    let eventId: String
    let text: String?
    let createdAt: String

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
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}
