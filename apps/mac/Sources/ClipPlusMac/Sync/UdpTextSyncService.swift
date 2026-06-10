import Darwin
import Foundation

final class UdpTextSyncService {
    private let port: UInt16 = 47_631
    private let state: SettingsState
    private let clipboard = NativeClipboard()
    private let logger: ClipPlusLogger
    private let receiveQueue = DispatchQueue(label: "clipplus.mac.udp.receive")
    private let deviceId: String
    private let deviceName: String
    private let autoTrustPeers: Bool
    private let peerHosts: [String]

    private var listenSocket: Int32 = -1
    private var sendSocket: Int32 = -1
    private var running = false
    private var timer: Timer?
    private var lastLocalText: String?
    private var lastRemoteText: String?
    private var tickCount = 0

    init(state: SettingsState, logger: ClipPlusLogger) {
        self.state = state
        self.logger = logger
        deviceId = UserDefaults.standard.string(forKey: "clipplus.device_id") ?? {
            let value = UUID().uuidString
            UserDefaults.standard.set(value, forKey: "clipplus.device_id")
            return value
        }()
        deviceName = Host.current().localizedName ?? "Mac"
        autoTrustPeers = ProcessInfo.processInfo.environment["CLIPPLUS_AUTO_TRUST"] == "1"
        peerHosts = ProcessInfo.processInfo.environment["CLIPPLUS_PEER_HOSTS"]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    func start() {
        guard !running else {
            return
        }

        applyEnvironmentKeyIfNeeded()
        do {
            try openSockets()
            running = true
            receiveQueue.async { [weak self] in
                self?.receiveLoop()
            }
            timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
                self?.pollClipboardAndBroadcast()
            }
            sendHello()
            logger.info("sync service started on UDP \(port)")
        } catch {
            state.lastStatusMessage = "同步服务启动失败"
            logger.error("sync service start failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil

        if listenSocket >= 0 {
            close(listenSocket)
            listenSocket = -1
        }
        if sendSocket >= 0 {
            close(sendSocket)
            sendSocket = -1
        }
    }

    private func applyEnvironmentKeyIfNeeded() {
        guard state.requiresKeySetup,
              let sharedKey = ProcessInfo.processInfo.environment["CLIPPLUS_SHARED_KEY"],
              !sharedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        do {
            try state.updateSharedKey(sharedKey, confirmation: sharedKey)
            logger.info("shared key configured from environment")
        } catch {
            logger.error("environment shared key rejected: \(error.localizedDescription)")
        }
    }

    private func openSockets() throws {
        listenSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard listenSocket >= 0 else {
            throw SocketError.openFailed
        }

        var yes: Int32 = 1
        setsockopt(listenSocket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
        setsockopt(listenSocket, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(listenSocket, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw SocketError.bindFailed
        }

        sendSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sendSocket >= 0 else {
            throw SocketError.openFailed
        }
        setsockopt(sendSocket, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
    }

    private func receiveLoop() {
        var buffer = [UInt8](repeating: 0, count: 65_535)

        while running {
            let count = recvfrom(listenSocket, &buffer, buffer.count, 0, nil, nil)
            guard count > 0 else {
                continue
            }

            let data = Data(buffer.prefix(count))
            guard let message = try? JSONDecoder().decode(ClipPlusMessage.self, from: data) else {
                continue
            }

            DispatchQueue.main.async { [weak self] in
                self?.handle(message)
            }
        }
    }

    private func pollClipboardAndBroadcast() {
        guard state.sharedKeyConfigured, state.sharingEnabled else {
            return
        }

        tickCount += 1
        if tickCount % 4 == 0 {
            sendHello()
        }

        guard let text = clipboard.readText(),
              !text.isEmpty,
              text != lastLocalText,
              text != lastRemoteText else {
            return
        }

        lastLocalText = text
        send(.text(
            groupId: state.sharedGroupId,
            senderDeviceId: deviceId,
            senderDeviceName: deviceName,
            text: text
        ))
        state.lastStatusMessage = "已广播文本剪贴板"
        logger.info("published text clipboard byte_count=\(text.utf8.count)")
    }

    private func handle(_ message: ClipPlusMessage) {
        guard state.sharedKeyConfigured,
              message.protocolVersion == 1,
              message.groupId == state.sharedGroupId,
              message.senderDeviceId != deviceId else {
            return
        }

        switch message.kind {
        case .hello:
            state.markPeerPending(
                deviceId: message.senderDeviceId,
                deviceName: message.senderDeviceName
            )
            if autoTrustPeers {
                state.approvePendingPeers()
            }
            logger.info("peer hello device_id_prefix=\(message.senderDeviceId.prefix(8))")
        case .text:
            guard state.sharingEnabled,
                  state.isPeerTrusted(message.senderDeviceId),
                  let text = message.text,
                  !text.isEmpty else {
                return
            }

            lastRemoteText = text
            lastLocalText = text
            clipboard.writeText(text)
            state.lastStatusMessage = "已接收远端文本剪贴板"
            logger.info("received text clipboard byte_count=\(text.utf8.count)")
        }
    }

    private func sendHello() {
        guard state.sharedKeyConfigured else {
            return
        }

        send(.hello(
            groupId: state.sharedGroupId,
            senderDeviceId: deviceId,
            senderDeviceName: deviceName
        ))
    }

    private func send(_ message: ClipPlusMessage) {
        guard sendSocket >= 0,
              let data = try? JSONEncoder().encode(message) else {
            return
        }

        var targets = ["255.255.255.255"]
        targets.append(contentsOf: peerHosts)

        for target in targets {
            send(data, to: target)
        }
    }

    private func send(_ data: Data, to host: String) {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr(host))

        _ = data.withUnsafeBytes { rawBuffer in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    sendto(
                        sendSocket,
                        rawBuffer.baseAddress,
                        data.count,
                        0,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
    }
}

private enum SocketError: LocalizedError {
    case openFailed
    case bindFailed

    var errorDescription: String? {
        switch self {
        case .openFailed:
            return "无法打开 UDP socket"
        case .bindFailed:
            return "无法绑定 UDP 端口"
        }
    }
}
