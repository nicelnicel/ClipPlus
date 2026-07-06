import Darwin
import Foundation

struct FileTreeDownloadResult: Decodable, Equatable {
    let fileCount: Int
    let byteCount: UInt64
    let topLevelPaths: [String]
}

struct CoreBridge {
    func statusJSON() -> String {
        #"{"core_version":"0.1.21"}"#
    }

    func deriveGroupId(for rawKey: String) -> String? {
        Self.ffiBridge?.deriveGroupId(for: rawKey)
    }

    func createHelloMessageJSON(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String
    ) -> String? {
        Self.ffiBridge?.createHelloMessageJSON(
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName
        )
    }

    func createTextMessageJSON(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        text: String
    ) -> String? {
        Self.ffiBridge?.createTextMessageJSON(
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName,
            text: text
        )
    }

    func createImageMessageJSON(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        pngData: Data
    ) -> String? {
        Self.ffiBridge?.createImageMessageJSON(
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName,
            pngData: pngData
        )
    }

    func createImageOfferMessageJSON(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        transferId: String,
        pngData: Data,
        archivePort: Int
    ) -> String? {
        Self.ffiBridge?.createImageOfferMessageJSON(
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName,
            transferId: transferId,
            pngData: pngData,
            archivePort: archivePort
        )
    }

    func createFileOfferMessageJSON(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        transferId: String,
        files: [FileTransferItem],
        archivePort: Int
    ) -> String? {
        Self.ffiBridge?.createFileOfferMessageJSON(
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName,
            transferId: transferId,
            files: files,
            archivePort: archivePort
        )
    }

    func writeFileArchiveZip(sourcePaths: [String], archivePath: String) -> Bool {
        Self.ffiBridge?.writeFileArchiveZip(sourcePaths: sourcePaths, archivePath: archivePath) ?? false
    }

    func serveFileArchive(socketDescriptor: Int32, sourcePaths: [String], archivePath: String) -> UInt64 {
        Self.ffiBridge?.serveFileArchive(
            socketDescriptor: socketDescriptor,
            sourcePaths: sourcePaths,
            archivePath: archivePath
        ) ?? 0
    }

    func downloadArchiveFile(host: String, port: Int, transferId: String, destinationPath: String) -> Bool {
        Self.ffiBridge?.downloadArchiveFile(
            host: host,
            port: port,
            transferId: transferId,
            destinationPath: destinationPath
        ) ?? false
    }

    func downloadFileTree(
        host: String,
        port: Int,
        transferId: String,
        destinationDirectory: String
    ) -> FileTreeDownloadResult? {
        Self.ffiBridge?.downloadFileTree(
            host: host,
            port: port,
            transferId: transferId,
            destinationDirectory: destinationDirectory
        )
    }

    func openUdpSocket(bindPort: Int) -> RustUdpSocket? {
        Self.ffiBridge?.openUdpSocket(bindPort: bindPort)
    }

    func openFileServer(bindPort: Int) -> RustFileServer? {
        Self.ffiBridge?.openFileServer(bindPort: bindPort)
    }

    func createTrustMessageJSON(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        approvedDeviceId: String
    ) -> String? {
        Self.ffiBridge?.createTrustMessageJSON(
            groupId: groupId,
            senderDeviceId: senderDeviceId,
            senderDeviceName: senderDeviceName,
            approvedDeviceId: approvedDeviceId
        )
    }

    private static let ffiBridge = ClipPlusFFIBridge.load()
}

struct RustUdpDatagram: Equatable {
    let payload: Data
    let sourceHost: String
    let sourcePort: Int
}

final class RustUdpSocket {
    private let bridge: ClipPlusFFIBridge
    private let lock = NSLock()
    private var handle: UnsafeMutableRawPointer?
    private var inFlightReceive = false

    fileprivate init(bridge: ClipPlusFFIBridge, handle: UnsafeMutableRawPointer) {
        self.bridge = bridge
        self.handle = handle
    }

    var localPort: Int {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else {
            return 0
        }

        return bridge.udpSocketLocalPort(handle)
    }

    func send(_ payload: Data, to host: String, port: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else {
            return false
        }

        return bridge.udpSocketSendTo(handle, payload: payload, host: host, port: port)
    }

    func receive() -> RustUdpDatagram? {
        lock.lock()
        guard let handle else {
            lock.unlock()
            return nil
        }
        inFlightReceive = true
        lock.unlock()

        let result = bridge.udpSocketReceive(handle)

        lock.lock()
        inFlightReceive = false
        lock.unlock()

        return result
    }

