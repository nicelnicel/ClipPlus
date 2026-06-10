import Darwin
import Foundation

final class UdpTextSyncService {
    private let port: UInt16 = 47_631
    private let archivePort: UInt16 = 47_632
    private let state: SettingsState
    private let clipboard = NativeClipboard()
    private let logger: ClipPlusLogger
    private let receiveQueue = DispatchQueue(label: "clipplus.mac.udp.receive")
    private let fileQueue = DispatchQueue(label: "clipplus.mac.file.transfer", attributes: .concurrent)
    private let deviceId: String
    private let deviceName: String
    private let autoTrustPeers: Bool
    private let peerHosts: [String]

    private var udpSocket: RustUdpSocket?
    private var fileServerSocket: Int32 = -1
    private var running = false
    private var timer: Timer?
    private var lastLocalText: String?
    private var lastRemoteText: String?
    private var lastLocalImageHash: String?
    private var lastRemoteImageHash: String?
    private var lastLocalFileSignature: String?
    private var localFileTransfers: [String: [URL]] = [:]
    private let localFileTransfersLock = NSLock()
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
        state.peerApproved = { [weak self] approvedDeviceId in
            self?.sendTrust(approvedDeviceId: approvedDeviceId)
        }
        state.remoteFileReceiveRequested = { [weak self] transferId in
            self?.downloadRemoteFileOffer(transferId: transferId)
        }
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

        udpSocket?.close()
        udpSocket = nil
        if fileServerSocket >= 0 {
            close(fileServerSocket)
            fileServerSocket = -1
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
        guard let udpSocket = CoreBridge().openUdpSocket(bindPort: Int(port)) else {
            throw SocketError.openFailed
        }

        self.udpSocket = udpSocket
    }

