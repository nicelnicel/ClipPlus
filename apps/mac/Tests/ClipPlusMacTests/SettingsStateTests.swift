import Darwin
import AppKit
import Network
import XCTest
@testable import ClipPlusMac

final class SettingsStateTests: XCTestCase {
    func testMissingKeyRequiresSetup() {
        let state = SettingsState(
            sharedKeyConfigured: false,
            sharingEnabled: true,
            startupEnabled: false
        )

        XCTAssertTrue(state.requiresKeySetup)
    }

    func testConfiguredSharedKeyUsesMaskedPlaceholderWithoutStoringRawKey() {
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false,
            sharedGroupId: "stored-group"
        )

        XCTAssertEqual(state.sharedKeyFieldPrompt, "输入 Key")
        XCTAssertEqual(state.sharedKeyInput, "")

        state.sharedKeyInput = "clipplus-test-key"

        XCTAssertEqual(state.sharedKeyFieldPrompt, "输入 Key")
        XCTAssertFalse(state.sharedGroupId.contains("clipplus-test-key"))
    }

    func testConfiguredSharedKeyCanLoadStoredRawKeyForEyeReveal() {
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false,
            sharedGroupId: "stored-group",
            sharedKeyInput: "clipplus-test-key"
        )

        XCTAssertEqual(state.sharedKeyInput, "clipplus-test-key")
        XCTAssertEqual(state.sharedKeyFieldPrompt, "输入 Key")
        XCTAssertFalse(state.sharedGroupId.contains("clipplus-test-key"))
    }

    func testStoredGroupIdWithoutPlainTextKeyRequiresSetupAgain() throws {
        let suiteName = "ClipPlusMacTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let sharedKeyVault = InMemorySharedKeyVault()
        let store = SettingsStore(userDefaults: userDefaults, sharedKeyVault: sharedKeyVault)

        store.saveSharedGroupId("legacy-group-id")

        XCTAssertEqual(
            SettingsStore(userDefaults: userDefaults, sharedKeyVault: sharedKeyVault).load(),
            StoredSettings(
                sharedKeyConfigured: false,
                sharingEnabled: true,
                sharedGroupId: "legacy-group-id",
                sharedKeyInput: ""
            )
        )
    }

    func testMissingSharedKeyUsesSetupPromptWithoutLaunchingFloatingWindow() throws {
        let missingKeyState = SettingsState(
            sharedKeyConfigured: false,
            sharingEnabled: true,
            startupEnabled: false
        )
        let configuredState = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        )

        XCTAssertEqual(missingKeyState.sharedKeyFieldPrompt, "输入 Key")
        XCTAssertTrue(missingKeyState.shouldShowKeySetupPrompt)
        XCTAssertFalse(configuredState.shouldShowKeySetupPrompt)

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("apps/mac/Sources/ClipPlusMac/App/ClipPlusApp.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(appSource.contains("SettingsWindowPresenter"))
        XCTAssertFalse(appSource.contains("NSApp.activate"))
        XCTAssertFalse(appSource.contains(".floating"))
    }

    func testStartupToggleUpdatesState() {
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        )

        state.startupEnabled = true

        XCTAssertTrue(state.startupEnabled)
    }

    func testSingleInstanceLockRejectsSecondRunningCopy() throws {
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)

        let firstLock = try XCTUnwrap(SingleInstanceLock.acquire(lockURL: lockURL))
        let secondLock = SingleInstanceLock.acquire(lockURL: lockURL)

        XCTAssertNil(secondLock)
        _ = firstLock
    }

    func testSettingsStorePersistsInstallSafeConfiguration() throws {
        let suiteName = "ClipPlusMacTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let sharedKeyVault = InMemorySharedKeyVault()
        let store = SettingsStore(userDefaults: userDefaults, sharedKeyVault: sharedKeyVault)

        XCTAssertEqual(
            store.load(),
            StoredSettings(
                sharedKeyConfigured: false,
                sharingEnabled: true,
                sharedGroupId: "",
                sharedKeyInput: ""
            )
        )

        try store.saveSharedKey("clipplus-test-key", sharedGroupId: "group-id")
        store.saveSharingEnabled(false)

        XCTAssertEqual(
            SettingsStore(userDefaults: userDefaults, sharedKeyVault: sharedKeyVault).load(),
            StoredSettings(
                sharedKeyConfigured: true,
                sharingEnabled: false,
                sharedGroupId: "group-id",
                sharedKeyInput: "clipplus-test-key"
            )
        )
        XCTAssertNil(userDefaults.string(forKey: "clipplus.shared_key"))
    }

    func testSharedKeyVaultPersistsPlainTextFileInProcessDirectory() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let sharedKeyFileURL = temporaryDirectory.appendingPathComponent("clipplus.shared-key")
        let vault = FileSharedKeyVault(fileURL: sharedKeyFileURL)

        try vault.saveSharedKey("clipplus-test-key")

        XCTAssertEqual(
            try String(contentsOf: sharedKeyFileURL, encoding: .utf8),
            "clipplus-test-key"
        )
        XCTAssertEqual(
            FileSharedKeyVault(fileURL: sharedKeyFileURL).loadSharedKey(),
            "clipplus-test-key"
        )
    }

    func testSharedKeyVaultMigratesLegacyExecutableDirectoryKeyToStableUserPath() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let stableKeyFileURL = temporaryDirectory
            .appendingPathComponent("Stable", isDirectory: true)
            .appendingPathComponent("clipplus.shared-key")
        let legacyKeyFileURL = temporaryDirectory
            .appendingPathComponent("Legacy", isDirectory: true)
            .appendingPathComponent("clipplus.shared-key")
        try FileManager.default.createDirectory(
            at: legacyKeyFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "clipplus-test-key".write(to: legacyKeyFileURL, atomically: true, encoding: .utf8)
        let vault = FileSharedKeyVault(fileURL: stableKeyFileURL, legacyFileURL: legacyKeyFileURL)

        XCTAssertEqual(vault.loadSharedKey(), "clipplus-test-key")
        XCTAssertEqual(
            try String(contentsOf: stableKeyFileURL, encoding: .utf8),
            "clipplus-test-key"
        )
    }

    func testSettingsUIOnlyShowsKeySharingAndStartupControls() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsViewURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/Settings/SettingsView.swift")
        let sharedKeyInputFieldURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/Settings/SharedKeyInputField.swift")
        let menuBarURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/MenuBar/MenuBarController.swift")
        let syncServiceURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/Sync/UdpTextSyncService.swift")
        let appSourceURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/App/ClipPlusApp.swift")
        let settingsSource = try String(contentsOf: settingsViewURL, encoding: .utf8)
        let sharedKeyInputFieldSource = try String(contentsOf: sharedKeyInputFieldURL, encoding: .utf8)
        let settingsViewStart = try XCTUnwrap(settingsSource.range(of: "struct SettingsView: View")?.lowerBound)
        let visibleSettingsSource = String(settingsSource[settingsViewStart...])
        let menuBarSource = try String(contentsOf: menuBarURL, encoding: .utf8)
        let syncSource = try String(contentsOf: syncServiceURL, encoding: .utf8)
        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)

        XCTAssertContainsVisibleControl("输入 Key", in: settingsSource)
        XCTAssertContainsVisibleControl("开启局域网剪贴板", in: visibleSettingsSource)
        XCTAssertTrue(visibleSettingsSource.contains("connectedPeerCount"))
        XCTAssertTrue(visibleSettingsSource.contains("connectedPeersTooltip"))
        XCTAssertTrue(settingsSource.contains("@Published private(set) var connectedPeerCount"))
        XCTAssertTrue(settingsSource.contains("@Published private(set) var connectedPeersTooltip"))
        XCTAssertFalse(
            settingsSource.contains("var connectedPeersTooltip: String {"),
            "悬浮提示必须读取后台维护的缓存字符串，不能在 hover 时临时计算"
        )
        XCTAssertTrue(syncSource.contains("DispatchQueue.global(qos: .utility).async"))
        XCTAssertTrue(syncSource.contains("state.setLocalDevice"))
        XCTAssertTrue(visibleSettingsSource.contains("Text(\"(\\(state.connectedPeerCount))\")"))
        XCTAssertTrue(visibleSettingsSource.contains("@State private var isConnectedPeersInfoVisible"))
        XCTAssertTrue(visibleSettingsSource.contains(".onHover { isHovering in"))
        XCTAssertTrue(visibleSettingsSource.contains("mainSettingsColumn"))
        XCTAssertTrue(visibleSettingsSource.contains(".popover("))
        XCTAssertTrue(visibleSettingsSource.contains("connectedPeersInfoPopover"))
        XCTAssertTrue(visibleSettingsSource.contains("Color(nsColor: .controlBackgroundColor)"))
        XCTAssertTrue(visibleSettingsSource.contains("Color(nsColor: .separatorColor)"))
        XCTAssertTrue(visibleSettingsSource.contains(".frame(width: 160, alignment: .leading)"))
        XCTAssertTrue(visibleSettingsSource.contains(".foregroundStyle(Color.accentColor)"))
        XCTAssertFalse(
            visibleSettingsSource.contains("HStack(alignment: .top, spacing: 8)"),
            "macOS 设备信息应该和 Windows 一样用浮窗，不应该再作为右侧并排列撑开菜单"
        )
        XCTAssertFalse(
            visibleSettingsSource.contains(".onTapGesture"),
            "设备信息应恢复鼠标移到数字上显示，不再点击显示"
        )
        XCTAssertFalse(
            visibleSettingsSource.contains(".overlay(alignment: .topTrailing)"),
            "设备信息不能再用覆盖浮层，否则容易被菜单窗口裁剪遮挡"
        )
        XCTAssertFalse(
            visibleSettingsSource.contains("connectedPeersInfoSidePanel"),
            "设备信息不能再作为设置面板内部的右侧框体，应该显示为独立浮窗"
        )
        XCTAssertFalse(
            visibleSettingsSource.contains("connectedPeersInfoPanel"),
            "设备信息不能再在下方内联展开，应该显示为独立浮窗"
        )
        XCTAssertFalse(
            visibleSettingsSource.contains(".help(state.connectedPeersTooltip)"),
            "macOS 原生 help tooltip 有系统延迟，数量悬浮信息必须使用自绘即时浮层"
        )
        XCTAssertFalse(
            visibleSettingsSource.contains("Toggle(isOn: sharingEnabledBinding) {\n                sharingToggleLabel\n            }\n            .help(state.connectedPeersTooltip)"),
            "设备信息提示应该只挂在数量上，避免整行开关都弹提示"
        )
        XCTAssertContainsVisibleControl("开机启动", in: visibleSettingsSource)
        XCTAssertContainsVisibleControl("ClipPlus", in: visibleSettingsSource)
        XCTAssertTrue(
            visibleSettingsSource.contains("AppVersion.display"),
            "设置界面的标题必须显示当前版本号，避免用户误跑旧版本时无法辨认"
        )
        XCTAssertFalse(
            appSource.contains("Window(AppVersion.settingsWindowTitle"),
            "状态栏 App 不能声明独立设置 Window，否则启动时会弹出 900x450 的默认窗口"
        )
        XCTAssertContainsVisibleControl("局域网剪贴板", in: visibleSettingsSource)
        XCTAssertContainsVisibleControl("退出 ClipPlus", in: visibleSettingsSource)
        XCTAssertTrue(visibleSettingsSource.contains(".accessibilityLabel(\"退出 ClipPlus\")"))
        XCTAssertContainsVisibleControl("by.YJY_hi", in: visibleSettingsSource)
        XCTAssertTrue(visibleSettingsSource.contains("isSharedKeyVisible"))
        XCTAssertTrue(visibleSettingsSource.contains("dismissSharedKeyEditor"))
        XCTAssertTrue(visibleSettingsSource.contains("sharedKeyDismissRequest"))
        XCTAssertTrue(visibleSettingsSource.contains("saveSharedKeyIfNeeded"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("eye.slash"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("eye"))
        XCTAssertTrue(visibleSettingsSource.contains("SharedKeyInputField("))
        XCTAssertTrue(visibleSettingsSource.contains("Link("))
        XCTAssertTrue(visibleSettingsSource.contains("https://github.com/nicelnicel"))
        XCTAssertTrue(visibleSettingsSource.contains("authorHomepageURL"))
        XCTAssertTrue(visibleSettingsSource.contains(".foregroundStyle(Color.accentColor)"))
        XCTAssertTrue(visibleSettingsSource.contains(".frame(width: 160)"))
        XCTAssertFalse(visibleSettingsSource.contains(".frame(width: 240)"))
        XCTAssertFalse(visibleSettingsSource.contains("请先设置共享 Key"))
        XCTAssertFalse(visibleSettingsSource.contains(".background(.orange"))
        XCTAssertFalse(
            visibleSettingsSource.contains("Toggle(\"开机启动\", isOn: startupEnabledBinding)\n\n            authorLink"),
            "作者链接不应该再作为开机启动下方的单独一行"
        )

        let infoBoxStart = try XCTUnwrap(visibleSettingsSource.range(of: "private var infoBox")?.lowerBound)
        let sharedKeyFieldDeclarationStart = try XCTUnwrap(
            visibleSettingsSource.range(of: "private var sharedKeyField")?.lowerBound
        )
        let infoBoxSource = String(visibleSettingsSource[infoBoxStart..<sharedKeyFieldDeclarationStart])
        XCTAssertTrue(infoBoxSource.contains("ZStack(alignment: .topTrailing)"), "信息框应该提供右上角布局")
        XCTAssertTrue(infoBoxSource.contains("Link(\"by.YJY_hi\""), "作者链接应该放在信息框里")
        XCTAssertTrue(infoBoxSource.contains("authorHomepageURL"), "信息框里的作者链接应该保持可点击")

        let disallowedVisibleLabels = [
            "状态",
            "保存 Key",
            "导出诊断包",
            "待确认设备",
            "允许",
            "可接收文件",
            "打开独立设置窗口",
            "请先设置共享 Key",
            "已设置",
            "未设置",
            "再次输入共享 Key",
            "作者 YJY"
        ]

        for label in disallowedVisibleLabels {
            XCTAssertFalse(visibleSettingsSource.contains(label), "SettingsView 不能显示复杂入口：\(label)")
            XCTAssertFalse(menuBarSource.contains(label), "MenuBarController 不能显示复杂入口：\(label)")
        }
        XCTAssertFalse(syncSource.contains("state.isPeerTrusted(message.senderDeviceId)"))
        XCTAssertTrue(syncSource.contains("recordConnectedPeer"))
        XCTAssertTrue(
            syncSource.contains("state.remoteConnectedPeerSummaries"),
            "发送逻辑应该把最近发现的设备 IP 作为单播目标，不能只依赖广播"
        )
    }

    func testSharedKeyEyeButtonKeepsFocusAndCursorAtEnd() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsViewURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/Settings/SettingsView.swift")
        let sharedKeyInputFieldURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/Settings/SharedKeyInputField.swift")
        let settingsSource = try String(contentsOf: settingsViewURL, encoding: .utf8)
        let sharedKeyInputFieldSource = try String(contentsOf: sharedKeyInputFieldURL, encoding: .utf8)
        let settingsViewStart = try XCTUnwrap(settingsSource.range(of: "struct SettingsView: View")?.lowerBound)
        let visibleSettingsSource = String(settingsSource[settingsViewStart...])

        XCTAssertFalse(
            visibleSettingsSource.contains("@FocusState"),
            "眼睛按钮不能依赖 SwiftUI 焦点切换，否则点击按钮会触发失焦保存并清空输入"
        )
        XCTAssertFalse(
            visibleSettingsSource.contains("TextField(state.sharedKeyFieldPrompt"),
            "显示/隐藏 Key 不能用 SwiftUI TextField 和 SecureField 互换，否则会丢失光标位置"
        )
        XCTAssertFalse(
            visibleSettingsSource.contains("SecureField(state.sharedKeyFieldPrompt"),
            "显示/隐藏 Key 不能用 SwiftUI TextField 和 SecureField 互换，否则会丢失光标位置"
        )
        XCTAssertTrue(sharedKeyInputFieldSource.contains("SharedKeyInputField: NSViewRepresentable"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("refusesFirstResponder = true"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("private let secureField = SharedKeySecureTextField()"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("private let plainField = SharedKeyPlainTextField()"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("focusActiveFieldAtEnd()"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("onVisibilityChanged"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("isHandlingVisibilityToggle"))
        XCTAssertTrue(
            sharedKeyInputFieldSource.contains("guard !isHandlingVisibilityToggle && !isCommittingAndHiding else")
        )
        XCTAssertTrue(sharedKeyInputFieldSource.contains("let currentText = fieldView.currentText"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("text: currentText"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("let nextVisibility = !parent.isVisible"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("syncTextFields"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("setVisible"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("parent.isVisible = false"))
        XCTAssertFalse(sharedKeyInputFieldSource.contains("installTextField"))
        XCTAssertFalse(sharedKeyInputFieldSource.contains("removeFromSuperview()"))
    }

    func testSharedKeyInputFieldCommitsWhenClickingOutsideIt() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sharedKeyInputFieldURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/Settings/SharedKeyInputField.swift")
        let sharedKeyInputFieldSource = try String(contentsOf: sharedKeyInputFieldURL, encoding: .utf8)

        XCTAssertTrue(sharedKeyInputFieldSource.contains("NSEvent.addLocalMonitorForEvents"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("matching: [.leftMouseDown, .rightMouseDown]"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("NSEvent.removeMonitor(mouseDownMonitor)"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("handleWindowMouseDown"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("guard !bounds.contains(clickLocation) else"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("commitFromOutsideClick"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("dismissRequest"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("applyDismissRequest"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("fieldView.clearFocus()"))
        XCTAssertTrue(
            sharedKeyInputFieldSource.contains("guard !isHandlingVisibilityToggle && !isCommittingAndHiding else"),
            "点击 checkbox 等输入框外部区域时，不能只等原生 end editing；必须主动提交、隐藏并清掉焦点"
        )
    }

    func testSharedKeyInputFieldHandlesMouseFocusAtEnd() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sharedKeyInputFieldURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/Settings/SharedKeyInputField.swift")
        let sharedKeyInputFieldSource = try String(contentsOf: sharedKeyInputFieldURL, encoding: .utf8)

        XCTAssertTrue(sharedKeyInputFieldSource.contains("override var acceptsFirstResponder: Bool"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("override func mouseDown(with event: NSEvent)"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("focusActiveFieldAtEnd()"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("selectInsertionPointAtEnd(in: textField)"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("DispatchQueue.main.async"))
    }

    func testSharedKeyEyeButtonUsesStableDirectPressHandling() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sharedKeyInputFieldURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/Settings/SharedKeyInputField.swift")
        let sharedKeyInputFieldSource = try String(contentsOf: sharedKeyInputFieldURL, encoding: .utf8)

        XCTAssertTrue(sharedKeyInputFieldSource.contains("SharedKeyVisibilityButton"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("onPress"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("pressVisibilityButton"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("pressVisibilityButton(self)"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("visibilityButton.performClick(nil)"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("override func accessibilityPerformPress() -> Bool"))
        XCTAssertTrue(sharedKeyInputFieldSource.contains("override func performClick(_ sender: Any?)"))
        XCTAssertFalse(
            sharedKeyInputFieldSource.contains("installTextField"),
            "显示/隐藏不能再通过销毁并重建输入框实现，否则焦点和光标会不稳定"
        )
        XCTAssertTrue(
            sharedKeyInputFieldSource.contains("guard !isHandlingVisibilityToggle && !isCommittingAndHiding else"),
            "小眼睛按钮 mouseDown 可能先触发输入框失焦，失焦保存逻辑必须识别这次切换，不能抢先隐藏并重建输入框"
        )
    }

    func testClipboardPollingDoesNotRunHeavyPasteboardWorkOnMainRunLoop() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let syncServiceURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/Sync/UdpTextSyncService.swift")
        let syncServiceSource = try String(contentsOf: syncServiceURL, encoding: .utf8)

        XCTAssertFalse(syncServiceSource.contains("Timer.scheduledTimer"))
        XCTAssertTrue(syncServiceSource.contains("DispatchSource.makeTimerSource"))
        XCTAssertTrue(syncServiceSource.contains("clipplus.mac.clipboard.poll"))
    }

    func testSettingsUIPanelDoesNotDependOnFormForMenuBarPresentation() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsViewURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/Settings/SettingsView.swift")
        let settingsSource = try String(contentsOf: settingsViewURL, encoding: .utf8)
        let settingsViewStart = try XCTUnwrap(settingsSource.range(of: "struct SettingsView: View")?.lowerBound)
        let visibleSettingsSource = String(settingsSource[settingsViewStart...])

        XCTAssertFalse(
            visibleSettingsSource.contains("Form {"),
            "MenuBarExtra 的窗口内容不能依赖 Form，否则点击状态栏图标时容易出现空白设置面板"
        )
    }

    func testMacStatusItemUsesAppKitControllerForReliableMenuBarClick() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/App/ClipPlusApp.swift")
        let statusBarControllerURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/MenuBar/StatusBarController.swift")
        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)
        let statusBarSource = try String(contentsOf: statusBarControllerURL, encoding: .utf8)

        XCTAssertTrue(appSource.contains("StatusBarController(state: state)"))
        XCTAssertFalse(
            appSource.contains("MenuBarExtra {"),
            "状态栏点击不能再依赖 SwiftUI MenuBarExtra；0.1.8 在真实安装后出现点击无响应"
        )
        XCTAssertFalse(
            appSource.contains("Window(AppVersion.settingsWindowTitle"),
            "设置窗口应该由显式窗口控制器承载，避免 SwiftUI 默认 Window 影响后台启动行为"
        )
        XCTAssertFalse(appSource.contains(".menuBarExtraStyle(.window)"))
        XCTAssertTrue(statusBarSource.contains("NSStatusBar.system.statusItem"))
        XCTAssertTrue(statusBarSource.contains("NSPopover()"))
        XCTAssertTrue(statusBarSource.contains("NSMenuDelegate"))
        XCTAssertTrue(statusBarSource.contains("popover.contentSize = NSSize(width: 180, height: 220)"))
        XCTAssertTrue(statusBarSource.contains("statusItem.menu = statusMenu"))
        XCTAssertTrue(statusBarSource.contains("statusMenu.delegate = self"))
        XCTAssertTrue(statusBarSource.contains("func menuWillOpen(_ menu: NSMenu)"))
        XCTAssertTrue(statusBarSource.contains("menu.cancelTrackingWithoutAnimation()"))
        XCTAssertTrue(statusBarSource.contains("popover.show(relativeTo: button.bounds"))
        XCTAssertFalse(statusBarSource.contains("button.action ="))
        XCTAssertFalse(
            statusBarSource.contains("button.sendAction(on:"),
            "状态栏按钮不能覆盖默认事件掩码，否则 Accessibility 的 AXPress 可能无法触发设置浮窗"
        )
        XCTAssertFalse(
            statusBarSource.contains("NSPanel("),
            "状态栏设置界面不能是普通 NSPanel，否则会显示成带标题栏的大窗口"
        )
    }

    func testMacUpdateVersionComparisonHandlesSemanticVersions() throws {
        XCTAssertLessThan(
            try XCTUnwrap(UpdateVersion("0.1.4")),
            try XCTUnwrap(UpdateVersion("v0.1.5"))
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(UpdateVersion("0.1.10")),
            try XCTUnwrap(UpdateVersion("0.1.9"))
        )
        XCTAssertEqual(try XCTUnwrap(UpdateVersion("v0.1.4")).description, "0.1.4")
        XCTAssertNil(UpdateVersion("dev"))
    }

    func testMacUpdateFetchesStaticReleaseManifestWithoutGitHubApiRateLimit() {
        XCTAssertEqual(
            GitHubReleaseClient.latestReleaseURL.absoluteString,
            "https://github.com/nicelnicel/ClipPlus/releases/latest/download/clipplus-update.json"
        )
        XCTAssertFalse(GitHubReleaseClient.latestReleaseURL.absoluteString.contains("api.github.com"))
    }

    func testMacUpdateSelectsDmgReleaseAssetAndRequiresDigest() throws {
        let releaseJSON = Data(
            """
            {
              "tag_name": "v0.1.5",
              "draft": false,
              "prerelease": false,
              "assets": [
                {
                  "name": "ClipPlus-Windows-x64-full.exe",
                  "browser_download_url": "https://example.com/windows.exe",
                  "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                  "size": 10
                },
                {
                  "name": "ClipPlus-macOS.dmg",
                  "browser_download_url": "https://example.com/ClipPlus-macOS.dmg",
                  "digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                  "size": 20
                }
              ]
            }
            """.utf8
        )

        let release = try GitHubReleaseClient.decodeRelease(from: releaseJSON)
        let asset = try GitHubReleaseClient.selectMacAsset(
            from: release,
            currentVersion: try XCTUnwrap(UpdateVersion("0.1.4"))
        )

        XCTAssertEqual(asset.version.description, "0.1.5")
        XCTAssertEqual(asset.name, "ClipPlus-macOS.dmg")
        XCTAssertEqual(asset.downloadURL.absoluteString, "https://example.com/ClipPlus-macOS.dmg")
        XCTAssertEqual(asset.sha256Hex, String(repeating: "b", count: 64))
        XCTAssertEqual(asset.size, 20)

        let missingDigestJSON = Data(
            """
            {
              "tag_name": "v0.1.5",
              "draft": false,
              "prerelease": false,
              "assets": [
                {
                  "name": "ClipPlus-macOS.dmg",
                  "browser_download_url": "https://example.com/ClipPlus-macOS.dmg",
                  "size": 20
                }
              ]
            }
            """.utf8
        )
        let missingDigestRelease = try GitHubReleaseClient.decodeRelease(from: missingDigestJSON)

        XCTAssertThrowsError(
            try GitHubReleaseClient.selectMacAsset(
                from: missingDigestRelease,
                currentVersion: try XCTUnwrap(UpdateVersion("0.1.4"))
            )
        ) { error in
            XCTAssertEqual(error as? UpdateError, .missingDigest)
        }
    }

    func testMacUpdateDownloaderVerifiesSha256() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let fileURL = temporaryDirectory.appendingPathComponent("payload.bin")
        try Data("clipplus update".utf8).write(to: fileURL)

        XCTAssertNoThrow(try UpdateDownloader.verifySha256(
            fileURL: fileURL,
            expectedHex: "6d117130cdf62d70ef384c91de7ef1de3c637afb3aef12df44fe61ba3b789b62"
        ))
        XCTAssertThrowsError(try UpdateDownloader.verifySha256(
            fileURL: fileURL,
            expectedHex: String(repeating: "0", count: 64)
        )) { error in
            XCTAssertEqual(error as? UpdateError, .sha256Mismatch)
        }
    }

    func testMacUpdateInstallerScriptPreservesSharedKeyAndRelaunchesApp() throws {
        let script = MacUpdateInstaller.makeInstallScript(
            dmgURL: URL(fileURLWithPath: "/tmp/ClipPlus-macOS.dmg"),
            appBundleURL: URL(fileURLWithPath: "/Applications/ClipPlus.app"),
            currentPID: 12345
        )

        XCTAssertTrue(script.contains("while kill -0 12345"))
        XCTAssertTrue(script.contains("hdiutil attach"))
        XCTAssertTrue(script.contains("clipplus.shared-key"))
        XCTAssertTrue(script.contains("ditto"))
        XCTAssertTrue(script.contains("codesign --force --deep --sign - \"$app_path\""))
        XCTAssertTrue(script.contains("codesign --verify --deep --strict \"$app_path\""))
        XCTAssertTrue(script.contains("open \"/Applications/ClipPlus.app\""))
    }

    func testMacSettingsUiContainsSimpleCheckUpdateButton() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsViewURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/Settings/SettingsView.swift")
        let settingsSource = try String(contentsOf: settingsViewURL, encoding: .utf8)

        XCTAssertTrue(settingsSource.contains("检查更新"))
        XCTAssertTrue(settingsSource.contains("检查中..."))
        XCTAssertTrue(settingsSource.contains("下载中"))
        XCTAssertTrue(settingsSource.contains("updateStatusMessage"))
        XCTAssertTrue(settingsSource.contains("已是最新版本"))
        XCTAssertFalse(settingsSource.contains("get: { updateAlertMessage != nil }"))
        XCTAssertFalse(settingsSource.contains("自动检查更新"))
    }

    func testMacMenuBarIconUsesAdaptiveTemplateImage() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceURL = repositoryRoot.appendingPathComponent("apps/mac/Sources/ClipPlusMac/App/ClipPlusApp.swift")
        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)
        let systemIconRange = try XCTUnwrap(
            appSource.range(of: #"systemSymbolName: "doc.on.clipboard""#)
        )
        let bitmapIconRange = try XCTUnwrap(appSource.range(of: #"ClipPlusMenuBar"#))

        XCTAssertTrue(
            appSource.contains("image.isTemplate = true"),
            "macOS 菜单栏图标必须是 template 图标，才能在浅色/深色菜单栏背景上自动反色显示"
        )
        XCTAssertLessThan(
            systemIconRange.lowerBound,
            bitmapIconRange.lowerBound,
            "菜单栏小图标应优先使用系统 template 图标，深色 PNG 只能作为兜底资源"
        )
    }

    func testMacPackageCreatesRegularDockVisibleApp() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let packageScriptURL = repositoryRoot.appendingPathComponent("scripts/dev/package-mac-app.sh")
        let packageScript = try String(contentsOf: packageScriptURL, encoding: .utf8)

        XCTAssertFalse(
            packageScript.contains("<key>LSUIElement</key>"),
            "ClipPlus 需要作为普通 Dock 可见应用运行，避免菜单栏图标被系统隐藏后用户找不到入口"
        )
    }

    func testDockReopenShowsSettingsWindow() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceURL = repositoryRoot.appendingPathComponent("apps/mac/Sources/ClipPlusMac/App/ClipPlusApp.swift")
        let appDelegateURL = repositoryRoot.appendingPathComponent("apps/mac/Sources/ClipPlusMac/App/ClipPlusAppDelegate.swift")
        let settingsWindowControllerURL = repositoryRoot
            .appendingPathComponent("apps/mac/Sources/ClipPlusMac/Settings/SettingsWindowController.swift")
        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)
        let appDelegateSource = (try? String(contentsOf: appDelegateURL, encoding: .utf8)) ?? ""
        let settingsWindowControllerSource = (try? String(contentsOf: settingsWindowControllerURL, encoding: .utf8)) ?? ""

        XCTAssertTrue(FileManager.default.fileExists(atPath: appDelegateURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsWindowControllerURL.path))
        XCTAssertTrue(appSource.contains("@NSApplicationDelegateAdaptor(ClipPlusAppDelegate.self)"))
        XCTAssertTrue(appSource.contains("settingsWindowController = SettingsWindowController(state: state)"))
        XCTAssertTrue(appSource.contains("func showSettingsWindow()"))
        XCTAssertTrue(appSource.contains("appDelegate.configure(appModel: appModel)"))
        XCTAssertTrue(appDelegateSource.contains("applicationDidFinishLaunching"))
        XCTAssertTrue(appDelegateSource.contains("applicationShouldHandleReopen"))
        XCTAssertTrue(appDelegateSource.contains("appModel?.showSettingsWindow()"))
        XCTAssertTrue(settingsWindowControllerSource.contains("NSHostingController(rootView: SettingsView(state: state))"))
        XCTAssertTrue(settingsWindowControllerSource.contains("NSWindow(contentViewController: hostingController)"))
        XCTAssertTrue(settingsWindowControllerSource.contains("NSApp.activate(ignoringOtherApps: true)"))
        XCTAssertTrue(settingsWindowControllerSource.contains("window.makeKeyAndOrderFront(nil)"))
        XCTAssertTrue(settingsWindowControllerSource.contains("window.isReleasedWhenClosed = false"))
    }

    func testSharedAppIconAssetsAreConfiguredForPackaging() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let mainPngURL = repositoryRoot.appendingPathComponent("assets/app-icon/clipplus-icon-1024.png")
        let macIconURL = repositoryRoot.appendingPathComponent("apps/mac/Resources/ClipPlus.icns")
        let macMenuBarIconURL = repositoryRoot.appendingPathComponent("apps/mac/Resources/ClipPlusMenuBar.png")
        let windowsIconURL = repositoryRoot.appendingPathComponent("apps/windows/ClipPlus.Windows/Resources/ClipPlus.ico")
        let packageScriptURL = repositoryRoot.appendingPathComponent("scripts/dev/package-mac-app.sh")
        let dmgScriptURL = repositoryRoot.appendingPathComponent("scripts/dev/package-mac-dmg.sh")
        let versionURL = repositoryRoot.appendingPathComponent("VERSION")
        let bumpVersionScriptURL = repositoryRoot.appendingPathComponent("scripts/dev/bump-version.sh")
        let checkReleaseVersionScriptURL = repositoryRoot.appendingPathComponent("scripts/dev/check-release-version.sh")
        let updateManifestScriptURL = repositoryRoot.appendingPathComponent("scripts/dev/generate-update-manifest.sh")
        let windowsRuntimeDependentScriptURL = repositoryRoot
            .appendingPathComponent("scripts/dev/publish-windows-runtime-dependent.ps1")
        let appSourceURL = repositoryRoot.appendingPathComponent("apps/mac/Sources/ClipPlusMac/App/ClipPlusApp.swift")
        let workflowURL = repositoryRoot.appendingPathComponent(".github/workflows/ci.yml")
        let readmeURL = repositoryRoot.appendingPathComponent("README.md")

        XCTAssertTrue(FileManager.default.fileExists(atPath: mainPngURL.path), "缺少同源主图 PNG")
        XCTAssertTrue(FileManager.default.fileExists(atPath: macIconURL.path), "缺少 macOS icns 图标")
        XCTAssertTrue(FileManager.default.fileExists(atPath: macMenuBarIconURL.path), "缺少 macOS 菜单栏图标")
        XCTAssertTrue(FileManager.default.fileExists(atPath: windowsIconURL.path), "缺少 Windows ico 图标")
        XCTAssertTrue(FileManager.default.fileExists(atPath: versionURL.path), "Release 版本号必须有唯一 VERSION 文件")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bumpVersionScriptURL.path), "Release 前必须有版本递增脚本")
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkReleaseVersionScriptURL.path), "Release 上传前必须校验 tag 和 VERSION")
        XCTAssertTrue(FileManager.default.fileExists(atPath: updateManifestScriptURL.path), "Release 必须生成静态更新清单")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dmgScriptURL.path), "macOS 发布产物应该提供 DMG 打包脚本")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: windowsRuntimeDependentScriptURL.path),
            "Windows 应该提供依赖系统运行环境的小体积发布脚本"
        )
        let releaseVersion = try String(contentsOf: versionURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotNil(
            releaseVersion.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression),
            "VERSION 必须使用 MAJOR.MINOR.PATCH"
        )

        let packageScript = try String(contentsOf: packageScriptURL, encoding: .utf8)
        XCTAssertTrue(packageScript.contains("CFBundleIconFile"))
        XCTAssertTrue(packageScript.contains("ClipPlus.icns"))
        XCTAssertTrue(packageScript.contains("version_file=\"$repo_root/VERSION\""))
        XCTAssertTrue(packageScript.contains("app_version="))
        XCTAssertTrue(packageScript.contains("/private/tmp/ClipPlusMac.app"))
        XCTAssertTrue(packageScript.contains("target/macos-build.noindex/ClipPlus.app"))
        XCTAssertFalse(packageScript.contains("app_dir=\"$repo_root/target/macos/ClipPlus.app\""))
        XCTAssertFalse(packageScript.contains("<string>0.1.0</string>"))
        XCTAssertTrue(packageScript.contains("legacy_indexed_app=\"$repo_root/target/macos/ClipPlus.app\""))
        XCTAssertTrue(packageScript.contains("installed_app=\"/Applications/ClipPlus.app\""))
        XCTAssertTrue(packageScript.contains("unregister_app \"$installed_app\""))
        XCTAssertTrue(packageScript.contains("-u \"$candidate\""))
        XCTAssertTrue(packageScript.contains("clipplus.shared-key"))
        XCTAssertTrue(packageScript.contains("preserved_shared_key"))
        XCTAssertTrue(packageScript.contains("codesign --force --deep --sign - \"$installed_app\""))
        XCTAssertTrue(packageScript.contains("codesign --verify --deep --strict \"$installed_app\""))

        let dmgScript = try String(contentsOf: dmgScriptURL, encoding: .utf8)
        XCTAssertTrue(dmgScript.contains("ClipPlus-macOS.dmg"))
        XCTAssertTrue(dmgScript.contains("target/macos-build.noindex/ClipPlus.app"))
        XCTAssertTrue(dmgScript.contains("hdiutil create"))
        XCTAssertTrue(dmgScript.contains("-format UDZO"))
        XCTAssertTrue(dmgScript.contains("-srcfolder \"$app_dir\""))

        let bumpVersionScript = try String(contentsOf: bumpVersionScriptURL, encoding: .utf8)
        XCTAssertTrue(bumpVersionScript.contains("VERSION"))
        XCTAssertTrue(bumpVersionScript.contains("Cargo.toml"))
        XCTAssertTrue(bumpVersionScript.contains("Cargo.lock"))
        XCTAssertTrue(bumpVersionScript.contains("ClipPlus.Windows.csproj"))
        XCTAssertTrue(bumpVersionScript.contains("CoreBridge.swift"))
        XCTAssertTrue(bumpVersionScript.contains("CoreBridge.cs"))

        let checkReleaseVersionScript = try String(contentsOf: checkReleaseVersionScriptURL, encoding: .utf8)
        XCTAssertTrue(checkReleaseVersionScript.contains("Release tag"))
        XCTAssertTrue(checkReleaseVersionScript.contains("VERSION"))
        XCTAssertTrue(checkReleaseVersionScript.contains("Cargo.lock"))

        let updateManifestScript = try String(contentsOf: updateManifestScriptURL, encoding: .utf8)
        XCTAssertTrue(updateManifestScript.contains("clipplus-update.json"))
        XCTAssertTrue(updateManifestScript.contains("ClipPlus-macOS.dmg"))
        XCTAssertTrue(updateManifestScript.contains("ClipPlus-Windows-x64-full.exe"))
        XCTAssertTrue(updateManifestScript.contains("ClipPlus-Windows-x64-runtime-dependent.exe"))
        XCTAssertTrue(updateManifestScript.contains("browser_download_url"))
        XCTAssertTrue(updateManifestScript.contains("sha256:"))

        let windowsRuntimeDependentScript = try String(contentsOf: windowsRuntimeDependentScriptURL, encoding: .utf8)
        XCTAssertTrue(windowsRuntimeDependentScript.contains("--self-contained false"))
        XCTAssertTrue(windowsRuntimeDependentScript.contains("/p:PublishSingleFile=true"))
        XCTAssertFalse(windowsRuntimeDependentScript.contains("EnableCompressionInSingleFile"))
        XCTAssertTrue(windowsRuntimeDependentScript.contains("target\\windows-runtime-dependent"))

        let workflowSource = try String(contentsOf: workflowURL, encoding: .utf8)
        XCTAssertTrue(workflowSource.contains("./scripts/dev/package-mac-dmg.sh"))
        XCTAssertTrue(workflowSource.contains("path: target/macos/ClipPlus-macOS.dmg"))
        XCTAssertTrue(workflowSource.contains("ClipPlus-Windows-x64-full.exe"))
        XCTAssertTrue(workflowSource.contains("ClipPlus-Windows-x64-runtime-dependent.exe"))
        XCTAssertTrue(workflowSource.contains("./scripts/dev/generate-update-manifest.sh"))
        XCTAssertTrue(workflowSource.contains("clipplus-update.json"))
        XCTAssertTrue(workflowSource.contains("Smoke test Windows x64 full exe"))
        XCTAssertTrue(workflowSource.contains("Smoke test Windows x64 runtime-dependent exe"))
        XCTAssertTrue(workflowSource.contains("./scripts/dev/check-release-version.sh \"$tag\""))
        XCTAssertFalse(
            workflowSource.contains("tags:\n      - \"v*\""),
            "Release 产物由本地发版脚本上传，tag push 不应再触发 CI 覆盖 Release assets"
        )
        XCTAssertFalse(
            workflowSource.contains("startsWith(github.ref, 'refs/tags/v')"),
            "Release job 只能由手动 workflow_dispatch 触发，避免覆盖本地上传产物"
        )
        XCTAssertTrue(workflowSource.contains("github.event_name == 'workflow_dispatch' && github.event.inputs.release_tag != ''"))

        let readmeSource = try String(contentsOf: readmeURL, encoding: .utf8)
        XCTAssertTrue(readmeSource.contains("ClipPlus-macOS.dmg"))
        XCTAssertTrue(readmeSource.contains("ClipPlus-Windows-x64-full.exe"))
        XCTAssertTrue(readmeSource.contains("ClipPlus-Windows-x64-runtime-dependent.exe"))
        XCTAssertTrue(readmeSource.contains(".NET 8 Desktop Runtime"))

        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)
        XCTAssertTrue(appSource.contains("ClipPlusMenuBar"))
        XCTAssertTrue(appSource.contains("sharedKeyInput: storedSettings.sharedKeyInput"))

        let sharedKeyVaultSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("apps/mac/Sources/ClipPlusMac/Settings/SharedKeyVault.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(sharedKeyVaultSource.contains("FileSharedKeyVault"))
        XCTAssertTrue(sharedKeyVaultSource.contains("clipplus.shared-key"))
        XCTAssertFalse(sharedKeyVaultSource.contains("KeychainSharedKeyVault"))
        XCTAssertFalse(sharedKeyVaultSource.contains("Security"))
        XCTAssertFalse(sharedKeyVaultSource.contains("LAContext"))
    }

    func testMissingKeyRequiresSetupWhenSharingDisabled() {
        let state = SettingsState(
            sharedKeyConfigured: false,
            sharingEnabled: false,
            startupEnabled: false
        )

        XCTAssertTrue(state.requiresKeySetup)
    }

    func testDefaultStateMatchesInitialAppConfiguration() {
        let state = SettingsState()

        XCTAssertFalse(state.sharedKeyConfigured)
        XCTAssertTrue(state.sharingEnabled)
        XCTAssertFalse(state.startupEnabled)
        XCTAssertTrue(state.requiresKeySetup)
    }

    func testSharedKeyStoresOnlyDerivedGroupIdentifier() throws {
        let state = SettingsState()
        var persistedGroupId: String?
        state.sharedGroupIdChanged = { persistedGroupId = $0 }

        try state.updateSharedKey("clipplus-test-key", confirmation: "clipplus-test-key")

        XCTAssertTrue(state.sharedKeyConfigured)
        XCTAssertEqual(state.sharedGroupId, expectedGroupId(for: "clipplus-test-key"))
        XCTAssertFalse(state.sharedGroupId.contains("clipplus-test-key"))
        XCTAssertEqual(persistedGroupId, expectedGroupId(for: "clipplus-test-key"))
    }

    func testMacSharedKeySaveUsesBackgroundPreparationAndDiscoveryRefresh() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsViewSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("apps/mac/Sources/ClipPlusMac/Settings/SettingsView.swift"),
            encoding: .utf8
        )
        let syncServiceSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("apps/mac/Sources/ClipPlusMac/Sync/UdpTextSyncService.swift"),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("apps/mac/Sources/ClipPlusMac/App/ClipPlusApp.swift"),
            encoding: .utf8
        )
        let saveStart = try XCTUnwrap(settingsViewSource.range(of: "private func saveSharedKeyIfNeeded()")?.lowerBound)
        let saveEnd = try XCTUnwrap(settingsViewSource.range(of: "private func checkForUpdates()")?.lowerBound)
        let saveSource = String(settingsViewSource[saveStart..<saveEnd])

        XCTAssertTrue(settingsViewSource.contains("PreparedSharedKeyUpdate"))
        XCTAssertTrue(settingsViewSource.contains("prepareSharedKeyUpdate"))
        XCTAssertTrue(settingsViewSource.contains("applySharedKeyUpdate"))
        XCTAssertTrue(saveSource.contains("Task.detached(priority: .utility)"))
        XCTAssertFalse(saveSource.contains("try state.updateSharedKey("))
        XCTAssertTrue(syncServiceSource.contains("scheduleDiscoveryRefresh"))
        XCTAssertTrue(syncServiceSource.contains("asyncAfter"))
        XCTAssertTrue(syncServiceSource.contains("resetPeerDiscovery"))
        XCTAssertTrue(appSource.contains("scheduleDiscoveryRefresh"))
    }

    func testCoreBridgeDerivesGroupIdWhenFFILibraryIsAvailable() {
        let ffiLibraryPath = ProcessInfo.processInfo.environment["CLIPPLUS_FFI_LIBRARY_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let groupId = CoreBridge().deriveGroupId(for: "clipplus-test-key") else {
            if let ffiLibraryPath, !ffiLibraryPath.isEmpty {
                XCTFail("Expected CoreBridge to load FFI library from CLIPPLUS_FFI_LIBRARY_PATH: \(ffiLibraryPath)")
            }

            return
        }

        XCTAssertEqual(groupId, "21YR2N3_wcdRPmEMLiuLMA")
    }

    func testMismatchedSharedKeyConfirmationFails() {
        let state = SettingsState()

        XCTAssertThrowsError(try state.updateSharedKey("clipplus-test-key", confirmation: "other-key"))
        XCTAssertFalse(state.sharedKeyConfigured)
        XCTAssertTrue(state.requiresKeySetup)
    }

    func testPendingPeerMustBeApprovedBeforeSync() {
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        )

        state.markPeerPending(deviceId: "windows-device", deviceName: "Windows 11")

        XCTAssertEqual(state.pendingPeerCount, 1)
        XCTAssertFalse(state.isPeerTrusted("windows-device"))

        state.approvePendingPeers()

        XCTAssertEqual(state.pendingPeerCount, 0)
        XCTAssertTrue(state.isPeerTrusted("windows-device"))
    }

    func testConfiguredKeyAllowsPublishingClipboardContentWithoutPeerApproval() {
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        )

        state.markPeerPending(deviceId: "windows-device", deviceName: "Windows 11")

        XCTAssertTrue(state.canPublishClipboardContent)
        XCTAssertEqual(state.trustedPeerCount, 0)
    }

    func testConnectedPeersTrackRecentDevicesForStatusTooltip() {
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        )
        let now = Date()

        state.setLocalDevice(
            deviceId: "mac-device",
            deviceName: "MacBook",
            ipAddress: "10.211.55.2"
        )
        state.recordConnectedPeer(
            deviceId: "windows-device",
            deviceName: "Windows 11",
            ipAddress: "10.211.55.3",
            now: now
        )

        XCTAssertEqual(state.connectedPeerCount, 2)
        XCTAssertEqual(state.connectedPeerSummaries.map(\.deviceName), ["MacBook", "Windows 11"])
        XCTAssertEqual(
            state.connectedPeersTooltip,
            "机器名：MacBook（本机）\nIP：10.211.55.2\n\n机器名：Windows 11\nIP：10.211.55.3"
        )
        XCTAssertTrue(state.connectedPeersTooltip.contains("机器名："))
        XCTAssertTrue(state.connectedPeersTooltip.contains("IP："))

        state.purgeExpiredConnectedPeers(now: now.addingTimeInterval(16))

        XCTAssertEqual(state.connectedPeerCount, 1)
        XCTAssertEqual(state.connectedPeerSummaries.first?.deviceName, "MacBook")
        XCTAssertTrue(state.remoteConnectedPeerSummaries.isEmpty)
        XCTAssertEqual(
            state.connectedPeersTooltip,
            "机器名：MacBook（本机）\nIP：10.211.55.2"
        )
    }

    func testPendingPeerSummariesAreSortedAndAllowSingleApproval() {
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        )

        state.markPeerPending(deviceId: "z-device", deviceName: "Windows")
        state.markPeerPending(deviceId: "a-device", deviceName: "MacBook")

        XCTAssertEqual(state.pendingPeerSummaries.map(\.deviceName), ["MacBook", "Windows"])

        state.approvePendingPeer(deviceId: "a-device")

        XCTAssertEqual(state.pendingPeerCount, 1)
        XCTAssertTrue(state.isPeerTrusted("a-device"))
        XCTAssertFalse(state.isPeerTrusted("z-device"))
    }

    func testRepeatedTrustForAlreadyTrustedPeerDoesNotRewriteStatus() {
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        )

        XCTAssertTrue(state.trustPeer(deviceId: "windows-device", deviceName: "Windows"))
        state.lastStatusMessage = "稳定状态"

        XCTAssertFalse(state.trustPeer(deviceId: "windows-device", deviceName: "Windows"))

        XCTAssertEqual(state.trustedPeerCount, 1)
        XCTAssertEqual(state.lastStatusMessage, "稳定状态")
    }

    func testClipPlusMessageRoundTripsTextPayload() throws {
        let message = ClipPlusMessage.text(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            text: "hello from mac"
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .text)
        XCTAssertEqual(decoded.protocolVersion, 1)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.text, "hello from mac")
    }

    func testCoreBridgeCreatesTextMessageJsonWhenFfiLibraryIsAvailable() throws {
        let json = try XCTUnwrap(CoreBridge().createTextMessageJSON(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            text: "hello from ffi"
        ))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .text)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.senderDeviceName, "Mac")
        XCTAssertEqual(decoded.text, "hello from ffi")
    }

    func testCoreBridgeCreatesHelloMessageJsonWhenFfiLibraryIsAvailable() throws {
        let json = try XCTUnwrap(CoreBridge().createHelloMessageJSON(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac"
        ))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .hello)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.senderDeviceName, "Mac")
    }

    func testCoreBridgeCreatesTrustMessageJsonWhenFfiLibraryIsAvailable() throws {
        let json = try XCTUnwrap(CoreBridge().createTrustMessageJSON(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            approvedDeviceId: "windows-device"
        ))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .trust)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.approvedDeviceId, "windows-device")
    }

    func testClipPlusMessageRoundTripsInlinePngImagePayload() throws {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let message = try XCTUnwrap(ClipPlusMessage.image(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            pngData: pngData
        ))

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .image)
        XCTAssertEqual(decoded.protocolVersion, 1)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.imageByteSize, pngData.count)
        XCTAssertEqual(decoded.imageBase64, pngData.base64EncodedString())
        XCTAssertEqual(decoded.decodedImageData, pngData)
        XCTAssertEqual(
            decoded.imageContentHash,
            "4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6"
        )
    }

    func testClipPlusMessageRoundTripsDirectImageOfferPayloadWithoutInlineData() throws {
        let pngData = Data(repeating: 0xAB, count: ClipPlusMessage.maxInlineImageBytes + 16)
        let message = ClipPlusMessage.imageOffer(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            transferId: "image-transfer-1",
            pngData: pngData,
            archivePort: 47_632
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .imageOffer)
        XCTAssertEqual(decoded.protocolVersion, 1)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.transferId, "image-transfer-1")
        XCTAssertEqual(decoded.transferFormat, .directTree)
        XCTAssertEqual(decoded.archivePort, 47_632)
        XCTAssertEqual(decoded.imageByteSize, pngData.count)
        XCTAssertEqual(decoded.imageBase64, nil)
        XCTAssertEqual(decoded.decodedImageData, nil)
        XCTAssertEqual(
            decoded.imageContentHash,
            "e5a22cfa04e9800c1b7c805736d6ba84b8f76fe9c5aabc203896966aab53009d"
        )
    }

    func testCoreBridgeCreatesImageMessageJsonWhenFfiLibraryIsAvailable() throws {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let json = try XCTUnwrap(CoreBridge().createImageMessageJSON(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            pngData: pngData
        ))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .image)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.imageByteSize, pngData.count)
        XCTAssertEqual(decoded.imageBase64, pngData.base64EncodedString())
        XCTAssertEqual(
            decoded.imageContentHash,
            "4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6"
        )
    }

    func testCoreBridgeCreatesImageOfferMessageJsonWhenFfiLibraryIsAvailable() throws {
        let pngData = Data(repeating: 0xAB, count: ClipPlusMessage.maxInlineImageBytes + 16)
        let json = try XCTUnwrap(CoreBridge().createImageOfferMessageJSON(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            transferId: "image-transfer-1",
            pngData: pngData,
            archivePort: 47_632
        ))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .imageOffer)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.transferId, "image-transfer-1")
        XCTAssertEqual(decoded.transferFormat, .directTree)
        XCTAssertEqual(decoded.archivePort, 47_632)
        XCTAssertEqual(decoded.imageByteSize, pngData.count)
        XCTAssertEqual(decoded.imageBase64, nil)
        XCTAssertEqual(
            decoded.imageContentHash,
            "e5a22cfa04e9800c1b7c805736d6ba84b8f76fe9c5aabc203896966aab53009d"
        )
    }

    func testImageContentHasherMatchesRustImageHash() {
        let pngData = Data(repeating: 0xAB, count: ClipPlusMessage.maxInlineImageBytes + 16)

        XCTAssertEqual(
            ImageContentHasher.sha256Hex(pngData),
            "e5a22cfa04e9800c1b7c805736d6ba84b8f76fe9c5aabc203896966aab53009d"
        )
    }

    func testClipPlusMessageRoundTripsTrustPayload() throws {
        let message = ClipPlusMessage.trust(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            approvedDeviceId: "windows-device"
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .trust)
        XCTAssertEqual(decoded.protocolVersion, 1)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.approvedDeviceId, "windows-device")
    }

    func testClipPlusMessageRoundTripsFileOfferPayloadWithoutLocalPaths() throws {
        let item = FileTransferItem(
            relativePath: "Reports/Q1.txt",
            byteSize: 12,
            isDirectory: false
        )
        let message = ClipPlusMessage.fileOffer(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            transferId: "transfer-1",
            files: [item],
            archivePort: 47_632
        )

        let data = try JSONEncoder().encode(message)
        let json = String(data: data, encoding: .utf8) ?? ""
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .fileOffer)
        XCTAssertEqual(decoded.transferId, "transfer-1")
        XCTAssertEqual(decoded.transferFormat, .directTree)
        XCTAssertEqual(decoded.archivePort, 47_632)
        XCTAssertEqual(decoded.files, [item])
        XCTAssertFalse(json.contains("/Users/"))
        XCTAssertFalse(json.contains("C:\\\\"))
    }

    func testCoreBridgeCreatesFileOfferMessageJsonWhenFfiLibraryIsAvailable() throws {
        let item = FileTransferItem(
            relativePath: "Reports/Q1.txt",
            byteSize: 12,
            isDirectory: false
        )
        let json = try XCTUnwrap(CoreBridge().createFileOfferMessageJSON(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            transferId: "transfer-1",
            files: [item],
            archivePort: 47_632
        ))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ClipPlusMessage.self, from: data)

        XCTAssertEqual(decoded.kind, .fileOffer)
        XCTAssertEqual(decoded.groupId, "group-1")
        XCTAssertEqual(decoded.senderDeviceId, "mac-device")
        XCTAssertEqual(decoded.transferId, "transfer-1")
        XCTAssertEqual(decoded.transferFormat, .directTree)
        XCTAssertEqual(decoded.archivePort, 47_632)
        XCTAssertEqual(decoded.files, [item])
        XCTAssertFalse(json.contains("/Users/"))
        XCTAssertFalse(json.contains("C:\\\\"))
    }

    func testRemoteFileTransferGateRejectsInFlightAndCompletedDuplicates() {
        let gate = RemoteFileTransferGate()

        XCTAssertTrue(gate.canAcceptOffer("transfer-a"))
        XCTAssertTrue(gate.begin("transfer-a"))
        XCTAssertFalse(gate.canAcceptOffer("transfer-a"))
        XCTAssertFalse(gate.begin("transfer-a"))

        gate.complete("transfer-a")

        XCTAssertFalse(gate.canAcceptOffer("transfer-a"))
        XCTAssertFalse(gate.begin("transfer-a"))
    }

    func testRemoteFileTransferGateAllowsRetryAfterFailure() {
        let gate = RemoteFileTransferGate()

        XCTAssertTrue(gate.begin("transfer-a"))
        gate.fail("transfer-a")

        XCTAssertTrue(gate.canAcceptOffer("transfer-a"))
        XCTAssertTrue(gate.begin("transfer-a"))
    }

    func testRemoteClipboardReceiveGuardSuppressesSingleImageFileAfterRecentImageFromSameDevice() {
        let guardWindow: TimeInterval = 15
        let guardState = RemoteClipboardReceiveGuard(imageFileSuppressionInterval: guardWindow)
        let imageTime = Date(timeIntervalSince1970: 1_000)
        let imageFile = FileTransferItem(relativePath: "wechat-image.png", byteSize: 12_881, isDirectory: false)

        guardState.recordRemoteImage(senderDeviceId: "windows-device", now: imageTime)

        XCTAssertTrue(guardState.shouldSuppressFileOfferAfterRecentImage(
            senderDeviceId: "windows-device",
            files: [imageFile],
            now: imageTime.addingTimeInterval(9)
        ))
        XCTAssertFalse(guardState.shouldSuppressFileOfferAfterRecentImage(
            senderDeviceId: "other-device",
            files: [imageFile],
            now: imageTime.addingTimeInterval(9)
        ))
        XCTAssertFalse(guardState.shouldSuppressFileOfferAfterRecentImage(
            senderDeviceId: "windows-device",
            files: [FileTransferItem(relativePath: "note.txt", byteSize: 42, isDirectory: false)],
            now: imageTime.addingTimeInterval(9)
        ))
        XCTAssertFalse(guardState.shouldSuppressFileOfferAfterRecentImage(
            senderDeviceId: "windows-device",
            files: [imageFile],
            now: imageTime.addingTimeInterval(guardWindow + 1)
        ))
    }

    func testRemoteFileOfferCanRequestReceive() {
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        )
        var requestedTransferId: String?
        state.remoteFileReceiveRequested = { requestedTransferId = $0 }

        state.updateRemoteFileOffer(RemoteFileOfferSummary(
            transferId: "transfer-1",
            sourceDeviceId: "windows-device",
            sourceDeviceName: "Windows",
            sourceHost: "10.211.55.3",
            fileCount: 2,
            totalBytes: 24
        ))

        XCTAssertEqual(state.remoteFileOffer?.displayTitle, "Windows：2 个文件可接收")
        XCTAssertTrue(state.hasRemoteFileOffer)
        XCTAssertEqual(requestedTransferId, "transfer-1")

        state.requestRemoteFileReceive()

        XCTAssertEqual(requestedTransferId, "transfer-1")
    }

    func testRemoteFileOfferCanAutoRequestReceiveForE2EAutomation() {
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        )
        var requestedTransferId: String?
        state.remoteFileReceiveRequested = { requestedTransferId = $0 }

        state.updateRemoteFileOffer(
            RemoteFileOfferSummary(
                transferId: "transfer-auto",
                sourceDeviceId: "windows-device",
                sourceDeviceName: "Windows",
                sourceHost: "10.211.55.3",
                fileCount: 1,
                totalBytes: 12
            ),
            autoRequestReceive: true
        )

        XCTAssertEqual(requestedTransferId, "transfer-auto")
    }

    func testFileTransferArchiveWritesZipEntriesForFilesAndDirectories() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = temporaryDirectory.appendingPathComponent("source", isDirectory: true)
        let nestedDirectory = sourceDirectory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try "alpha".write(to: sourceDirectory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "beta".write(to: nestedDirectory.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let archiveURL = temporaryDirectory.appendingPathComponent("files.zip")
        try FileTransferArchive.writeZip(
            sourceURLs: [sourceDirectory.appendingPathComponent("a.txt"), nestedDirectory],
            to: archiveURL
        )

        let extractedDirectory = temporaryDirectory.appendingPathComponent("unzipped", isDirectory: true)
        try FileManager.default.createDirectory(at: extractedDirectory, withIntermediateDirectories: true)
        try unzip(archiveURL, to: extractedDirectory)

        let a = try String(contentsOf: extractedDirectory.appendingPathComponent("a.txt"), encoding: .utf8)
        let b = try String(contentsOf: extractedDirectory.appendingPathComponent("Nested/b.txt"), encoding: .utf8)
        XCTAssertEqual(a, "alpha")
        XCTAssertEqual(b, "beta")
    }

    func testCoreBridgeWritesFileTransferArchiveWhenFfiLibraryIsAvailable() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = temporaryDirectory.appendingPathComponent("source", isDirectory: true)
        let nestedDirectory = sourceDirectory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try "alpha".write(to: sourceDirectory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "beta".write(to: nestedDirectory.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let archiveURL = temporaryDirectory.appendingPathComponent("core-files.zip")
        XCTAssertTrue(CoreBridge().writeFileArchiveZip(
            sourcePaths: [sourceDirectory.appendingPathComponent("a.txt").path, nestedDirectory.path],
            archivePath: archiveURL.path
        ))

        let extractedDirectory = temporaryDirectory.appendingPathComponent("core-unzipped", isDirectory: true)
        try FileManager.default.createDirectory(at: extractedDirectory, withIntermediateDirectories: true)
        try unzip(archiveURL, to: extractedDirectory)

        XCTAssertEqual(
            try String(contentsOf: extractedDirectory.appendingPathComponent("a.txt"), encoding: .utf8),
            "alpha"
        )
        XCTAssertEqual(
            try String(contentsOf: extractedDirectory.appendingPathComponent("Nested/b.txt"), encoding: .utf8),
            "beta"
        )
    }

    func testCoreBridgeServesFileArchiveToSocketWhenFfiLibraryIsAvailable() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let sourceURL = temporaryDirectory.appendingPathComponent("source.txt")
        try "served from mac ffi socket".write(to: sourceURL, atomically: true, encoding: .utf8)
        let archiveURL = temporaryDirectory.appendingPathComponent("served.zip")
        let listener = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(listener, 0)
        defer { Darwin.close(listener) }
        var reuse: Int32 = 1
        XCTAssertEqual(Darwin.setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)), 0)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(listener, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bindResult, 0)
        XCTAssertEqual(Darwin.listen(listener, 1), 0)
        var localAddress = sockaddr_in()
        var localAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &localAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.getsockname(listener, sockaddrPointer, &localAddressLength)
            }
        }
        XCTAssertEqual(nameResult, 0)
        let port = Int(UInt16(bigEndian: localAddress.sin_port))
        let servedExpectation = expectation(description: "archive served")
        var served: UInt64 = 0
        DispatchQueue.global().async {
            let client = Darwin.accept(listener, nil, nil)
            if client >= 0 {
                defer { Darwin.close(client) }
                served = CoreBridge().serveFileArchive(
                    socketDescriptor: client,
                    sourcePaths: [sourceURL.path],
                    archivePath: archiveURL.path
                )
            }
            servedExpectation.fulfill()
        }
        let receiver = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(receiver, 0)
        defer { Darwin.close(receiver) }
        var targetAddress = sockaddr_in()
        targetAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        targetAddress.sin_family = sa_family_t(AF_INET)
        targetAddress.sin_port = UInt16(port).bigEndian
        targetAddress.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let connectResult = withUnsafePointer(to: &targetAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(receiver, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(connectResult, 0)
        let lengthData = try readSocketData(receiver, byteCount: 8)
        XCTAssertEqual(lengthData.count, 8)
        let byteCount = lengthData.withUnsafeBytes { rawBuffer in
            UInt64(bigEndian: rawBuffer.load(as: UInt64.self))
        }
        let payload = try readSocketData(receiver, byteCount: Int(byteCount))
        wait(for: [servedExpectation], timeout: 2)
        XCTAssertGreaterThan(served, 0)
        XCTAssertEqual(byteCount, served)
        XCTAssertEqual(payload.count, Int(byteCount))
        let receivedURL = temporaryDirectory.appendingPathComponent("received.zip")
        try payload.write(to: receivedURL)
        let extractedDirectory = temporaryDirectory.appendingPathComponent("served-unzipped", isDirectory: true)
        try unzip(receivedURL, to: extractedDirectory)

        XCTAssertEqual(
            try String(contentsOf: extractedDirectory.appendingPathComponent("source.txt"), encoding: .utf8),
            "served from mac ffi socket"
        )
    }

    func testCoreBridgeFileServerServesRegisteredArchiveWhenFfiLibraryIsAvailable() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let sourceURL = temporaryDirectory.appendingPathComponent("registered.txt")
        try "served from mac ffi file server".write(to: sourceURL, atomically: true, encoding: .utf8)
        guard let server = CoreBridge().openFileServer(bindPort: 0) else {
            return XCTFail("file server ffi handle should open")
        }
        defer { server.close() }
        XCTAssertGreaterThan(server.localPort, 0)
        XCTAssertTrue(server.registerTransfer(transferId: "transfer-a", sourcePaths: [sourceURL.path]))
        let servedExpectation = expectation(description: "file server served archive")
        var served: UInt64 = 0
        DispatchQueue.global().async {
            served = server.serveNextArchive(tempDirectory: temporaryDirectory.path)
            servedExpectation.fulfill()
        }

        let receiver = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(receiver, 0)
        defer { Darwin.close(receiver) }
        var targetAddress = sockaddr_in()
        targetAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        targetAddress.sin_family = sa_family_t(AF_INET)
        targetAddress.sin_port = UInt16(server.localPort).bigEndian
        targetAddress.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let connectResult = withUnsafePointer(to: &targetAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(receiver, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(connectResult, 0)
        _ = "transfer-a\n".withCString { pointer in
            Darwin.send(receiver, pointer, strlen(pointer), 0)
        }
        let lengthData = try readSocketData(receiver, byteCount: 8)
        let byteCount = lengthData.withUnsafeBytes { rawBuffer in
            UInt64(bigEndian: rawBuffer.load(as: UInt64.self))
        }
        let payload = try readSocketData(receiver, byteCount: Int(byteCount))
        wait(for: [servedExpectation], timeout: 6)
        XCTAssertEqual(served, byteCount)
        XCTAssertGreaterThan(served, 0)
        let receivedURL = temporaryDirectory.appendingPathComponent("file-server-received.zip")
        try payload.write(to: receivedURL)
        let extractedDirectory = temporaryDirectory.appendingPathComponent("file-server-unzipped", isDirectory: true)
        try unzip(receivedURL, to: extractedDirectory)

        XCTAssertEqual(
            try String(contentsOf: extractedDirectory.appendingPathComponent("registered.txt"), encoding: .utf8),
            "served from mac ffi file server"
        )
    }

    func testCoreBridgeDownloadsFileTreeWhenFfiLibraryIsAvailable() throws {
        let queue = DispatchQueue(label: "clipplus.test.file-tree-download")
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "tree listener ready")
        let served = expectation(description: "tree served")
        let payload = Data("ffi tree".utf8)
        let manifest = Data(
            #"[{"relativePath":"ffi.txt","byteSize":8,"isDirectory":false}]"#.utf8
        )
        var listenerPort: UInt16 = 0
        var requestedTransferId: String?
        listener.stateUpdateHandler = { state in
            if case .ready = state, let port = listener.port {
                listenerPort = port.rawValue
                ready.fulfill()
            }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            var requestData = Data()

            func sendTreePayload() {
                var manifestLength = UInt64(manifest.count).bigEndian
                var payloadLength = UInt64(payload.count).bigEndian
                let manifestLengthData = Swift.withUnsafeBytes(of: &manifestLength) { Data($0) }
                let payloadLengthData = Swift.withUnsafeBytes(of: &payloadLength) { Data($0) }
                connection.send(
                    content: manifestLengthData + manifest + payloadLengthData + payload,
                    completion: .contentProcessed { _ in
                        served.fulfill()
                        connection.cancel()
                    }
                )
            }

            func receiveRequest() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, isComplete, error in
                    if let data {
                        requestData.append(data)
                    }

                    let hasRequestTerminator = requestData.contains(0x0A)
                    if hasRequestTerminator || isComplete || error != nil {
                        requestedTransferId = String(data: requestData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        sendTreePayload()
                        return
                    }

                    receiveRequest()
                }
            }

            receiveRequest()
        }
        listener.start(queue: queue)
        wait(for: [ready], timeout: 2)

        let stagingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            listener.cancel()
            try? FileManager.default.removeItem(at: stagingURL)
        }

        let result = try XCTUnwrap(CoreBridge().downloadFileTree(
            host: "127.0.0.1",
            port: Int(listenerPort),
            transferId: "transfer-a",
            destinationDirectory: stagingURL.path
        ))
        wait(for: [served], timeout: 2)

        XCTAssertEqual(requestedTransferId, "tree:transfer-a")
        XCTAssertEqual(result.fileCount, 1)
        XCTAssertEqual(result.byteCount, 8)
        XCTAssertEqual(result.topLevelPaths, [stagingURL.appendingPathComponent("ffi.txt").path])
        XCTAssertEqual(
            try String(contentsOf: stagingURL.appendingPathComponent("ffi.txt"), encoding: .utf8),
            "ffi tree"
        )
    }

    func testCoreBridgeFileServerServesRegisteredFileTreeWhenFfiLibraryIsAvailable() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let sourceURL = temporaryDirectory.appendingPathComponent("registered.txt")
        try "served from mac ffi direct tree".write(to: sourceURL, atomically: true, encoding: .utf8)
        let stagingURL = temporaryDirectory.appendingPathComponent("staging", isDirectory: true)
        guard let server = CoreBridge().openFileServer(bindPort: 0) else {
            return XCTFail("file server ffi handle should open")
        }
        defer { server.close() }
        XCTAssertGreaterThan(server.localPort, 0)
        XCTAssertTrue(server.registerTransfer(transferId: "transfer-a", sourcePaths: [sourceURL.path]))
        let servedExpectation = expectation(description: "file server served direct tree")
        var served: FileTreeDownloadResult?
        DispatchQueue.global().async {
            served = server.serveNextTree()
            servedExpectation.fulfill()
        }

        let downloaded = try XCTUnwrap(CoreBridge().downloadFileTree(
            host: "127.0.0.1",
            port: server.localPort,
            transferId: "transfer-a",
            destinationDirectory: stagingURL.path
        ))
        wait(for: [servedExpectation], timeout: 6)

        XCTAssertEqual(served?.fileCount, 1)
        XCTAssertEqual(served?.byteCount, UInt64("served from mac ffi direct tree".utf8.count))
        XCTAssertEqual(served?.topLevelPaths, ["registered.txt"])
        XCTAssertEqual(downloaded.fileCount, 1)
        XCTAssertEqual(downloaded.byteCount, UInt64("served from mac ffi direct tree".utf8.count))
        XCTAssertEqual(downloaded.topLevelPaths, [stagingURL.appendingPathComponent("registered.txt").path])
        XCTAssertEqual(
            try String(contentsOf: stagingURL.appendingPathComponent("registered.txt"), encoding: .utf8),
            "served from mac ffi direct tree"
        )
    }

    func testCoreBridgeDownloadsFileArchiveWhenFfiLibraryIsAvailable() throws {
        let queue = DispatchQueue(label: "clipplus.test.file-download")
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "listener ready")
        let served = expectation(description: "archive served")
        let payload = Data("archive from swift server".utf8)
        var listenerPort: UInt16 = 0
        var requestedTransferId: String?
        listener.stateUpdateHandler = { state in
            if case .ready = state, let port = listener.port {
                listenerPort = port.rawValue
                ready.fulfill()
            }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                requestedTransferId = data.flatMap { String(data: $0, encoding: .utf8) }?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                var length = UInt64(payload.count).bigEndian
                let lengthData = Swift.withUnsafeBytes(of: &length) { Data($0) }
                connection.send(content: lengthData + payload, completion: .contentProcessed { _ in
                    served.fulfill()
                    connection.cancel()
                })
            }
        }
        listener.start(queue: queue)
        wait(for: [ready], timeout: 2)

        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("received.zip")
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        XCTAssertTrue(CoreBridge().downloadArchiveFile(
            host: "127.0.0.1",
            port: Int(listenerPort),
            transferId: "transfer-a",
            destinationPath: destinationURL.path
        ))
        wait(for: [served], timeout: 2)
        listener.cancel()

        XCTAssertEqual(requestedTransferId, "transfer-a")
        XCTAssertEqual(try Data(contentsOf: destinationURL), payload)
    }

    func testNativeClipboardWritesFileURLsForFinderPaste() throws {
        let originalPasteboard = PasteboardSnapshot.capture()
        defer {
            originalPasteboard.restore()
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let sourceURL = temporaryDirectory.appendingPathComponent("finder-paste.txt")
        try "paste from finder".write(to: sourceURL, atomically: true, encoding: .utf8)

        let backgroundWrite = expectation(description: "background pasteboard write rejected")
        var backgroundWriteResult: Bool?
        DispatchQueue.global().async {
            backgroundWriteResult = NativeClipboard().writeFileURLs([sourceURL])
            backgroundWrite.fulfill()
        }
        wait(for: [backgroundWrite], timeout: 2)
        XCTAssertEqual(backgroundWriteResult, false)

        let writeSucceeded: Bool
        if Thread.isMainThread {
            writeSucceeded = NativeClipboard().writeFileURLs([sourceURL])
        } else {
            writeSucceeded = DispatchQueue.main.sync {
                NativeClipboard().writeFileURLs([sourceURL])
            }
        }

        XCTAssertTrue(writeSucceeded)

        XCTAssertEqual(NativeClipboard().readFileURLs().map(\.standardizedFileURL.path), [sourceURL.path])
    }

    func testNativeClipboardWritesSingleImageFileAsFileAndImage() throws {
        let originalPasteboard = PasteboardSnapshot.capture()
        defer {
            originalPasteboard.restore()
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let sourceURL = temporaryDirectory.appendingPathComponent("copied-image.png")
        let pngData = try makeTestPNGData(width: 24, height: 18)
        try pngData.write(to: sourceURL)

        let writeSucceeded: Bool
        if Thread.isMainThread {
            writeSucceeded = NativeClipboard().writeFileURLs([sourceURL])
        } else {
            writeSucceeded = DispatchQueue.main.sync {
                NativeClipboard().writeFileURLs([sourceURL])
            }
        }

        XCTAssertTrue(writeSucceeded)
        XCTAssertEqual(NativeClipboard().readFileURLs().map(\.standardizedFileURL.path), [sourceURL.path])
        XCTAssertEqual(NativeClipboard().readPngImageData(), pngData)
    }

    func testNativeClipboardWritesPngImageAsMacCompatiblePasteboardTypes() throws {
        let originalPasteboard = PasteboardSnapshot.capture()
        defer {
            originalPasteboard.restore()
        }

        let pngData = try makeTestPNGData(width: 24, height: 18)

        NativeClipboard().writePngImageData(pngData)

        let pasteboard = NSPasteboard.general
        XCTAssertEqual(pasteboard.data(forType: .png), pngData)
        XCTAssertNotNil(pasteboard.data(forType: .tiff))
        XCTAssertNotNil(pasteboard.data(forType: NSPasteboard.PasteboardType("Apple PNG pasteboard type")))
        XCTAssertNotNil(pasteboard.data(forType: NSPasteboard.PasteboardType("NeXT TIFF v4.0 pasteboard type")))
        XCTAssertNotNil(NSImage(pasteboard: pasteboard))
    }

    func testNativeClipboardReadsWeChatScreenshotPublicTiffPasteboardWithoutTreatingItAsFile() throws {
        let originalPasteboard = PasteboardSnapshot.capture()
        defer {
            originalPasteboard.restore()
        }

        try writeWeChatScreenshotLikePasteboard(tiffType: .tiff, width: 32, height: 20)

        XCTAssertTrue(NativeClipboard().readFileURLs().isEmpty)
        XCTAssertPngDimensions(NativeClipboard().readPngImageData(), width: 32, height: 20)
    }

    func testNativeClipboardReadsApplePngPasteboardTypeWithoutPublicPng() throws {
        let originalPasteboard = PasteboardSnapshot.capture()
        defer {
            originalPasteboard.restore()
        }

        let pngData = try makeTestPNGData(width: 24, height: 18)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(pngData, forType: NSPasteboard.PasteboardType("Apple PNG pasteboard type"))
        NSPasteboard.general.setData(Data([1]), forType: NSPasteboard.PasteboardType("com.trolltech.anymime.WeChatScreenshotFormat"))

        XCTAssertTrue(NativeClipboard().readFileURLs().isEmpty)
        XCTAssertPngDimensions(NativeClipboard().readPngImageData(), width: 24, height: 18)
    }

    func testMacFileRuntimeNoLongerUsesDownloadsZip() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let syncServiceURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/Sync/UdpTextSyncService.swift")
        let syncServiceSource = try String(contentsOf: syncServiceURL, encoding: .utf8)

        XCTAssertTrue(syncServiceSource.contains("downloadFileTree("))
        XCTAssertTrue(syncServiceSource.contains("writeFileURLs"))
        XCTAssertTrue(syncServiceSource.contains("message.transferFormat == .directTree"))
        XCTAssertFalse(syncServiceSource.contains("ClipPlus-Received"))
        XCTAssertFalse(syncServiceSource.contains(".downloadsDirectory"))
        XCTAssertFalse(syncServiceSource.contains("downloadFileArchive("))
        XCTAssertFalse(syncServiceSource.contains("serveNext(tempDirectory:"))
        XCTAssertFalse(syncServiceSource.contains("logger.error(\"file tree staging failed: \\(error.localizedDescription)\""))
    }

    func testMacImageRuntimeUsesDirectTransferForOversizedImages() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let syncServiceURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/Sync/UdpTextSyncService.swift")
        let syncServiceSource = try String(contentsOf: syncServiceURL, encoding: .utf8)

        XCTAssertTrue(syncServiceSource.contains("publishImageOffer"))
        XCTAssertTrue(syncServiceSource.contains("downloadRemoteImageOffer"))
        XCTAssertTrue(syncServiceSource.contains("case .imageOffer"))
        XCTAssertTrue(syncServiceSource.contains("ImageContentHasher.sha256Hex"))
        XCTAssertTrue(syncServiceSource.contains("maxReliableInlineImageBytes"))
        XCTAssertTrue(syncServiceSource.contains("pngData.count <= Self.maxReliableInlineImageBytes"))
        XCTAssertTrue(syncServiceSource.contains("registerTemporaryImageTransferSource"))
        XCTAssertTrue(syncServiceSource.contains("downloadFileTreeWithRetry"))
        XCTAssertTrue(syncServiceSource.contains(".milliseconds(250)"))
    }

    func testMacFileRuntimeSynchronizesFileSignaturesThroughLock() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let syncServiceURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/Sync/UdpTextSyncService.swift")
        let syncServiceSource = try String(contentsOf: syncServiceURL, encoding: .utf8)

        XCTAssertTrue(syncServiceSource.contains("private let fileSignatureLock = NSLock()"))
        XCTAssertTrue(syncServiceSource.contains("shouldPublishLocalFileSignature("))
        XCTAssertTrue(syncServiceSource.contains("recordRemoteFileSignature("))
        let pollStart = try XCTUnwrap(syncServiceSource.range(of: "private func pollClipboardAndBroadcast()")?.lowerBound)
        let localImageStart = try XCTUnwrap(syncServiceSource.range(of: "private func localImageHashAfterClipboardWrite()")?.lowerBound)
        let pollSource = String(syncServiceSource[pollStart..<localImageStart])
        XCTAssertFalse(pollSource.contains("lastLocalFileSignature"))
        XCTAssertFalse(pollSource.contains("lastRemoteFileSignature"))
        XCTAssertFalse(syncServiceSource.contains("lastLocalFileSignature = remoteSignature"))
        XCTAssertFalse(syncServiceSource.contains("lastRemoteFileSignature = remoteSignature"))
        XCTAssertFalse(syncServiceSource.contains("lastLocalFileSignature = pasteboardSignature"))
        XCTAssertFalse(syncServiceSource.contains("lastRemoteFileSignature = pasteboardSignature"))
    }

    func testMacFileRuntimeUsesCollisionFreeFileSignaturesAndSafeTransferIds() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let syncServiceURL = packageRoot
            .appendingPathComponent("Sources/ClipPlusMac/Sync/UdpTextSyncService.swift")
        let syncServiceSource = try String(contentsOf: syncServiceURL, encoding: .utf8)

        XCTAssertFalse(syncServiceSource.contains(".joined(separator: \"|\")"))
        XCTAssertTrue(syncServiceSource.contains("fileSignatureComponents"))
        XCTAssertTrue(syncServiceSource.contains("\\($0.utf8.count):\\($0)"))
        XCTAssertTrue(syncServiceSource.contains("[A-Za-z0-9-]{1,128}"))
        XCTAssertTrue(syncServiceSource.contains("options: .regularExpression"))
    }

    func testCoreBridgeUdpSocketSendsAndReceivesDatagramsWhenFfiLibraryIsAvailable() throws {
        let bridge = CoreBridge()
        let receiver = try XCTUnwrap(bridge.openUdpSocket(bindPort: 0))
        let sender = try XCTUnwrap(bridge.openUdpSocket(bindPort: 0))
        defer {
            receiver.close()
            sender.close()
        }

        XCTAssertNotEqual(receiver.localPort, 0)
        let payload = Data("hello from mac udp ffi".utf8)
        XCTAssertTrue(sender.send(payload, to: "127.0.0.1", port: receiver.localPort))

        let datagram = try XCTUnwrap(receiver.receive())

        XCTAssertEqual(datagram.payload, payload)
        XCTAssertEqual(datagram.sourceHost, "127.0.0.1")
        XCTAssertNotEqual(datagram.sourcePort, 0)
    }

    func testClipPlusMessageRejectsOversizedInlineImagePayload() {
        let pngData = Data(repeating: 0xFF, count: ClipPlusMessage.maxInlineImageBytes + 1)

        let message = ClipPlusMessage.image(
            groupId: "group-1",
            senderDeviceId: "mac-device",
            senderDeviceName: "Mac",
            pngData: pngData
        )

        XCTAssertNil(message)
    }

    func testLoginItemManagerReportsServiceState() {
        let service = FakeLoginItemService(enabled: true)
        let manager = LoginItemManager(service: service)

        XCTAssertTrue(manager.isEnabled())
    }

    func testLoginItemManagerForwardsEnableAndDisable() throws {
        let service = FakeLoginItemService(enabled: false)
        let manager = LoginItemManager(service: service)

        try manager.setEnabled(true)
        try manager.setEnabled(false)

        XCTAssertEqual(service.requests, [true, false])
        XCTAssertFalse(manager.isEnabled())
    }

    func testLoginItemSmokeTestRestoresDisabledOriginalState() throws {
        let service = FakeLoginItemService(enabled: false)
        let manager = LoginItemManager(service: service)

        let result = try LoginItemSmokeTest.perform(manager: manager)

        XCTAssertEqual(
            result,
            LoginItemSmokeTestResult(
                enabledAfterRegister: true,
                disabledAfterUnregister: true,
                restoredOriginal: true
            )
        )
        XCTAssertEqual(service.requests, [true, false, false])
        XCTAssertFalse(manager.isEnabled())
    }

    func testLoginItemSmokeTestRestoresEnabledOriginalState() throws {
        let service = FakeLoginItemService(enabled: true)
        let manager = LoginItemManager(service: service)

        let result = try LoginItemSmokeTest.perform(manager: manager)

        XCTAssertTrue(result.passed)
        XCTAssertEqual(service.requests, [true, false, true])
        XCTAssertTrue(manager.isEnabled())
    }

    func testDiagnosticsExporterWritesRedactedStatusAndLogZip() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let logURL = temporaryDirectory.appendingPathComponent("clipplus.log")
        try "raw key clipplus-test-key clipboard secret-value".write(to: logURL, atomically: true, encoding: .utf8)
        let state = SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false,
            sharedGroupId: "group-id"
        )
        state.markPeerPending(deviceId: "windows-device", deviceName: "Windows")
        let exporter = DiagnosticsExporter(
            logURL: logURL,
            destinationDirectory: temporaryDirectory,
            sensitiveValues: ["clipplus-test-key", "secret-value"]
        )

        let exportURL = try exporter.export(state: state)
        let extractedDirectory = temporaryDirectory.appendingPathComponent("unzipped", isDirectory: true)
        try FileManager.default.createDirectory(at: extractedDirectory, withIntermediateDirectories: true)
        try unzip(exportURL, to: extractedDirectory)
        let status = try String(
            contentsOf: extractedDirectory.appendingPathComponent("status.json"),
            encoding: .utf8
        )
        let log = try String(
            contentsOf: extractedDirectory.appendingPathComponent("clipplus.log"),
            encoding: .utf8
        )

        XCTAssertEqual(exportURL.pathExtension, "zip")
        XCTAssertTrue(status.contains("\"shared_key_configured\""))
        XCTAssertTrue(status.contains("\"pending_peer_count\""))
        XCTAssertFalse(status.contains("clipplus-test-key"))
        XCTAssertFalse(log.contains("clipplus-test-key"))
        XCTAssertFalse(log.contains("secret-value"))
        XCTAssertTrue(log.contains("<redacted>"))
    }
}

