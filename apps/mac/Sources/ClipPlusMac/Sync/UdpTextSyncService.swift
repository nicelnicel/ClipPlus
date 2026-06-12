import Darwin
import Foundation

final class RemoteFileTransferGate {
    private let lock = NSLock()
    private let maxCompletedCount = 128
    private var activeTransferIds = Set<String>()
    private var completedTransferIds = Set<String>()
    private var completedOrder: [String] = []

    func canAcceptOffer(_ transferId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isUsableTransferId(transferId)
            && !activeTransferIds.contains(transferId)
            && !completedTransferIds.contains(transferId)
    }

    @discardableResult
    func begin(_ transferId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isUsableTransferId(transferId),
              !activeTransferIds.contains(transferId),
              !completedTransferIds.contains(transferId) else {
            return false
        }

        activeTransferIds.insert(transferId)
        return true
    }

    func complete(_ transferId: String) {
        lock.lock()
        defer { lock.unlock() }
        activeTransferIds.remove(transferId)
        guard completedTransferIds.insert(transferId).inserted else {
            return
        }

        completedOrder.append(transferId)
        while completedOrder.count > maxCompletedCount {
            let removedTransferId = completedOrder.removeFirst()
            completedTransferIds.remove(removedTransferId)
        }
    }

    func fail(_ transferId: String) {
        lock.lock()
        defer { lock.unlock() }
        activeTransferIds.remove(transferId)
    }