    private func openFileServer() throws {
        fileServerSocket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fileServerSocket >= 0 else {
            throw SocketError.openFailed
        }

        var yes: Int32 = 1
        setsockopt(fileServerSocket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = archivePort.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(fileServerSocket, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw SocketError.bindFailed
        }

        listen(fileServerSocket, 8)
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
        guard state.sharedKeyConfigured, state.sharingEnabled else {
            return
        }

        tickCount += 1
        if tickCount % 4 == 0 {
            sendHello()
        }

        guard state.canPublishClipboardContent else {
            return
        }

        let fileURLs = clipboard.readFileURLs()
        if !fileURLs.isEmpty {
            let signature = fileURLs.map(\.path).sorted().joined(separator: "|")
            if signature != lastLocalFileSignature {
                lastLocalFileSignature = signature
                publishFileOffer(fileURLs: fileURLs)
            }
            return
        }

        if let text = clipboard.readText(),
           !text.isEmpty,
           text != lastLocalText,
           text != lastRemoteText {
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

        guard let pngData = clipboard.readPngImageData(),
              let message = ClipPlusMessage.image(
            groupId: state.sharedGroupId,
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
        state.lastStatusMessage = "已广播图片剪贴板"
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

    private func handle(_ message: ClipPlusMessage, sourceHost: String) {
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
        case .image:
            guard state.sharingEnabled,
                  state.isPeerTrusted(message.senderDeviceId),
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
                  state.isPeerTrusted(message.senderDeviceId),
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

    private func publishFileOffer(fileURLs: [URL]) {
        let transferId = UUID().uuidString
        storeLocalFileTransfer(transferId: transferId, fileURLs: fileURLs)
        let items = fileURLs.map { fileTransferItem(for: $0) }
        send(.fileOffer(
            groupId: state.sharedGroupId,
            senderDeviceId: deviceId,
            senderDeviceName: deviceName,
            transferId: transferId,
            files: items,
            archivePort: Int(archivePort)
        ))
        state.lastStatusMessage = "已广播文件剪贴板"
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
        while running && fileServerSocket >= 0 {
            let client = accept(fileServerSocket, nil, nil)
            guard client >= 0 else {
                continue
            }

            fileQueue.async { [weak self] in
                self?.handleFileClient(client)
            }
        }
    }

    private func handleFileClient(_ client: Int32) {
        defer { close(client) }

        guard let transferId = readLine(from: client),
              let fileURLs = localFileTransfer(transferId: transferId) else {
            return
        }

        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipPlus-\(transferId).zip")

        do {
            try FileTransferArchive.writeZip(sourceURLs: fileURLs, to: archiveURL)
            let data = try Data(contentsOf: archiveURL)
            try? FileManager.default.removeItem(at: archiveURL)
            sendLengthAndData(data, to: client)
            logger.info("served file archive file_count=\(fileURLs.count) byte_count=\(data.count)")
        } catch {
            logger.error("file transfer serve failed: \(error.localizedDescription)")
        }
    }

    private func storeLocalFileTransfer(transferId: String, fileURLs: [URL]) {
        localFileTransfersLock.lock()
        localFileTransfers[transferId] = fileURLs
        localFileTransfersLock.unlock()
    }

    private func localFileTransfer(transferId: String) -> [URL]? {
        localFileTransfersLock.lock()
        let fileURLs = localFileTransfers[transferId]
        localFileTransfersLock.unlock()
        return fileURLs
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
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketDescriptor >= 0 else {
            return
        }
        defer { close(socketDescriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = archivePort.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr(offer.sourceHost))

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(socketDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else {
            DispatchQueue.main.async { [weak self] in
                self?.state.lastStatusMessage = "文件接收失败"
            }
            return
        }

        sendData(Data("\(offer.transferId)\n".utf8), to: socketDescriptor)
        guard let archiveData = readLengthPrefixedData(from: socketDescriptor) else {
            return
        }

        do {
            let destinationURL = uniqueDownloadURL(for: offer.transferId)
            try archiveData.write(to: destinationURL, options: .atomic)
            DispatchQueue.main.async { [weak self] in
                self?.state.clearRemoteFileOffer(transferId: offer.transferId)
                self?.state.lastStatusMessage = "文件已接收到 \(destinationURL.lastPathComponent)"
            }
            logger.info("downloaded file archive byte_count=\(archiveData.count)")
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

    private func readLine(from socketDescriptor: Int32) -> String? {
        var bytes: [UInt8] = []
        var byte: UInt8 = 0
        while recv(socketDescriptor, &byte, 1, 0) == 1 {
            if byte == 0x0A {
                break
            }
            bytes.append(byte)
        }

        return String(data: Data(bytes), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendLengthAndData(_ data: Data, to socketDescriptor: Int32) {
        var length = UInt64(data.count).bigEndian
        let lengthData = Swift.withUnsafeBytes(of: &length) { Data($0) }
        sendData(lengthData, to: socketDescriptor)
        sendData(data, to: socketDescriptor)
    }

    private func sendData(_ data: Data, to socketDescriptor: Int32) {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            var sent = 0
            while sent < data.count {
                let result = Darwin.send(socketDescriptor, baseAddress.advanced(by: sent), data.count - sent, 0)
                guard result > 0 else {
                    return
                }
                sent += result
            }
        }
    }

    private func readLengthPrefixedData(from socketDescriptor: Int32) -> Data? {
        guard let lengthData = readExactByteCount(8, from: socketDescriptor) else {
            return nil
        }

        var encodedLength: UInt64 = 0
        _ = Swift.withUnsafeMutableBytes(of: &encodedLength) { rawBuffer in
            lengthData.copyBytes(to: rawBuffer)
        }
        let length = UInt64(bigEndian: encodedLength)
        guard length <= 512 * 1024 * 1024 else {
            return nil
        }

        return readExactByteCount(Int(length), from: socketDescriptor)
    }

    private func readExactByteCount(_ byteCount: Int, from socketDescriptor: Int32) -> Data? {
        var data = Data(count: byteCount)
        var received = 0
        let result = data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return -1
            }
            while received < byteCount {
                let count = recv(socketDescriptor, baseAddress.advanced(by: received), byteCount - received, 0)
                guard count > 0 else {
                    return -1
                }
                received += count
            }
            return received
        }

        return result == byteCount ? data : nil
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

        for trustedPeerId in state.trustedPeerIds {
            sendTrust(approvedDeviceId: trustedPeerId)
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

        var targets = ["255.255.255.255"]
        targets.append(contentsOf: peerHosts)

        for target in targets {
            _ = udpSocket.send(data, to: target, port: Int(port))
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