private func unzip(_ archiveURL: URL, to destinationURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-q", archiveURL.path, "-d", destinationURL.path]
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
}

private func readSocketData(_ socketDescriptor: Int32, byteCount: Int) throws -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: min(byteCount, 64 * 1024))
    while data.count < byteCount {
        let remaining = byteCount - data.count
        let readCount = recv(socketDescriptor, &buffer, min(buffer.count, remaining), 0)
        if readCount <= 0 {
            throw NSError(domain: "ClipPlusMacTests", code: Int(readCount))
        }
        data.append(buffer, count: readCount)
    }
    return data
}

private func expectedGroupId(for rawKey: String) -> String {
    switch rawKey {
    case "clipplus-test-key":
        return "21YR2N3_wcdRPmEMLiuLMA"
    default:
        XCTFail("Missing expected group id fixture for \(rawKey)")
        return ""
    }
}

private func XCTAssertContainsVisibleControl(
    _ label: String,
    in source: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(source.contains(label), "设置界面缺少必要控件：\(label)", file: file, line: line)
}

private func makeTestPNGData(width: Int, height: Int) throws -> Data {
    guard let imageRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4,
        bitsPerPixel: 32
    ), let bitmapData = imageRep.bitmapData else {
        throw NSError(domain: "ClipPlusMacTests", code: 1)
    }

    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * imageRep.bytesPerRow) + (x * 4)
            bitmapData[offset] = UInt8(30 + (x % 120))
            bitmapData[offset + 1] = UInt8(80 + (y % 120))
            bitmapData[offset + 2] = 190
            bitmapData[offset + 3] = 255
        }
    }

    guard let pngData = imageRep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ClipPlusMacTests", code: 1)
    }

    return pngData
}

