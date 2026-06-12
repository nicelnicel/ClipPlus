import AppKit
import SwiftUI

final class ClipPlusAppModel: ObservableObject {
    let settingsState: SettingsState
    private let loginItemManager: LoginItemManager
    private let syncService: UdpTextSyncService

    init() {
        CoreBridgeSmokeTest.runIfRequested()
        LoginItemSmokeTest.runIfRequested()

        let loginItemManager = LoginItemManager()
        let settingsStore = SettingsStore()
        let storedSettings = settingsStore.load()
        let state = SettingsState(
            sharedKeyConfigured: storedSettings.sharedKeyConfigured,
            sharingEnabled: storedSettings.sharingEnabled,
            startupEnabled: loginItemManager.isEnabled(),
            sharedGroupId: storedSettings.sharedGroupId,
            sharedKeyInput: storedSettings.sharedKeyInput
        )
        let logger = ClipPlusLogger()
        self.loginItemManager = loginItemManager
        settingsState = state
        syncService = UdpTextSyncService(state: state, logger: logger)
        settingsState.sharedKeyChanged = { [settingsStore] sharedKey, sharedGroupId in
            try settingsStore.saveSharedKey(sharedKey, sharedGroupId: sharedGroupId)
        }
        settingsState.sharingEnabledChanged = { [settingsStore] enabled in
            settingsStore.saveSharingEnabled(enabled)
        }
        settingsState.startupEnabledChanged = { [loginItemManager, weak state] enabled in
            do {
                try loginItemManager.setEnabled(enabled)
            } catch {
                state?.lastStatusMessage = "开机启动设置失败"
            }
        }
        syncService.start()
    }
}

@main
struct ClipPlusApp: App {
    @StateObject private var appModel: ClipPlusAppModel
    private let singleInstanceLock: SingleInstanceLock

    init() {
        guard let singleInstanceLock = SingleInstanceLock.acquireDefault() else {
            exit(0)
        }

        self.singleInstanceLock = singleInstanceLock
        _appModel = StateObject(wrappedValue: ClipPlusAppModel())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarController(state: appModel.settingsState)
        } label: {
            Image(nsImage: ClipPlusAppIcon.menuBarImage)
                .accessibilityLabel("ClipPlus")
        }
        .menuBarExtraStyle(.window)

        Window("ClipPlus 设置", id: "settings") {
            SettingsView(state: appModel.settingsState)
        }

        Settings {
            SettingsView(state: appModel.settingsState)
        }
    }
}

private enum ClipPlusAppIcon {
    static var menuBarImage: NSImage {
        if let resourceURL = Bundle.main.url(forResource: "ClipPlusMenuBar", withExtension: "png"),
           let image = NSImage(contentsOf: resourceURL) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        return NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "ClipPlus"
        ) ?? NSImage()
    }
}
