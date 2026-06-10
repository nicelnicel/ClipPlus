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
    private typealias FreeStringFunction = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    private let handle: UnsafeMutableRawPointer
    private let deriveGroupIdFunction: DeriveGroupIdFunction
    private let createHelloMessageJSONFunction: CreateHelloMessageJSONFunction
    private let createTextMessageJSONFunction: CreateTextMessageJSONFunction
    private let createTrustMessageJSONFunction: CreateTextMessageJSONFunction
    private let freeStringFunction: FreeStringFunction

    private init(
        handle: UnsafeMutableRawPointer,
        deriveGroupIdFunction: @escaping DeriveGroupIdFunction,
        createHelloMessageJSONFunction: @escaping CreateHelloMessageJSONFunction,
        createTextMessageJSONFunction: @escaping CreateTextMessageJSONFunction,
        createTrustMessageJSONFunction: @escaping CreateTextMessageJSONFunction,
        freeStringFunction: @escaping FreeStringFunction
    ) {
        self.handle = handle
        self.deriveGroupIdFunction = deriveGroupIdFunction
        self.createHelloMessageJSONFunction = createHelloMessageJSONFunction
        self.createTextMessageJSONFunction = createTextMessageJSONFunction
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
