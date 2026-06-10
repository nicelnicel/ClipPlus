import SwiftUI

final class ClipPlusAppModel: ObservableObject {
    let settingsState: SettingsState
    private let loginItemManager: LoginItemManager
    private let syncService: UdpTextSyncService

    init() {
        CoreBridgeSmokeTest.runIfRequested()
        LoginItemSmokeTest.runIfRequested()

        let loginItemManager = LoginItemManager()
        let state = SettingsState(startupEnabled: loginItemManager.isEnabled())
        let logger = ClipPlusLogger()
        self.loginItemManager = loginItemManager
        settingsState = state
        syncService = UdpTextSyncService(state: state, logger: logger)
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
    @StateObject private var appModel = ClipPlusAppModel()

    var body: some Scene {
        MenuBarExtra("ClipPlus", systemImage: "doc.on.clipboard") {
            MenuBarController(state: appModel.settingsState)
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