    func close() {
        lock.lock()
        let handleToClose = handle
        handle = nil
        while inFlightReceive {
            lock.unlock()
            Thread.sleep(forTimeInterval: 0.002)
            lock.lock()
        }
        lock.unlock()

        if let handleToClose {
            bridge.udpSocketFree(handleToClose)
        }
    }

    deinit {
        close()
    }
}

final class RustFileServer {
    private let bridge: ClipPlusFFIBridge
    private let condition = NSCondition()
    private var handle: UnsafeMutableRawPointer?
    private var closing = false
    private var activeOperations = 0

    fileprivate init(bridge: ClipPlusFFIBridge, handle: UnsafeMutableRawPointer) {
        self.bridge = bridge
        self.handle = handle
    }

    var localPort: Int {
        guard let handle = beginOperation() else {
            return 0
        }
        defer { endOperation() }

        return bridge.fileServerLocalPort(handle)
    }

    func registerTransfer(transferId: String, sourcePaths: [String]) -> Bool {
        guard let handle = beginOperation() else {
            return false
        }
        defer { endOperation() }

        return bridge.fileServerRegisterTransfer(handle, transferId: transferId, sourcePaths: sourcePaths)
    }

    func serveNextArchive(tempDirectory: String) -> UInt64 {
        guard let handle = beginOperation() else {
            return 0
        }
        defer { endOperation() }

        return bridge.fileServerServeNext(handle, tempDirectory: tempDirectory)
    }

    func serveNextTree() -> FileTreeDownloadResult? {
        guard let handle = beginOperation() else {
            return nil
        }
        defer { endOperation() }

        return bridge.fileServerServeNextTree(handle)
    }

    func close() {
        condition.lock()
        closing = true
        while activeOperations > 0 {
            condition.wait()
        }
        let handleToClose = handle
        handle = nil
        condition.unlock()

        if let handleToClose {
            bridge.fileServerFree(handleToClose)
        }
    }

    deinit {
        close()
    }

    private func beginOperation() -> UnsafeMutableRawPointer? {
        condition.lock()
        defer { condition.unlock() }
        guard !closing, let handle else {
            return nil
        }

        activeOperations += 1
        return handle
    }

    private func endOperation() {
        condition.lock()
        activeOperations -= 1
        if activeOperations == 0 {
            condition.broadcast()
        }
        condition.unlock()
    }
}

