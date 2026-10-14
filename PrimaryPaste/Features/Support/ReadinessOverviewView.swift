import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct Phase6ReadinessDisclosureCard: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var permissions: PermissionsCoordinator
    @Binding var isExpanded: Bool
    let runClipboardLinkProbe: () -> Void
    let runPrivacyProbe: () -> Void
    let runAppProbes: () -> Void
    let copyDiagnostics: () -> Void
    let hideSupport: () -> Void

    private var permissionsAreReady: Bool {
        (!preferences.shouldUseAccessibility || permissions.isAccessibilityTrusted)
            && (!preferences.shouldMonitorGlobalEvents || permissions.isInputMonitoringTrusted)
            && (!preferences.captureFileSelections || permissions.isFinderAutomationTrusted)
    }

    private var checksPassed: Bool {
        appState.diagnostics.clipboardLinkModeProbePassed
            && appState.diagnostics.privacyProbePassed
    }

    private var healthIsReady: Bool {
        permissionsAreReady && checksPassed
    }

    private var healthStatusText: String {
        guard appState.diagnostics.hasHealthCheckEvidence else { return "Not checked" }
        return healthIsReady ? "Healthy" : "Needs attention"
    }

    private var healthStatusTone: StatusBadgeTone {
        guard appState.diagnostics.hasHealthCheckEvidence else { return .neutral }
        return healthIsReady ? .success : .warning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard {
                SettingsCardHeader(
                    title: "Health Check",
                    detail: "Check permissions, clipboard isolation, and privacy filters.",
                    systemImage: healthIsReady ? "checkmark.seal.fill" : "waveform.path.ecg",
                    tint: healthIsReady ? Color.green : Color.accentColor
                ) {
                    Spacer()
                    StatusBadge(
                        isComplete: healthIsReady,
                        text: healthStatusText,
                        tone: healthStatusTone
                    )
                    Button(isExpanded ? "Hide" : "Open") {
                        withAnimation(.snappy(duration: 0.22)) {
                            isExpanded.toggle()
                        }
                    }
                    .controlSize(.small)
                    Menu {
                        Button(action: hideSupport) {
                            Label("Hide Support", systemImage: "eye.slash")
                        }
                    } label: {
                        Label("Support Options", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Support options")
                }
            }

            if isExpanded {
                Phase6ReadinessCard(
                    appState: appState,
                    preferences: preferences,
                    permissions: permissions,
                    runClipboardLinkProbe: runClipboardLinkProbe,
                    runPrivacyProbe: runPrivacyProbe,
                    runAppProbes: runAppProbes,
                    copyDiagnostics: copyDiagnostics
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct Phase6ReadinessCard: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var permissions: PermissionsCoordinator
    let runClipboardLinkProbe: () -> Void
    let runPrivacyProbe: () -> Void
    let runAppProbes: () -> Void
    let copyDiagnostics: () -> Void

    @State private var showsReadinessDetails = false

    private var setupReady: Bool {
        (!preferences.shouldUseAccessibility || permissions.isAccessibilityTrusted)
            && (!preferences.shouldMonitorGlobalEvents || permissions.isInputMonitoringTrusted)
            && (!preferences.captureFileSelections || permissions.isFinderAutomationTrusted)
    }

    private var textCaptureReady: Bool {
        preferences.isEnabled && preferences.captureSelections && permissions.isAccessibilityTrusted
    }

    private var pasteGuardReady: Bool {
        true
    }

    private var middleClickSeen: Bool {
        appState.diagnostics.middleClickCount > 0
    }

    private var pasteSucceeded: Bool {
        let decision = appState.diagnostics.lastPasteDecision
        return decision.hasPrefix("Paste requested")
            || decision.hasPrefix("Paste command sent")
            || decision.hasPrefix("Inserted text directly")
            || decision.hasPrefix("Typed text")
            || decision.hasPrefix("Clipboard-restored text pasted")
            || decision.hasPrefix("Clipboard-only payload pasted")
    }

    private var passThroughObserved: Bool {
        PastePassThroughEvidence.confirmsTargetSafety(appState.diagnostics.lastPasteDecision)
    }

    private var clipboardLinkModeProbeIsCurrent: Bool {
        appState.diagnostics.clipboardLinkModeProbePassed
            && appState.diagnostics.clipboardLinkModeProbeModeTitle == preferences.clipboardLinkMode.title
    }

    private var nativeClipboardDefaultProbeIsCurrent: Bool {
        preferences.clipboardLinkMode == .separate
            && appState.diagnostics.nativeClipboardDefaultProbePassed
    }

    private var showsFinderReadinessCheck: Bool {
        preferences.captureFileSelections
            || permissions.isFinderAutomationTrusted
            || appState.diagnostics.hasFileSelectionEvidence
    }

    private var finderReadinessDetail: String {
        if preferences.captureFileSelections {
            return permissions.isFinderAutomationTrusted
                ? appState.diagnostics.lastFileSelectionDecision
                : "Needs Finder Automation"
        }
        return permissions.isFinderAutomationTrusted ? "Off; Automation allowed" : "Off"
    }

    var body: some View {
        SettingsCard {
            SettingsCardHeader(
                title: "Check Results",
                detail: "Current permission and safety status.",
                systemImage: setupReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                tint: setupReady ? Color.green : Color.orange
            ) {
                Spacer()
                Button("Run Checks", action: runAppProbes)
                ReadinessActionMenu(
                    runClipboardLinkProbe: runClipboardLinkProbe,
                    runPrivacyProbe: runPrivacyProbe,
                    copyDiagnostics: copyDiagnostics
                )
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ReadinessSummaryTile(
                    title: "Permissions",
                    detail: setupReady ? "Ready for enabled features" : "Needs attention",
                    systemImage: "lock.shield",
                    isComplete: setupReady
                )
                ReadinessSummaryTile(
                    title: "Selection",
                    detail: textCaptureReady ? "Ready to capture" : "Paused until allowed",
                    systemImage: "selection.pin.in.out",
                    isComplete: textCaptureReady
                )
                ReadinessSummaryTile(
                    title: "Middle-Click",
                    detail: pasteSucceeded ? "Paste observed" : "Try an input field",
                    systemImage: "cursorarrow.click.2",
                    isComplete: pasteGuardReady && middleClickSeen && pasteSucceeded
                )
                ReadinessSummaryTile(
                    title: "Privacy",
                    detail: appState.diagnostics.privacyProbePassed ? "Self-test passed" : "Awaiting self-test",
                    systemImage: "hand.raised",
                    isComplete: preferences.sensitiveTextFiltering && appState.diagnostics.privacyProbePassed
                )
            }

            SettingsDisclosureButton(isExpanded: $showsReadinessDetails) {
                Text(showsReadinessDetails ? "Hide check details" : "Show check details")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if showsReadinessDetails {
                VStack(alignment: .leading, spacing: 14) {
                    Divider()

                    ReadinessProofGroup(title: "System") {
                        ReadinessCheckRow(
                            title: "Required permissions",
                            detail: setupReady ? "Ready" : "Needs attention",
                            isComplete: setupReady
                        )
                        if showsFinderReadinessCheck {
                            ReadinessCheckRow(
                                title: "Finder file capture",
                                detail: finderReadinessDetail,
                                isComplete: !preferences.captureFileSelections || permissions.isFinderAutomationTrusted
                            )
                        }
                    }

                    ReadinessProofGroup(title: "Clipboard") {
                        ReadinessCheckRow(
                            title: "Clipboard link",
                            detail: preferences.clipboardLinkMode == .separate
                                ? "Separate by default" : preferences.clipboardLinkMode.title,
                            isComplete: preferences.clipboardLinkMode == .separate
                        )
                        ReadinessCheckRow(
                            title: "Native clipboard default",
                            detail: nativeClipboardDefaultProbeIsCurrent
                                ? appState.diagnostics.lastNativeClipboardDefaultProbe
                                : "Awaiting Separate-mode clipboard proof",
                            isComplete: nativeClipboardDefaultProbeIsCurrent
                        )
                        ReadinessCheckRow(
                            title: "Clipboard self-capture guard",
                            detail: appState.diagnostics.lastClipboardSelfCaptureProbe,
                            isComplete: appState.diagnostics.clipboardSelfCaptureProbePassed
                        )
                        ReadinessCheckRow(
                            title: "Clipboard mode check",
                            detail: clipboardLinkModeProbeIsCurrent
                                ? appState.diagnostics.lastClipboardLinkModeProbe
                                : "Awaiting \(preferences.clipboardLinkMode.title) check",
                            isComplete: clipboardLinkModeProbeIsCurrent
                        )
                    }

                    ReadinessProofGroup(title: "Interaction") {
                        ReadinessCheckRow(
                            title: "Text selection capture",
                            detail: textCaptureReady
                                ? appState.diagnostics.lastSelectionDecision : "Paused until enabled and allowed",
                            isComplete: textCaptureReady
                        )
                        ReadinessCheckRow(
                            title: "Paste guard",
                            detail: "Editable fields only, pass-through elsewhere",
                            isComplete: pasteGuardReady
                        )
                        ReadinessCheckRow(
                            title: "Middle-click observed",
                            detail: middleClickSeen
                                ? "\(appState.diagnostics.middleClickCount) seen" : "No middle-click seen yet",
                            isComplete: middleClickSeen
                        )
                        ReadinessCheckRow(
                            title: "Paste decision",
                            detail: appState.diagnostics.lastPasteDecision,
                            isComplete: pasteSucceeded
                        )
                        ReadinessCheckRow(
                            title: "Pass-through check",
                            detail: passThroughObserved
                                ? appState.diagnostics.lastPasteDecision : "Awaiting non-editable middle-click",
                            isComplete: passThroughObserved
                        )
                    }

                    ReadinessProofGroup(title: "Privacy") {
                        ReadinessCheckRow(
                            title: "Sensitive-text self-test",
                            detail: appState.diagnostics.privacyProbePassed
                                ? appState.diagnostics.lastPrivacyProbe
                                : (preferences.sensitiveTextFiltering
                                    ? "Awaiting privacy self-test" : "Sensitive filtering off"),
                            isComplete: preferences.sensitiveTextFiltering && appState.diagnostics.privacyProbePassed
                        )
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

struct ReadinessActionMenu: View {
    let runClipboardLinkProbe: () -> Void
    let runPrivacyProbe: () -> Void
    let copyDiagnostics: () -> Void

    var body: some View {
        Menu {
            Button("Check Clipboard", action: runClipboardLinkProbe)
            Button("Check Privacy", action: runPrivacyProbe)
            Divider()
            Button("Copy Report", action: copyDiagnostics)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }
}

struct EngineStatusStrip: View {
    let textCaptureStatus: EngineStatus
    let middleClickStatus: EngineStatus
    let clipboardImportStatus: EngineStatus
    let finderStatus: EngineStatus

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                horizontalEngineColumns
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                gridEngineColumns
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.settingsAdaptiveSurface(lightOpacity: 0.025, darkOpacity: 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.10))
        )
    }

    @ViewBuilder
    private var horizontalEngineColumns: some View {
        HStack(spacing: 8) {
            EngineStatusColumn(
                systemImage: "selection.pin.in.out",
                title: "Text Capture",
                status: textCaptureStatus
            )
            EngineStatusDivider()

            EngineStatusColumn(
                systemImage: "cursorarrow.click",
                title: "Middle-Click",
                status: middleClickStatus
            )
            EngineStatusDivider()

            EngineStatusColumn(
                systemImage: "doc.on.clipboard",
                title: "Clipboard",
                status: clipboardImportStatus
            )
            EngineStatusDivider()

            EngineStatusColumn(
                systemImage: "folder",
                title: "Finder",
                status: finderStatus
            )
        }
    }

    @ViewBuilder
    private var gridEngineColumns: some View {
        EngineStatusColumn(
            systemImage: "selection.pin.in.out",
            title: "Text Capture",
            status: textCaptureStatus
        )
        EngineStatusColumn(
            systemImage: "cursorarrow.click",
            title: "Middle-Click",
            status: middleClickStatus
        )
        EngineStatusColumn(
            systemImage: "doc.on.clipboard",
            title: "Clipboard",
            status: clipboardImportStatus
        )
        EngineStatusColumn(
            systemImage: "folder",
            title: "Finder",
            status: finderStatus
        )
    }
}

enum EngineStatus {
    case running(String)
    case needsPermission(String)
    case paused(String)
    case idle(String)

    var label: String {
        switch self {
        case .running(let label), .needsPermission(let label), .paused(let label), .idle(let label):
            return label
        }
    }

    var tint: Color {
        switch self {
        case .running:
            return Color.green
        case .needsPermission:
            return Color.orange
        case .paused:
            return Color.indigo
        case .idle:
            return Color.secondary
        }
    }

    var isComplete: Bool {
        if case .running = self {
            return true
        }
        return false
    }
}

struct EngineStatusDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.18))
            .frame(width: 1)
            .padding(.vertical, 3)
    }
}

struct EngineStatusColumn: View {
    let systemImage: String
    let title: String
    let status: EngineStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(status.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.tint)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
}

enum ManualVerificationGroup: String, CaseIterable, Identifiable {
    case setup
    case selection
    case paste
    case clipboard
    case filesAndPrivacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup: "Setup"
        case .selection: "Selection"
        case .paste: "Paste"
        case .clipboard: "Clipboard"
        case .filesAndPrivacy: "Files & Privacy"
        }
    }

    var systemImage: String {
        switch self {
        case .setup: "checklist.checked"
        case .selection: "selection.pin.in.out"
        case .paste: "cursorarrow.click"
        case .clipboard: "doc.on.clipboard"
        case .filesAndPrivacy: "lock.shield"
        }
    }
}

enum ManualVerificationProofKind: CaseIterable {
    case appProbe
    case runtimeEvidence
    case settingsAndHuman
    case humanCheck

    var title: String {
        switch self {
        case .appProbe: "Built-in Check"
        case .runtimeEvidence: "Seen This Run"
        case .settingsAndHuman: "Setting + Check"
        case .humanCheck: "Hands-on Check"
        }
    }

    var detail: String {
        switch self {
        case .appProbe:
            return "Primary Paste can run this built-in check, but real-world confirmation is still useful."
        case .runtimeEvidence:
            return "Primary Paste can confirm this from matching source, target, or warning activity seen this run."
        case .settingsAndHuman:
            return "Primary Paste can confirm the setting, while the native app behavior still needs a quick check."
        case .humanCheck:
            return
                "This depends on macOS permissions, third-party app behavior, or real gestures that need a hands-on check."
        }
    }

    var systemImage: String {
        switch self {
        case .appProbe: "checkmark.shield"
        case .runtimeEvidence: "waveform.path.ecg"
        case .settingsAndHuman: "switch.2"
        case .humanCheck: "hand.tap"
        }
    }

    var tint: Color {
        switch self {
        case .appProbe: Color.green
        case .runtimeEvidence: Color.accentColor
        case .settingsAndHuman: Color.indigo
        case .humanCheck: Color.orange
        }
    }
}

struct ManualVerificationItem: Identifiable {
    let id: String
    let group: ManualVerificationGroup
    let title: String
    let detail: String

    var proofKind: ManualVerificationProofKind {
        switch id {
        case "native-clipboard-default", "clipboard-link-modes":
            return .appProbe
        case "url-bar-auto-selection", "cross-app-text-capture", "browser-pass-through", "editable-paste",
            "finder-file-paste", "text-limit-toast", "finder-limit-toast":
            return .runtimeEvidence
        case "permission-persistence", "privacy-guards":
            return .settingsAndHuman
        default:
            return .humanCheck
        }
    }

    static let all: [ManualVerificationItem] = [
        ManualVerificationItem(
            id: "setup-needed-status",
            group: .setup,
            title: "Setup-needed status",
            detail:
                "When a required permission is missing, the menu bar item clearly changes to the setup-needed state."
        ),
        ManualVerificationItem(
            id: "permission-persistence",
            group: .setup,
            title: "Permission persistence",
            detail:
                "A rebuild keeps Accessibility and any currently needed Input Monitoring permission attached to the signed app."
        ),
        ManualVerificationItem(
            id: "url-bar-auto-selection",
            group: .selection,
            title: "URL bar auto-selection",
            detail: "Arc or Safari address-bar focus does not replace Primary unless you deliberately select text."
        ),
        ManualVerificationItem(
            id: "cross-app-text-capture",
            group: .selection,
            title: "Cross-app text capture",
            detail: "Safari or Arc, Codex, Terminal, TextEdit, and Finder name fields capture when AX allows it."
        ),
        ManualVerificationItem(
            id: "browser-pass-through",
            group: .paste,
            title: "Browser pass-through",
            detail:
                "Middle-click links, tabs, and close targets keep their native browser behavior; Support Details should record the pass-through."
        ),
        ManualVerificationItem(
            id: "editable-paste",
            group: .paste,
            title: "Editable paste",
            detail: "Middle-click pastes into native fields, web inputs, and the Codex composer."
        ),
        ManualVerificationItem(
            id: "native-clipboard-default",
            group: .clipboard,
            title: "Native clipboard default",
            detail: "Cmd+C and Cmd+V keep normal macOS behavior while Clipboard Link is Separate."
        ),
        ManualVerificationItem(
            id: "clipboard-link-modes",
            group: .clipboard,
            title: "Clipboard link modes",
            detail:
                "Import Copies and Mirror Selections work without immediately feeding Primary's own writes back into itself."
        ),
        ManualVerificationItem(
            id: "finder-file-paste",
            group: .filesAndPrivacy,
            title: "Finder file paste",
            detail: "Finder selections paste or attach in apps that accept file paste."
        ),
        ManualVerificationItem(
            id: "text-limit-toast",
            group: .filesAndPrivacy,
            title: "Text cap warning",
            detail: "Over-limit text shows a warning toast and leaves the previous Primary item alone."
        ),
        ManualVerificationItem(
            id: "finder-limit-toast",
            group: .filesAndPrivacy,
            title: "Finder cap warning",
            detail: "Over-limit Finder selections show a warning toast and do not partially capture."
        ),
        ManualVerificationItem(
            id: "privacy-guards",
            group: .filesAndPrivacy,
            title: "Privacy guards",
            detail:
                "Private Mode, blocked apps, and secure fields block capture; sensitive-looking text is refused and not stored."
        ),
    ]
}
