import AppKit
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

struct ConnectedPeerSummary: Identifiable, Equatable {
    let deviceId: String
    let deviceName: String
    let ipAddress: String
    let lastSeen: Date

    var id: String {
        deviceId
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
    @Published var sharedKeyConfigured: Bool {
        didSet {
            guard sharedKeyConfigured != oldValue else {
                return
            }
            refreshConnectedPeerDisplay()
        }
    }
    @Published var sharingEnabled: Bool {
        didSet {
            guard sharingEnabled != oldValue else {
                return
            }
            refreshConnectedPeerDisplay()
            sharingEnabledChanged?(sharingEnabled)
        }
    }
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
    @Published private(set) var localDevice: ConnectedPeerSummary?
    @Published private(set) var connectedPeers: [String: ConnectedPeerSummary]
    @Published private(set) var remoteConnectedPeerSummaries: [ConnectedPeerSummary]
    @Published private(set) var connectedPeerSummaries: [ConnectedPeerSummary]
    @Published private(set) var connectedPeerCount: Int
    @Published private(set) var connectedPeersTooltip: String
    @Published private(set) var remoteFileOffer: RemoteFileOfferSummary?
    @Published var sharedKeyInput: String
    @Published var sharedKeyConfirmationInput: String
    @Published var lastStatusMessage: String
    var startupEnabledChanged: ((Bool) -> Void)?
    var sharingEnabledChanged: ((Bool) -> Void)?
    var sharedGroupIdChanged: ((String) -> Void)?
    var sharedKeyChanged: ((String, String) throws -> Void)?
    var peerApproved: ((String) -> Void)?
    var remoteFileReceiveRequested: ((String) -> Void)?

    private static let connectedPeerTimeout: TimeInterval = 15

    var requiresKeySetup: Bool {
        !sharedKeyConfigured
    }

    var shouldShowKeySetupPrompt: Bool {
        requiresKeySetup
    }

    var sharedKeyFieldPrompt: String {
        "输入 Key"
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
        sharedKeyConfigured && sharingEnabled
    }

    var hasRemoteFileOffer: Bool {
        remoteFileOffer != nil
    }

    init(
        sharedKeyConfigured: Bool = false,
        sharingEnabled: Bool = true,
        startupEnabled: Bool = false,
        sharedGroupId: String = "",
        sharedKeyInput: String = "",
        trustedPeerIds: Set<String> = []
    ) {
        self.sharedKeyConfigured = sharedKeyConfigured
        self.sharingEnabled = sharingEnabled
        self.startupEnabled = startupEnabled
        self.sharedGroupId = sharedGroupId
        self.pendingPeers = [:]
        self.trustedPeerIds = trustedPeerIds
        self.localDevice = nil
        self.connectedPeers = [:]
        self.remoteConnectedPeerSummaries = []
        self.connectedPeerSummaries = []
        self.connectedPeerCount = 0
        self.connectedPeersTooltip = "暂无连接设备"
        self.remoteFileOffer = nil
        self.sharedKeyInput = sharedKeyInput
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
            && lhs.localDevice == rhs.localDevice
            && lhs.connectedPeers == rhs.connectedPeers
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

        let derivedSharedGroupId = try SharedKeyHasher.groupId(for: normalizedKey)
        try sharedKeyChanged?(normalizedKey, derivedSharedGroupId)

        sharedGroupId = derivedSharedGroupId
        sharedKeyConfigured = true
        sharedKeyConfirmationInput = ""
        lastStatusMessage = "共享 Key 已设置"
        sharedGroupIdChanged?(sharedGroupId)
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

    func recordConnectedPeer(
        deviceId: String,
        deviceName: String,
        ipAddress: String,
        now: Date = Date()
    ) {
        let normalizedDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDeviceId.isEmpty else {
            return
        }

        let normalizedDeviceName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedIPAddress = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        connectedPeers[normalizedDeviceId] = ConnectedPeerSummary(
            deviceId: normalizedDeviceId,
            deviceName: normalizedDeviceName.isEmpty ? normalizedDeviceId : normalizedDeviceName,
            ipAddress: normalizedIPAddress.isEmpty ? "未知 IP" : normalizedIPAddress,
            lastSeen: now
        )
        purgeExpiredConnectedPeers(now: now)
    }

    func setLocalDevice(
        deviceId: String,
        deviceName: String,
        ipAddress: String
    ) {
        let normalizedDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDeviceId.isEmpty else {
            return
        }

        let normalizedDeviceName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedIPAddress = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        localDevice = ConnectedPeerSummary(
            deviceId: normalizedDeviceId,
            deviceName: normalizedDeviceName.isEmpty ? normalizedDeviceId : normalizedDeviceName,
            ipAddress: normalizedIPAddress.isEmpty ? "未知 IP" : normalizedIPAddress,
            lastSeen: Date()
        )
        refreshConnectedPeerDisplay()
    }

    func purgeExpiredConnectedPeers(now: Date = Date()) {
        let activePeers = connectedPeers.filter {
            now.timeIntervalSince($0.value.lastSeen) <= Self.connectedPeerTimeout
        }
        if activePeers.count != connectedPeers.count {
            connectedPeers = activePeers
        }
        refreshConnectedPeerDisplay(now: now)
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

    func updateRemoteFileOffer(_ offer: RemoteFileOfferSummary, autoRequestReceive: Bool = true) {
        remoteFileOffer = offer
        lastStatusMessage = offer.displayTitle
        if autoRequestReceive {
            requestRemoteFileReceive()
        }
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

    private func recentConnectedPeerSummaries(now: Date) -> [ConnectedPeerSummary] {
        connectedPeers.values
            .filter { now.timeIntervalSince($0.lastSeen) <= Self.connectedPeerTimeout }
            .sorted { lhs, rhs in
                let nameOrder = lhs.deviceName.localizedCaseInsensitiveCompare(rhs.deviceName)
                if nameOrder == .orderedSame {
                    if lhs.ipAddress == rhs.ipAddress {
                        return lhs.deviceId < rhs.deviceId
                    }

                    return lhs.ipAddress < rhs.ipAddress
                }

                return nameOrder == .orderedAscending
            }
    }

    private func refreshConnectedPeerDisplay(now: Date = Date()) {
        let remoteSummaries = recentConnectedPeerSummaries(now: now)
        var allSummaries = remoteSummaries
        if sharedKeyConfigured,
           sharingEnabled,
           let localDevice {
            allSummaries.removeAll { $0.deviceId == localDevice.deviceId }
            allSummaries.insert(localDevice, at: 0)
        }

        remoteConnectedPeerSummaries = remoteSummaries
        connectedPeerSummaries = allSummaries
        connectedPeerCount = allSummaries.count
        connectedPeersTooltip = Self.connectedPeersTooltip(
            for: allSummaries,
            localDeviceId: canPublishClipboardContent ? localDevice?.deviceId : nil
        )
    }

    private static func connectedPeersTooltip(
        for summaries: [ConnectedPeerSummary],
        localDeviceId: String?
    ) -> String {
        guard !summaries.isEmpty else {
            return "暂无连接设备"
        }

        return summaries
            .map { summary in
                let localMarker = summary.deviceId == localDeviceId ? "（本机）" : ""
                return "机器名：\(summary.deviceName)\(localMarker)\nIP：\(summary.ipAddress)"
            }
            .joined(separator: "\n\n")
    }
}

struct SettingsView: View {
    @ObservedObject var state: SettingsState
    @State private var isSharedKeyVisible = false
    @State private var sharedKeyDismissRequest = 0
    @State private var keySaveErrorMessage: String?
    @State private var isConnectedPeersInfoVisible = false

    private let authorHomepageURL = URL(string: "https://github.com/nicelnicel")!

    var body: some View {
        mainSettingsColumn
        .controlSize(.small)
        .padding(10)
        .fixedSize(horizontal: true, vertical: true)
        .alert(
            "ClipPlus",
            isPresented: Binding(
                get: { keySaveErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        keySaveErrorMessage = nil
                    }
                }
            )
        ) {
            Button("确定") {
                keySaveErrorMessage = nil
            }
        } message: {
            Text(keySaveErrorMessage ?? "")
        }
    }

    private var mainSettingsColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            infoBox

            Divider()

            sharedKeyField

            sharingToggleRow

            Toggle("开机启动", isOn: startupEnabledBinding)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出 ClipPlus", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("退出 ClipPlus")
        }
        .frame(width: 160)
    }

    private var infoBox: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("ClipPlus")
                        .font(.headline)

                    Text(AppVersion.display)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("局域网剪贴板")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            authorLink
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
    }

