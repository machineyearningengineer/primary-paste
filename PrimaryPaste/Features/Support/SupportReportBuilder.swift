import AppKit
import Foundation

struct SupportReportBuilder {
    let appState: AppState
    let permissions: PermissionsCoordinator
    let privacyFilter: PrivacyFilter

    func makeReport() -> String {
        let preferences = appState.preferences
        let current = appState.primaryStore.current
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let lastPoint =
            appState.diagnostics.lastEventLocation.map {
                "\(Int($0.x)), \(Int($0.y))"
            } ?? "none"

        return """
            Primary Paste Support Report
            Generated: \(ISO8601DateFormatter().string(from: Date()))
            Version: \(appVersion) (\(buildNumber))
            Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")
            macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)

            Setup
            Accessibility: \(accessibilityDiagnosticsStatus(preferences: preferences))
            Input Monitoring: \(inputMonitoringDiagnosticsStatus(preferences: preferences))
            Finder Automation: \(finderAutomationDiagnosticsStatus(preferences: preferences))

            State
            Enabled: \(preferences.isEnabled)
            Text Capture Engine Running: \(appState.textCaptureIsRunning)
            Middle Click Engine Running: \(appState.middleClickIsRunning)
            Finder Capture Engine Running: \(appState.fileCaptureIsRunning)
            Private Mode: \(preferences.isPrivateModeEnabled)
            Paste Mode: \(preferences.pasteMode.title)
            Middle Click Trigger: \(preferences.middleClickTriggerEnabled)
            Keyboard Shortcut Trigger: \(preferences.keyboardShortcutTriggerEnabled) (\(KeyboardShortcutController.shortcutDisplayName))
            External Trigger: \(preferences.externalTriggerEnabled)
            Show Dock Icon: \(preferences.showDockIcon)
            Menu Bar Icon: \(preferences.menuBarIconVariant.title)
            App Icon: \(preferences.appIconVariant.title)
            Menu Bar Status Text: \(preferences.showMenuBarStatusText)
            Show Setup On Launch: \(preferences.showSetupOnLaunch)
            Launch At Login: \(preferences.launchAtLogin)
            Preserve Clipboard: \(preferences.preserveClipboard)
            Editable Fields Only: Always
            Outside Editable Fields Pass Through: Always
            Capture Text Selections: \(preferences.captureSelections)
            Selection Capture Mode: \(preferences.selectionCaptureMode.title)
            Clipboard Link: \(preferences.clipboardLinkMode.title)
            Capture Finder File Selections: \(preferences.captureFileSelections)
            Plain Text Only: \(preferences.plainTextOnly)
            Sensitive Text Filtering: \(preferences.sensitiveTextFiltering)
            Capture Toasts: \(preferences.showCaptureToasts)
            Toast Source Label: \(preferences.showToastSourceLabel)
            Toast Size: \(preferences.captureToastSize.title)
            Toast Duration: \(String(format: "%.1f", preferences.captureToastDisplaySeconds))s

            Limits
            Selection Debounce: \(preferences.selectionCaptureDebounceMilliseconds)ms
            Text Minimum: \(preferences.minimumSelectionLength)
            Text Maximum: \(preferences.maximumSelectionLength == 0 ? "Unlimited" : preferences.maximumSelectionLength.formatted())
            Finder File Maximum: \(preferences.maximumFileSelectionCount)
            Queue Size: \(preferences.queueSize)
            Manual Checks Count: \(preferences.completedManualVerificationIDs.count)
            Manual Checks IDs: \(preferences.completedManualVerificationIDs.isEmpty ? "None" : preferences.completedManualVerificationIDs.joined(separator: ", "))

            Privacy Self Check
            Sensitive Sample: \(sensitiveSampleDecisionDescription())
            Privacy Probe: \(appState.diagnostics.lastPrivacyProbe)
            Privacy Probe Passed: \(appState.diagnostics.privacyProbePassed)
            Text Limit Policy: \(textLimitPolicyDescription(preferences: preferences))
            Finder Limit Policy: \(preferences.maximumFileSelectionCount.formatted()) item cap, refused as a whole

            Current Primary
            Has Primary: \(current != nil)
            Source: \(current?.sourceAppName ?? "None")
            Source Bundle ID: \(current?.sourceBundleIdentifier ?? "None")
            Clipboard Copy: \(current?.isClipboardCopy.description ?? "None")
            Payload: \(current.map(payloadDescription(for:)) ?? "None")
            Queue Count: \(appState.primaryStore.queue.count)

            Frontmost App
            Name: \(appState.appRules.frontmostAppName)
            Bundle ID: \(appState.appRules.frontmostBundleIdentifier ?? "unknown")

            Last Decisions
            Selection: \(appState.diagnostics.lastSelectionDecision)
            Selection Capture Sources: \(appState.diagnostics.selectionCaptureSourceSummary)
            Selection Capture Source Bundle IDs: \(appState.diagnostics.selectionCaptureSourceBundleIdentifiers.isEmpty ? "None" : appState.diagnostics.selectionCaptureSourceBundleIdentifiers.joined(separator: ", "))
            Clipboard: \(appState.diagnostics.lastClipboardDecision)
            Clipboard Self-Capture Probe: \(appState.diagnostics.lastClipboardSelfCaptureProbe)
            Clipboard Self-Capture Probe Passed: \(appState.diagnostics.clipboardSelfCaptureProbePassed)
            Clipboard Link Mode Probe: \(appState.diagnostics.lastClipboardLinkModeProbe)
            Clipboard Link Mode Probe Mode: \(appState.diagnostics.clipboardLinkModeProbeModeTitle.isEmpty ? "None" : appState.diagnostics.clipboardLinkModeProbeModeTitle)
            Clipboard Link Mode Probe Passed: \(appState.diagnostics.clipboardLinkModeProbePassed)
            Native Clipboard Default Probe: \(appState.diagnostics.lastNativeClipboardDefaultProbe)
            Native Clipboard Default Probe Passed: \(appState.diagnostics.nativeClipboardDefaultProbePassed)
            Paste: \(appState.diagnostics.lastPasteDecision)
            Paste Target Apps: \(appState.diagnostics.pasteTargetSummary)
            Paste Target Bundle IDs: \(appState.diagnostics.pasteTargetBundleIdentifiers.isEmpty ? "None" : appState.diagnostics.pasteTargetBundleIdentifiers.joined(separator: ", "))
            Pass-Through Apps: \(appState.diagnostics.passThroughSummary)
            Pass-Through Bundle IDs: \(appState.diagnostics.passThroughBundleIdentifiers.isEmpty ? "None" : appState.diagnostics.passThroughBundleIdentifiers.joined(separator: ", "))
            Finder: \(appState.diagnostics.lastFileSelectionDecision)
            Middle Clicks Seen: \(appState.diagnostics.middleClickCount)
            Last Mouse Button: \(appState.diagnostics.lastButtonNumber?.description ?? "none")
            Last Event Point: \(lastPoint)

            Structured Diagnostic Events
            Count: \(appState.diagnostics.recentEvents.count)
            Summary: \(diagnosticEventSummary())
            """
    }

