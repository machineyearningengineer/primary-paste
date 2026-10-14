import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case setup
    case general
    case selection
    case paste
    case apps
    case privacy
    case license
    case support

    var id: String { rawValue }

    static func visibleTabs(showSupport: Bool, showLicense: Bool = false) -> [SettingsTab] {
        allCases.filter { tab in
            (showSupport || tab != .support) && (showLicense || tab != .license)
        }
    }

    var title: String {
        switch self {
        case .setup: "Setup"
        case .general: "General"
        case .selection: "Selection"
        case .paste: "Paste"
        case .apps: "Apps"
        case .privacy: "Privacy"
        case .license: "License"
        case .support: "Support"
        }
    }

    var systemImage: String {
        switch self {
        case .setup: "checklist.checked"
        case .general: "switch.2"
        case .selection: "selection.pin.in.out"
        case .paste: "cursorarrow.click"
        case .apps: "app.badge"
        case .privacy: "lock.shield"
        case .license: "key"
        case .support: "wrench.and.screwdriver"
        }
    }
}

final class SettingsNavigation: ObservableObject {
    @Published var selectedTab: SettingsTab = .setup
    @Published var presentationID = UUID()

    func present(_ tab: SettingsTab) {
        selectedTab = tab
        presentationID = UUID()
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var permissions: PermissionsCoordinator
    @ObservedObject var navigation: SettingsNavigation
    var sendPrimaryToClipboard: () -> Void = {}
    var previewCaptureToast: () -> Void = {}
    var previewLimitToast: () -> Void = {}
    var runClipboardLinkProbe: () -> Void = {}
    var runPrivacyProbe: () -> Void = {}
    var copyManualVerificationReportText: (String) -> Void = { _ in }
    var copyDiagnostics: () -> Void = {}
    var retryServices: () -> Void = {}

    @ViewBuilder
    private var selectedContent: some View {
        switch navigation.selectedTab {
        case .setup:
            SetupSettingsView(
                appState: appState,
                preferences: appState.preferences,
                permissions: permissions,
                navigation: navigation,
                retryServices: retryServices
            )

        case .general:
            GeneralSettingsView(
                preferences: appState.preferences,
                appState: appState,
                previewCaptureToast: previewCaptureToast,
                previewLimitToast: previewLimitToast
            )

        case .selection:
            SelectionSettingsView(
                preferences: appState.preferences,
                permissions: permissions
            )

        case .paste:
            PasteSettingsView(
                appState: appState,
                preferences: appState.preferences,
                sendPrimaryToClipboard: sendPrimaryToClipboard
            )

        case .apps:
            AppsSettingsView(appState: appState)

        case .privacy:
            PrivacySettingsView(
                appState: appState,
                preferences: appState.preferences,
                permissions: permissions
            )

        case .license:
            LicensingSettingsView(licensing: appState.licensing)

        case .support:
            SupportSettingsView(
                appState: appState,
                preferences: appState.preferences,
                permissions: permissions,
                navigation: navigation,
                runClipboardLinkProbe: runClipboardLinkProbe,
                runPrivacyProbe: runPrivacyProbe,
                copyManualVerificationReportText: copyManualVerificationReportText,
                copyDiagnostics: copyDiagnostics
            )
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            SettingsTabBar(
                selection: $navigation.selectedTab,
                tabs: SettingsTab.visibleTabs(
                    showSupport: appState.preferences.showSupport,
                    showLicense: appState.licensing.isAvailable
                )
            )
            selectedContent
                .id(navigation.presentationID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(18)
        .frame(minWidth: 720, minHeight: 520)
        .onChange(of: appState.preferences.showSupport) { _, isVisible in
            if !isVisible && navigation.selectedTab == .support {
                navigation.selectedTab = .setup
            }
        }
    }
}

struct SettingsTabBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: SettingsTab
    let tabs: [SettingsTab]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        if tabs.count <= 7 || selection == tab { Image(systemName: tab.systemImage) }
                        Text(tab.title)
                    }
                    .font(.callout.weight(selection == tab ? .semibold : .regular))
                    .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                .help("\(tab.title) (⌘\(index + 1))")
            }
        }
        .padding(4)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.16))
        )
        .frame(maxWidth: 820)
    }
}

