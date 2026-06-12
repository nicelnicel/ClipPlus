import Darwin
import Foundation

final class UdpTextSyncService {
    private let port: UInt16 = 47_631
    private let archivePort: UInt16 = 47_632
    private let state: SettingsState
    private let clipboard = NativeClipboard()
    private let logger: ClipPlusLogger
    private let receiveQueue = DispatchQueue(label: "clipplus.mac.udp.receive")
    private let clipboardQueue = DispatchQueue(label: "clipplus.mac.clipboard.poll")
    private let fileQueue = DispatchQueue(label: "clipplus.mac.file.transfer", attributes: .concurrent)
    private let deviceId: String
    private let deviceName: String
    private let peerHosts: [String]

    private var udpSocket: RustUdpSocket?
    private var fileServer: RustFileServer?
    private var running = false
    private var clipboardTimer: DispatchSourceTimer?
    private var lastLocalText: String?
    private var lastRemoteText: String?
    private var lastLocalImageHash: String?
    private var lastRemoteImageHash: String?
    private var lastLocalFileSignature: String?
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
        peerHosts = ProcessInfo.processInfo.environment["CLIPPLUS_PEER_HOSTS"]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        state.peerApproved = { [weak self] approvedDeviceId in
            self?.sendTrust(approvedDeviceId: approvedDeviceId)
        }
        state.remoteFileReceiveRequested = { [weak self] transferId in
            self?.downloadRemoteFileOffer(transferId: transferId)
        }
        refreshLocalDeviceInfo()
    }

    func start() {
        guard !running else {
            return
        }

        applyEnvironmentKeyIfNeeded()
        do {
            try openSockets()
            try openFileServer()
            running = true
            receiveQueue.async { [weak self] in
                self?.receiveLoop()
            }
            fileQueue.async { [weak self] in
                self?.fileServerLoop()
            }
            let timer = DispatchSource.makeTimerSource(queue: clipboardQueue)
            timer.schedule(deadline: .now() + 0.75, repeating: 0.75)
            timer.setEventHandler { [weak self] in
                self?.pollClipboardAndBroadcast()
            }
            clipboardTimer = timer
            timer.resume()
            sendHello()
            logger.info("sync service started on UDP \(port)")
        } catch {
            state.lastStatusMessage = "同步服务启动失败"
            logger.error("sync service start failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        running = false
        clipboardTimer?.cancel()
        clipboardTimer = nil

        udpSocket?.close()
        udpSocket = nil
        wakeFileServer()
        fileServer?.close()
        fileServer = nil
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
        guard let udpSocket = CoreBridge().openUdpSocket(bindPort: Int(port)) else {
            throw SocketError.openFailed
        }

        self.udpSocket = udpSocket
    }

    private func openFileServer() throws {
        guard let fileServer = CoreBridge().openFileServer(bindPort: Int(archivePort)),
              fileServer.localPort == Int(archivePort) else {
            throw SocketError.openFailed
        }

        self.fileServer = fileServer
    }

    private func receiveLoop() {
        while running {
            guard let datagram = udpSocket?.receive() else {
                continue
            }

            let data = datagram.payload
            guard let message = try? JSONDecoder().decode(ClipPlusMessage.self, from: data) else {
                continue
            }
            let sourceHost = datagram.sourceHost

            DispatchQueue.main.async { [weak self] in
                self?.handle(message, sourceHost: sourceHost)
            }
        }
    }

    private func pollClipboardAndBroadcast() {
        let snapshot = syncSnapshot()
        guard snapshot.sharedKeyConfigured, snapshot.sharingEnabled else {
            return
        }

        tickCount += 1
        if tickCount % 4 == 0 {
            sendHello(groupId: snapshot.sharedGroupId, trustedPeerIds: snapshot.trustedPeerIds)
        }

        guard snapshot.canPublishClipboardContent else {
            return
        }

        let fileURLs = clipboard.readFileURLs()
        if !fileURLs.isEmpty {
            let signature = fileURLs.map(\.path).sorted().joined(separator: "|")
            if signature != lastLocalFileSignature {
                lastLocalFileSignature = signature
                publishFileOffer(fileURLs: fileURLs, groupId: snapshot.sharedGroupId)
            }
            return
        }

        if let text = clipboard.readText(),
           !text.isEmpty,
           text != lastLocalText,
           text != lastRemoteText {
            lastLocalText = text
            send(.text(
                groupId: snapshot.sharedGroupId,
                senderDeviceId: deviceId,
                senderDeviceName: deviceName,
                text: text
            ))
            updateStatus("已广播文本剪贴板")
            logger.info("published text clipboard byte_count=\(text.utf8.count)")
        }

        guard let pngData = clipboard.readPngImageData(),
              let message = ClipPlusMessage.image(
            groupId: snapshot.sharedGroupId,
            senderDeviceId: deviceId,
            senderDeviceName: deviceName,
            pngData: pngData
        ),
              let imageHash = message.imageContentHash,
              imageHash != lastLocalImageHash,
              imageHash != lastRemoteImageHash else {
            return
        }

        lastLocalImageHash = imageHash
        send(message)
        updateStatus("已广播图片剪贴板")
        logger.info("published image clipboard byte_count=\(pngData.count)")
    }

    private func localImageHashAfterClipboardWrite() -> String? {
        guard let writtenPngData = clipboard.readPngImageData(),
              let message = ClipPlusMessage.image(
                groupId: state.sharedGroupId,
                senderDeviceId: deviceId,
                senderDeviceName: deviceName,
                pngData: writtenPngData
              ) else {
            return nil
        }

        return message.imageContentHash
    }

    private func syncSnapshot() -> SyncSnapshot {
        DispatchQueue.main.sync {
            state.purgeExpiredConnectedPeers()
            return SyncSnapshot(
                sharedKeyConfigured: state.sharedKeyConfigured,
                sharingEnabled: state.sharingEnabled,
                canPublishClipboardContent: state.canPublishClipboardContent,
                sharedGroupId: state.sharedGroupId,
                trustedPeerIds: Array(state.trustedPeerIds)
            )
        }
    }

    private func updateStatus(_ status: String) {
        DispatchQueue.main.async { [weak self] in
            self?.state.lastStatusMessage = status
        }
    }

    private func handle(_ message: ClipPlusMessage, sourceHost: String) {
        guard state.sharedKeyConfigured,
              message.protocolVersion == 1,
              message.groupId == state.sharedGroupId,
              message.senderDeviceId != deviceId else {
            return
        }

        state.recordConnectedPeer(
            deviceId: message.senderDeviceId,
            deviceName: message.senderDeviceName,
            ipAddress: sourceHost
        )

        switch message.kind {
        case .hello:
            let newlyTrusted = state.trustPeer(
                deviceId: message.senderDeviceId,
                deviceName: message.senderDeviceName
            )
            if newlyTrusted {
                sendTrust(approvedDeviceId: message.senderDeviceId)
                logger.info("peer hello trusted device_id_prefix=\(message.senderDeviceId.prefix(8))")
            } else {
                logger.info("peer hello device_id_prefix=\(message.senderDeviceId.prefix(8))")
            }
        case .trust:
            guard message.approvedDeviceId == deviceId else {
                return
            }

            let newlyTrusted = state.trustPeer(
                deviceId: message.senderDeviceId,
                deviceName: message.senderDeviceName
            )
            if newlyTrusted {
                logger.info("peer trust accepted device_id_prefix=\(message.senderDeviceId.prefix(8))")
            }
        case .text:
            guard state.sharingEnabled,
                  let text = message.text,
                  !text.isEmpty else {
                return
            }

            lastRemoteText = text
            lastLocalText = text
            clipboard.writeText(text)
            state.lastStatusMessage = "已接收远端文本剪贴板"
            logger.info("received text clipboard byte_count=\(text.utf8.count)")
        case .image:
            guard state.sharingEnabled,
                  let imageData = message.decodedImageData,
                  let imageHash = message.imageContentHash,
                  imageData.count <= ClipPlusMessage.maxInlineImageBytes else {
                return
            }

            lastRemoteImageHash = imageHash
            lastLocalImageHash = imageHash
            clipboard.writePngImageData(imageData)
            if let writtenImageHash = localImageHashAfterClipboardWrite() {
                lastLocalImageHash = writtenImageHash
            }
            state.lastStatusMessage = "已接收远端图片剪贴板"
            logger.info("received image clipboard byte_count=\(imageData.count)")
        case .fileOffer:
            guard state.sharingEnabled,
                  let transferId = message.transferId,
                  let files = message.files,
                  !files.isEmpty else {
                return
            }

            let totalBytes = files.reduce(Int64(0)) { $0 + $1.byteSize }
            state.updateRemoteFileOffer(RemoteFileOfferSummary(
                transferId: transferId,
                sourceDeviceId: message.senderDeviceId,
                sourceDeviceName: message.senderDeviceName,
                sourceHost: sourceHost,
                fileCount: files.count,
                totalBytes: totalBytes
            ))
            logger.info("received file offer file_count=\(files.count) byte_count=\(totalBytes)")
        }
    }

    private func publishFileOffer(fileURLs: [URL], groupId: String) {
        let transferId = UUID().uuidString
        guard let fileServer,
              fileServer.registerTransfer(transferId: transferId, sourcePaths: fileURLs.map(\.path)) else {
            updateStatus("文件广播失败")
            logger.error("file transfer registration failed")
            return
        }

        let items = fileURLs.map { fileTransferItem(for: $0) }
        send(.fileOffer(
            groupId: groupId,
            senderDeviceId: deviceId,
            senderDeviceName: deviceName,
            transferId: transferId,
            files: items,
            archivePort: Int(archivePort)
        ))
        updateStatus("已广播文件剪贴板")
        logger.info("published file offer file_count=\(items.count)")
    }

    private func fileTransferItem(for url: URL) -> FileTransferItem {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey])
        let isDirectory = values?.isDirectory == true
        return FileTransferItem(
            relativePath: url.lastPathComponent,
            byteSize: isDirectory ? directorySize(url) : Int64(values?.fileSize ?? 0),
            isDirectory: isDirectory
        )
    }

    private func directorySize(_ url: URL) -> Int64 {
        let urls = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? []

        return urls.reduce(Int64(0)) { total, childURL in
            let values = try? childURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            return values?.isDirectory == true ? total : total + Int64(values?.fileSize ?? 0)
        }
    }

    private func fileServerLoop() {
        while running {
            guard let fileServer else {
                return
            }

            let byteCount = fileServer.serveNext(tempDirectory: FileManager.default.temporaryDirectory.path)
            guard running else {
                return
            }
            guard byteCount > 0 else {
                continue
            }

            logger.info("served file archive byte_count=\(byteCount)")
        }
    }

    private func downloadRemoteFileOffer(transferId: String) {
        guard let offer = state.remoteFileOffer,
              offer.transferId == transferId else {
            return
        }

        fileQueue.async { [weak self] in
            self?.downloadRemoteFileOffer(offer)
        }
    }

    private func downloadRemoteFileOffer(_ offer: RemoteFileOfferSummary) {
        let destinationURL = uniqueDownloadURL(for: offer.transferId)
        let downloaded = CoreBridge().downloadFileArchive(
            host: offer.sourceHost,
            port: Int(archivePort),
            transferId: offer.transferId,
            destinationPath: destinationURL.path
        )
        guard downloaded else {
            DispatchQueue.main.async { [weak self] in
                self?.state.lastStatusMessage = "文件接收失败"
            }
            logger.error("file transfer download failed")
            return
        }

        do {
            let byteCount = try FileManager.default
                .attributesOfItem(atPath: destinationURL.path)[.size] as? NSNumber
            DispatchQueue.main.async { [weak self] in
                self?.state.clearRemoteFileOffer(transferId: offer.transferId)
                self?.state.lastStatusMessage = "文件已接收到 \(destinationURL.lastPathComponent)"
            }
            logger.info("downloaded file archive byte_count=\(byteCount?.intValue ?? 0)")
        } catch {
            logger.error("file transfer download failed: \(error.localizedDescription)")
        }
    }

    private func uniqueDownloadURL(for transferId: String) -> URL {
        let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var candidate = directory.appendingPathComponent("ClipPlus-Received-\(transferId).zip")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("ClipPlus-Received-\(transferId)-\(index).zip")
            index += 1
        }
        return candidate
    }

    private func sendHello() {
        guard state.sharedKeyConfigured else {
            return
        }

        sendHello(groupId: state.sharedGroupId, trustedPeerIds: Array(state.trustedPeerIds))
    }

    private func sendHello(groupId: String, trustedPeerIds: [String]) {
        send(.hello(
            groupId: groupId,
            senderDeviceId: deviceId,
            senderDeviceName: deviceName
        ))

        for trustedPeerId in trustedPeerIds {
            send(.trust(
                groupId: groupId,
                senderDeviceId: deviceId,
                senderDeviceName: deviceName,
                approvedDeviceId: trustedPeerId
            ))
        }
    }

    private func sendTrust(approvedDeviceId: String) {
        guard state.sharedKeyConfigured else {
            return
        }

        send(.trust(
            groupId: state.sharedGroupId,
            senderDeviceId: deviceId,
            senderDeviceName: deviceName,
            approvedDeviceId: approvedDeviceId
        ))
    }

    private func send(_ message: ClipPlusMessage) {
        guard let udpSocket,
              let data = try? JSONEncoder().encode(message) else {
            return
        }

        var targets = Set(["255.255.255.255"])
        targets.formUnion(peerHosts)
        targets.formUnion(state.remoteConnectedPeerSummaries.map(\.ipAddress))

        for target in targets {
            _ = udpSocket.send(data, to: target, port: Int(port))
        }
    }

    private static func localIPv4Address() -> String {
        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceAddresses) == 0 else {
            return "未知 IP"
        }
        defer { freeifaddrs(interfaceAddresses) }

        var fallbackAddress: String?
        var currentAddress = interfaceAddresses
        while let interface = currentAddress?.pointee {
            defer { currentAddress = interface.ifa_next }
            guard let socketAddress = interface.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET),
                  interface.ifa_flags & UInt32(IFF_UP) != 0,
                  interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else {
                continue
            }

            let ipAddress = String(cString: host)
            if isPrivateIPv4Address(ipAddress) {
                return ipAddress
            }

            if fallbackAddress == nil {
                fallbackAddress = ipAddress
            }
        }

        return fallbackAddress ?? "未知 IP"
    }

    private static func isPrivateIPv4Address(_ ipAddress: String) -> Bool {
        let parts = ipAddress.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else {
            return false
        }

        return parts[0] == 10
            || (parts[0] == 172 && (16...31).contains(parts[1]))
            || (parts[0] == 192 && parts[1] == 168)
    }

    private func refreshLocalDeviceInfo() {
        let currentDeviceId = deviceId
        let currentDeviceName = deviceName
        DispatchQueue.global(qos: .utility).async { [weak self, currentDeviceId, currentDeviceName] in
            let ipAddress = Self.localIPv4Address()
            DispatchQueue.main.async {
                self?.state.setLocalDevice(
                    deviceId: currentDeviceId,
                    deviceName: currentDeviceName,
                    ipAddress: ipAddress
                )
            }
        }
    }

    private func wakeFileServer() {
        let client = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard client >= 0 else {
            return
        }
        defer { close(client) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = archivePort.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(client, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connectResult == 0 {
            _ = "\n".withCString { pointer in
                Darwin.send(client, pointer, strlen(pointer), 0)
            }
        }
    }
}

private enum SocketError: LocalizedError {
    case openFailed

    var errorDescription: String? {
        switch self {
        case .openFailed:
            return "无法打开 UDP socket"
        }
    }
}

private struct SyncSnapshot {
    let sharedKeyConfigured: Bool
    let sharingEnabled: Bool
    let canPublishClipboardContent: Bool
    let sharedGroupId: String
    let trustedPeerIds: [String]
}
