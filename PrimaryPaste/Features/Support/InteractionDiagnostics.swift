import Combine
import Foundation

enum PastePassThroughEvidence {
    static func confirmsTargetSafety(_ decision: String) -> Bool {
        decision.hasPrefix("Passed through: pointer was not detected over an editable field")
            || decision.hasPrefix("Passed through: target app keeps middle-click native")
    }
}

final class InteractionDiagnostics: ObservableObject, DiagnosticRecording {
    private static let maximumRecentEventCount = 100
    static let initialFileSelectionDecision = "Finder file selection capture has not run yet"
    static let initialClipboardLinkModeProbe = "Clipboard link mode probe has not run yet"
    static let initialPrivacyProbe = "Privacy self-test has not run yet"

    @Published private(set) var runtimeEvidenceRunStartedAt = Date()
    @Published private(set) var middleClickCount = 0
    @Published private(set) var lastButtonNumber: Int64?
    @Published private(set) var lastEventLocation: CGPoint?
    @Published private(set) var lastSelectionDecision = "No text selection seen yet"
    @Published private(set) var lastPasteDecision = "No middle-click seen yet"
    @Published private(set) var lastClipboardDecision = "Clipboard copy capture has not run yet"
    @Published private(set) var lastClipboardSelfCaptureProbe = "Clipboard self-capture probe has not run yet"
    @Published private(set) var clipboardSelfCaptureProbePassed = false
    @Published private(set) var lastClipboardLinkModeProbe = InteractionDiagnostics.initialClipboardLinkModeProbe
    @Published private(set) var clipboardLinkModeProbePassed = false
    @Published private(set) var clipboardLinkModeProbeModeTitle = ""
    @Published private(set) var lastNativeClipboardDefaultProbe = "Native clipboard default probe has not run yet"
    @Published private(set) var nativeClipboardDefaultProbePassed = false
    @Published private(set) var lastPrivacyProbe = InteractionDiagnostics.initialPrivacyProbe
    @Published private(set) var privacyProbePassed = false
    @Published private(set) var lastFileSelectionDecision = InteractionDiagnostics.initialFileSelectionDecision
    @Published private(set) var selectionCaptureSourceNames: [String] = []
    @Published private(set) var selectionCaptureSourceBundleIdentifiers: [String] = []
    @Published private(set) var pasteTargetAppNames: [String] = []
    @Published private(set) var pasteTargetBundleIdentifiers: [String] = []
    @Published private(set) var passThroughAppNames: [String] = []
    @Published private(set) var passThroughBundleIdentifiers: [String] = []
    @Published private(set) var recentEvents: [DiagnosticEvent] = []
    private lazy var eventRecorder = DiagnosticRouter([
        UnifiedLogSink(),
        SupportDiagnosticsSink(diagnostics: self),
    ])

    func record(_ event: DiagnosticEvent) {
        eventRecorder.record(event)
    }

    func storeForSupport(_ event: DiagnosticEvent) {
        guard event.audience.includesSupport else { return }
        recentEvents.append(event.supportSafe)
        if recentEvents.count > Self.maximumRecentEventCount {
            recentEvents.removeFirst(recentEvents.count - Self.maximumRecentEventCount)
        }
    }

    var selectionCaptureSourceSummary: String {
        sourceSummary(selectionCaptureSourceNames)
    }

    var pasteTargetSummary: String {
        sourceSummary(pasteTargetAppNames)
    }

    var passThroughSummary: String {
        sourceSummary(passThroughAppNames)
    }

    var hasFileSelectionEvidence: Bool {
        lastFileSelectionDecision != Self.initialFileSelectionDecision
    }

    var hasHealthCheckEvidence: Bool {
        lastClipboardLinkModeProbe != Self.initialClipboardLinkModeProbe
            || lastPrivacyProbe != Self.initialPrivacyProbe
    }

    func recordMouseEvent(buttonNumber: Int64, location: CGPoint) {
        if lastButtonNumber != buttonNumber {
            lastButtonNumber = buttonNumber
        }
        if lastEventLocation != location {
            lastEventLocation = location
        }
        if buttonNumber == 2 {
            middleClickCount += 1
        }
        updateIfChanged(&lastPasteDecision, "Saw mouse button \(buttonNumber)")
        emit(capability: .input, code: "mouse-event", supportMessage: lastPasteDecision)
    }

    func recordPasteDecision(_ decision: String) {
        updateIfChanged(&lastPasteDecision, decision)
        emit(capability: .paste, code: "paste-decision", supportMessage: decision)
    }

    func recordPasteTarget(
        decision: String,
        targetAppName: String,
        bundleIdentifier: String?
    ) {
        recordPasteDecision(decision)
        appendUnique(&pasteTargetAppNames, targetAppName)
        if let bundleIdentifier {
            appendUnique(&pasteTargetBundleIdentifiers, bundleIdentifier)
        }
    }

    func recordPastePassThrough(
        decision: String,
        targetAppName: String,
        bundleIdentifier: String?
    ) {
        recordPasteDecision(decision)
        guard PastePassThroughEvidence.confirmsTargetSafety(decision) else { return }
        appendUnique(&passThroughAppNames, targetAppName)
        if let bundleIdentifier {
            appendUnique(&passThroughBundleIdentifiers, bundleIdentifier)
        }
    }

    func recordClipboardDecision(_ decision: String) {
        updateIfChanged(&lastClipboardDecision, decision)
        emit(capability: .clipboard, code: "clipboard-decision", supportMessage: decision)
    }

