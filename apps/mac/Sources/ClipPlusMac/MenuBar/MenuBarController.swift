import AppKit
import SwiftUI

struct MenuBarController: View {
    @Binding var state: SettingsState

    var body: some View {
        Text(statusText)

        Toggle("启用共享", isOn: $state.sharingEnabled)

        Divider()

        Button("打开设置") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("退出 ClipPlus") {
            NSApp.terminate(nil)
        }
    }

    private var statusText: String {
        if state.requiresKeySetup {
            return "需要设置共享 Key"
        }

        if state.sharingEnabled {
            return "剪贴板共享已启用"
        }

        return "剪贴板共享已停用"
    }
}