    private var authorLink: some View {
        Link("by.YJY_hi", destination: authorHomepageURL)
            .font(.caption)
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var sharedKeyField: some View {
        SharedKeyInputField(
            prompt: state.sharedKeyFieldPrompt,
            text: $state.sharedKeyInput,
            isVisible: $isSharedKeyVisible,
            dismissRequest: sharedKeyDismissRequest,
            onCommit: saveSharedKeyIfNeeded,
            onVisibilityChanged: {}
        )
        .frame(height: 22)
    }

    private var sharingToggleRow: some View {
        HStack(spacing: 2) {
            Toggle("开启局域网剪贴板", isOn: sharingEnabledBinding)

            connectedPeerCountLabel
        }
    }

    private var connectedPeerCountLabel: some View {
        Text("(\(state.connectedPeerCount))")
            .foregroundStyle(Color.accentColor)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onHover { isHovering in
                withAnimation(.easeOut(duration: 0.08)) {
                    isConnectedPeersInfoVisible = isHovering
                }
            }
            .accessibilityHint(Text(state.connectedPeersTooltip))
            .popover(
                isPresented: $isConnectedPeersInfoVisible,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .trailing
            ) {
                connectedPeersInfoPopover
            }
    }

    private var connectedPeersInfoPopover: some View {
        Text(state.connectedPeersTooltip)
            .font(.caption2)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .frame(width: 160, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
    }

    private var sharingEnabledBinding: Binding<Bool> {
        Binding(
            get: { state.sharingEnabled },
            set: { newValue in
                dismissSharedKeyEditor()
                isConnectedPeersInfoVisible = false
                state.sharingEnabled = newValue
            }
        )
    }

    private var startupEnabledBinding: Binding<Bool> {
        Binding(
            get: { state.startupEnabled },
            set: { newValue in
                dismissSharedKeyEditor()
                isConnectedPeersInfoVisible = false
                state.startupEnabled = newValue
            }
        )
    }

    private func dismissSharedKeyEditor() {
        isSharedKeyVisible = false
        sharedKeyDismissRequest += 1
    }

    private func saveSharedKeyIfNeeded() {
        guard !state.sharedKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        do {
            try state.updateSharedKey(
                state.sharedKeyInput,
                confirmation: state.sharedKeyInput
            )
            keySaveErrorMessage = nil
        } catch {
            keySaveErrorMessage = error.localizedDescription
        }
    }
}
