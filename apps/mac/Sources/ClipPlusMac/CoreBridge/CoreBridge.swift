import Darwin
import Foundation

struct CoreBridge {
    func statusJSON() -> String {
        #"{"core_version":"0.1.0"}"#
    }

    func deriveGroupId(for rawKey: String) -> String? {
        Self.ffiBridge?.deriveGroupId(for: rawKey)
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

    private static let ffiBridge = ClipPlusFFIBridge.load()
}

private final class ClipPlusFFIBridge {
    private typealias DeriveGroupIdFunction = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    private typealias CreateTextMessageJSONFunction = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?
    private typealias FreeStringFunction = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    private let handle: UnsafeMutableRawPointer
    private let deriveGroupIdFunction: DeriveGroupIdFunction
    private let createTextMessageJSONFunction: CreateTextMessageJSONFunction
    private let freeStringFunction: FreeStringFunction

    private init(
        handle: UnsafeMutableRawPointer,
        deriveGroupIdFunction: @escaping DeriveGroupIdFunction,
        createTextMessageJSONFunction: @escaping CreateTextMessageJSONFunction,
        freeStringFunction: @escaping FreeStringFunction
    ) {
        self.handle = handle
        self.deriveGroupIdFunction = deriveGroupIdFunction
        self.createTextMessageJSONFunction = createTextMessageJSONFunction
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
                  let createTextMessageJSONSymbol = dlsym(handle, "clipplus_create_text_message_json"),
                  let freeSymbol = dlsym(handle, "clipplus_free_string") else {
                dlclose(handle)
                continue
            }

            let deriveGroupIdFunction = unsafeBitCast(deriveSymbol, to: DeriveGroupIdFunction.self)
            let createTextMessageJSONFunction = unsafeBitCast(
                createTextMessageJSONSymbol,
                to: CreateTextMessageJSONFunction.self
            )
            let freeStringFunction = unsafeBitCast(freeSymbol, to: FreeStringFunction.self)
            return ClipPlusFFIBridge(
                handle: handle,
                deriveGroupIdFunction: deriveGroupIdFunction,
                createTextMessageJSONFunction: createTextMessageJSONFunction,
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
