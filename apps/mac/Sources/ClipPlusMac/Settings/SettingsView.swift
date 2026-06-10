import SwiftUI

enum SettingsStateError: LocalizedError, Equatable {
    case emptySharedKey
    case confirmationMismatch

    var errorDescription: String? {
        switch self {
        case .emptySharedKey:
            return "共享 Key 不能为空"
        case .confirmationMismatch:
            return "两次输入的共享 Key 不一致"
        }
    }
}

final class SettingsState: ObservableObject, Equatable {
    @Published var sharedKeyConfigured: Bool
    @Published var sharingEnabled: Bool
    @Published var startupEnabled: Bool
    @Published private(set) var sharedGroupId: String
    @Published private(set) var pendingPeers: [String: String]
    @Published private(set) var trustedPeerIds: Set<String>
    @Published var sharedKeyInput: String
    @Published var sharedKeyConfirmationInput: String
    @Published var lastStatusMessage: String

    var requiresKeySetup: Bool {
        !sharedKeyConfigured
    }

    var pendingPeerCount: Int {
        pendingPeers.count
    }

    init(
        sharedKeyConfigured: Bool = false,
        sharingEnabled: Bool = true,
        startupEnabled: Bool = false,
        sharedGroupId: String = "",
        trustedPeerIds: Set<String> = []
    ) {
        self.sharedKeyConfigured = sharedKeyConfigured
        self.sharingEnabled = sharingEnabled
        self.startupEnabled = startupEnabled
        self.sharedGroupId = sharedGroupId
        self.pendingPeers = [:]
        self.trustedPeerIds = trustedPeerIds
        self.sharedKeyInput = ""
        self.sharedKeyConfirmationInput = ""
        self.lastStatusMessage = sharedKeyConfigured ? "剪贴板共享准备就绪" : "请先设置共享 Key"
    }

    static func == (lhs: SettingsState, rhs: SettingsState) -> Bool {
        lhs.sharedKeyConfigured == rhs.sharedKeyConfigured
            && lhs.sharingEnabled == rhs.sharingEnabled
            && lhs.startupEnabled == rhs.startupEnabled
            && lhs.sharedGroupId == rhs.sharedGroupId
            && lhs.pendingPeers == rhs.pendingPeers
            && lhs.trustedPeerIds == rhs.trustedPeerIds
    }

    func updateSharedKey(_ rawKey: String, confirmation: String) throws {
        let normalizedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedConfirmation = confirmation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedKey.isEmpty else {
            throw SettingsStateError.emptySharedKey
        }
        guard normalizedKey == normalizedConfirmation else {
            throw SettingsStateError.confirmationMismatch
        }

        sharedGroupId = SharedKeyHasher.groupId(for: normalizedKey)
        sharedKeyConfigured = true
        sharedKeyInput = ""
        sharedKeyConfirmationInput = ""
        lastStatusMessage = "共享 Key 已设置"
    }

    func markPeerPending(deviceId: String, deviceName: String) {
        guard !deviceId.isEmpty, !trustedPeerIds.contains(deviceId) else {
            return
        }

        pendingPeers[deviceId] = deviceName.isEmpty ? deviceId : deviceName
        lastStatusMessage = "发现 \(pendingPeers.count) 台待确认设备"
    }

    func approvePendingPeers() {
        trustedPeerIds.formUnion(pendingPeers.keys)
        pendingPeers.removeAll()
        lastStatusMessage = "待确认设备已允许"
    }

    func isPeerTrusted(_ deviceId: String) -> Bool {
        trustedPeerIds.contains(deviceId)
    }
}

struct SettingsView: View {
    @ObservedObject var state: SettingsState
    @State private var keyErrorMessage: String?

    var body: some View {
        Form {
            Section("共享") {
                Toggle("启用剪贴板共享", isOn: $state.sharingEnabled)

                LabeledContent("共享 Key") {
                    keyStatusText
                }

                SecureField("输入共享 Key", text: $state.sharedKeyInput)
                SecureField("再次输入共享 Key", text: $state.sharedKeyConfirmationInput)

                if let keyErrorMessage {
                    Text(keyErrorMessage)
                        .foregroundStyle(.red)
                }

                Button("保存 Key") {
                    do {
                        try state.updateSharedKey(
                            state.sharedKeyInput,
                            confirmation: state.sharedKeyConfirmationInput
                        )
                        keyErrorMessage = nil
                    } catch {
                        keyErrorMessage = error.localizedDescription
                    }
                }
            }

            Section("设备") {
                LabeledContent("待确认设备") {
                    Text("\(state.pendingPeerCount)")
                        .foregroundStyle(state.pendingPeerCount == 0 ? .secondary : .primary)
                }

                Button("允许全部待确认设备") {
                    state.approvePendingPeers()
                }
                .disabled(state.pendingPeerCount == 0)
            }

            Section("系统") {
                Toggle("开机自动启动", isOn: $state.startupEnabled)

                Button("导出诊断包") {}
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
    }

    @ViewBuilder
    private var keyStatusText: some View {
        if state.sharedKeyConfigured {
            Text("已设置")
                .foregroundStyle(.secondary)
        } else {
            Text("未设置")
                .foregroundStyle(.red)
        }
    }
}