    func recordClipboardSelfCaptureProbe(_ decision: String, passed: Bool) {
        updateIfChanged(&lastClipboardSelfCaptureProbe, decision)
        if passed && !clipboardSelfCaptureProbePassed {
            clipboardSelfCaptureProbePassed = true
        }
        emit(
            capability: .clipboard,
            outcome: passed ? .succeeded : .observed,
            code: "self-capture-probe",
            supportMessage: decision
        )
    }

    func recordClipboardLinkModeProbe(_ decision: String, modeTitle: String, passed: Bool) {
        updateIfChanged(&lastClipboardLinkModeProbe, decision)
        updateIfChanged(&clipboardLinkModeProbeModeTitle, modeTitle)
        if clipboardLinkModeProbePassed != passed {
            clipboardLinkModeProbePassed = passed
        }
        emit(
            capability: .clipboard,
            outcome: passed ? .succeeded : .observed,
            code: "link-mode-probe",
            supportMessage: decision
        )
    }

    func recordNativeClipboardDefaultProbe(_ decision: String, passed: Bool) {
        updateIfChanged(&lastNativeClipboardDefaultProbe, decision)
        if nativeClipboardDefaultProbePassed != passed {
            nativeClipboardDefaultProbePassed = passed
        }
        emit(
            capability: .clipboard,
            outcome: passed ? .succeeded : .observed,
            code: "native-default-probe",
            supportMessage: decision
        )
    }

    func recordPrivacyProbe(_ decision: String, passed: Bool) {
        updateIfChanged(&lastPrivacyProbe, decision)
        if passed && !privacyProbePassed {
            privacyProbePassed = true
        }
        emit(
            capability: .privacy,
            outcome: passed ? .succeeded : .failed,
            code: "privacy-probe",
            supportMessage: decision
        )
    }

    func recordSelectionDecision(_ decision: String) {
        updateIfChanged(&lastSelectionDecision, decision)
        emit(capability: .selection, code: "selection-decision", supportMessage: decision)
    }

    func recordSelectionCapture(
        characterCount: Int,
        sourceAppName: String,
        bundleIdentifier: String?
    ) {
        recordSelectionDecision("Captured \(characterCount.formatted()) chars from \(sourceAppName)")
        eventRecorder.record(
            DiagnosticEvent(
                capability: .selection,
                outcome: .succeeded,
                code: "selection-captured",
                metadata: .init(characterCount: characterCount)
            )
        )
        appendUniqueSelectionSourceName(sourceAppName)
        if let bundleIdentifier {
            appendUniqueSelectionSourceBundleIdentifier(bundleIdentifier)
        }
    }

    func recordFileSelectionDecision(_ decision: String) {
        updateIfChanged(&lastFileSelectionDecision, decision)
        emit(capability: .fileSelection, code: "file-selection-decision", supportMessage: decision)
    }

    func resetRuntimeEvidence() {
        runtimeEvidenceRunStartedAt = Date()
        middleClickCount = 0
        lastButtonNumber = nil
        lastEventLocation = nil
        lastSelectionDecision = "No text selection seen yet"
        lastPasteDecision = "No middle-click seen yet"
        lastClipboardDecision = "Clipboard copy capture has not run yet"
        lastClipboardSelfCaptureProbe = "Clipboard self-capture probe has not run yet"
        clipboardSelfCaptureProbePassed = false
        lastClipboardLinkModeProbe = Self.initialClipboardLinkModeProbe
        clipboardLinkModeProbePassed = false
        clipboardLinkModeProbeModeTitle = ""
        lastNativeClipboardDefaultProbe = "Native clipboard default probe has not run yet"
        nativeClipboardDefaultProbePassed = false
        lastPrivacyProbe = Self.initialPrivacyProbe
        privacyProbePassed = false
        lastFileSelectionDecision = Self.initialFileSelectionDecision
        selectionCaptureSourceNames = []
        selectionCaptureSourceBundleIdentifiers = []
        pasteTargetAppNames = []
        pasteTargetBundleIdentifiers = []
        passThroughAppNames = []
        passThroughBundleIdentifiers = []
        recentEvents = []
    }

    private func appendUniqueSelectionSourceName(_ name: String) {
        appendUnique(&selectionCaptureSourceNames, name)
    }

    private func appendUniqueSelectionSourceBundleIdentifier(_ bundleIdentifier: String) {
        appendUnique(&selectionCaptureSourceBundleIdentifiers, bundleIdentifier)
    }

    private func appendUnique(_ values: inout [String], _ value: String) {
        guard !value.isEmpty, !values.contains(value) else { return }
        values.append(value)
        if values.count > 8 {
            values.removeFirst(values.count - 8)
        }
    }

    private func sourceSummary(_ sourceNames: [String]) -> String {
        guard !sourceNames.isEmpty else { return "None yet" }
        let shownNames = sourceNames.prefix(4)
        let remainder = sourceNames.count - shownNames.count
        let suffix = remainder > 0 ? ", +\(remainder) more" : ""
        return "\(shownNames.joined(separator: ", "))\(suffix)"
    }

    private func updateIfChanged(_ value: inout String, _ nextValue: String) {
        guard value != nextValue else { return }
        value = nextValue
    }

    private func emit(
        capability: DiagnosticEvent.Capability,
        outcome: DiagnosticEvent.Outcome = .observed,
        code: String,
        supportMessage: String? = nil
    ) {
        eventRecorder.record(
            DiagnosticEvent(
                capability: capability,
                outcome: outcome,
                code: code,
                supportMessage: supportMessage
            )
        )
    }
}
