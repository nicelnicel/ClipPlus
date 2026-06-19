import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject {
    private let state: SettingsState
    private var window: NSWindow?

    init(state: SettingsState) {
        self.state = state
    }

    func showSettingsWindow() {
        let window = window ?? makeWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: SettingsView(state: state))
        let window = NSWindow(contentViewController: hostingController)
        window.title = AppVersion.settingsWindowTitle
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]
        window.setContentSize(NSSize(width: 180, height: 240))
        window.center()
        self.window = window
        return window
    }
}
