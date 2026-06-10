import Foundation

enum SharedKeyHasherError: LocalizedError, Equatable {
    case coreBridgeUnavailable

    var errorDescription: String? {
        switch self {
        case .coreBridgeUnavailable:
            return "Rust 核心库不可用，无法派生共享组 ID"
        }
    }
}

enum SharedKeyHasher {
    static func groupId(for rawKey: String) throws -> String {
        if let groupId = CoreBridge().deriveGroupId(for: rawKey) {
            return groupId
        }

        throw SharedKeyHasherError.coreBridgeUnavailable
    }
}
