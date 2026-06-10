import AppKit
import SwiftUI

struct MenuBarController: View {
    @Environment(\.openWindow) private var openWindow

    @ObservedObject var state: SettingsState
    @State private var diagnosticsMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(statusText)
                .font(.headline)

            Toggle("启用剪贴板共享", isOn: $state.sharingEnabled)

            LabeledContent("共享 Key") {
                keyStatusText
            }

            Button("修改 Key") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Toggle("开机自动启动", isOn: $state.startupEnabled)

            if state.pendingPeerCount > 0 {
                Button("允许全部待确认设备（\(state.pendingPeerCount)）") {
                    state.approvePendingPeers()
                }
            }

            Button("导出诊断包") {
                exportDiagnostics()
            }

            if let diagnosticsMessage {
                Text(diagnosticsMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

    private func exportDiagnostics() {
        let sensitiveValues = [
            ProcessInfo.processInfo.environment["CLIPPLUS_SHARED_KEY"]
        ].compactMap { $0 }

        do {
            let exportURL = try DiagnosticsExporter(sensitiveValues: sensitiveValues).export(state: state)
            diagnosticsMessage = "已导出：\(exportURL.lastPathComponent)"
        } catch {
            diagnosticsMessage = "诊断包导出失败"
        }
    }
}
