import SwiftUI

final class ClipPlusAppModel: ObservableObject {
    let settingsState: SettingsState
    private let syncService: UdpTextSyncService

    init() {
        let state = SettingsState()
        let logger = ClipPlusLogger()
        settingsState = state
        syncService = UdpTextSyncService(state: state, logger: logger)
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