struct SetupSettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var permissions: PermissionsCoordinator
    @ObservedObject var navigation: SettingsNavigation
    let retryServices: () -> Void
    @State private var isSetupDetailsExpanded = false

    private var setupProgress: (complete: Int, total: Int) {
        var checks = [
            accessibilityIsReady,
            inputMonitoringIsReady,
            preferences.isEnabled,
            appState.licensing.allowsProductUse,
            !preferences.shouldRunTextSelectionCapture || appState.textCaptureIsRunning,
            !preferences.shouldMonitorGlobalEvents || appState.middleClickIsRunning,
            !preferences.shouldRunFileSelectionCapture || appState.fileCaptureIsRunning,
        ]
        if preferences.shouldRunFileSelectionCapture {
            checks.append(permissions.isFinderAutomationTrusted)
        }
        return (checks.filter { $0 }.count, checks.count)
    }

    private var setupIsComplete: Bool {
        setupProgress.complete == setupProgress.total
    }

    private var setupShouldFoldDetails: Bool {
        setupSummaryKind == .ready || setupSummaryKind == .paused
    }

    private var setupSummaryKind: SetupSummaryKind {
        if setupIsComplete {
            return .ready
        }
        if !preferences.isEnabled {
            return .paused
        }
        return .needsAttention
    }

    private var setupSummaryTitle: String {
        switch setupSummaryKind {
        case .ready:
            return "Ready to Use"
        case .paused:
            return "Paused"
        case .needsAttention:
            return "Needs Attention"
        }
    }

    private var setupSummaryDetail: String {
        switch setupSummaryKind {
        case .ready:
            return "Your enabled features have the permissions they need."
        case .paused:
            return
                "Primary Paste is off. Enable it when you want selection capture and middle-click paste running again."
        case .needsAttention:
            return "\(setupProgress.complete) of \(setupProgress.total) essentials are ready. Fix the next step below."
        }
    }

    private var nextCheckLabel: String {
        nextSetupCheck.isComplete ? "Ready" : "Next Step"
    }

    private var accessibilityIsNeeded: Bool {
        preferences.shouldUseAccessibility
    }

    private var accessibilityIsReady: Bool {
        !accessibilityIsNeeded || permissions.isAccessibilityTrusted
    }

    private var accessibilityStatusText: String {
        if !accessibilityIsNeeded {
            return "Optional"
        }
        return permissions.isAccessibilityTrusted ? "Allowed" : "Required"
    }

    private var accessibilityDetailText: String {
        if !accessibilityIsNeeded {
            return
                "Not needed while Primary Paste is paused or the current features do not use selection/paste automation."
        }
        return "Lets Primary Paste read selected text, inspect text fields, and paste only where it should."
    }

    private var inputMonitoringIsNeeded: Bool {
        preferences.shouldMonitorGlobalEvents
    }

    private var inputMonitoringIsReady: Bool {
        !inputMonitoringIsNeeded || permissions.isInputMonitoringTrusted
    }

    private var inputMonitoringStatusText: String {
        if !inputMonitoringIsNeeded {
            return "Optional"
        }
        return permissions.isInputMonitoringTrusted ? "Allowed" : "Required"
    }

    private var inputMonitoringDetailText: String {
        if !inputMonitoringIsNeeded {
            return
                "Input Monitoring is optional with the current capture and paste settings because no global event tap is needed."
        }
        return "Lets Primary Paste see the global mouse, trackpad, or keyboard events enabled in settings."
    }

    private var finderFileSelectionIsReady: Bool {
        !preferences.captureFileSelections || permissions.isFinderAutomationTrusted
    }

    private var finderFileSelectionStatusText: String {
        if !preferences.captureFileSelections {
            return "Off"
        }
        return permissions.isFinderAutomationTrusted ? "Ready" : "Needs Permission"
    }

    private var finderAutomationPrimaryActionTitle: String {
        if !preferences.captureFileSelections {
            return "Review"
        }
        return permissions.isFinderAutomationTrusted ? "Refresh" : "Allow"
    }

    private var finderFileSelectionPrimaryActionTitle: String {
        preferences.captureFileSelections && !permissions.isFinderAutomationTrusted ? "Allow" : "Review"
    }

    private var showsFinderSetupRows: Bool {
        preferences.captureFileSelections
    }

    private var clipboardLinkStatusIsComplete: Bool {
        preferences.clipboardLinkMode == .separate
    }

    private var showsCaptureLinkSetupRows: Bool {
        !clipboardLinkStatusIsComplete || showsFinderSetupRows
    }

    private var clipboardLinkStatusText: String {
        preferences.clipboardLinkMode.title
    }

    private var textCaptureStatus: EngineStatus {
        guard preferences.isEnabled else { return .paused("Paused") }
        guard preferences.captureSelections else { return .idle("Off") }
        guard !preferences.isPrivateModeEnabled else { return .paused("Private") }
        guard !appState.appRules.isScreenLocked else { return .paused("Locked") }
        guard permissions.isAccessibilityTrusted else { return .needsPermission("Needs Access") }
        guard appState.licensing.allowsProductUse else { return .idle("Needs License") }
        return appState.textCaptureIsRunning ? .running("Running") : .idle("Starting")
    }

    private var middleClickStatus: EngineStatus {
        guard preferences.isEnabled else { return .paused("Paused") }
        guard preferences.middleClickTriggerEnabled else { return .idle("Off") }
        guard permissions.isInputMonitoringTrusted else { return .needsPermission("Needs Input") }
        guard permissions.isAccessibilityTrusted else { return .needsPermission("Needs Access") }
        guard appState.licensing.allowsProductUse else { return .idle("Needs License") }
        return appState.middleClickIsRunning ? .running("Listening") : .needsPermission("Unavailable")
    }

    private var clipboardImportStatus: EngineStatus {
        guard preferences.isEnabled else { return .paused("Paused") }
        guard !preferences.isPrivateModeEnabled else { return .paused("Private") }
        guard !appState.appRules.isScreenLocked else { return .paused("Locked") }
        switch preferences.clipboardLinkMode {
        case .separate:
            return .running("Separate")
        case .importCopies:
            return .running("Importing")
        case .mirrorSelections:
            return .running("Mirroring")
        }
    }

    private var finderStatus: EngineStatus {
        guard preferences.isEnabled else { return .paused("Paused") }
        guard preferences.captureFileSelections else { return .idle("Off") }
        guard !preferences.isPrivateModeEnabled else { return .paused("Private") }
        guard !appState.appRules.isScreenLocked else { return .paused("Locked") }
        guard permissions.isFinderAutomationTrusted else { return .needsPermission("Needs Finder") }
        guard appState.licensing.allowsProductUse else { return .idle("Needs License") }
        return appState.fileCaptureIsRunning ? .running("Watching") : .idle("Starting")
    }

    private var nextSetupCheck: SetupNextCheck {
        if accessibilityIsNeeded && !permissions.isAccessibilityTrusted {
            return SetupNextCheck(
                title: "Accessibility",
                detail:
                    "Allow Primary Paste to read selected text, inspect editable fields, and perform paste actions for the current settings.",
                statusText: "Required",
                isComplete: false,
                actionTitle: "Allow",
                action: permissions.requestAccessibilityPermission
            )
        }

        if inputMonitoringIsNeeded && !permissions.isInputMonitoringTrusted {
            return SetupNextCheck(
                title: "Input Monitoring",
                detail: "Allow global event monitoring for the current middle-click or selection settings.",
                statusText: "Required",
                isComplete: false,
                actionTitle: "Allow",
                action: permissions.requestInputMonitoringPermission
            )
        }

        if preferences.shouldRunFileSelectionCapture && !permissions.isFinderAutomationTrusted {
            return SetupNextCheck(
                title: "Finder Automation",
                detail: "Allow Finder selection capture, or turn file selection capture back off.",
                statusText: "Optional",
                isComplete: false,
                actionTitle: "Allow",
                action: permissions.requestFinderAutomationPermission
            )
        }

        if !preferences.isEnabled {
            return SetupNextCheck(
                title: "Primary Paste Paused",
                detail: "Enable the app when you want selection capture and middle-click paste to run.",
                statusText: "Paused",
                isComplete: false,
                actionTitle: "Enable",
                action: { preferences.isEnabled = true }
            )
        }

        if !appState.licensing.allowsProductUse {
            return SetupNextCheck(
                title: "License",
                detail: "Review your license to resume capture and paste.",
                statusText: "Required",
                isComplete: false,
                actionTitle: "Review License",
                action: { navigation.selectedTab = .license }
            )
        }

        if (preferences.shouldRunTextSelectionCapture && !appState.textCaptureIsRunning)
            || (preferences.shouldMonitorGlobalEvents && !appState.middleClickIsRunning)
            || (preferences.shouldRunFileSelectionCapture && !appState.fileCaptureIsRunning)
        {
            return SetupNextCheck(
                title: "Restart Background Services",
                detail:
                    "Permissions are ready, but an enabled service has not started. Retry without changing your settings.",
                statusText: "Unavailable",
                isComplete: false,
                actionTitle: "Retry",
                action: retryServices
            )
        }

        return SetupNextCheck(
            title: "Ready",
            detail: "Primary Paste is configured for the features you have enabled.",
            statusText: "Complete",
            isComplete: true,
            actionTitle: nil,
            action: nil
        )
    }

    private func handleFinderAutomationAction() {
        if !preferences.captureFileSelections {
            navigation.selectedTab = .selection
        } else if permissions.isFinderAutomationTrusted {
            permissions.refreshFinderAutomationStatus()
        } else {
            permissions.requestFinderAutomationPermission()
        }
    }

    private func handleFinderFileSelectionAction() {
        if preferences.captureFileSelections && !permissions.isFinderAutomationTrusted {
            permissions.requestFinderAutomationPermission()
        } else {
            navigation.selectedTab = .selection
        }
    }

    private func reviewPasteSettings() {
        navigation.selectedTab = .paste
    }

    private func reviewSelectionSettings() {
        navigation.selectedTab = .selection
    }

    private var practiceDisabledReason: String? {
        if !preferences.isEnabled { return "Enable Primary Paste above when you’re ready to try it." }
        if !appState.licensing.allowsProductUse { return "Review your license above to resume capture and paste." }
        if !accessibilityIsReady || !inputMonitoringIsReady {
            return "Finish the permissions above, then try your first paste."
        }
        if preferences.isPrivateModeEnabled {
            return "Private Mode is on. Turn it off from the menu bar when you want to capture new text."
        }
        if !preferences.captureSelections {
            return "Text selection capture is off. Enable it in Selection to use the practice page."
        }
        if !preferences.middleClickTriggerEnabled {
            return "Middle-click is off. Enable it in Paste, or use your configured shortcut."
        }
        if !appState.textCaptureIsRunning || !appState.middleClickIsRunning {
            return "Retry the background services above, then try your first paste."
        }
        return nil
    }

    @ViewBuilder
    private var setupDetailsSections: some View {
        SettingsSectionLabel(
            title: "Permissions",
            detail: "Only the permissions needed by your enabled features stay active."
        )

        SettingsCard {
            SetupStatusRow(
                title: "Accessibility",
                detail: accessibilityDetailText,
                isComplete: accessibilityIsReady,
                completeText: accessibilityStatusText,
                incompleteText: accessibilityStatusText,
                primaryActionTitle: permissions.isAccessibilityTrusted ? "Refresh" : "Allow",
                primaryAction: {
                    if permissions.isAccessibilityTrusted {
                        permissions.refreshFastStatus()
                    } else {
                        permissions.requestAccessibilityPermission()
                    }
                },
                secondaryActionTitle: "Open Settings",
                secondaryAction: permissions.openAccessibilitySettings
            )

            Divider()

            SetupStatusRow(
                title: "Input Monitoring",
                detail: inputMonitoringDetailText,
                isComplete: inputMonitoringIsReady,
                completeText: inputMonitoringStatusText,
                incompleteText: inputMonitoringStatusText,
                primaryActionTitle: permissions.isInputMonitoringTrusted ? "Refresh" : "Allow",
                primaryAction: {
                    if permissions.isInputMonitoringTrusted {
                        permissions.refreshFastStatus()
                    } else {
                        permissions.requestInputMonitoringPermission()
                    }
                },
                secondaryActionTitle: "Open Settings",
                secondaryAction: permissions.openInputMonitoringSettings
            )

            if showsFinderSetupRows {
                Divider()

                SetupStatusRow(
                    title: "Finder Automation",
                    detail:
                        "Lets Primary Paste read the selected files in Finder and Desktop while file selection capture is on.",
                    isComplete: permissions.isFinderAutomationTrusted,
                    completeText: "Allowed",
                    incompleteText: "Required for files",
                    primaryActionTitle: finderAutomationPrimaryActionTitle,
                    primaryAction: handleFinderAutomationAction,
                    secondaryActionTitle: "Open Settings",
                    secondaryAction: permissions.openAutomationSettings
                )
            }
        }

        SettingsSectionLabel(
            title: "Safety",
            detail: "Review paste targeting, clipboard restore, and enabled sources."
        )

        SettingsCard {
            SetupStatusRow(
                title: "App Enabled",
                detail: "Keeps selection capture and middle-click paste active.",
                isComplete: preferences.isEnabled,
                completeText: "On",
                incompleteText: "Paused",
                primaryActionTitle: preferences.isEnabled ? "Pause" : "Enable",
                primaryAction: { preferences.isEnabled.toggle() }
            )

            Divider()

            SetupStatusRow(
                title: "Clipboard Restore",
                detail:
                    "Middle-click paste restores the previous clipboard afterward. Rich multi-item clipboards are best-effort.",
                isComplete: preferences.preserveClipboard,
                completeText: "On",
                incompleteText: "Off",
                primaryActionTitle: "Review",
                primaryAction: reviewPasteSettings
            )

            Divider()

            SetupStatusRow(
                title: "Clipboard Link",
                detail:
                    "Controls whether Primary stays separate from the normal clipboard or shares selected content with it.",
                isComplete: clipboardLinkStatusIsComplete,
                completeText: clipboardLinkStatusText,
                incompleteText: clipboardLinkStatusText,
                primaryActionTitle: "Open Selection",
                primaryAction: reviewSelectionSettings
            )

            Divider()

            SetupStatusRow(
                title: "Middle-Click Pass-Through",
                detail:
                    "Editable targets can paste; tabs, links, and other non-text controls keep their native behavior.",
                isComplete: true,
                completeText: "Always",
                incompleteText: "Off",
                primaryActionTitle: "Review",
                primaryAction: reviewPasteSettings
            )
        }

        if showsFinderSetupRows {
            SettingsSectionLabel(
                title: "Extra Sources",
                detail: "Additional ways Primary can receive content, with shortcuts back to the right settings."
            )

            SettingsCard {
                SetupStatusRow(
                    title: "Finder File Selection",
                    detail:
                        "Selected files in Finder or on the Desktop become the next Primary item for middle-click paste or attach.",
                    isComplete: finderFileSelectionIsReady,
                    completeText: finderFileSelectionStatusText,
                    incompleteText: finderFileSelectionStatusText,
                    primaryActionTitle: finderFileSelectionPrimaryActionTitle,
                    primaryAction: handleFinderFileSelectionAction,
                    secondaryActionTitle: !permissions.isFinderAutomationTrusted ? "Open Settings" : nil,
                    secondaryAction: !permissions.isFinderAutomationTrusted
                        ? {
                            permissions.openAutomationSettings()
                        } : nil
                )
            }
        }
    }

    var body: some View {
        SettingsPage(
            title: "Setup",
            subtitle: "Select text once. Middle-click to paste it."
        ) {
            SetupOverviewCard(
                title: setupSummaryTitle,
                detail: setupSummaryDetail,
                setupIsComplete: setupIsComplete,
                summaryKind: setupSummaryKind,
                nextLabel: nextCheckLabel,
                nextCheck: nextSetupCheck,
                textCaptureStatus: textCaptureStatus,
                middleClickStatus: middleClickStatus,
                clipboardImportStatus: clipboardImportStatus,
                finderStatus: finderStatus
            )

            SetupPracticeCard(
                disabledReason: practiceDisabledReason,
                clipboardLinkMode: preferences.clipboardLinkMode,
                settingsActionTitle: !preferences.captureSelections
                    ? "Open Selection" : !preferences.middleClickTriggerEnabled ? "Open Paste" : nil,
                openPracticeSettings: !preferences.captureSelections ? reviewSelectionSettings : reviewPasteSettings,
                continueInMenuBar: {
                    preferences.showSetupOnLaunch = false
                    NSApp.keyWindow?.close()
                }
            )

            if setupShouldFoldDetails {
                SetupReviewDisclosureCard(
                    title: "Review Setup Details",
                    detail: setupSummaryKind == .paused
                        ? "Permissions and guardrails are still available if you want to inspect them."
                        : "Review permissions, clipboard choices, and optional sources.",
                    systemImage: "checklist",
                    isExpanded: $isSetupDetailsExpanded
                ) {
                    setupDetailsSections
                }
            } else {
                setupDetailsSections
            }

        }
        .onAppear {
            permissions.refreshFastStatus()
        }
    }
}

