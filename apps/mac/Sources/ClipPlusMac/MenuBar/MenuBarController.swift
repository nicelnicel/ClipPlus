import SwiftUI

struct MenuBarController: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        SettingsView(state: state)
    }
}