    private func sensitiveSampleDecisionDescription() -> String {
        let sample = "api_key=PRIMARYPASTEFAKEKEY1234567890"
        switch privacyFilter.decision(for: sample) {
        case .allowed:
            return "Allowed"
        case .denied(let reason):
            return "Denied (\(reason.diagnosticDescription))"
        }
    }

    private func textLimitPolicyDescription(preferences: PreferencesStore) -> String {
        if preferences.maximumSelectionLength == 0 {
            return "Unlimited"
        }
        return "\(preferences.maximumSelectionLength.formatted()) char cap, refused as a whole"
    }

    private func payloadDescription(for item: SelectionItem) -> String {
        switch item.payload {
        case .text(let text):
            return "Text, \(text.count.formatted()) chars, \(item.wordCount.formatted()) words"
        case .pasteboard(let snapshot):
            if !snapshot.fileURLs.isEmpty {
                return "File selection, \(snapshot.fileURLs.count.formatted()) item(s)"
            }
            return "Pasteboard, \(snapshot.items.count.formatted()) item(s)"
        }
    }

    private func diagnosticEventSummary() -> String {
        let counts = Dictionary(grouping: appState.diagnostics.recentEvents, by: \.capability)
        return DiagnosticEvent.Capability.allCases.map { capability in
            "\(capability.rawValue)=\(counts[capability]?.count ?? 0)"
        }.joined(separator: ", ")
    }
    private func accessibilityDiagnosticsStatus(preferences: PreferencesStore) -> String {
        if !preferences.shouldUseAccessibility {
            return "Optional/off"
        }
        return permissions.isAccessibilityTrusted ? "Allowed" : "Needed"
    }

    private func inputMonitoringDiagnosticsStatus(preferences: PreferencesStore) -> String {
        if !preferences.shouldMonitorGlobalEvents {
            return "Optional/off"
        }
        return permissions.isInputMonitoringTrusted ? "Allowed" : "Needed"
    }

    private func finderAutomationDiagnosticsStatus(preferences: PreferencesStore) -> String {
        if !preferences.captureFileSelections {
            return "Optional/off"
        }
        return permissions.isFinderAutomationTrusted ? "Allowed" : "Needed"
    }
}