struct SetupNextCheck {
    let title: String
    let detail: String
    let statusText: String
    let isComplete: Bool
    let actionTitle: String?
    let action: (() -> Void)?
}

enum SetupSummaryKind {
    case ready
    case paused
    case needsAttention

    var tint: Color {
        switch self {
        case .ready:
            return Color.green
        case .paused:
            return Color.indigo
        case .needsAttention:
            return Color.orange
        }
    }

    var systemImage: String {
        switch self {
        case .ready:
            return "checkmark.seal.fill"
        case .paused:
            return "pause.circle.fill"
        case .needsAttention:
            return "exclamationmark.triangle.fill"
        }
    }
}

struct SetupOverviewCard: View {
    let title: String
    let detail: String
    let setupIsComplete: Bool
    let summaryKind: SetupSummaryKind
    let nextLabel: String
    let nextCheck: SetupNextCheck
    let textCaptureStatus: EngineStatus
    let middleClickStatus: EngineStatus
    let clipboardImportStatus: EngineStatus
    let finderStatus: EngineStatus

    private var badgeTone: StatusBadgeTone {
        if nextCheck.isComplete {
            return .success
        }
        if nextCheck.statusText == "Paused" {
            return .paused
        }
        return .warning
    }

    private var summaryTint: Color {
        summaryKind.tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(summaryTint.opacity(0.12))
                        Image(systemName: summaryKind.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(summaryTint)
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.title2.weight(.semibold))
                        Text(detail)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    SetupReadinessIndicator(kind: summaryKind)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Live Engines", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    EngineStatusStrip(
                        textCaptureStatus: textCaptureStatus,
                        middleClickStatus: middleClickStatus,
                        clipboardImportStatus: clipboardImportStatus,
                        finderStatus: finderStatus
                    )
                }
            }

            if !nextCheck.isComplete {
                Divider()

                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(nextLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            StatusBadge(isComplete: false, text: nextCheck.statusText, tone: badgeTone)
                        }
                        Text(nextCheck.title)
                            .font(.headline)
                        Text(nextCheck.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 16)

                    if let actionTitle = nextCheck.actionTitle, let action = nextCheck.action {
                        Button(actionTitle, action: action)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsSurface(
            Color.settingsOverviewSurface(),
            material: .ultraThin,
            materialOpacity: 0.24,
            strokeOpacity: 0.12
        )
    }
}

struct SetupReadinessIndicator: View {
    let kind: SetupSummaryKind

    var body: some View {
        switch kind {
        case .ready:
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)
                .padding(7)
                .accessibilityLabel("Ready")
        case .paused:
            StatusBadge(isComplete: false, text: "Paused", tone: .paused)
        case .needsAttention:
            StatusBadge(isComplete: false, text: "Needs Action", tone: .warning)
        }
    }
}

struct SetupReviewDisclosureCard<Content: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    private var backgroundFill: Color {
        Color.settingsReviewSurface(isExpanded: isExpanded)
    }

    private var strokeOpacity: Double {
        isExpanded ? 0.18 : 0.12
    }

    private var shadowOpacity: Double {
        isExpanded ? 0.06 : 0.035
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsDisclosureButton(isExpanded: $isExpanded, minHeight: 48) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    Text(isExpanded ? "Hide" : "Show")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    content
                }
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsSurface(
            backgroundFill,
            material: .thin,
            materialOpacity: 0.26,
            strokeOpacity: strokeOpacity,
            shadowOpacity: shadowOpacity,
            shadowRadius: 10,
            shadowY: 2
        )
    }
}
