import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let panel: NSPanel
    private let hostingView: NSHostingView<SettingsView>

    init(state: SettingsState) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        hostingView = NSHostingView(rootView: SettingsView(state: state))
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 220),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        configureStatusItem()
        configurePanel()

        if state.requiresKeySetup {
            DispatchQueue.main.async { [weak self] in
                self?.showSettingsWindow()
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
        button.target = self
        button.action = #selector(toggleSettingsWindow)
        button.sendAction(on: [.leftMouseUp])
        button.setAccessibilityLabel("ClipPlus")
    }

    private func configurePanel() {
        panel.contentView = hostingView
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .statusBar
        panel.collectionBehavior = [.transient, .ignoresCycle]
    }

    @objc private func toggleSettingsWindow() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showSettingsWindow()
        }
    }

    private func showSettingsWindow() {
        resizePanelToFitContent()
        positionPanelBelowStatusItem()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func resizePanelToFitContent() {
        let fittingSize = hostingView.fittingSize
        let width = max(180, fittingSize.width)
        let height = max(1, fittingSize.height)
        panel.setContentSize(NSSize(width: width, height: height))
    }

    private func positionPanelBelowStatusItem() {
        guard let button = statusItem.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else {
            panel.center()
            return
        }

        let buttonFrame = buttonWindow.convertToScreen(button.frame)
        let panelSize = panel.frame.size
        let visibleFrame = screen.visibleFrame
        var origin = NSPoint(
            x: buttonFrame.midX - (panelSize.width / 2),
            y: buttonFrame.minY - panelSize.height - 6
        )

        origin.x = min(max(origin.x, visibleFrame.minX + 4), visibleFrame.maxX - panelSize.width - 4)
        if origin.y < visibleFrame.minY + 4 {
            origin.y = buttonFrame.maxY + 6
        }

        panel.setFrameOrigin(origin)
    }
}
