import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    init(rootView: SettingsView) {
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Primary Paste"
        window.setContentSize(NSSize(width: 880, height: 680))
        window.contentMinSize = NSSize(width: 720, height: 520)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.setFrameAutosaveName("PrimaryPasteSettingsWindow")
        if !window.setFrameUsingName("PrimaryPasteSettingsWindow") {
            window.center()
        }
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
