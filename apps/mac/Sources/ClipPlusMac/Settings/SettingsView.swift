import SwiftUI

struct SettingsState: Equatable {
    var sharedKeyConfigured: Bool
    var sharingEnabled: Bool
    var startupEnabled: Bool

    var requiresKeySetup: Bool {
        sharingEnabled && !sharedKeyConfigured
    }

    init(
        sharedKeyConfigured: Bool = false,
        sharingEnabled: Bool = false,
        startupEnabled: Bool = false
    ) {
        self.sharedKeyConfigured = sharedKeyConfigured
        self.sharingEnabled = sharingEnabled
        self.startupEnabled = startupEnabled
    }
}

struct SettingsView: View {
    @Binding var state: SettingsState

    var body: some View {
        Form {
            Section("共享") {
                Toggle("启用剪贴板共享", isOn: $state.sharingEnabled)

                LabeledContent("共享 Key") {
                    keyStatusText
                }

                Button("修改 Key") {
                    state.sharedKeyConfigured = true
                }
            }

            Section("系统") {
                Toggle("开机自动启动", isOn: $state.startupEnabled)

                Button("导出诊断包") {}
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
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
}
