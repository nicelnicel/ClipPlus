import Darwin
import Foundation

struct CoreBridge {
    func statusJSON() -> String {
        #"{"core_version":"0.1.0"}"#
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

    func downloadFileArchive(host: String, port: Int, transferId: String, destinationPath: String) -> Bool {
        Self.ffiBridge?.downloadFileArchive(
            host: host,
            port: port,
            transferId: transferId,
            destinationPath: destinationPath
        ) ?? false
    }

    func openUdpSocket(bindPort: Int) -> RustUdpSocket? {
        Self.ffiBridge?.openUdpSocket(bindPort: bindPort)
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
        defer { lock.unlock() }
        guard let handle else {
            return nil
        }

        return bridge.udpSocketReceive(handle)
    }

    func close() {
        lock.lock()
        let handleToClose = handle
        handle = nil
        lock.unlock()

        if let handleToClose {
            bridge.udpSocketFree(handleToClose)
        }
    }

    deinit {
        close()
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
    private typealias FreeStringFunction = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    private let handle: UnsafeMutableRawPointer
    private let deriveGroupIdFunction: DeriveGroupIdFunction
    private let createHelloMessageJSONFunction: CreateHelloMessageJSONFunction
    private let createTextMessageJSONFunction: CreateTextMessageJSONFunction
    private let createImageMessageJSONFunction: CreateImageMessageJSONFunction
    private let createFileOfferMessageJSONFunction: CreateFileOfferMessageJSONFunction
    private let writeFileArchiveZipFunction: WriteFileArchiveZipFunction
    private let serveFileArchiveToSocketFunction: ServeFileArchiveToSocketFunction
    private let downloadFileArchiveFunction: DownloadFileArchiveFunction
    private let udpSocketBindFunction: UdpSocketBindFunction
    private let udpSocketFreeFunction: UdpSocketFreeFunction
    private let udpSocketLocalPortFunction: UdpSocketLocalPortFunction
    private let udpSocketSendToFunction: UdpSocketSendToFunction
    private let udpSocketRecvFunction: UdpSocketRecvFunction
    private let createTrustMessageJSONFunction: CreateTextMessageJSONFunction
    private let freeStringFunction: FreeStringFunction

    private init(
        handle: UnsafeMutableRawPointer,
        deriveGroupIdFunction: @escaping DeriveGroupIdFunction,
        createHelloMessageJSONFunction: @escaping CreateHelloMessageJSONFunction,
        createTextMessageJSONFunction: @escaping CreateTextMessageJSONFunction,
        createImageMessageJSONFunction: @escaping CreateImageMessageJSONFunction,
        createFileOfferMessageJSONFunction: @escaping CreateFileOfferMessageJSONFunction,
        writeFileArchiveZipFunction: @escaping WriteFileArchiveZipFunction,
        serveFileArchiveToSocketFunction: @escaping ServeFileArchiveToSocketFunction,
        downloadFileArchiveFunction: @escaping DownloadFileArchiveFunction,
        udpSocketBindFunction: @escaping UdpSocketBindFunction,
        udpSocketFreeFunction: @escaping UdpSocketFreeFunction,
        udpSocketLocalPortFunction: @escaping UdpSocketLocalPortFunction,
        udpSocketSendToFunction: @escaping UdpSocketSendToFunction,
        udpSocketRecvFunction: @escaping UdpSocketRecvFunction,
        createTrustMessageJSONFunction: @escaping CreateTextMessageJSONFunction,
        freeStringFunction: @escaping FreeStringFunction
    ) {
        self.handle = handle
        self.deriveGroupIdFunction = deriveGroupIdFunction
        self.createHelloMessageJSONFunction = createHelloMessageJSONFunction
        self.createTextMessageJSONFunction = createTextMessageJSONFunction
        self.createImageMessageJSONFunction = createImageMessageJSONFunction
        self.createFileOfferMessageJSONFunction = createFileOfferMessageJSONFunction
        self.writeFileArchiveZipFunction = writeFileArchiveZipFunction
        self.serveFileArchiveToSocketFunction = serveFileArchiveToSocketFunction
        self.downloadFileArchiveFunction = downloadFileArchiveFunction
        self.udpSocketBindFunction = udpSocketBindFunction
        self.udpSocketFreeFunction = udpSocketFreeFunction
        self.udpSocketLocalPortFunction = udpSocketLocalPortFunction
        self.udpSocketSendToFunction = udpSocketSendToFunction
        self.udpSocketRecvFunction = udpSocketRecvFunction
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
                  let createFileOfferMessageJSONSymbol = dlsym(handle, "clipplus_create_file_offer_message_json"),
                  let writeFileArchiveZipSymbol = dlsym(handle, "clipplus_write_file_archive_zip"),
                  let serveFileArchiveToSocketSymbol = dlsym(handle, "clipplus_serve_file_archive_to_socket"),
                  let downloadFileArchiveSymbol = dlsym(handle, "clipplus_download_file_archive"),
                  let udpSocketBindSymbol = dlsym(handle, "clipplus_udp_socket_bind"),
                  let udpSocketFreeSymbol = dlsym(handle, "clipplus_udp_socket_free"),
                  let udpSocketLocalPortSymbol = dlsym(handle, "clipplus_udp_socket_local_port"),
                  let udpSocketSendToSymbol = dlsym(handle, "clipplus_udp_socket_send_to"),
                  let udpSocketRecvSymbol = dlsym(handle, "clipplus_udp_socket_recv"),
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
                createFileOfferMessageJSONFunction: createFileOfferMessageJSONFunction,
                writeFileArchiveZipFunction: writeFileArchiveZipFunction,
                serveFileArchiveToSocketFunction: serveFileArchiveToSocketFunction,
                downloadFileArchiveFunction: downloadFileArchiveFunction,
                udpSocketBindFunction: udpSocketBindFunction,
                udpSocketFreeFunction: udpSocketFreeFunction,
                udpSocketLocalPortFunction: udpSocketLocalPortFunction,
                udpSocketSendToFunction: udpSocketSendToFunction,
                udpSocketRecvFunction: udpSocketRecvFunction,
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

    func downloadFileArchive(
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
        return [
            environmentPath,
            executableDirectory?.appendingPathComponent("libclipplus_ffi.dylib").path,
            executableDirectory?.appendingPathComponent("../Frameworks/libclipplus_ffi.dylib").standardizedFileURL.path
        ].compactMap { $0 }
    }
}
