import SwiftUI

@main
struct ClipPlusApp: App {
    @State private var settingsState = SettingsState()

    var body: some Scene {
        MenuBarExtra("ClipPlus", systemImage: "doc.on.clipboard") {
            MenuBarController(state: $settingsState)
        }
        .menuBarExtraStyle(.window)

        Window("ClipPlus 设置", id: "settings") {
            SettingsView(state: $settingsState)
        }

        Settings {
            SettingsView(state: $settingsState)
        }
    }
}
