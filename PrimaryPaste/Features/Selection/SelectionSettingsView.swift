import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SelectionSettingsView: View {
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var permissions: PermissionsCoordinator
    @State private var isTextTimingExpanded = false
    @State private var isTextCustomLimitExpanded = false
    @State private var isFinderCustomLimitExpanded = false

    private let textCaptureLimitOptions = [2_000, 10_000, 50_000, 0]
    private let fileSelectionLimitOptions = [10, 25, 50, 100, 250]

    private var captureFileSelectionsBinding: Binding<Bool> {
        Binding(
            get: { preferences.captureFileSelections },
            set: { newValue in
                preferences.captureFileSelections = newValue
            }
        )
    }

    private var fileSelectionStatusIsComplete: Bool {
        !preferences.captureFileSelections || permissions.isFinderAutomationTrusted
    }

    private var fileSelectionStatusText: String {
        if !preferences.captureFileSelections {
            return "Off"
        }
        return permissions.isFinderAutomationTrusted ? "Ready" : "Needs Permission"
    }

    private var fileSelectionDetailText: String {
        if !preferences.captureFileSelections {
            return
                "File selection capture is off by default. Turn it on only if Finder selections should become Primary items."
        }
        if !permissions.isFinderAutomationTrusted {
            return "Finder file selection capture is on but paused until Finder Automation is allowed."
        }
        return
            "Selected Finder or Desktop files become one Primary item. Paste them into apps that accept files or attachments."
    }

    private var textCaptureLimitSelection: Binding<Int> {
        Binding(
            get: {
                textCaptureLimitOptions.contains(preferences.maximumSelectionLength)
                    ? preferences.maximumSelectionLength
                    : -1
            },
            set: { newValue in
                guard newValue != -1 else { return }
                preferences.maximumSelectionLength = newValue
            }
        )
    }

    private var fileSelectionLimitSelection: Binding<Int> {
        Binding(
            get: {
                fileSelectionLimitOptions.contains(preferences.maximumFileSelectionCount)
                    ? preferences.maximumFileSelectionCount
                    : -1
            },
            set: { newValue in
                guard newValue != -1 else { return }
                preferences.maximumFileSelectionCount = newValue
            }
        )
    }

    private var customTextCaptureLimitBinding: Binding<Int> {
        Binding(
            get: {
                let current = preferences.maximumSelectionLength
                return current == 0 ? 10_000 : PreferencesStore.normalizedMaximumSelectionLength(current)
            },
            set: { newValue in
                preferences.maximumSelectionLength = PreferencesStore.normalizedMaximumSelectionLength(newValue)
            }
        )
    }

    private var customFileSelectionLimitBinding: Binding<Int> {
        Binding(
            get: {
                PreferencesStore.normalizedMaximumFileSelectionCount(preferences.maximumFileSelectionCount)
            },
            set: { newValue in
                preferences.maximumFileSelectionCount = PreferencesStore.normalizedMaximumFileSelectionCount(newValue)
            }
        )
    }

    private var hasCustomTextCaptureLimit: Bool {
        preferences.maximumSelectionLength > 0
            && !textCaptureLimitOptions.contains(preferences.maximumSelectionLength)
    }

    private var hasCustomFileSelectionLimit: Bool {
        !fileSelectionLimitOptions.contains(preferences.maximumFileSelectionCount)
    }

    private var textCaptureLimitDescription: String {
        if preferences.maximumSelectionLength == 0 {
            return "Unlimited text capture is useful for long documents, but it can store very large selections."
        }
        return
            "Selections over \(preferences.maximumSelectionLength.formatted()) characters are ignored as a whole, so accidental huge selections never replace Primary with a clipped partial item."
    }

    private var showsClipboardImportOptions: Bool {
        preferences.clipboardLinkMode.importsClipboardCopies
    }

    var body: some View {
        SettingsPage(
            title: "Selection",
            subtitle: "Choose which selections become Primary."
        ) {
            SettingsSectionLabel(
                title: "Capture Sources",
                detail: "Capture selected text or Finder items."
            )

            SettingsCard {
                SettingsCardHeader(
                    title: "What Becomes Primary",
                    detail: "Enable the sources you want to capture.",
                    systemImage: "selection.pin.in.out",
                    tint: Color.accentColor
                ) {
                    Spacer()
                }

                Divider()

                Toggle("Capture selected text automatically", isOn: $preferences.captureSelections)

                if preferences.captureSelections {
                    Picker("Capture Style", selection: $preferences.selectionCaptureMode) {
                        ForEach(SelectionCaptureMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(preferences.selectionCaptureMode.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if preferences.selectionCaptureMode == .customManualGestures {
                        ManualGestureCaptureOptions(preferences: preferences)
                    }
                }

                HStack(alignment: .center, spacing: 10) {
                    Toggle("Capture Finder file selections", isOn: captureFileSelectionsBinding)
                    Spacer()
                    StatusBadge(
                        isComplete: fileSelectionStatusIsComplete,
                        text: fileSelectionStatusText
                    )
                    if preferences.captureFileSelections && !permissions.isFinderAutomationTrusted {
                        Button("Allow") {
                            permissions.requestFinderAutomationPermission()
                        }
                    }
                }

                Text(fileSelectionDetailText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            SettingsSectionLabel(
                title: "Clipboard Link",
                detail:
                    "Decide whether normal Cmd+C copies and selection captures stay separate or flow into each other."
            )

            SettingsCard {
                SettingsCardHeader(
                    title: "Normal Clipboard",
                    detail: "Keep Primary separate from the clipboard, or connect them when needed.",
                    systemImage: "doc.on.clipboard",
                    tint: preferences.clipboardLinkMode == .separate ? Color.green : Color.accentColor
                ) {
                    Spacer()
                    StatusBadge(
                        isComplete: preferences.clipboardLinkMode == .separate,
                        text: preferences.clipboardLinkMode.title,
                        tone: preferences.clipboardLinkMode == .separate ? .success : .progress
                    )
                }

                Divider()

                Picker("Clipboard Link", selection: $preferences.clipboardLinkMode) {
                    ForEach(ClipboardLinkMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(preferences.clipboardLinkMode.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if showsClipboardImportOptions {
                    Toggle("Capture plain text only", isOn: $preferences.plainTextOnly)
                    Text(
                        preferences.plainTextOnly
                            ? "Normal Cmd+C copies add only text to Primary. Images, files, and rich clipboard data are ignored."
                            : "Normal Cmd+C copies keep their full paste data, including images, files, and rich app content."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            if preferences.captureSelections {
                SettingsSectionLabel(
                    title: "Text Limits",
                    detail: "Set capture thresholds for selected text."
                )

                SettingsCard {
                    SettingsCardHeader(
                        title: "Text Capture",
                        detail: "Timing and size limits for selected text.",
                        systemImage: "text.cursor",
                        tint: Color.accentColor
                    ) {
                        Spacer()
                    }

                    Divider()

                    Stepper(
                        "Minimum length: \(preferences.minimumSelectionLength)",
                        value: $preferences.minimumSelectionLength, in: 1...100)

                    Picker("Text limit", selection: textCaptureLimitSelection) {
                        Text("2K").tag(2_000)
                        Text("10K").tag(10_000)
                        Text("50K").tag(50_000)
                        Text("Unlimited").tag(0)
                        if hasCustomTextCaptureLimit {
                            Text("Custom").tag(-1)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(textCaptureLimitDescription)
                        .font(.callout)
                        .foregroundStyle(preferences.maximumSelectionLength == 0 ? Color.orange : Color.secondary)

                    SettingsDisclosureButton(isExpanded: $isTextCustomLimitExpanded) {
                        Text(isTextCustomLimitExpanded ? "Hide Custom Limit" : "Show Custom Limit")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if isTextCustomLimitExpanded {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Stepper(
                                    "Custom max characters: \(customTextCaptureLimitBinding.wrappedValue.formatted())",
                                    value: customTextCaptureLimitBinding,
                                    in: PreferencesStore.maximumSelectionLengthRange,
                                    step: 500
                                )
                                Spacer()
                                Button("Default") {
                                    preferences.maximumSelectionLength = 10_000
                                }
                                .disabled(preferences.maximumSelectionLength == 10_000)
                            }

                            Text("Use a custom cap only when the presets do not match your workflow.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)
                    }

                    SettingsDisclosureButton(isExpanded: $isTextTimingExpanded) {
                        Text(isTextTimingExpanded ? "Hide Fine Tuning" : "Show Fine Tuning")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if isTextTimingExpanded {
                        VStack(alignment: .leading, spacing: 12) {
                            SliderSettingRow(
                                title: "Selection Debounce",
                                value: $preferences.selectionCaptureDebounceMilliseconds,
                                range: PreferencesStore.selectionDebounceRange,
                                step: 25,
                                suffix: "ms"
                            )

                            SliderSettingRow(
                                title: "Slow Drag Grace",
                                value: $preferences.selectionIntentWindowMilliseconds,
                                range: PreferencesStore.selectionIntentWindowRange,
                                step: 250,
                                suffix: "ms"
                            )

                            Text(
                                "How long Primary keeps a slow drag alive while you are still dragging. Increase this if long selections stop updating before you let go."
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)
                    }
                }
            }

            if preferences.captureFileSelections {
                SettingsSectionLabel(
                    title: "Finder Limits",
                    detail: "Multi-selects are captured together, with a conservative cap for select-all mistakes."
                )

                SettingsCard {
                    SettingsCardHeader(
                        title: "Finder File Capture",
                        detail: "Control how many selected files can become Primary at once.",
                        systemImage: "folder",
                        tint: permissions.isFinderAutomationTrusted ? Color.accentColor : Color.orange
                    ) {
                        Spacer()
                        StatusBadge(
                            isComplete: permissions.isFinderAutomationTrusted,
                            text: permissions.isFinderAutomationTrusted ? "Ready" : "Needs Permission"
                        )
                    }

                    Divider()

                    Picker("File limit", selection: fileSelectionLimitSelection) {
                        Text("10").tag(10)
                        Text("25").tag(25)
                        Text("50").tag(50)
                        Text("100").tag(100)
                        Text("250").tag(250)
                        if hasCustomFileSelectionLimit {
                            Text("Custom").tag(-1)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(
                        "Finder selections over \(preferences.maximumFileSelectionCount.formatted()) items are ignored as a whole, so Primary never silently captures a partial set."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    Text(
                        "The default is intentionally conservative for accidental select-all moments; raise it when Finder file capture becomes part of your normal workflow."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    SettingsDisclosureButton(isExpanded: $isFinderCustomLimitExpanded) {
                        Text(isFinderCustomLimitExpanded ? "Hide Custom Limit" : "Show Custom Limit")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if isFinderCustomLimitExpanded {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Stepper(
                                    "Custom max items: \(customFileSelectionLimitBinding.wrappedValue.formatted())",
                                    value: customFileSelectionLimitBinding,
                                    in: PreferencesStore.maximumFileSelectionCountRange,
                                    step: 5
                                )
                                Spacer()
                                Button("Default") {
                                    preferences.maximumFileSelectionCount = 50
                                }
                                .disabled(preferences.maximumFileSelectionCount == 50)
                            }

                            Text(
                                "Use a custom file cap only when the presets are too small or too broad for your Finder workflow."
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)
                    }
                }
            }
        }
    }
}

struct ManualGestureCaptureOptions: View {
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Text("Also Capture")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Toggle("Dragged selections", isOn: .constant(true))
                .disabled(true)
            Toggle("Double-clicked words", isOn: $preferences.captureDoubleClickSelections)
            Toggle("Triple-clicked lines or paragraphs", isOn: $preferences.captureTripleClickSelections)
            Toggle("Shift-arrow ranges", isOn: $preferences.captureShiftArrowSelections)
            Toggle("Cmd+A select-all", isOn: $preferences.captureCommandASelections)
        }
        .padding(.top, 4)
    }
}
