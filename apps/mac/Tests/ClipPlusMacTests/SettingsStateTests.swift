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
        XCTAssertEqual(state.sharedGroupId, "OcePlqBkjK6NLJjtPRglTw")
        XCTAssertFalse(state.sharedGroupId.contains("clipplus-test-key"))
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

    func testDiagnosticsExporterWritesRedactedStatusAndLog() throws {
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
        let status = try String(
            contentsOf: exportURL.appendingPathComponent("status.json"),
            encoding: .utf8
        )
        let log = try String(
            contentsOf: exportURL.appendingPathComponent("clipplus.log"),
            encoding: .utf8
        )

        XCTAssertTrue(status.contains("\"shared_key_configured\""))
        XCTAssertTrue(status.contains("\"pending_peer_count\""))
        XCTAssertFalse(status.contains("clipplus-test-key"))
        XCTAssertFalse(log.contains("clipplus-test-key"))
        XCTAssertFalse(log.contains("secret-value"))
        XCTAssertTrue(log.contains("<redacted>"))
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
