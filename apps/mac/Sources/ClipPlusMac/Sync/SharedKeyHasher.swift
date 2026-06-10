import CryptoKit
import Foundation

enum SharedKeyHasher {
    static func groupId(for rawKey: String) -> String {
        if let groupId = CoreBridge().deriveGroupId(for: rawKey) {
            return groupId
        }

        let normalizedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data("clipplus.shared-key.v1:\(normalizedKey)".utf8)
        let digest = SHA256.hash(data: data)
        let groupBytes = Data(digest.prefix(16))

        return groupBytes
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
