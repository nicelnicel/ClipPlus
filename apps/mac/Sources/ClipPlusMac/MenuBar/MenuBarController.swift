import AppKit
import SwiftUI

struct MenuBarController: View {
    @Environment(\.openWindow) private var openWindow

    @Binding var state: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(statusText)
                .font(.headline)

            Toggle("启用剪贴板共享", isOn: $state.sharingEnabled)

            LabeledContent("共享 Key") {
                keyStatusText
            }

            Button("修改 Key") {
                state.sharedKeyConfigured = true
            }

            Divider()

            Toggle("开机自动启动", isOn: $state.startupEnabled)

            Button("导出诊断包") {}

            Button("打开独立设置窗口") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("退出 ClipPlus") {
                NSApp.terminate(nil)
            }
        }
        .padding()
        .frame(width: 280)
    }

    @ViewBuilder
    private var keyStatusText: some View {
        if state.sharedKeyConfigured {
            Text("已设置")
                .foregroundStyle(.secondary)
        } else {
            Text("未设置")
                .foregroundStyle(.red)
        }
    }

    private var statusText: String {
        if state.requiresKeySetup {
            return "状态：共享 Key 未设置"
        }

        if state.sharingEnabled {
            return "状态：剪贴板共享已启用"
        }

        return "状态：剪贴板共享已停用"
    }
}
