import SwiftUI

@main
struct ClipPlusApp: App {
    @State private var settingsState = SettingsState()

    var body: some Scene {
        MenuBarExtra("ClipPlus", systemImage: "doc.on.clipboard") {
            MenuBarController(state: $settingsState)
        }

        Settings {
            SettingsView(state: $settingsState)
        }
    }
}