private func makeTestTIFFData(width: Int, height: Int) throws -> Data {
    let pngData = try makeTestPNGData(width: width, height: height)
    guard let image = NSImage(data: pngData),
          let tiffData = image.tiffRepresentation else {
        throw NSError(domain: "ClipPlusMacTests", code: 2)
    }

    return tiffData
}

private func writeWeChatScreenshotLikePasteboard(
    tiffType: NSPasteboard.PasteboardType,
    width: Int,
    height: Int
) throws {
    let item = NSPasteboardItem()
    item.setData(try makeTestTIFFData(width: width, height: height), forType: tiffType)
    item.setData(Data(), forType: NSPasteboard.PasteboardType("com.trolltech.anymime.application--x-qt-image"))
    item.setData(Data([1]), forType: NSPasteboard.PasteboardType("com.trolltech.anymime.application--x-capturer-status"))
    item.setData(Data([1]), forType: NSPasteboard.PasteboardType("com.trolltech.anymime.WeChatScreenshotFormat"))

    NSPasteboard.general.clearContents()
    XCTAssertTrue(NSPasteboard.general.writeObjects([item]))
}

private func XCTAssertPngDimensions(
    _ pngData: Data?,
    width expectedWidth: Int,
    height expectedHeight: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let pngData else {
        XCTFail("Expected PNG data", file: file, line: line)
        return
    }

    let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    XCTAssertEqual(Data(pngData.prefix(pngSignature.count)), pngSignature, file: file, line: line)

    guard let imageRep = NSBitmapImageRep(data: pngData) else {
        XCTFail("Expected decodable PNG data", file: file, line: line)
        return
    }

    XCTAssertEqual(imageRep.pixelsWide, expectedWidth, file: file, line: line)
    XCTAssertEqual(imageRep.pixelsHigh, expectedHeight, file: file, line: line)
}

