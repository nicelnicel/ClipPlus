import Foundation

struct StoredSettings: Equatable {
    let sharedKeyConfigured: Bool
    let sharingEnabled: Bool
    let sharedGroupId: String
    let sharedKeyInput: String
}

final class SettingsStore {
    private enum Key {
        static let sharedGroupId = "clipplus.shared_group_id"
        static let sharingEnabled = "clipplus.sharing_enabled"
    }

    private let userDefaults: UserDefaults
    private let sharedKeyVault: SharedKeyVault

    init(
        userDefaults: UserDefaults = .standard,
        sharedKeyVault: SharedKeyVault = FileSharedKeyVault()
    ) {
        self.userDefaults = userDefaults
        self.sharedKeyVault = sharedKeyVault
    }

    func load() -> StoredSettings {
        let sharedGroupId = userDefaults.string(forKey: Key.sharedGroupId) ?? ""
        let sharingEnabled = userDefaults.object(forKey: Key.sharingEnabled) as? Bool ?? true
        let sharedKeyInput = sharedKeyVault.loadSharedKey()

        return StoredSettings(
            sharedKeyConfigured: !sharedGroupId.isEmpty && !sharedKeyInput.isEmpty,
            sharingEnabled: sharingEnabled,
            sharedGroupId: sharedGroupId,
            sharedKeyInput: sharedKeyInput
        )
    }

    func saveSharedGroupId(_ sharedGroupId: String) {
        let trimmedGroupId = sharedGroupId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedGroupId.isEmpty {
            userDefaults.removeObject(forKey: Key.sharedGroupId)
        } else {
            userDefaults.set(trimmedGroupId, forKey: Key.sharedGroupId)
        }
    }

    func saveSharedKey(_ sharedKey: String, sharedGroupId: String) throws {
        try sharedKeyVault.saveSharedKey(sharedKey)
        saveSharedGroupId(sharedGroupId)
    }

    func saveSharingEnabled(_ sharingEnabled: Bool) {
        userDefaults.set(sharingEnabled, forKey: Key.sharingEnabled)
    }
}
