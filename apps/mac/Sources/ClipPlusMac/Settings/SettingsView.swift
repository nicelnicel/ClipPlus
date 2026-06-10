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

struct PendingPeerSummary: Identifiable, Equatable {
    let deviceId: String
    let deviceName: String

    var id: String {
        deviceId
    }

    var shortDeviceId: String {
        String(deviceId.prefix(8))
    }
}

struct RemoteFileOfferSummary: Equatable {
    let transferId: String
    let sourceDeviceId: String
    let sourceDeviceName: String
    let sourceHost: String
    let fileCount: Int
    let totalBytes: Int64

    var displayTitle: String {
        "\(sourceDeviceName)：\(fileCount) 个文件可接收"
    }
}

final class SettingsState: ObservableObject, Equatable {
    @Published var sharedKeyConfigured: Bool
    @Published var sharingEnabled: Bool
    @Published var startupEnabled: Bool {
        didSet {
            guard startupEnabled != oldValue else {
                return
            }
            startupEnabledChanged?(startupEnabled)
        }
    }
    @Published private(set) var sharedGroupId: String
    @Published private(set) var pendingPeers: [String: String]
    @Published private(set) var trustedPeerIds: Set<String>
    @Published private(set) var remoteFileOffer: RemoteFileOfferSummary?
    @Published var sharedKeyInput: String
    @Published var sharedKeyConfirmationInput: String
    @Published var lastStatusMessage: String
    var startupEnabledChanged: ((Bool) -> Void)?
    var peerApproved: ((String) -> Void)?
    var remoteFileReceiveRequested: ((String) -> Void)?

    var requiresKeySetup: Bool {
        !sharedKeyConfigured
    }

    var pendingPeerCount: Int {
        pendingPeers.count
    }

    var trustedPeerCount: Int {
        trustedPeerIds.count
    }

    var pendingPeerSummaries: [PendingPeerSummary] {
        pendingPeers
            .map { PendingPeerSummary(deviceId: $0.key, deviceName: $0.value) }
            .sorted { lhs, rhs in
                let nameOrder = lhs.deviceName.localizedCaseInsensitiveCompare(rhs.deviceName)
                if nameOrder == .orderedSame {
                    return lhs.deviceId < rhs.deviceId
                }

                return nameOrder == .orderedAscending
            }
    }

    var canPublishClipboardContent: Bool {
        sharedKeyConfigured && sharingEnabled && !trustedPeerIds.isEmpty
    }

    var hasRemoteFileOffer: Bool {
        remoteFileOffer != nil
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
        self.remoteFileOffer = nil
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
            && lhs.remoteFileOffer == rhs.remoteFileOffer
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
        let approvedDeviceIds = Array(pendingPeers.keys)
        trustedPeerIds.formUnion(approvedDeviceIds)
        pendingPeers.removeAll()
        lastStatusMessage = "待确认设备已允许"
        approvedDeviceIds.forEach { peerApproved?($0) }
    }

    func approvePendingPeer(deviceId: String) {
        guard pendingPeers.removeValue(forKey: deviceId) != nil else {
            return
        }

        trustedPeerIds.insert(deviceId)
        lastStatusMessage = pendingPeers.isEmpty
            ? "设备已允许"
            : "设备已允许，仍有 \(pendingPeers.count) 台待确认设备"
        peerApproved?(deviceId)
    }

    func isPeerTrusted(_ deviceId: String) -> Bool {
        trustedPeerIds.contains(deviceId)
    }

    @discardableResult
    func trustPeer(deviceId: String, deviceName: String) -> Bool {
        guard !deviceId.isEmpty else {
            return false
        }

        guard !trustedPeerIds.contains(deviceId) else {
            return false
        }

        pendingPeers.removeValue(forKey: deviceId)
        trustedPeerIds.insert(deviceId)
        lastStatusMessage = "设备 \(deviceName.isEmpty ? deviceId : deviceName) 已信任"
        return true
    }

    func updateRemoteFileOffer(_ offer: RemoteFileOfferSummary) {
        remoteFileOffer = offer
        lastStatusMessage = offer.displayTitle
    }

    func clearRemoteFileOffer(transferId: String) {
        guard remoteFileOffer?.transferId == transferId else {
            return
        }

        remoteFileOffer = nil
    }

    func requestRemoteFileReceive() {
        guard let transferId = remoteFileOffer?.transferId else {
            return
        }

        remoteFileReceiveRequested?(transferId)
    }
}

struct SettingsView: View {
    @ObservedObject var state: SettingsState
    @State private var keyErrorMessage: String?
    @State private var diagnosticsMessage: String?

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

                if state.pendingPeerSummaries.isEmpty {
                    Text("暂无待确认设备")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.pendingPeerSummaries) { peer in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(peer.deviceName)
                                Text("ID \(peer.shortDeviceId)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("允许") {
                                state.approvePendingPeer(deviceId: peer.deviceId)
                            }
                        }
                    }
                }

                Button("允许全部待确认设备") {
                    state.approvePendingPeers()
                }
                .disabled(state.pendingPeerCount == 0)

                if let remoteFileOffer = state.remoteFileOffer {
                    Button(remoteFileOffer.displayTitle) {
                        state.requestRemoteFileReceive()
                    }
                }
            }

            Section("系统") {
                Toggle("开机自动启动", isOn: $state.startupEnabled)

                Button("导出诊断包") {
                    exportDiagnostics()
                }

                if let diagnosticsMessage {
                    Text(diagnosticsMessage)
                        .foregroundStyle(.secondary)
                }
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

    private func exportDiagnostics() {
        let sensitiveValues = [
            ProcessInfo.processInfo.environment["CLIPPLUS_SHARED_KEY"]
        ].compactMap { $0 }

        do {
            let exportURL = try DiagnosticsExporter(sensitiveValues: sensitiveValues).export(state: state)
            diagnosticsMessage = "已导出：\(exportURL.path)"
        } catch {
            diagnosticsMessage = "诊断包导出失败"
        }
    }
}
