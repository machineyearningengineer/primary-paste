import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SupportSettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var permissions: PermissionsCoordinator
    @ObservedObject var navigation: SettingsNavigation
    let runClipboardLinkProbe: () -> Void
    let runPrivacyProbe: () -> Void
    let copyManualVerificationReportText: (String) -> Void
    let copyDiagnostics: () -> Void
    @State private var testSource = "Select this text, then middle-click the field below."
    @State private var testDestination = ""
    @State private var isSystemChecksExpanded = false
    @State private var isManualVerificationExpanded = false
    @State private var isTestBenchExpanded = false
    @State private var isAdvancedDiagnosticsExpanded = false

    private var showsFinderDiagnosticsTools: Bool {
        preferences.captureFileSelections
            || permissions.isFinderAutomationTrusted
            || appState.diagnostics.hasFileSelectionEvidence
    }

    private var clipboardLinkModeProbeIsCurrent: Bool {
        appState.diagnostics.clipboardLinkModeProbePassed
            && appState.diagnostics.clipboardLinkModeProbeModeTitle == preferences.clipboardLinkMode.title
    }

    private var nativeClipboardDefaultProbeIsCurrent: Bool {
        preferences.clipboardLinkMode == .separate
            && appState.diagnostics.nativeClipboardDefaultProbePassed
    }

    private func reviewPasteOrderSettings() {
        navigation.selectedTab = .paste
    }

    private func runAppProbes() {
        runClipboardLinkProbe()
        runPrivacyProbe()
    }

    private var currentPrimarySummaryText: String {
        guard let current = appState.primaryStore.current else {
            return "Primary is empty"
        }

        switch current.payload {
        case .text(let text):
            let wordCount = text.split(whereSeparator: \.isWhitespace).count
            return wordCount == 1 ? "Primary has 1 word" : "Primary has \(wordCount) words"

        case .pasteboard(let snapshot):
            if !snapshot.fileURLs.isEmpty {
                let count = snapshot.fileURLs.count
                return count == 1 ? "Primary has 1 file" : "Primary has \(count) files"
            }
            if snapshot.containsImageData {
                return "Primary has an image"
            }
            return snapshot.items.count == 1
                ? "Primary has 1 clipboard item" : "Primary has \(snapshot.items.count) clipboard items"
        }
    }

    var body: some View {
        SettingsPage(
            title: "Support",
            subtitle: "Diagnostics and troubleshooting for capture, paste, and permissions."
        ) {
            Phase6ReadinessDisclosureCard(
                appState: appState,
                preferences: preferences,
                permissions: permissions,
                isExpanded: $isSystemChecksExpanded,
                runClipboardLinkProbe: runClipboardLinkProbe,
                runPrivacyProbe: runPrivacyProbe,
                runAppProbes: runAppProbes,
                copyDiagnostics: copyDiagnostics,
                hideSupport: {
                    preferences.showSupport = false
                    navigation.selectedTab = .setup
                }
            )

            Phase6ManualVerificationDisclosureCard(
                appState: appState,
                preferences: preferences,
                permissions: permissions,
                isExpanded: $isManualVerificationExpanded,
                runClipboardLinkProbe: runClipboardLinkProbe,
                runPrivacyProbe: runPrivacyProbe,
                runAppProbes: runAppProbes,
                copyManualVerificationReportText: copyManualVerificationReportText
            )

            SettingsDisclosureCard(
                title: "Test Area",
                detail: "Check text capture and middle-click paste without leaving Primary Paste.",
                systemImage: "cursorarrow.motionlines",
                isExpanded: $isTestBenchExpanded
            ) {
                TextEditor(text: $testSource)
                    .font(.body)
                    .frame(height: 72)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))

                TextField("Middle-click here after selecting text above", text: $testDestination)
                    .textFieldStyle(.roundedBorder)

                PassThroughProbeView(decision: appState.diagnostics.lastPasteDecision)

                HStack {
                    Button("Clear Field") {
                        testDestination = ""
                    }
                    Button("Open Paste", action: reviewPasteOrderSettings)
                    Spacer()
                    Text(currentPrimarySummaryText)
                        .foregroundStyle(.secondary)
                }

                Divider()

                SettingsCardHeader(
                    title: "Activity",
                    detail: "Latest capture, paste, clipboard, privacy, and Finder results.",
                    systemImage: "waveform.path.ecg",
                    tint: Color.accentColor
                ) {
                    Spacer()
                    ReadinessActionMenu(
                        runClipboardLinkProbe: runClipboardLinkProbe,
                        runPrivacyProbe: runPrivacyProbe,
                        copyDiagnostics: copyDiagnostics
                    )
                }

                DiagnosticsSignalGrid(
                    diagnostics: appState.diagnostics,
                    permissions: permissions,
                    showsFinderDiagnostics: showsFinderDiagnosticsTools,
                    clipboardProbeIsHealthy: clipboardLinkModeProbeIsCurrent || nativeClipboardDefaultProbeIsCurrent
                )

                SettingsDisclosureButton(isExpanded: $isAdvancedDiagnosticsExpanded) {
                    Label(
                        isAdvancedDiagnosticsExpanded ? "Hide Details" : "Show Details",
                        systemImage: "slider.horizontal.3"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }

                if isAdvancedDiagnosticsExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        Divider()

                        Text("Selection")
                            .font(.headline)
                        LabeledContent("Last selection", value: appState.diagnostics.lastSelectionDecision)
                        LabeledContent("Captured apps", value: appState.diagnostics.selectionCaptureSourceSummary)

                        Divider()

                        Text("Clipboard")
                            .font(.headline)
                        LabeledContent("Last clipboard", value: appState.diagnostics.lastClipboardDecision)
                        LabeledContent("Self-capture check", value: appState.diagnostics.lastClipboardSelfCaptureProbe)
                        LabeledContent("Mode check", value: appState.diagnostics.lastClipboardLinkModeProbe)
                        LabeledContent("Native default", value: appState.diagnostics.lastNativeClipboardDefaultProbe)

                        Divider()

                        Text("Privacy")
                            .font(.headline)
                        LabeledContent("Privacy self-test", value: appState.diagnostics.lastPrivacyProbe)

                        Divider()

                        Text("Middle-Click")
                            .font(.headline)
                        LabeledContent("Middle-clicks seen", value: "\(appState.diagnostics.middleClickCount)")
                        if let buttonNumber = appState.diagnostics.lastButtonNumber {
                            LabeledContent("Last mouse button", value: "\(buttonNumber)")
                        }
                        if let location = appState.diagnostics.lastEventLocation {
                            LabeledContent("Last event point", value: "\(Int(location.x)), \(Int(location.y))")
                        }
                        LabeledContent("Last decision", value: appState.diagnostics.lastPasteDecision)
                        LabeledContent("Paste targets", value: appState.diagnostics.pasteTargetSummary)
                        LabeledContent("Pass-through apps", value: appState.diagnostics.passThroughSummary)

                        if showsFinderDiagnosticsTools {
                            Divider()

                            Text("Finder File Selection")
                                .font(.headline)
                            LabeledContent(
                                "Automation", value: permissions.isFinderAutomationTrusted ? "Allowed" : "Not allowed")
                            LabeledContent("Last file decision", value: appState.diagnostics.lastFileSelectionDecision)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .onAppear {
            permissions.refreshFastStatus()
        }
    }
}
