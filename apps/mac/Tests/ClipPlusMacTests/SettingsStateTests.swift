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
        var state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        )

        state.startupEnabled = true

        XCTAssertTrue(state.startupEnabled)
    }
}