    private func isUsableTransferId(_ transferId: String) -> Bool {
        !transferId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

final class UdpTextSyncService {
    private let port: UInt16 = 47_631
    private let archivePort: UInt16 = 47_632
    private static let imageOfferDownloadRetryDelay: DispatchTimeInterval = .milliseconds(250)
    private let state: SettingsState
    private let clipboard = NativeClipboard()
    private let logger: ClipPlusLogger
    private let remoteFileTransfers = RemoteFileTransferGate()
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
    private let fileSignatureLock = NSLock()
    private var lastLocalFileSignature: String?
    private var lastRemoteFileSignature: String?
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
            let signature = fileSignature(fileURLs.map(\.path))
            guard shouldPublishLocalFileSignature(signature) else {
                return
            }

            publishFileOffer(fileURLs: fileURLs, groupId: snapshot.sharedGroupId)
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

        guard let pngData = clipboard.readPngImageData() else {
            return
        }

        let imageHash = ImageContentHasher.sha256Hex(pngData)
        guard imageHash != lastLocalImageHash,
              imageHash != lastRemoteImageHash else {
            return
        }

        lastLocalImageHash = imageHash
        if let message = ClipPlusMessage.image(
            groupId: snapshot.sharedGroupId,
            senderDeviceId: deviceId,
            senderDeviceName: deviceName,
            pngData: pngData
        ) {
            send(message)
            updateStatus("已广播图片剪贴板")
            logger.info("published image clipboard byte_count=\(pngData.count)")
        } else if publishImageOffer(pngData: pngData, groupId: snapshot.sharedGroupId, imageHash: imageHash) {
            updateStatus("已广播图片剪贴板")
            logger.info("published image clipboard byte_count=\(pngData.count)")
        } else {
            lastLocalImageHash = nil
        }
    }

    private func localImageHashAfterClipboardWrite() -> String? {
        guard let writtenPngData = clipboard.readPngImageData() else {
            return nil
        }

        return ImageContentHasher.sha256Hex(writtenPngData)
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
        case .imageOffer:
            guard state.sharingEnabled,
                  let transferId = message.transferId,
                  message.transferFormat == .directTree,
                  let expectedByteSize = message.imageByteSize,
                  expectedByteSize > 0,
                  let expectedHash = message.imageContentHash,
                  let imagePort = message.archivePort,
                  imagePort > 0,
                  remoteFileTransfers.begin(transferId) else {
                return
            }

            fileQueue.async { [weak self] in
                self?.downloadRemoteImageOffer(
                    sourceHost: sourceHost,
                    transferId: transferId,
                    expectedByteSize: expectedByteSize,
                    expectedHash: expectedHash,
                    port: imagePort
                )
            }
            logger.info("received image offer byte_count=\(expectedByteSize) source_host=\(sourceHost) port=\(imagePort)")
        case .fileOffer:
            guard state.sharingEnabled,
                  let transferId = message.transferId,
                  message.transferFormat == .directTree,
                  let files = message.files,
                  !files.isEmpty,
                  remoteFileTransfers.canAcceptOffer(transferId) else {
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

    @discardableResult
    private func publishImageOffer(pngData: Data, groupId: String, imageHash: String) -> Bool {
        let transferId = UUID().uuidString
        guard let sourceURL = imageTransferSourceURL(for: transferId) else {
            updateStatus("图片广播失败")
            logger.error("image transfer registration failed stage=source")
            return false
        }

        let transferDirectoryURL = sourceURL.deletingLastPathComponent()
        do {
            if FileManager.default.fileExists(atPath: transferDirectoryURL.path) {
                try FileManager.default.removeItem(at: transferDirectoryURL)
            }
            try FileManager.default.createDirectory(at: transferDirectoryURL, withIntermediateDirectories: true)
            try pngData.write(to: sourceURL, options: .atomic)
        } catch {
            updateStatus("图片广播失败")
            logger.error("image transfer source write failed")
            return false
        }

        guard registerTemporaryImageTransferSource(transferId: transferId, sourceURL: sourceURL) else {
            try? FileManager.default.removeItem(at: transferDirectoryURL)
            updateStatus("图片广播失败")
            logger.error("image transfer registration failed stage=server")
            return false
        }

        let message = ClipPlusMessage.imageOffer(
            groupId: groupId,
            senderDeviceId: deviceId,
            senderDeviceName: deviceName,
            transferId: transferId,
            pngData: pngData,
            archivePort: Int(archivePort)
        )
        guard message.imageContentHash == imageHash else {
            try? FileManager.default.removeItem(at: transferDirectoryURL)
            updateStatus("图片广播失败")
            logger.error("image transfer registration failed stage=hash")
            return false
        }

        send(message)
        scheduleTemporaryImageTransferCleanup(transferDirectoryURL)
        logger.info("published image offer byte_count=\(pngData.count)")
        return true
    }

    private func registerTemporaryImageTransferSource(transferId: String, sourceURL: URL) -> Bool {
        guard let fileServer else {
            return false
        }

        return fileServer.registerTransfer(transferId: transferId, sourcePaths: [sourceURL.path])
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

            let result = fileServer.serveNextTree()
            guard running else {
                return
            }
            guard let result else {
                continue
            }

            logger.info("served file tree file_count=\(result.fileCount) byte_count=\(result.byteCount)")
        }
    }

    private func downloadRemoteFileOffer(transferId: String) {
        guard let offer = state.remoteFileOffer,
              offer.transferId == transferId else {
            return
        }
        guard remoteFileTransfers.begin(transferId) else {
            return
        }

        fileQueue.async { [weak self] in
            self?.downloadRemoteFileOffer(offer)
        }
    }

    private func downloadRemoteFileOffer(_ offer: RemoteFileOfferSummary) {
        guard let stagingURL = stagingDirectoryURL(for: offer.transferId) else {
            DispatchQueue.main.async { [weak self] in
                self?.state.lastStatusMessage = "文件接收失败"
            }
            remoteFileTransfers.fail(offer.transferId)
            logger.error("file tree staging failed: invalid transfer id")
            return
        }

        do {
            if FileManager.default.fileExists(atPath: stagingURL.path) {
                try FileManager.default.removeItem(at: stagingURL)
            }
            try FileManager.default.createDirectory(
                at: stagingURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.state.lastStatusMessage = "文件接收失败"
            }
            remoteFileTransfers.fail(offer.transferId)
            logger.error("file tree staging failed")
            return
        }

        guard let result = CoreBridge().downloadFileTree(
            host: offer.sourceHost,
            port: Int(archivePort),
            transferId: offer.transferId,
            destinationDirectory: stagingURL.path
        ) else {
            DispatchQueue.main.async { [weak self] in
                self?.state.lastStatusMessage = "文件接收失败"
            }
            remoteFileTransfers.fail(offer.transferId)
            logger.error("file tree download failed")
            return
        }

        let urls = result.topLevelPaths.map { URL(fileURLWithPath: $0) }
        let remoteSignature = fileSignature(urls.map(\.path))
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            recordRemoteFileSignature(remoteSignature)
            guard clipboard.writeFileURLs(urls) else {
                clearRemoteFileSignature(ifMatching: remoteSignature)
                remoteFileTransfers.fail(offer.transferId)
                state.lastStatusMessage = "文件接收失败"
                logger.error("file clipboard write failed")
                return
            }

            let pasteboardSignature = fileSignature(clipboard.readFileURLs().map(\.path))
            if !pasteboardSignature.isEmpty {
                recordRemoteFileSignature(pasteboardSignature)
            }

            state.clearRemoteFileOffer(transferId: offer.transferId)
            state.lastStatusMessage = "文件已放入剪贴板，可在目标文件夹粘贴"
            remoteFileTransfers.complete(offer.transferId)
        }

        logger.info("downloaded file tree file_count=\(result.fileCount) byte_count=\(result.byteCount)")
    }

    private func downloadRemoteImageOffer(
        sourceHost: String,
        transferId: String,
        expectedByteSize: Int,
        expectedHash: String,
        port: Int
    ) {
        guard let stagingURL = stagingDirectoryURL(for: transferId) else {
            DispatchQueue.main.async { [weak self] in
                self?.state.lastStatusMessage = "图片接收失败"
            }
            remoteFileTransfers.fail(transferId)
            logger.error("image transfer download failed stage=staging")
            return
        }

        do {
            if FileManager.default.fileExists(atPath: stagingURL.path) {
                try FileManager.default.removeItem(at: stagingURL)
            }
            try FileManager.default.createDirectory(
                at: stagingURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.state.lastStatusMessage = "图片接收失败"
            }
            remoteFileTransfers.fail(transferId)
            logger.error("image transfer download failed stage=prepare")
            return
        }

        guard let result = downloadFileTreeWithRetry(
            host: sourceHost,
            port: port,
            transferId: transferId,
            destinationDirectory: stagingURL.path
        ) else {
            DispatchQueue.main.async { [weak self] in
                self?.state.lastStatusMessage = "图片接收失败"
            }
            remoteFileTransfers.fail(transferId)
            logger.error("image transfer download failed stage=download source_host=\(sourceHost) port=\(port)")
            return
        }

        guard result.fileCount == 1,
              result.topLevelPaths.count == 1,
              result.byteCount == UInt64(expectedByteSize),
              let imagePath = result.topLevelPaths.first,
              let imageData = try? Data(contentsOf: URL(fileURLWithPath: imagePath)),
              imageData.count == expectedByteSize,
              ImageContentHasher.sha256Hex(imageData) == expectedHash else {
            DispatchQueue.main.async { [weak self] in
                self?.state.lastStatusMessage = "图片接收失败"
            }
            remoteFileTransfers.fail(transferId)
            logger.error("image transfer download failed stage=verify")
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            lastRemoteImageHash = expectedHash
            lastLocalImageHash = expectedHash
            clipboard.writePngImageData(imageData)
            if let writtenImageHash = localImageHashAfterClipboardWrite() {
                lastLocalImageHash = writtenImageHash
            }
            state.lastStatusMessage = "已接收远端图片剪贴板"
            remoteFileTransfers.complete(transferId)
        }

        logger.info("downloaded image clipboard byte_count=\(imageData.count)")
    }

    private func downloadFileTreeWithRetry(
        host: String,
        port: Int,
        transferId: String,
        destinationDirectory: String
    ) -> FileTreeDownloadResult? {
        let bridge = CoreBridge()
        if let result = bridge.downloadFileTree(
            host: host,
            port: port,
            transferId: transferId,
            destinationDirectory: destinationDirectory
        ) {
            return result
        }

        sleep(for: Self.imageOfferDownloadRetryDelay)
        return bridge.downloadFileTree(
            host: host,
            port: port,
            transferId: transferId,
            destinationDirectory: destinationDirectory
        )
    }

    private func sleep(for delay: DispatchTimeInterval) {
        switch delay {
        case .seconds(let value):
            Thread.sleep(forTimeInterval: TimeInterval(value))
        case .milliseconds(let value):
            Thread.sleep(forTimeInterval: TimeInterval(value) / 1_000)
        case .microseconds(let value):
            Thread.sleep(forTimeInterval: TimeInterval(value) / 1_000_000)
        case .nanoseconds(let value):
            Thread.sleep(forTimeInterval: TimeInterval(value) / 1_000_000_000)
        case .never:
            return
        @unknown default:
            return
        }
    }

    private func stagingDirectoryURL(for transferId: String) -> URL? {
        guard transferId.range(
            of: #"^[A-Za-z0-9-]{1,128}$"#,
            options: .regularExpression
        ) == transferId.startIndex..<transferId.endIndex else {
            return nil
        }

        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupportURL
            .appendingPathComponent("ClipPlus", isDirectory: true)
            .appendingPathComponent("Staging", isDirectory: true)
            .appendingPathComponent(transferId, isDirectory: true)
    }

    private func imageTransferSourceURL(for transferId: String) -> URL? {
        guard transferId.range(
            of: #"^[A-Za-z0-9-]{1,128}$"#,
            options: .regularExpression
        ) == transferId.startIndex..<transferId.endIndex else {
            return nil
        }

        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupportURL
            .appendingPathComponent("ClipPlus", isDirectory: true)
            .appendingPathComponent("ImageTransfer", isDirectory: true)
            .appendingPathComponent(transferId, isDirectory: true)
            .appendingPathComponent("clipboard.png", isDirectory: false)
    }

    private func scheduleTemporaryImageTransferCleanup(_ directoryURL: URL) {
        fileQueue.asyncAfter(deadline: .now() + 600) {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    private func fileSignature(_ paths: [String]) -> String {
        let fileSignatureComponents = paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .sorted()
            .map { "\($0.utf8.count):\($0)" }

        return fileSignatureComponents.joined()
    }

    private func shouldPublishLocalFileSignature(_ signature: String) -> Bool {
        guard !signature.isEmpty else {
            return false
        }

        fileSignatureLock.lock()
        defer { fileSignatureLock.unlock() }

        guard signature != lastLocalFileSignature,
              signature != lastRemoteFileSignature else {
            return false
        }

        lastLocalFileSignature = signature
        return true
    }

    private func recordRemoteFileSignature(_ signature: String) {
        guard !signature.isEmpty else {
            return
        }

        fileSignatureLock.lock()
        defer { fileSignatureLock.unlock() }
        lastRemoteFileSignature = signature
        lastLocalFileSignature = signature
    }

    private func clearRemoteFileSignature(ifMatching signature: String) {
        fileSignatureLock.lock()
        defer { fileSignatureLock.unlock() }

        if lastRemoteFileSignature == signature {
            lastRemoteFileSignature = nil
        }
        if lastLocalFileSignature == signature {
            lastLocalFileSignature = nil
        }
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
