import AppKit
import Combine
import Foundation

enum MenuAction {
    case about
    case showSetup
    case settings
    case toggleEnabled
    case togglePrivateMode
    case sendPrimaryToClipboard
    case clear
    case pauseCurrentApp
    case quit
}

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let appState: AppState
    private let permissions: PermissionsCoordinator
    private let actionHandler: (MenuAction) -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(
        appState: AppState,
        permissions: PermissionsCoordinator,
        actionHandler: @escaping (MenuAction) -> Void
    ) {
        self.appState = appState
        self.permissions = permissions
        self.actionHandler = actionHandler
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        refreshStatusItem()
        observeState()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        permissions.refresh()
        menu.removeAllItems()
        refreshStatusItem()

        let modeTitle = appState.preferences.pasteMode.title

        menu.addItem(disabledItem("Mode: \(modeTitle)"))
        menu.addItem(disabledItem("Triggers: \(triggerStatusTitle)"))

        if let current = appState.primaryStore.peekItem() {
            menu.addItem(disabledItem("Primary: \(current.preview)"))
        } else {
            menu.addItem(disabledItem("Primary: Empty"))
        }

        if !appState.primaryStore.queue.isEmpty {
            menu.addItem(disabledItem("\(retainedItemsMenuLabel): \(retainedItemsCountText)"))
        }

        if needsSetupAttention {
            menu.addItem(disabledItem("Setup: Needs Attention"))
            setupAttentionItems.forEach { menu.addItem(disabledItem($0)) }
        }
        menu.addItem(.separator())

        menu.addItem(
            actionItem(
                appState.preferences.isEnabled ? "Pause" : "Resume",
                action: #selector(toggleEnabled)
            ))
        let privateModeItem = actionItem("Private Mode", action: #selector(togglePrivateMode))
        privateModeItem.state = appState.preferences.isPrivateModeEnabled ? .on : .off
        menu.addItem(privateModeItem)
        menu.addItem(
            actionItem(pauseCurrentAppTitle, action: #selector(pauseCurrentApp), isEnabled: canPauseCurrentApp))
        menu.addItem(
            actionItem(
                "Send Primary to Clipboard", action: #selector(sendPrimaryToClipboard),
                isEnabled: appState.primaryStore.peekItem() != nil))
        menu.addItem(
            actionItem(
                "Clear Primary", action: #selector(clear),
                isEnabled: appState.primaryStore.peekItem() != nil || !appState.primaryStore.queue.isEmpty))
        menu.addItem(.separator())
        if needsSetupAttention {
            menu.addItem(actionItem("Permissions & Setup...", action: #selector(showSetup)))
        }
        menu.addItem(actionItem("Settings...", action: #selector(settings)))
        menu.addItem(actionItem("About Primary Paste...", action: #selector(about)))
        menu.addItem(actionItem("Quit Primary Paste", action: #selector(quit)))
    }

    private var needsSetupAttention: Bool {
        (appState.preferences.shouldUseAccessibility && !permissions.isAccessibilityTrusted)
            || (appState.preferences.shouldMonitorGlobalEvents && !permissions.isInputMonitoringTrusted)
            || (appState.preferences.captureFileSelections && !permissions.isFinderAutomationTrusted)
    }

    private var setupAttentionItems: [String] {
        var items: [String] = []

        if appState.preferences.shouldUseAccessibility && !permissions.isAccessibilityTrusted {
            items.append("Accessibility: Needed")
        }

        if appState.preferences.shouldMonitorGlobalEvents && !permissions.isInputMonitoringTrusted {
            items.append("Input Monitoring: Needed")
        }

        if appState.preferences.captureFileSelections && !permissions.isFinderAutomationTrusted {
            items.append("Finder Automation: Needed")
        }

        return items
    }

    private var triggerStatusTitle: String {
        var titles: [String] = []
        if appState.preferences.middleClickTriggerEnabled {
            titles.append("Middle-click")
        }
        if appState.preferences.keyboardShortcutTriggerEnabled {
            titles.append("Shortcut")
        }
        if appState.preferences.externalTriggerEnabled {
            titles.append("URL")
        }
        return titles.isEmpty ? "None" : titles.joined(separator: ", ")
    }

    private var retainedItemsMenuLabel: String {
        switch appState.preferences.pasteMode {
        case .latest:
            return "History"
        case .queue:
            return "Queue"
        case .stack:
            return "Stack"
        case .cycle:
            return "Cycle"
        }
    }

    private var retainedItemsCountText: String {
        let count = appState.primaryStore.queue.count
        return count == 1 ? "1 item" : "\(count) items"
    }

    private var pauseCurrentAppTitle: String {
        "Pause for \(appState.appRules.frontmostAppName)"
    }

    private var canPauseCurrentApp: Bool {
        guard let bundleIdentifier = appState.appRules.frontmostBundleIdentifier else {
            return false
        }

        return !appState.appRules.isSelfBundleIdentifier(bundleIdentifier)
            && !appState.preferences.blockedBundleIdentifiers.contains(bundleIdentifier)
    }

    private func observeState() {
        appState.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshStatusItem()
                }
            }
            .store(in: &cancellables)

        permissions.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshStatusItem()
                }
            }
            .store(in: &cancellables)
    }

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }

        let image: NSImage?
        let title: String
        let tooltip: String

        if appState.preferences.isPrivateModeEnabled {
            image = NSImage(
                systemSymbolName: "lock.shield", accessibilityDescription: "Primary Paste is in Private Mode")
            title = appState.preferences.showMenuBarStatusText ? "Private" : ""
            tooltip = "Primary Paste is in Private Mode"
        } else if !appState.preferences.isEnabled {
            image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Primary Paste is paused")
            title = appState.preferences.showMenuBarStatusText ? "Paused" : ""
            tooltip = "Primary Paste is paused"
        } else if needsSetupAttention {
            image = NSImage(
                systemSymbolName: "exclamationmark.circle",
                accessibilityDescription: "Primary Paste setup needs attention")
            title = appState.preferences.showMenuBarStatusText ? "Setup" : ""
            tooltip = "Primary Paste setup needs attention"
        } else {
            image = PrimaryPasteIconRenderer.image(
                for: appState.preferences.menuBarIconVariant,
                size: 18,
                style: .menuBar
            )
            title = ""
            tooltip = "Primary Paste is active"
        }

        image?.isTemplate = true
        statusItem.length = title.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
        button.image = image
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        button.title = title
        button.toolTip = tooltip
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, action: Selector, isEnabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = isEnabled
        return item
    }

    @objc private func showSetup() {
        actionHandler(.showSetup)
    }

    @objc private func settings() {
        actionHandler(.settings)
    }

    @objc private func about() {
        actionHandler(.about)
    }

    @objc private func toggleEnabled() {
        actionHandler(.toggleEnabled)
    }

    @objc private func togglePrivateMode() {
        actionHandler(.togglePrivateMode)
    }

    @objc private func sendPrimaryToClipboard() {
        actionHandler(.sendPrimaryToClipboard)
    }

    @objc private func clear() {
        actionHandler(.clear)
    }

    @objc private func pauseCurrentApp() {
        actionHandler(.pauseCurrentApp)
    }

    @objc private func quit() {
        actionHandler(.quit)
    }
}
