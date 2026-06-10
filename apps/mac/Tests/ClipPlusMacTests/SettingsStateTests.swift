import XCTest
@testable import ClipPlusMac

final class SettingsStateTests: XCTestCase {
    func testMissingKeyRequiresSetup() {
        let state = SettingsState(
            sharedKeyConfigured: false,
            sharingEnabled: true,
            startupEnabled: false
        )

        XCTAssertTrue(state.requiresKeySetup)
    }

    func testStartupToggleUpdatesState() {
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        )

        state.startupEnabled = true

        XCTAssertTrue(state.startupEnabled)
    }

    func testMissingKeyRequiresSetupWhenSharingDisabled() {
        let state = SettingsState(
            sharedKeyConfigured: false,
            sharingEnabled: false,
            startupEnabled: false
        )

        XCTAssertTrue(state.requiresKeySetup)
    }

    func testDefaultStateMatchesInitialAppConfiguration() {
        let state = SettingsState()

        XCTAssertFalse(state.sharedKeyConfigured)
        XCTAssertTrue(state.sharingEnabled)
        XCTAssertFalse(state.startupEnabled)
        XCTAssertTrue(state.requiresKeySetup)
    }

    func testSharedKeyStoresOnlyDerivedGroupIdentifier() throws {
        let state = SettingsState()

        try state.updateSharedKey("clipplus-test-key", confirmation: "clipplus-test-key")

        XCTAssertTrue(state.sharedKeyConfigured)
        XCTAssertEqual(state.sharedGroupId, expectedGroupId(for: "clipplus-test-key"))
        XCTAssertFalse(state.sharedGroupId.contains("clipplus-test-key"))
    }

    func testCoreBridgeDerivesGroupIdWhenFFILibraryIsAvailable() {
        let ffiLibraryPath = ProcessInfo.processInfo.environment["CLIPPLUS_FFI_LIBRARY_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let groupId = CoreBridge().deriveGroupId(for: "clipplus-test-key") else {
            if let ffiLibraryPath, !ffiLibraryPath.isEmpty {
                XCTFail("Expected CoreBridge to load FFI library from CLIPPLUS_FFI_LIBRARY_PATH: \(ffiLibraryPath)")
            }

            return
        }

        XCTAssertEqual(groupId, "21YR2N3_wcdRPmEMLiuLMA")
    }

    func testMismatchedSharedKeyConfirmationFails() {
        let state = SettingsState()

        XCTAssertThrowsError(try state.updateSharedKey("clipplus-test-key", confirmation: "other-key"))
        XCTAssertFalse(state.sharedKeyConfigured)
        XCTAssertTrue(state.requiresKeySetup)
    }

    func testPendingPeerMustBeApprovedBeforeSync() {
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        )

        state.markPeerPending(deviceId: "windows-device", deviceName: "Windows 11")

        XCTAssertEqual(state.pendingPeerCount, 1)
        XCTAssertFalse(state.isPeerTrusted("windows-device"))

        state.approvePendingPeers()

        XCTAssertEqual(state.pendingPeerCount, 0)
        XCTAssertTrue(state.isPeerTrusted("windows-device"))
    }

    func testPendingPeerDoesNotAllowPublishingClipboardContentUntilApproved() {
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        )

        state.markPeerPending(deviceId: "windows-device", deviceName: "Windows 11")

        XCTAssertFalse(state.canPublishClipboardContent)

        state.approvePendingPeer(deviceId: "windows-device")

        XCTAssertTrue(state.canPublishClipboardContent)
        XCTAssertEqual(state.trustedPeerCount, 1)
    }

    func testPendingPeerSummariesAreSortedAndAllowSingleApproval() {
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        )

        state.markPeerPending(deviceId: "z-device", deviceName: "Windows")
        state.markPeerPending(deviceId: "a-device", deviceName: "MacBook")

        XCTAssertEqual(state.pendingPeerSummaries.map(\.deviceName), ["MacBook", "Windows"])

        state.approvePendingPeer(deviceId: "a-device")

        XCTAssertEqual(state.pendingPeerCount, 1)
        XCTAssertTrue(state.isPeerTrusted("a-device"))
        XCTAssertFalse(state.isPeerTrusted("z-device"))
    }

    func testRepeatedTrustForAlreadyTrustedPeerDoesNotRewriteStatus() {
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        )

        XCTAssertTrue(state.trustPeer(deviceId: "windows-device", deviceName: "Windows"))
        state.lastStatusMessage = "稳定状态"

        XCTAssertFalse(state.trustPeer(deviceId: "windows-device", deviceName: "Windows"))

        XCTAssertEqual(state.trustedPeerCount, 1)
        XCTAssertEqual(state.lastStatusMessage, "稳定状态")
    }

    func testClipPlusMessageRoundTripsTextPayload() throws {
        let message = ClipPlusMessage.text(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            text: "hello from mac"
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .text)
        XCTAssertEqual(decoded.protocolVersion, 1)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.text, "hello from mac")
    }

    func testCoreBridgeCreatesTextMessageJsonWhenFfiLibraryIsAvailable() throws {
        let json = try XCTUnwrap(CoreBridge().createTextMessageJSON(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            text: "hello from ffi"
        ))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .text)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.senderDeviceName, "Mac")
        XCTAssertEqual(decoded.text, "hello from ffi")
    }

    func testCoreBridgeCreatesHelloMessageJsonWhenFfiLibraryIsAvailable() throws {
        let json = try XCTUnwrap(CoreBridge().createHelloMessageJSON(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac"
        ))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .hello)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.senderDeviceName, "Mac")
    }

    func testCoreBridgeCreatesTrustMessageJsonWhenFfiLibraryIsAvailable() throws {
        let json = try XCTUnwrap(CoreBridge().createTrustMessageJSON(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            approvedDeviceId: "windows-device"
        ))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .trust)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.approvedDeviceId, "windows-device")
    }

    func testClipPlusMessageRoundTripsInlinePngImagePayload() throws {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let message = try XCTUnwrap(ClipPlusMessage.image(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            pngData: pngData
        ))

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .image)
        XCTAssertEqual(decoded.protocolVersion, 1)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.imageByteSize, pngData.count)
        XCTAssertEqual(decoded.imageBase64, pngData.base64EncodedString())
        XCTAssertEqual(decoded.decodedImageData, pngData)
        XCTAssertEqual(
            decoded.imageContentHash,
            "4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6"
        )
    }

    func testCoreBridgeCreatesImageMessageJsonWhenFfiLibraryIsAvailable() throws {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let json = try XCTUnwrap(CoreBridge().createImageMessageJSON(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            pngData: pngData
        ))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .image)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.imageByteSize, pngData.count)
        XCTAssertEqual(decoded.imageBase64, pngData.base64EncodedString())
        XCTAssertEqual(
            decoded.imageContentHash,
            "4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6"
        )
    }

    func testClipPlusMessageRoundTripsTrustPayload() throws {
        let message = ClipPlusMessage.trust(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            approvedDeviceId: "windows-device"
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .trust)
        XCTAssertEqual(decoded.protocolVersion, 1)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.approvedDeviceId, "windows-device")
    }

    func testClipPlusMessageRoundTripsFileOfferPayloadWithoutLocalPaths() throws {
        let item = FileTransferItem(
            relativePath: "Reports/Q1.txt",
            byteSize: 12,
            isDirectory: false
        )
        let message = ClipPlusMessage.fileOffer(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            transferId: "transfer-1",
            files: [item],
            archivePort: 47_632
        )

        let data = try JSONEncoder().encode(message)
        let json = String(data: data, encoding: .utf8) ?? ""
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .fileOffer)
        XCTAssertEqual(decoded.transferId, "transfer-1")
        XCTAssertEqual(decoded.archivePort, 47_632)
        XCTAssertEqual(decoded.files, [item])
        XCTAssertFalse(json.contains("/Users/"))
        XCTAssertFalse(json.contains("C:\\\\"))
    }

    func testCoreBridgeCreatesFileOfferMessageJsonWhenFfiLibraryIsAvailable() throws {
        let item = FileTransferItem(
            relativePath: "Reports/Q1.txt",
            byteSize: 12,
            isDirectory: false
        )
        let json = try XCTUnwrap(CoreBridge().createFileOfferMessageJSON(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            transferId: "transfer-1",
            files: [item],
            archivePort: 47_632
        ))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .fileOffer)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.transferId, "transfer-1")
        XCTAssertEqual(decoded.archivePort, 47_632)
        XCTAssertEqual(decoded.files, [item])
        XCTAssertFalse(json.contains("/Users/"))
        XCTAssertFalse(json.contains("C:\\\\"))
    }

    func testRemoteFileOfferCanRequestReceive() {
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        )
        var requestedTransferId: String?
        state.remoteFileReceiveRequested = { requestedTransferId = $0 }

        state.updateRemoteFileOffer(RemoteFileOfferSummary(
            transferId: "transfer-1",
            sourceDeviceId: "windows-device",
            sourceDeviceName: "Windows",
            sourceHost: "10.211.55.3",
            fileCount: 2,
            totalBytes: 24
        ))

        XCTAssertEqual(state.remoteFileOffer?.displayTitle, "Windows：2 个文件可接收")
        XCTAssertTrue(state.hasRemoteFileOffer)

        state.requestRemoteFileReceive()

        XCTAssertEqual(requestedTransferId, "transfer-1")
    }

    func testFileTransferArchiveWritesZipEntriesForFilesAndDirectories() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = temporaryDirectory.appendingPathComponent("source", isDirectory: true)
        let nestedDirectory = sourceDirectory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try "alpha".write(to: sourceDirectory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "beta".write(to: nestedDirectory.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let archiveURL = temporaryDirectory.appendingPathComponent("files.zip")
        try FileTransferArchive.writeZip(
            sourceURLs: [sourceDirectory.appendingPathComponent("a.txt"), nestedDirectory],
            to: archiveURL
        )

        let extractedDirectory = temporaryDirectory.appendingPathComponent("unzipped", isDirectory: true)
        try FileManager.default.createDirectory(at: extractedDirectory, withIntermediateDirectories: true)
        try unzip(archiveURL, to: extractedDirectory)

        let a = try String(contentsOf: extractedDirectory.appendingPathComponent("a.txt"), encoding: .utf8)
        let b = try String(contentsOf: extractedDirectory.appendingPathComponent("Nested/b.txt"), encoding: .utf8)
        XCTAssertEqual(a, "alpha")
        XCTAssertEqual(b, "beta")
    }

    func testClipPlusMessageRejectsOversizedInlineImagePayload() {
        let pngData = Data(repeating: 0xFF, count: ClipPlusMessage.maxInlineImageBytes + 1)

        let message = ClipPlusMessage.image(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            pngData: pngData
        )

        XCTAssertNil(message)
    }

    func testLoginItemManagerReportsServiceState() {
        let service = FakeLoginItemService(enabled: true)
        let manager = LoginItemManager(service: service)

        XCTAssertTrue(manager.isEnabled())
    }

    func testLoginItemManagerForwardsEnableAndDisable() throws {
        let service = FakeLoginItemService(enabled: false)
        let manager = LoginItemManager(service: service)

        try manager.setEnabled(true)
        try manager.setEnabled(false)

        XCTAssertEqual(service.requests, [true, false])
        XCTAssertFalse(manager.isEnabled())
    }

    func testLoginItemSmokeTestRestoresDisabledOriginalState() throws {
        let service = FakeLoginItemService(enabled: false)
        let manager = LoginItemManager(service: service)

        let result = try LoginItemSmokeTest.perform(manager: manager)

        XCTAssertEqual(
            result,
            LoginItemSmokeTestResult(
                enabledAfterRegister: true,
                disabledAfterUnregister: true,
                restoredOriginal: true
            )
        )
        XCTAssertEqual(service.requests, [true, false, false])
        XCTAssertFalse(manager.isEnabled())
    }

    func testLoginItemSmokeTestRestoresEnabledOriginalState() throws {
        let service = FakeLoginItemService(enabled: true)
        let manager = LoginItemManager(service: service)

        let result = try LoginItemSmokeTest.perform(manager: manager)

        XCTAssertTrue(result.passed)
        XCTAssertEqual(service.requests, [true, false, true])
        XCTAssertTrue(manager.isEnabled())
    }

    func testDiagnosticsExporterWritesRedactedStatusAndLogZip() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let logURL = temporaryDirectory.appendingPathComponent("clipplus.log")
        try "raw key clipplus-test-key clipboard secret-value".write(to: logURL, atomically: true, encoding: .utf8)
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false,
            sharedGroupId: "group-id"
        )
        state.markPeerPending(deviceId: "windows-device", deviceName: "Windows")
        let exporter = DiagnosticsExporter(
            logURL: logURL,
            destinationDirectory: temporaryDirectory,
            sensitiveValues: ["clipplus-test-key", "secret-value"]
        )

        let exportURL = try exporter.export(state: state)
        let extractedDirectory = temporaryDirectory.appendingPathComponent("unzipped", isDirectory: true)
        try FileManager.default.createDirectory(at: extractedDirectory, withIntermediateDirectories: true)
        try unzip(exportURL, to: extractedDirectory)
        let status = try String(
            contentsOf: extractedDirectory.appendingPathComponent("status.json"),
            encoding: .utf8
        )
        let log = try String(
            contentsOf: extractedDirectory.appendingPathComponent("clipplus.log"),
            encoding: .utf8
        )

        XCTAssertEqual(exportURL.pathExtension, "zip")
        XCTAssertTrue(status.contains("\"shared_key_configured\""))
        XCTAssertTrue(status.contains("\"pending_peer_count\""))
        XCTAssertFalse(status.contains("clipplus-test-key"))
        XCTAssertFalse(log.contains("clipplus-test-key"))
        XCTAssertFalse(log.contains("secret-value"))
        XCTAssertTrue(log.contains("<redacted>"))
    }
}

private func unzip(_ archiveURL: URL, to destinationURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-q", archiveURL.path, "-d", destinationURL.path]
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
}

private func expectedGroupId(for rawKey: String) -> String {
    switch rawKey {
    case "clipplus-test-key":
        return "21YR2N3_wcdRPmEMLiuLMA"
    default:
        XCTFail("Missing expected group id fixture for \(rawKey)")
        return ""
    }
}

private final class FakeLoginItemService: LoginItemService {
    var enabled: Bool
    var requests: [Bool] = []

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        requests.append(enabled)
        self.enabled = enabled
    }
}