private struct PasteboardSnapshot {
    let items: [PasteboardItemSnapshot]

    static func capture() -> PasteboardSnapshot {
        let items = NSPasteboard.general.pasteboardItems?.map { item in
            PasteboardItemSnapshot(typeData: item.types.compactMap { type in
                guard let data = item.data(forType: type) else {
                    return nil
                }

                return (type, data)
            })
        } ?? []

        return PasteboardSnapshot(items: items)
    }

    func restore() {
        NSPasteboard.general.clearContents()
        let pasteboardItems = items.map { itemSnapshot in
            let item = NSPasteboardItem()
            for (type, data) in itemSnapshot.typeData {
                item.setData(data, forType: type)
            }
            return item
        }

        if !pasteboardItems.isEmpty {
            NSPasteboard.general.writeObjects(pasteboardItems)
        }
    }
}

private struct PasteboardItemSnapshot {
    let typeData: [(NSPasteboard.PasteboardType, Data)]
}

private final class FakeLoginItemService: LoginItemService {
    var enabled: Bool
    var requests: [Bool] = []

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        requests.append(enabled)
        self.enabled = enabled
    }
}

private final class InMemorySharedKeyVault: SharedKeyVault {
    var sharedKey = ""

    func loadSharedKey() -> String {
        sharedKey
    }

    func saveSharedKey(_ sharedKey: String) throws {
        self.sharedKey = sharedKey
    }
}