private final class ClipPlusFFIBridge {
    private typealias DeriveGroupIdFunction = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    private typealias CreateHelloMessageJSONFunction = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?
    private typealias CreateTextMessageJSONFunction = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?
    private typealias CreateImageMessageJSONFunction = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafeRawPointer?,
        Int
    ) -> UnsafeMutablePointer<CChar>?
    private typealias CreateImageOfferMessageJSONFunction = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafeRawPointer?,
        Int,
        UInt16
    ) -> UnsafeMutablePointer<CChar>?
    private typealias CreateFileOfferMessageJSONFunction = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UInt16
    ) -> UnsafeMutablePointer<CChar>?
    private typealias WriteFileArchiveZipFunction = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> Bool
    private typealias ServeFileArchiveToSocketFunction = @convention(c) (
        UInt,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> UInt64
    private typealias DownloadFileArchiveFunction = @convention(c) (
        UnsafePointer<CChar>?,
        UInt16,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> Bool
    private typealias DownloadFileTreeFunction = @convention(c) (
        UnsafePointer<CChar>?,
        UInt16,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?
    private typealias UdpSocketBindFunction = @convention(c) (UInt16) -> UnsafeMutableRawPointer?
    private typealias UdpSocketFreeFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias UdpSocketLocalPortFunction = @convention(c) (UnsafeMutableRawPointer?) -> UInt16
    private typealias UdpSocketSendToFunction = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeRawPointer?,
        Int,
        UnsafePointer<CChar>?,
        UInt16
    ) -> Bool
    private typealias UdpSocketRecvFunction = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutableRawPointer?,
        Int,
        UnsafeMutablePointer<CChar>?,
        Int,
        UnsafeMutablePointer<UInt16>?
    ) -> Int
    private typealias FileServerBindFunction = @convention(c) (UInt16) -> UnsafeMutableRawPointer?
    private typealias FileServerFreeFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias FileServerLocalPortFunction = @convention(c) (UnsafeMutableRawPointer?) -> UInt16
    private typealias FileServerRegisterTransferFunction = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> Bool
    private typealias FileServerServeNextFunction = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?
    ) -> UInt64
    private typealias FileServerServeNextTreeFunction = @convention(c) (
        UnsafeMutableRawPointer?
    ) -> UnsafeMutablePointer<CChar>?
    private typealias FreeStringFunction = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    private let handle: UnsafeMutableRawPointer
    private let deriveGroupIdFunction: DeriveGroupIdFunction
    private let createHelloMessageJSONFunction: CreateHelloMessageJSONFunction
    private let createTextMessageJSONFunction: CreateTextMessageJSONFunction
    private let createImageMessageJSONFunction: CreateImageMessageJSONFunction
    private let createImageOfferMessageJSONFunction: CreateImageOfferMessageJSONFunction
    private let createFileOfferMessageJSONFunction: CreateFileOfferMessageJSONFunction
    private let writeFileArchiveZipFunction: WriteFileArchiveZipFunction
    private let serveFileArchiveToSocketFunction: ServeFileArchiveToSocketFunction
    private let downloadFileArchiveFunction: DownloadFileArchiveFunction
    private let downloadFileTreeFunction: DownloadFileTreeFunction
    private let udpSocketBindFunction: UdpSocketBindFunction
    private let udpSocketFreeFunction: UdpSocketFreeFunction
    private let udpSocketLocalPortFunction: UdpSocketLocalPortFunction
    private let udpSocketSendToFunction: UdpSocketSendToFunction
    private let udpSocketRecvFunction: UdpSocketRecvFunction
    private let fileServerBindFunction: FileServerBindFunction
    private let fileServerFreeFunction: FileServerFreeFunction
    private let fileServerLocalPortFunction: FileServerLocalPortFunction
    private let fileServerRegisterTransferFunction: FileServerRegisterTransferFunction
    private let fileServerServeNextFunction: FileServerServeNextFunction
    private let fileServerServeNextTreeFunction: FileServerServeNextTreeFunction
    private let createTrustMessageJSONFunction: CreateTextMessageJSONFunction
    private let freeStringFunction: FreeStringFunction

    private init(
        handle: UnsafeMutableRawPointer,
        deriveGroupIdFunction: @escaping DeriveGroupIdFunction,
        createHelloMessageJSONFunction: @escaping CreateHelloMessageJSONFunction,
        createTextMessageJSONFunction: @escaping CreateTextMessageJSONFunction,
        createImageMessageJSONFunction: @escaping CreateImageMessageJSONFunction,
        createImageOfferMessageJSONFunction: @escaping CreateImageOfferMessageJSONFunction,
        createFileOfferMessageJSONFunction: @escaping CreateFileOfferMessageJSONFunction,
        writeFileArchiveZipFunction: @escaping WriteFileArchiveZipFunction,
        serveFileArchiveToSocketFunction: @escaping ServeFileArchiveToSocketFunction,
        downloadFileArchiveFunction: @escaping DownloadFileArchiveFunction,
        downloadFileTreeFunction: @escaping DownloadFileTreeFunction,
        udpSocketBindFunction: @escaping UdpSocketBindFunction,
        udpSocketFreeFunction: @escaping UdpSocketFreeFunction,
        udpSocketLocalPortFunction: @escaping UdpSocketLocalPortFunction,
        udpSocketSendToFunction: @escaping UdpSocketSendToFunction,
        udpSocketRecvFunction: @escaping UdpSocketRecvFunction,
        fileServerBindFunction: @escaping FileServerBindFunction,
        fileServerFreeFunction: @escaping FileServerFreeFunction,
        fileServerLocalPortFunction: @escaping FileServerLocalPortFunction,
        fileServerRegisterTransferFunction: @escaping FileServerRegisterTransferFunction,
        fileServerServeNextFunction: @escaping FileServerServeNextFunction,
        fileServerServeNextTreeFunction: @escaping FileServerServeNextTreeFunction,
        createTrustMessageJSONFunction: @escaping CreateTextMessageJSONFunction,
        freeStringFunction: @escaping FreeStringFunction
    ) {
        self.handle = handle
        self.deriveGroupIdFunction = deriveGroupIdFunction
        self.createHelloMessageJSONFunction = createHelloMessageJSONFunction
        self.createTextMessageJSONFunction = createTextMessageJSONFunction
        self.createImageMessageJSONFunction = createImageMessageJSONFunction
        self.createImageOfferMessageJSONFunction = createImageOfferMessageJSONFunction
        self.createFileOfferMessageJSONFunction = createFileOfferMessageJSONFunction
        self.writeFileArchiveZipFunction = writeFileArchiveZipFunction
        self.serveFileArchiveToSocketFunction = serveFileArchiveToSocketFunction
        self.downloadFileArchiveFunction = downloadFileArchiveFunction
        self.downloadFileTreeFunction = downloadFileTreeFunction
        self.udpSocketBindFunction = udpSocketBindFunction
        self.udpSocketFreeFunction = udpSocketFreeFunction
        self.udpSocketLocalPortFunction = udpSocketLocalPortFunction
        self.udpSocketSendToFunction = udpSocketSendToFunction
        self.udpSocketRecvFunction = udpSocketRecvFunction
        self.fileServerBindFunction = fileServerBindFunction
        self.fileServerFreeFunction = fileServerFreeFunction
        self.fileServerLocalPortFunction = fileServerLocalPortFunction
        self.fileServerRegisterTransferFunction = fileServerRegisterTransferFunction
        self.fileServerServeNextFunction = fileServerServeNextFunction
        self.fileServerServeNextTreeFunction = fileServerServeNextTreeFunction
        self.createTrustMessageJSONFunction = createTrustMessageJSONFunction
        self.freeStringFunction = freeStringFunction
    }

    deinit {
        dlclose(handle)
    }

    static func load() -> ClipPlusFFIBridge? {
        for candidatePath in libraryCandidatePaths() {
            guard FileManager.default.fileExists(atPath: candidatePath),
                  let handle = dlopen(candidatePath, RTLD_NOW | RTLD_LOCAL) else {
                continue
            }

            guard let deriveSymbol = dlsym(handle, "clipplus_derive_group_id"),
                  let createHelloMessageJSONSymbol = dlsym(handle, "clipplus_create_hello_message_json"),
                  let createTextMessageJSONSymbol = dlsym(handle, "clipplus_create_text_message_json"),
                  let createImageMessageJSONSymbol = dlsym(handle, "clipplus_create_image_message_json"),
                  let createImageOfferMessageJSONSymbol = dlsym(handle, "clipplus_create_image_offer_message_json"),
                  let createFileOfferMessageJSONSymbol = dlsym(handle, "clipplus_create_file_offer_message_json"),
                  let writeFileArchiveZipSymbol = dlsym(handle, "clipplus_write_file_archive_zip"),
                  let serveFileArchiveToSocketSymbol = dlsym(handle, "clipplus_serve_file_archive_to_socket"),
                  let downloadFileArchiveSymbol = dlsym(handle, "clipplus_download_file_archive"),
                  let downloadFileTreeSymbol = dlsym(handle, "clipplus_download_file_tree"),
                  let udpSocketBindSymbol = dlsym(handle, "clipplus_udp_socket_bind"),
                  let udpSocketFreeSymbol = dlsym(handle, "clipplus_udp_socket_free"),
                  let udpSocketLocalPortSymbol = dlsym(handle, "clipplus_udp_socket_local_port"),
                  let udpSocketSendToSymbol = dlsym(handle, "clipplus_udp_socket_send_to"),
                  let udpSocketRecvSymbol = dlsym(handle, "clipplus_udp_socket_recv"),
                  let fileServerBindSymbol = dlsym(handle, "clipplus_file_server_bind"),
                  let fileServerFreeSymbol = dlsym(handle, "clipplus_file_server_free"),
                  let fileServerLocalPortSymbol = dlsym(handle, "clipplus_file_server_local_port"),
                  let fileServerRegisterTransferSymbol = dlsym(handle, "clipplus_file_server_register_transfer"),
                  let fileServerServeNextSymbol = dlsym(handle, "clipplus_file_server_serve_next"),
                  let fileServerServeNextTreeSymbol = dlsym(handle, "clipplus_file_server_serve_next_tree"),
                  let createTrustMessageJSONSymbol = dlsym(handle, "clipplus_create_trust_message_json"),
                  let freeSymbol = dlsym(handle, "clipplus_free_string") else {
                dlclose(handle)
                continue
            }

            let deriveGroupIdFunction = unsafeBitCast(deriveSymbol, to: DeriveGroupIdFunction.self)
            let createHelloMessageJSONFunction = unsafeBitCast(
                createHelloMessageJSONSymbol,
                to: CreateHelloMessageJSONFunction.self
            )
            let createTextMessageJSONFunction = unsafeBitCast(
                createTextMessageJSONSymbol,
                to: CreateTextMessageJSONFunction.self
            )
            let createImageMessageJSONFunction = unsafeBitCast(
                createImageMessageJSONSymbol,
                to: CreateImageMessageJSONFunction.self
            )
            let createImageOfferMessageJSONFunction = unsafeBitCast(
                createImageOfferMessageJSONSymbol,
                to: CreateImageOfferMessageJSONFunction.self
            )
            let createFileOfferMessageJSONFunction = unsafeBitCast(
                createFileOfferMessageJSONSymbol,
                to: CreateFileOfferMessageJSONFunction.self
            )
            let writeFileArchiveZipFunction = unsafeBitCast(
                writeFileArchiveZipSymbol,
                to: WriteFileArchiveZipFunction.self
            )
            let serveFileArchiveToSocketFunction = unsafeBitCast(
                serveFileArchiveToSocketSymbol,
                to: ServeFileArchiveToSocketFunction.self
            )
            let downloadFileArchiveFunction = unsafeBitCast(
                downloadFileArchiveSymbol,
                to: DownloadFileArchiveFunction.self
            )
            let downloadFileTreeFunction = unsafeBitCast(
                downloadFileTreeSymbol,
                to: DownloadFileTreeFunction.self
            )
            let udpSocketBindFunction = unsafeBitCast(udpSocketBindSymbol, to: UdpSocketBindFunction.self)
            let udpSocketFreeFunction = unsafeBitCast(udpSocketFreeSymbol, to: UdpSocketFreeFunction.self)
            let udpSocketLocalPortFunction = unsafeBitCast(
                udpSocketLocalPortSymbol,
                to: UdpSocketLocalPortFunction.self
            )
            let udpSocketSendToFunction = unsafeBitCast(
                udpSocketSendToSymbol,
                to: UdpSocketSendToFunction.self
            )
            let udpSocketRecvFunction = unsafeBitCast(
                udpSocketRecvSymbol,
                to: UdpSocketRecvFunction.self
            )
            let fileServerBindFunction = unsafeBitCast(fileServerBindSymbol, to: FileServerBindFunction.self)
            let fileServerFreeFunction = unsafeBitCast(fileServerFreeSymbol, to: FileServerFreeFunction.self)
            let fileServerLocalPortFunction = unsafeBitCast(
                fileServerLocalPortSymbol,
                to: FileServerLocalPortFunction.self
            )
            let fileServerRegisterTransferFunction = unsafeBitCast(
                fileServerRegisterTransferSymbol,
                to: FileServerRegisterTransferFunction.self
            )
            let fileServerServeNextFunction = unsafeBitCast(
                fileServerServeNextSymbol,
                to: FileServerServeNextFunction.self
            )
            let fileServerServeNextTreeFunction = unsafeBitCast(
                fileServerServeNextTreeSymbol,
                to: FileServerServeNextTreeFunction.self
            )
            let createTrustMessageJSONFunction = unsafeBitCast(
                createTrustMessageJSONSymbol,
                to: CreateTextMessageJSONFunction.self
            )
            let freeStringFunction = unsafeBitCast(freeSymbol, to: FreeStringFunction.self)
            return ClipPlusFFIBridge(
                handle: handle,
                deriveGroupIdFunction: deriveGroupIdFunction,
                createHelloMessageJSONFunction: createHelloMessageJSONFunction,
                createTextMessageJSONFunction: createTextMessageJSONFunction,
                createImageMessageJSONFunction: createImageMessageJSONFunction,
                createImageOfferMessageJSONFunction: createImageOfferMessageJSONFunction,
                createFileOfferMessageJSONFunction: createFileOfferMessageJSONFunction,
                writeFileArchiveZipFunction: writeFileArchiveZipFunction,
                serveFileArchiveToSocketFunction: serveFileArchiveToSocketFunction,
                downloadFileArchiveFunction: downloadFileArchiveFunction,
                downloadFileTreeFunction: downloadFileTreeFunction,
                udpSocketBindFunction: udpSocketBindFunction,
                udpSocketFreeFunction: udpSocketFreeFunction,
                udpSocketLocalPortFunction: udpSocketLocalPortFunction,
                udpSocketSendToFunction: udpSocketSendToFunction,
                udpSocketRecvFunction: udpSocketRecvFunction,
                fileServerBindFunction: fileServerBindFunction,
                fileServerFreeFunction: fileServerFreeFunction,
                fileServerLocalPortFunction: fileServerLocalPortFunction,
                fileServerRegisterTransferFunction: fileServerRegisterTransferFunction,
                fileServerServeNextFunction: fileServerServeNextFunction,
                fileServerServeNextTreeFunction: fileServerServeNextTreeFunction,
                createTrustMessageJSONFunction: createTrustMessageJSONFunction,
                freeStringFunction: freeStringFunction
            )
        }

        return nil
    }

    func deriveGroupId(for rawKey: String) -> String? {
        let resultPointer = rawKey.withCString { rawKeyPointer in
            deriveGroupIdFunction(rawKeyPointer)
        }

        guard let resultPointer else {
            return nil
        }
        defer { freeStringFunction(resultPointer) }

        return String(cString: resultPointer)
    }

    func createHelloMessageJSON(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String
    ) -> String? {
        let resultPointer = groupId.withCString { groupIdPointer in
            senderDeviceId.withCString { senderDeviceIdPointer in
                senderDeviceName.withCString { senderDeviceNamePointer in
                    createHelloMessageJSONFunction(
                        groupIdPointer,
                        senderDeviceIdPointer,
                        senderDeviceNamePointer
                    )
                }
            }
        }

        guard let resultPointer else {
            return nil
        }
        defer { freeStringFunction(resultPointer) }

        return String(cString: resultPointer)
    }

    func createTextMessageJSON(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        text: String
    ) -> String? {
        let resultPointer = groupId.withCString { groupIdPointer in
            senderDeviceId.withCString { senderDeviceIdPointer in
                senderDeviceName.withCString { senderDeviceNamePointer in
                    text.withCString { textPointer in
                        createTextMessageJSONFunction(
                            groupIdPointer,
                            senderDeviceIdPointer,
                            senderDeviceNamePointer,
                            textPointer
                        )
                    }
                }
            }
        }

        guard let resultPointer else {
            return nil
        }
        defer { freeStringFunction(resultPointer) }

        return String(cString: resultPointer)
    }

    func createImageMessageJSON(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        pngData: Data
    ) -> String? {
        guard !pngData.isEmpty else {
            return nil
        }

        let resultPointer = groupId.withCString { groupIdPointer in
            senderDeviceId.withCString { senderDeviceIdPointer in
                senderDeviceName.withCString { senderDeviceNamePointer in
                    pngData.withUnsafeBytes { rawBuffer in
                        createImageMessageJSONFunction(
                            groupIdPointer,
                            senderDeviceIdPointer,
                            senderDeviceNamePointer,
                            rawBuffer.baseAddress,
                            pngData.count
                        )
                    }
                }
            }
        }

        guard let resultPointer else {
            return nil
        }
        defer { freeStringFunction(resultPointer) }

        return String(cString: resultPointer)
    }

    func createImageOfferMessageJSON(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        transferId: String,
        pngData: Data,
        archivePort: Int
    ) -> String? {
        guard !pngData.isEmpty,
              archivePort > 0,
              archivePort <= Int(UInt16.max) else {
            return nil
        }

        let resultPointer = groupId.withCString { groupIdPointer in
            senderDeviceId.withCString { senderDeviceIdPointer in
                senderDeviceName.withCString { senderDeviceNamePointer in
                    transferId.withCString { transferIdPointer in
                        pngData.withUnsafeBytes { rawBuffer in
                            createImageOfferMessageJSONFunction(
                                groupIdPointer,
                                senderDeviceIdPointer,
                                senderDeviceNamePointer,
                                transferIdPointer,
                                rawBuffer.baseAddress,
                                pngData.count,
                                UInt16(archivePort)
                            )
                        }
                    }
                }
            }
        }

        guard let resultPointer else {
            return nil
        }
        defer { freeStringFunction(resultPointer) }

        return String(cString: resultPointer)
    }

    func createFileOfferMessageJSON(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        transferId: String,
        files: [FileTransferItem],
        archivePort: Int
    ) -> String? {
        guard archivePort > 0,
              archivePort <= Int(UInt16.max),
              let filesData = try? JSONEncoder().encode(files),
              let filesJSON = String(data: filesData, encoding: .utf8) else {
            return nil
        }

        let resultPointer = groupId.withCString { groupIdPointer in
            senderDeviceId.withCString { senderDeviceIdPointer in
                senderDeviceName.withCString { senderDeviceNamePointer in
                    transferId.withCString { transferIdPointer in
                        filesJSON.withCString { filesJSONPointer in
                            createFileOfferMessageJSONFunction(
                                groupIdPointer,
                                senderDeviceIdPointer,
                                senderDeviceNamePointer,
                                transferIdPointer,
                                filesJSONPointer,
                                UInt16(archivePort)
                            )
                        }
                    }
                }
            }
        }

        guard let resultPointer else {
            return nil
        }
        defer { freeStringFunction(resultPointer) }

        return String(cString: resultPointer)
    }

    func writeFileArchiveZip(sourcePaths: [String], archivePath: String) -> Bool {
        guard let sourcePathsData = try? JSONEncoder().encode(sourcePaths),
              let sourcePathsJSON = String(data: sourcePathsData, encoding: .utf8) else {
            return false
        }

        return sourcePathsJSON.withCString { sourcePathsPointer in
            archivePath.withCString { archivePathPointer in
                writeFileArchiveZipFunction(sourcePathsPointer, archivePathPointer)
            }
        }
    }

    func serveFileArchive(
        socketDescriptor: Int32,
        sourcePaths: [String],
        archivePath: String
    ) -> UInt64 {
        guard socketDescriptor > 0,
              let sourcePathsData = try? JSONEncoder().encode(sourcePaths),
              let sourcePathsJSON = String(data: sourcePathsData, encoding: .utf8) else {
            return 0
        }

        return sourcePathsJSON.withCString { sourcePathsPointer in
            archivePath.withCString { archivePathPointer in
                serveFileArchiveToSocketFunction(
                    UInt(socketDescriptor),
                    sourcePathsPointer,
                    archivePathPointer
                )
            }
        }
    }

    func downloadArchiveFile(
        host: String,
        port: Int,
        transferId: String,
        destinationPath: String
    ) -> Bool {
        guard port > 0,
              port <= Int(UInt16.max) else {
            return false
        }

        return host.withCString { hostPointer in
            transferId.withCString { transferIdPointer in
                destinationPath.withCString { destinationPathPointer in
                    downloadFileArchiveFunction(
                        hostPointer,
                        UInt16(port),
                        transferIdPointer,
                        destinationPathPointer
                    )
                }
            }
        }
    }

    func downloadFileTree(
        host: String,
        port: Int,
        transferId: String,
        destinationDirectory: String
    ) -> FileTreeDownloadResult? {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              port > 0,
              port <= Int(UInt16.max),
              !transferId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !destinationDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let resultPointer = host.withCString { hostPointer in
            transferId.withCString { transferIdPointer in
                destinationDirectory.withCString { destinationDirectoryPointer in
                    downloadFileTreeFunction(
                        hostPointer,
                        UInt16(port),
                        transferIdPointer,
                        destinationDirectoryPointer
                    )
                }
            }
        }

        return decodeFileTreeResult(resultPointer)
    }

    func openUdpSocket(bindPort: Int) -> RustUdpSocket? {
        guard bindPort >= 0,
              bindPort <= Int(UInt16.max),
              let handle = udpSocketBindFunction(UInt16(bindPort)) else {
            return nil
        }

        return RustUdpSocket(bridge: self, handle: handle)
    }

    fileprivate func udpSocketLocalPort(_ handle: UnsafeMutableRawPointer) -> Int {
        Int(udpSocketLocalPortFunction(handle))
    }

    fileprivate func udpSocketSendTo(
        _ handle: UnsafeMutableRawPointer,
        payload: Data,
        host: String,
        port: Int
    ) -> Bool {
        guard !payload.isEmpty,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              port > 0,
              port <= Int(UInt16.max) else {
            return false
        }

        return payload.withUnsafeBytes { rawBuffer in
            host.withCString { hostPointer in
                udpSocketSendToFunction(
                    handle,
                    rawBuffer.baseAddress,
                    payload.count,
                    hostPointer,
                    UInt16(port)
                )
            }
        }
    }

    fileprivate func udpSocketReceive(_ handle: UnsafeMutableRawPointer) -> RustUdpDatagram? {
        var payload = [UInt8](repeating: 0, count: 65_535)
        var sourceHost = [CChar](repeating: 0, count: 64)
        var sourcePort: UInt16 = 0
        let payloadCapacity = payload.count
        let sourceHostCapacity = sourceHost.count
        let byteCount = payload.withUnsafeMutableBytes { payloadBuffer in
            sourceHost.withUnsafeMutableBufferPointer { sourceHostBuffer in
                udpSocketRecvFunction(
                    handle,
                    payloadBuffer.baseAddress,
                    payloadCapacity,
                    sourceHostBuffer.baseAddress,
                    sourceHostCapacity,
                    &sourcePort
                )
            }
        }
        guard byteCount > 0,
              byteCount <= payload.count else {
            return nil
        }

        return RustUdpDatagram(
            payload: Data(payload.prefix(byteCount)),
            sourceHost: String(cString: sourceHost),
            sourcePort: Int(sourcePort)
        )
    }

    fileprivate func udpSocketFree(_ handle: UnsafeMutableRawPointer) {
        udpSocketFreeFunction(handle)
    }

    func openFileServer(bindPort: Int) -> RustFileServer? {
        guard bindPort >= 0,
              bindPort <= Int(UInt16.max),
              let handle = fileServerBindFunction(UInt16(bindPort)) else {
            return nil
        }

        return RustFileServer(bridge: self, handle: handle)
    }

    fileprivate func fileServerLocalPort(_ handle: UnsafeMutableRawPointer) -> Int {
        Int(fileServerLocalPortFunction(handle))
    }

    fileprivate func fileServerRegisterTransfer(
        _ handle: UnsafeMutableRawPointer,
        transferId: String,
        sourcePaths: [String]
    ) -> Bool {
        guard !transferId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let sourcePathsData = try? JSONEncoder().encode(sourcePaths),
              let sourcePathsJSON = String(data: sourcePathsData, encoding: .utf8) else {
            return false
        }

        return transferId.withCString { transferIdPointer in
            sourcePathsJSON.withCString { sourcePathsPointer in
                fileServerRegisterTransferFunction(handle, transferIdPointer, sourcePathsPointer)
            }
        }
    }

    fileprivate func fileServerServeNext(_ handle: UnsafeMutableRawPointer, tempDirectory: String) -> UInt64 {
        guard !tempDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return 0
        }

        return tempDirectory.withCString { tempDirectoryPointer in
            fileServerServeNextFunction(handle, tempDirectoryPointer)
        }
    }

    fileprivate func fileServerServeNextTree(_ handle: UnsafeMutableRawPointer) -> FileTreeDownloadResult? {
        decodeFileTreeResult(fileServerServeNextTreeFunction(handle))
    }

    fileprivate func fileServerFree(_ handle: UnsafeMutableRawPointer) {
        fileServerFreeFunction(handle)
    }

    private func decodeFileTreeResult(_ pointer: UnsafeMutablePointer<CChar>?) -> FileTreeDownloadResult? {
        guard let pointer else {
            return nil
        }
        defer { freeStringFunction(pointer) }

        let json = String(cString: pointer)
        guard let data = json.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(FileTreeDownloadResult.self, from: data)
    }

    func createTrustMessageJSON(
        groupId: String,
        senderDeviceId: String,
        senderDeviceName: String,
        approvedDeviceId: String
    ) -> String? {
        let resultPointer = groupId.withCString { groupIdPointer in
            senderDeviceId.withCString { senderDeviceIdPointer in
                senderDeviceName.withCString { senderDeviceNamePointer in
                    approvedDeviceId.withCString { approvedDeviceIdPointer in
                        createTrustMessageJSONFunction(
                            groupIdPointer,
                            senderDeviceIdPointer,
                            senderDeviceNamePointer,
                            approvedDeviceIdPointer
                        )
                    }
                }
            }
        }

        guard let resultPointer else {
            return nil
        }
        defer { freeStringFunction(resultPointer) }

        return String(cString: resultPointer)
    }

    private static func libraryCandidatePaths() -> [String] {
        let environmentPath = ProcessInfo.processInfo.environment["CLIPPLUS_FFI_LIBRARY_PATH"]
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        let bundleCandidates = [
            environmentPath,
            executableDirectory?.appendingPathComponent("libclipplus_ffi.dylib").path,
            executableDirectory?.appendingPathComponent("../../../libclipplus_ffi.dylib").standardizedFileURL.path,
            executableDirectory?.appendingPathComponent("../Frameworks/libclipplus_ffi.dylib").standardizedFileURL.path
        ].compactMap { $0 }

        return bundleCandidates + swiftPMBuildLibraryCandidatePaths()
    }

    private static func swiftPMBuildLibraryCandidatePaths() -> [String] {
        let buildDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: buildDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item -> String? in
            guard let url = item as? URL,
                  url.lastPathComponent == "libclipplus_ffi.dylib",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }

            return url.path
        }
    }
}
