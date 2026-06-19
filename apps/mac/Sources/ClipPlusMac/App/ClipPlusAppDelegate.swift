import AppKit

@MainActor
final class ClipPlusAppDelegate: NSObject, NSApplicationDelegate {
    private weak var appModel: ClipPlusAppModel?

    func configure(appModel: ClipPlusAppModel) {
        self.appModel = appModel
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appModel?.showSettingsWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appModel?.showSettingsWindow()
        return true
    }
}
