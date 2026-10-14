import AppKit
import ApplicationServices
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var menuBarController: MenuBarController!
    private var permissions: PermissionsCoordinator!
    private var selectionEngine: SelectionEngine!
    private var fileSelectionObserver: FileSelectionObserver!
    private var clipboardObserver: ClipboardObserver!
    private var clipboardRestorer: ClipboardRestorer!
    private var privacyFilter: PrivacyFilter!
    private var mouseEventTap: MouseEventTap!
    private var keyboardShortcutController: KeyboardShortcutController!
    private var pasteController: PasteController!
    private var toastPresenter: CaptureToastPresenter!
    private var supportActions: SupportActions!
    private let launchAtLoginController = LaunchAtLoginController()
    private var settingsWindowController: SettingsWindowController?
    private let settingsNavigation = SettingsNavigation()
    private var cancellables: Set<AnyCancellable> = []
    private var pendingDeepLinks: [URL] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        installDeepLinkHandler()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let preferences = PreferencesStore()
        applyActivationPolicy(showDockIcon: preferences.showDockIcon)
        applyApplicationIcon(preferences.appIconVariant)
        installMainMenu()

        let primaryStore = PrimarySelectionStore(preferences: preferences)
        let diagnostics = InteractionDiagnostics()
        diagnostics.record(
            DiagnosticEvent(
                capability: .app,
                audience: .developers,
                outcome: .succeeded,
                code: "application-launched"
            )
        )
        privacyFilter = PrivacyFilter(preferences: preferences)
        let appRules = AppRulesEngine(preferences: preferences)
        let licensing = LicenseController()
        let hitTester = EditableHitTester(appRules: appRules)
        clipboardRestorer = ClipboardRestorer()
        toastPresenter = CaptureToastPresenter(preferences: preferences)

        pasteController = PasteController(
            primaryStore: primaryStore,
            preferences: preferences,
            hitTester: hitTester,
            clipboardRestorer: clipboardRestorer,
            appRules: appRules,
            diagnostics: diagnostics,
            licensing: licensing
        )

        appState = AppState(
            preferences: preferences,
            primaryStore: primaryStore,
            appRules: appRules,
            diagnostics: diagnostics,
            licensing: licensing
        )

        permissions = PermissionsCoordinator(monitorsFinderAutomation: preferences.captureFileSelections)
        selectionEngine = SelectionEngine(
            primaryStore: primaryStore,
            preferences: preferences,
            privacyFilter: privacyFilter,
            appRules: appRules,
            diagnostics: diagnostics,
            clipboardRestorer: clipboardRestorer,
            noticeHandler: { [weak toastPresenter] notice in
                toastPresenter?.show(notice: notice)
            }
        )
        fileSelectionObserver = FileSelectionObserver(
            primaryStore: primaryStore,
            preferences: preferences,
            clipboardRestorer: clipboardRestorer,
            appRules: appRules,
            permissions: permissions,
            diagnostics: diagnostics,
            noticeHandler: { [weak toastPresenter] notice in
                toastPresenter?.show(notice: notice)
            }
        )
        clipboardObserver = ClipboardObserver(
            primaryStore: primaryStore,
            preferences: preferences,
            clipboardRestorer: clipboardRestorer,
            appRules: appRules,
            privacyFilter: privacyFilter,
            diagnostics: diagnostics
        )
        supportActions = SupportActions(
            appState: appState,
            clipboardObserver: clipboardObserver,
            clipboardRestorer: clipboardRestorer,
            privacyFilter: privacyFilter,
            toastPresenter: toastPresenter
        )
        primaryStore.onRecord = {
            [weak preferences, weak toastPresenter, weak clipboardObserver, weak clipboardRestorer] item in
            if preferences?.showCaptureToasts == true {
                toastPresenter?.show(item: item)
            }

            guard preferences?.clipboardLinkMode == .mirrorSelections else { return }
            guard !item.isClipboardCopy else { return }
            guard case .text = item.payload else { return }
            clipboardObserver?.suppressProgrammaticChanges(reason: "mirror selection to clipboard")
            clipboardRestorer?.writeToUserClipboard(item)
        }
        pasteController.onProgrammaticPasteboardWrite = { [weak clipboardObserver] in
            clipboardObserver?.adoptCurrentPasteboardState()
        }
        selectionEngine.onProgrammaticPasteboardWrite = { [weak clipboardObserver] in
            clipboardObserver?.suppressProgrammaticChanges(reason: "compatibility copy selection")
        }
        selectionEngine.onProgrammaticPasteboardRestore = { [weak clipboardObserver] in
            clipboardObserver?.adoptCurrentPasteboardState()
        }
        mouseEventTap = MouseEventTap(
            preferences: preferences,
            pasteController: pasteController,
            diagnostics: diagnostics,
            selectionGestureHandler: { [weak selectionEngine] kind in
                selectionEngine?.noteSelectionGesture(kind)
            },
            selectionDragEndedHandler: { [weak selectionEngine] distance in
                selectionEngine?.noteMouseDragSelectionEnded(distance: distance)
            },
            selectionDragCancelledHandler: { [weak selectionEngine] in
                selectionEngine?.noteMouseDragSelectionCancelled()
            }
        )
        keyboardShortcutController = KeyboardShortcutController(
            preferences: preferences,
            diagnostics: diagnostics,
            action: { [weak self] in
                self?.pasteController.pastePrimarySelectionFromShortcut()
            }
        )

        menuBarController = MenuBarController(appState: appState, permissions: permissions) { [weak self] action in
            self?.handleMenuAction(action)
        }

        observeStateChanges(preferences: preferences, primaryStore: primaryStore, licensing: licensing)

        preferences.launchAtLogin = launchAtLoginController.isRegistered
        permissions.refresh()
        permissions.startAutoRefresh()
        refreshSelectionEngine()
        refreshFileSelectionObserver()
        refreshClipboardObserver()
        keyboardShortcutController.start()
        refreshMouseEventTap()
        let launchURLs = pendingDeepLinks
        pendingDeepLinks.removeAll()
        launchURLs.forEach(handleDeepLink)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak preferences] in
            guard
                let self,
                let preferences,
                self.shouldShowSetupOnLaunch(preferences: preferences)
            else {
                return
            }
            self.showSettings(selectedTab: .setup)
        }
    }

    private func observeStateChanges(
        preferences: PreferencesStore, primaryStore: PrimarySelectionStore, licensing: LicenseController
    ) {
        let permissions = self.permissions!
        let toastPresenter = self.toastPresenter!
        preferences.$showDockIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showDockIcon in
                self?.applyActivationPolicy(showDockIcon: showDockIcon)
            }
            .store(in: &cancellables)

        preferences.$launchAtLogin
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                guard let self else { return }
                if launchAtLoginController.setEnabled(isEnabled) {
                    appState.startupError =
                        launchAtLoginController.requiresApproval
                        ? "Allow Primary Paste in System Settings → Login Items to finish enabling startup." : nil
                } else {
                    appState.startupError = "macOS could not update Launch at Login. Check Login Items and try again."
                    if preferences.launchAtLogin != launchAtLoginController.isRegistered {
                        preferences.launchAtLogin = launchAtLoginController.isRegistered
                    }
                }
            }
            .store(in: &cancellables)

        preferences.$appIconVariant
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] variant in
                self?.applyApplicationIcon(variant)
            }
            .store(in: &cancellables)

        preferences.$captureFileSelections
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak permissions] isEnabled in
                permissions?.monitorsFinderAutomation = isEnabled
                guard isEnabled, permissions?.isFinderAutomationTrusted == false else { return }
                permissions?.requestFinderAutomationPermission()
            }
            .store(in: &cancellables)

        permissions.$isInputMonitoringTrusted
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTrusted in
                self?.appState.diagnostics.record(
                    DiagnosticEvent(
                        capability: .permissions,
                        audience: .developers,
                        code: "input-monitoring-state-changed",
                        metadata: .init(state: isTrusted ? "allowed" : "not-allowed")
                    )
                )
                if isTrusted {
                    self?.refreshMouseEventTap()
                } else {
                    self?.mouseEventTap.stop()
                    self?.appState.middleClickIsRunning = false
                }
            }
            .store(in: &cancellables)

        permissions.$isAccessibilityTrusted
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTrusted in
                self?.appState.diagnostics.record(
                    DiagnosticEvent(
                        capability: .permissions,
                        audience: .developers,
                        code: "accessibility-state-changed",
                        metadata: .init(state: isTrusted ? "allowed" : "not-allowed")
                    )
                )
                if !isTrusted { self?.pasteController.cancelPendingPastes() }
                self?.refreshSelectionEngine()
            }
            .store(in: &cancellables)

        permissions.$isFinderAutomationTrusted
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTrusted in
                self?.appState.diagnostics.record(
                    DiagnosticEvent(
                        capability: .permissions,
                        audience: .developers,
                        code: "finder-automation-state-changed",
                        metadata: .init(state: isTrusted ? "allowed" : "not-allowed")
                    )
                )
                self?.refreshFileSelectionObserver()
            }
            .store(in: &cancellables)

        licensing.$status
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshLicensedEngines()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            preferences.$captureSelections,
            preferences.$isEnabled,
            preferences.$isPrivateModeEnabled
        )
        .dropFirst()
        .removeDuplicates { previous, current in
            previous.0 == current.0 && previous.1 == current.1 && previous.2 == current.2
        }
        .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.refreshSelectionEngine()
        }
        .store(in: &cancellables)

        Publishers.CombineLatest3(
            preferences.$captureFileSelections,
            preferences.$isEnabled,
            preferences.$isPrivateModeEnabled
        )
        .dropFirst()
        .removeDuplicates { previous, current in
            previous.0 == current.0 && previous.1 == current.1 && previous.2 == current.2
        }
        .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.refreshFileSelectionObserver()
        }
        .store(in: &cancellables)

        Publishers.CombineLatest4(
            preferences.$selectionCaptureMode,
            preferences.$captureSelections,
            preferences.$isEnabled,
            preferences.$middleClickTriggerEnabled
        )
        .dropFirst()
        .removeDuplicates { previous, current in
            previous.0 == current.0 && previous.1 == current.1 && previous.2 == current.2 && previous.3 == current.3
        }
        .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
        .sink { [weak self, weak permissions] _ in
            guard permissions?.isInputMonitoringTrusted == true else { return }
            self?.refreshMouseEventTap()
        }
        .store(in: &cancellables)

        Publishers.MergeMany([
            preferences.$captureDoubleClickSelections.map { _ in () }.eraseToAnyPublisher(),
            preferences.$captureTripleClickSelections.map { _ in () }.eraseToAnyPublisher(),
            preferences.$captureShiftArrowSelections.map { _ in () }.eraseToAnyPublisher(),
            preferences.$captureCommandASelections.map { _ in () }.eraseToAnyPublisher(),
        ])
        .dropFirst(4)
        .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
        .sink { [weak self, weak permissions] _ in
            guard permissions?.isInputMonitoringTrusted == true else { return }
            self?.refreshMouseEventTap()
        }
        .store(in: &cancellables)

        preferences.$isPrivateModeEnabled
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak permissions] _ in
                guard permissions?.isInputMonitoringTrusted == true else { return }
                self?.refreshMouseEventTap()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            preferences.$clipboardLinkMode, preferences.$isEnabled, preferences.$isPrivateModeEnabled
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.refreshClipboardObserver() }
        .store(in: &cancellables)

        primaryStore.$current.receive(on: DispatchQueue.main)
            .sink { [weak toastPresenter] item in
                if item == nil { toastPresenter?.dismiss() }
            }.store(in: &cancellables)
        preferences.$isPrivateModeEnabled.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak toastPresenter] enabled in
                if enabled { toastPresenter?.dismiss() }
            }.store(in: &cancellables)
        preferences.$showCaptureToasts.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak toastPresenter] enabled in
                if !enabled { toastPresenter?.dismiss() }
            }.store(in: &cancellables)

        preferences.$isEnabled.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.pasteController.cancelPendingPastes() }
            }.store(in: &cancellables)

    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.diagnostics.record(
            DiagnosticEvent(
                capability: .app,
                audience: .developers,
                outcome: .succeeded,
                code: "application-stopping"
            )
        )
        pasteController.cancelPendingPastes()
        supportActions.cancelClipboardProbe()
        toastPresenter.dismiss()
        permissions.stopAutoRefresh()
        selectionEngine.stop()
        fileSelectionObserver.stop()
        clipboardObserver.stop()
        keyboardShortcutController.stop()
        mouseEventTap.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showSettings()
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        permissions?.refresh()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Permissions & Setup...", action: #selector(showSettingsFromMenu), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        return menu
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(handleDeepLink)
    }

    private func refreshMouseEventTap() {
        defer { appState.middleClickIsRunning = mouseEventTap.isRunning }
        guard permissions.isInputMonitoringTrusted, appState.licensing.allowsProductUse else {
            mouseEventTap.stop()
            return
        }
        mouseEventTap.start()
    }

    private func refreshSelectionEngine() {
        appState.textCaptureIsRunning = false
        guard permissions.isAccessibilityTrusted,
            appState.preferences.shouldRunTextSelectionCapture,
            appState.licensing.allowsProductUse
        else {
            selectionEngine.stop()
            return
        }
        selectionEngine.start()
        appState.textCaptureIsRunning = true
    }

    private func refreshFileSelectionObserver() {
        appState.fileCaptureIsRunning = false
        guard permissions.isFinderAutomationTrusted,
            appState.preferences.shouldRunFileSelectionCapture,
            appState.licensing.allowsProductUse
        else {
            fileSelectionObserver.stop()
            return
        }
        fileSelectionObserver.start()
        appState.fileCaptureIsRunning = true
    }

    private func refreshClipboardObserver() {
        if appState.licensing.allowsProductUse && appState.preferences.shouldRunClipboardImport {
            clipboardObserver.start()
        } else {
            clipboardObserver.stop()
        }
    }

    private func refreshLicensedEngines() {
        if !appState.licensing.allowsProductUse { pasteController.cancelPendingPastes() }
        refreshMouseEventTap()
        refreshSelectionEngine()
        refreshFileSelectionObserver()
        refreshClipboardObserver()
    }

    private func handleMenuAction(_ action: MenuAction) {
        switch action {
        case .about:
            showAbout()
        case .showSetup:
            showSettings(selectedTab: .setup)
        case .settings:
            showSettings()
        case .toggleEnabled:
            appState.preferences.isEnabled.toggle()
        case .togglePrivateMode:
            appState.preferences.isPrivateModeEnabled.toggle()
        case .sendPrimaryToClipboard:
            sendPrimaryToClipboard()
        case .clear:
            pasteController.cancelPendingPastes()
            appState.primaryStore.clear()
        case .pauseCurrentApp:
            appState.appRules.pauseFrontmostApp()
        case .quit:
            NSApp.terminate(nil)
        }
    }

    @objc private func showAbout() {
        let credits = NSMutableAttributedString(
            string:
                "Select text. Middle-click to paste.\n\nFree software. Redistribution permitted.\nProvided without warranty.\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 12)])
        if let licenseURL = Bundle.main.url(forResource: "LICENSE", withExtension: "txt")
            ?? URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")
        {
            credits.append(NSAttributedString(string: "GPL-3.0-only", attributes: [.link: licenseURL]))
        }
        credits.append(NSAttributedString(string: " · "))
        if let repositoryURL = URL(string: "https://github.com/machineyearningengineer/primary-paste") {
            credits.append(NSAttributedString(string: "Source and issues", attributes: [.link: repositoryURL]))
        }
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showSettings(selectedTab: SettingsTab? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showSettings(selectedTab: selectedTab)
            }
            return
        }

        if let selectedTab {
            settingsNavigation.present(selectedTab)
        }

        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                rootView: SettingsView(
                    appState: appState,
                    permissions: permissions,
                    navigation: settingsNavigation,
                    sendPrimaryToClipboard: { [weak self] in
                        self?.sendPrimaryToClipboard()
                    },
                    previewCaptureToast: { [weak self] in
                        Task { @MainActor in self?.supportActions.previewCaptureToast() }
                    },
                    previewLimitToast: { [weak self] in
                        Task { @MainActor in self?.supportActions.previewLimitToast() }
                    },
                    runClipboardLinkProbe: { [weak self] in
                        Task { @MainActor in self?.supportActions.runClipboardLinkProbe() }
                    },
                    runPrivacyProbe: { [weak self] in
                        Task { @MainActor in self?.supportActions.runPrivacyProbe() }
                    },
                    copyManualVerificationReportText: { [weak self] report in
                        self?.copyManualVerificationReport(report)
                    },
                    copyDiagnostics: { [weak self] in
                        self?.copyDiagnostics()
                    },
                    retryServices: { [weak self] in
                        self?.permissions.refresh()
                        self?.refreshLicensedEngines()
                    }
                )
            )
        }

        guard let window = settingsWindowController?.window else { return }
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.centerIfNeeded()
        window.level = .floating
        settingsWindowController?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak window] in
            window?.level = .normal
        }
    }

    private func sendPrimaryToClipboard() {
        guard let current = appState.primaryStore.peekItem() else { return }
        clipboardRestorer.writeToUserClipboard(current)
        clipboardObserver.adoptCurrentPasteboardState()
    }

    private func copyDiagnostics() {
        clipboardObserver.suppressProgrammaticChanges(reason: "copy diagnostics")

        let report = SupportReportBuilder(
            appState: appState,
            permissions: permissions,
            privacyFilter: privacyFilter
        ).makeReport()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
        clipboardObserver.adoptCurrentPasteboardState()
    }

    private func copyManualVerificationReport(_ report: String) {
        clipboardObserver.suppressProgrammaticChanges(reason: "copy manual checks report")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
        clipboardObserver.adoptCurrentPasteboardState()
    }

    private func shouldShowSetupOnLaunch(preferences: PreferencesStore) -> Bool {
        SetupLaunchPolicy.shouldOpenSetupWindowOnLaunch(
            showSetupOnLaunch: preferences.showSetupOnLaunch,
            needsAccessibilitySetup: preferences.shouldUseAccessibility && !permissions.isAccessibilityTrusted,
            needsInputMonitoringSetup: preferences.shouldMonitorGlobalEvents && !permissions.isInputMonitoringTrusted,
            needsFinderAutomationSetup: preferences.shouldRunFileSelectionCapture
                && !permissions.isFinderAutomationTrusted,
            isAppActive: NSApp.isActive
        )
    }

    private func installDeepLinkHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: urlString)
        else {
            return
        }

        handleDeepLink(url)
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.caseInsensitiveCompare("primarypaste") == .orderedSame else { return }
        guard appState != nil else {
            pendingDeepLinks.append(url)
            return
        }

        let parts = ([url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
        guard let command = parts.first else {
            showSettings(selectedTab: .setup)
            return
        }

        switch command {
        case "paste":
            handleExternalPasteTrigger()
        case "show-setup", "setup", "onboarding":
            showSettings(selectedTab: .setup)
        case "settings":
            showSettings(selectedTab: settingsTab(named: parts.dropFirst().first) ?? .setup)
        case "license":
            guard appState.licensing.isAvailable,
                parts.dropFirst().first == "claim",
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let sessionID = components.queryItems?.first(where: { $0.name == "session_id" })?.value,
                !sessionID.isEmpty
            else {
                showSettings(selectedTab: .setup)
                return
            }
            showSettings(selectedTab: .license)
            Task { await appState.licensing.claimPurchase(sessionID: sessionID) }
        default:
            showSettings(selectedTab: .setup)
        }
    }

    private func handleExternalPasteTrigger() {
        guard appState.preferences.externalTriggerEnabled else {
            appState.diagnostics.recordPasteDecision("Blocked external trigger: disabled in Paste settings")
            return
        }

        pasteController.pastePrimarySelectionFromExternalTrigger()
    }

    private func settingsTab(named name: String?) -> SettingsTab? {
        switch name {
        case "setup", "onboarding":
            return .setup
        case "general":
            return .general
        case "selection", "capture":
            return .selection
        case "paste":
            return .paste
        case "queue":
            return .paste
        case "apps", "rules":
            return .apps
        case "privacy":
            return .privacy
        case "license":
            return appState.licensing.isAvailable ? .license : nil
        default:
            return nil
        }
    }

    @objc private func showSettingsFromMenu() {
        showSettings(selectedTab: .setup)
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Primary Paste")
        appMenuItem.submenu = appMenu

        let aboutItem = NSMenuItem(
            title: "About Primary Paste...", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let showItem = NSMenuItem(
            title: "Permissions & Setup...", action: #selector(showSettingsFromMenu), keyEquivalent: ",")
        showItem.target = self
        appMenu.addItem(showItem)
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(title: "Quit Primary Paste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        mainMenu.addItem(appMenuItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        for (title, action, key) in [
            ("Undo", Selector(("undo:")), "z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ] {
            editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func applyActivationPolicy(showDockIcon: Bool) {
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }

    private func applyApplicationIcon(_ variant: PrimaryPasteIconVariant) {
        NSApp.applicationIconImage = PrimaryPasteIconRenderer.image(
            for: variant,
            size: 512,
            style: .appIcon
        )
    }

}

private extension NSWindow {
    func centerIfNeeded() {
        guard !isVisible else { return }
        center()
    }
}

@main
enum PrimaryPasteMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
