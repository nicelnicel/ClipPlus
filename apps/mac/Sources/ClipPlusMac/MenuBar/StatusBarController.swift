import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let statusMenu: NSMenu
    private let popover: NSPopover
    private let hostingController: NSHostingController<SettingsView>

    init(state: SettingsState) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusMenu = NSMenu()
        popover = NSPopover()
        hostingController = NSHostingController(rootView: SettingsView(state: state))
        super.init()

        configureStatusItem()
        configureStatusMenu()
        configurePopover()

        if state.requiresKeySetup {
            DispatchQueue.main.async { [weak self] in
                self?.showSettingsPopover()
            }
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = ClipPlusAppIcon.menuBarImage
        button.imagePosition = .imageOnly
        button.toolTip = "ClipPlus"
        button.setAccessibilityLabel("ClipPlus")
    }

    private func configureStatusMenu() {
        statusMenu.delegate = self
        statusMenu.addItem(NSMenuItem(title: "ClipPlus", action: nil, keyEquivalent: ""))
        statusItem.menu = statusMenu
    }

    private func configurePopover() {
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 180, height: 220)
        popover.behavior = .transient
        popover.animates = false
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.cancelTrackingWithoutAnimation()
        DispatchQueue.main.async { [weak self] in
            self?.showSettingsPopover()
        }
    }

    private func showSettingsPopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
