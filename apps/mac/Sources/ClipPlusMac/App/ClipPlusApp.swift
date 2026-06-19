import AppKit
import SwiftUI

@MainActor
final class ClipPlusAppModel: ObservableObject {
    let settingsState: SettingsState
    private let loginItemManager: LoginItemManager
    private let syncService: UdpTextSyncService
    private let statusBarController: StatusBarController
    private let settingsWindowController: SettingsWindowController

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
        statusBarController = StatusBarController(state: state)
        settingsWindowController = SettingsWindowController(state: state)
        let syncService = self.syncService
        settingsState.sharedKeyChanged = { [settingsStore] sharedKey, sharedGroupId in
            try settingsStore.saveSharedKey(sharedKey, sharedGroupId: sharedGroupId)
        }
        settingsState.sharedGroupIdChanged = { [weak syncService] _ in
            syncService?.scheduleDiscoveryRefresh()
        }
        settingsState.sharingEnabledChanged = { [settingsStore, weak syncService] enabled in
            settingsStore.saveSharingEnabled(enabled)
            syncService?.scheduleDiscoveryRefresh()
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

    func showSettingsWindow() {
        settingsWindowController.showSettingsWindow()
    }
}

@main
struct ClipPlusApp: App {
    @NSApplicationDelegateAdaptor(ClipPlusAppDelegate.self) private var appDelegate
    @StateObject private var appModel: ClipPlusAppModel
    private let singleInstanceLock: SingleInstanceLock

    init() {
        guard let singleInstanceLock = SingleInstanceLock.acquireDefault() else {
            exit(0)
        }

        self.singleInstanceLock = singleInstanceLock
        let appModel = ClipPlusAppModel()
        _appModel = StateObject(wrappedValue: appModel)
        appDelegate.configure(appModel: appModel)
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

enum ClipPlusAppIcon {
    static var menuBarImage: NSImage {
        if let image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "ClipPlus"
        ) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }

        if let resourceURL = Bundle.main.url(forResource: "ClipPlusMenuBar", withExtension: "png"),
           let image = NSImage(contentsOf: resourceURL) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }

        return NSImage()
    }
}
