import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct PasteSettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: PreferencesStore
    let sendPrimaryToClipboard: () -> Void
    @State private var isSecondaryPasteTriggersExpanded = false

    private var retainedItemsStatusLabel: String {
        switch preferences.pasteMode {
        case .latest:
            return "Retained history"
        case .queue:
            return "Queued items"
        case .stack:
            return "Stacked items"
        case .cycle:
            return "Cycle items"
        }
    }

    private var retainedItemsCountText: String {
        let count = appState.primaryStore.queue.count
        return count == 1 ? "1 item retained" : "\(count) items retained"
    }

    private var clearButtonTitle: String {
        switch preferences.pasteMode {
        case .latest:
            return "Clear Primary and History"
        case .queue:
            return "Clear Primary and Queue"
        case .stack:
            return "Clear Primary and Stack"
        case .cycle:
            return "Clear Primary and Cycle"
        }
    }

    private var pasteModeDetail: String {
        switch preferences.pasteMode {
        case .latest:
            return "Paste triggers always use the newest Primary item. Older captures are kept only for review."
        case .queue:
            return "Paste triggers use oldest-to-newest order when Clear Primary after paste is enabled."
        case .stack:
            return "Paste triggers use newest-to-oldest order when Clear Primary after paste is enabled."
        case .cycle:
            return "Paste triggers walk through retained items without removing them."
        }
    }

    private var retentionLimitTitle: String {
        switch preferences.pasteMode {
        case .latest:
            return "Keep up to \(preferences.queueSize) recent items"
        case .queue:
            return "Keep up to \(preferences.queueSize) queued items"
        case .stack:
            return "Keep up to \(preferences.queueSize) stacked items"
        case .cycle:
            return "Keep up to \(preferences.queueSize) cycle items"
        }
    }

    private var recentSectionTitle: String {
        switch preferences.pasteMode {
        case .latest:
            return "Recent History"
        case .queue:
            return "Recent Queue"
        case .stack:
            return "Recent Stack"
        case .cycle:
            return "Recent Cycle"
        }
    }

    private var recentSectionDetail: String {
        switch preferences.pasteMode {
        case .latest:
            return "Recent items are kept for visibility, but only the newest item is pasted."
        case .queue:
            return "A short view of the oldest-to-newest paste queue."
        case .stack:
            return "A short view of the newest-to-oldest paste stack."
        case .cycle:
            return "A short view of the retained items the paste trigger cycles through."
        }
    }

    private var emptyRecentPayloadText: String {
        switch preferences.pasteMode {
        case .latest:
            return "No recent selections yet."
        case .queue:
            return "No queued selections yet."
        case .stack:
            return "No stacked selections yet."
        case .cycle:
            return "No cycle items yet."
        }
    }

    private var anyPasteTriggerEnabled: Bool {
        preferences.middleClickTriggerEnabled
            || preferences.keyboardShortcutTriggerEnabled
            || preferences.externalTriggerEnabled
    }

    private var pasteTriggerStatusText: String {
        if preferences.middleClickTriggerEnabled {
            return "On"
        }
        return anyPasteTriggerEnabled ? "Custom" : "Off"
    }

    private var pasteTriggerStatusTone: StatusBadgeTone {
        if preferences.middleClickTriggerEnabled {
            return .progress
        }
        return anyPasteTriggerEnabled ? .neutral : .warning
    }

    var body: some View {
        SettingsPage(
            title: "Paste",
            subtitle: "Configure paste triggers, targets, and item order."
        ) {
            SettingsSectionLabel(
                title: "Paste Triggers",
                detail: "Middle-click is enabled by default; shortcuts and URL triggers are optional."
            )

            SettingsCard {
                SettingsCardHeader(
                    title: "Primary Trigger",
                    detail:
                        "Primary Paste listens for a real middle-click event, whether it comes from a mouse or a trackpad gesture.",
                    systemImage: "cursorarrow.click",
                    tint: Color.accentColor
                ) {
                    Spacer()
                    StatusBadge(
                        isComplete: anyPasteTriggerEnabled,
                        text: pasteTriggerStatusText,
                        tone: pasteTriggerStatusTone
                    )
                }

                Divider()

                Toggle("Middle-click", isOn: $preferences.middleClickTriggerEnabled)

                SettingsDisclosureButton(isExpanded: $isSecondaryPasteTriggersExpanded) {
                    Text(isSecondaryPasteTriggersExpanded ? "Hide More Triggers" : "Show More Triggers")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if isSecondaryPasteTriggersExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(
                            "Keyboard shortcut (\(KeyboardShortcutController.shortcutDisplayName))",
                            isOn: $preferences.keyboardShortcutTriggerEnabled)
                        Toggle("External URL trigger", isOn: $preferences.externalTriggerEnabled)
                        Text(
                            "The URL trigger listens for primarypaste://paste so automation tools can paste Primary without using the global middle-click hook."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }
            }

            SettingsSectionLabel(
                title: "Where Paste Is Allowed",
                detail: "Only editable fields receive a Primary paste."
            )

            SettingsCard {
                SettingsCardHeader(
                    title: "Editable Targets",
                    detail: "Editable fields paste; browser links, tabs, and other surfaces stay native.",
                    systemImage: "hand.point.up.left.fill",
                    tint: Color.green
                ) {
                    Spacer()
                }

                Divider()

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "arrow.forward.circle.fill")
                        .foregroundStyle(Color.green)
                        .frame(width: 18)
                    Text("Middle-clicks outside editable text fields pass through to the current app.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    StatusBadge(isComplete: true, text: "Always", tone: .success)
                }
            }

            SettingsSectionLabel(
                title: "Clipboard Restore",
                detail: "Primary Paste borrows the normal clipboard for paste, then puts it back."
            )

            SettingsCard {
                SettingsCardHeader(
                    title: "Restore After Paste",
                    detail: preferences.preserveClipboard
                        ? "The previous macOS clipboard is restored after a Primary paste. Complex rich clipboards are best-effort."
                        : "Primary paste will leave the pasted item on the normal clipboard.",
                    systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard",
                    tint: preferences.preserveClipboard ? Color.green : Color.orange
                ) {
                    Spacer()
                    StatusBadge(
                        isComplete: preferences.preserveClipboard,
                        text: preferences.preserveClipboard ? "Restoring" : "Off",
                        tone: preferences.preserveClipboard ? .success : .warning
                    )
                }

                Divider()

                Toggle("Preserve normal clipboard after paste", isOn: $preferences.preserveClipboard)
            }

            SettingsSectionLabel(
                title: "Current Primary",
                detail: "What the next paste trigger will use, plus the retained items behind it."
            )

            SettingsCard {
                SettingsCardHeader(
                    title: "Next Paste",
                    detail: appState.primaryStore.peekItem() == nil
                        ? "Nothing is ready to paste yet."
                        : "This is what the next paste trigger will use.",
                    systemImage: "tray.full",
                    tint: appState.primaryStore.peekItem() == nil ? Color.secondary : Color.accentColor
                ) {
                    Spacer()
                    StatusBadge(
                        isComplete: appState.primaryStore.peekItem() != nil,
                        text: appState.primaryStore.peekItem() == nil ? "Empty" : "Ready",
                        tone: appState.primaryStore.peekItem() == nil ? .neutral : .progress
                    )
                }

                Divider()

                if let current = appState.primaryStore.peekItem() {
                    PrimaryPayloadRow(item: current)
                } else {
                    EmptyPayloadView()
                }

                LabeledContent(retainedItemsStatusLabel, value: retainedItemsCountText)

                HStack {
                    Button {
                        sendPrimaryToClipboard()
                    } label: {
                        Label("Send to Clipboard", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.primaryStore.peekItem() == nil)

                    Button(role: .destructive) {
                        appState.primaryStore.clear()
                    } label: {
                        Label(clearButtonTitle, systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.primaryStore.peekItem() == nil && appState.primaryStore.queue.isEmpty)

                    Spacer()
                }
            }

            SettingsSectionLabel(
                title: "Order",
                detail: "Choose whether Primary behaves like one latest selection or a small retained paste pool."
            )

            SettingsCard {
                Picker("Paste Mode", selection: $preferences.pasteMode) {
                    ForEach(PasteMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(pasteModeDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Stepper(retentionLimitTitle, value: $preferences.queueSize, in: PreferencesStore.queueSizeRange)

                Toggle("Remove items after paste", isOn: $preferences.clearAfterPaste)
                    .disabled(preferences.pasteMode == .cycle)

                Text(
                    preferences.pasteMode == .cycle
                        ? "Cycle always keeps its items and advances to the next one after paste."
                        : preferences.clearAfterPaste
                            ? "Each pasted item is removed. Queue and Stack then move to the next item."
                            : "The same item stays ready for repeated pastes. Enable removal to advance Queue or Stack."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            SettingsSectionLabel(
                title: recentSectionTitle,
                detail: recentSectionDetail
            )

            SettingsCard {
                if appState.primaryStore.queue.isEmpty {
                    Text(emptyRecentPayloadText)
                        .foregroundStyle(.secondary)
                } else {
                    let recentItems =
                        preferences.pasteMode == .stack || preferences.pasteMode == .latest
                        ? Array(appState.primaryStore.queue.suffix(8).reversed())
                        : Array(appState.primaryStore.queue.prefix(8))

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(recentItems.enumerated()), id: \.element.id) { index, item in
                            PrimaryPayloadRow(item: item)
                            if index < recentItems.count - 1 {
                                Divider()
                                    .padding(.leading, 34)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct PrimaryPayloadRow: View {
    let item: SelectionItem

    private var payloadIcon: String {
        switch item.payload {
        case .text:
            return "text.alignleft"
        case .pasteboard(let snapshot):
            if !snapshot.fileURLs.isEmpty {
                return "doc.on.doc"
            }
            if snapshot.containsImageData {
                return "photo"
            }
            return "doc.on.clipboard"
        }
    }

    private var payloadLabel: String {
        switch item.payload {
        case .text:
            return "Text"
        case .pasteboard(let snapshot):
            if !snapshot.fileURLs.isEmpty {
                return snapshot.fileURLs.count == 1 ? "File" : "\(snapshot.fileURLs.count) files"
            }
            if snapshot.containsImageData {
                return "Image"
            }
            return "Clipboard"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: payloadIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    Text(item.sourceAppName)
                    Text(payloadLabel)
                    if item.isClipboardCopy {
                        Text("Clipboard copy")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 10)
        }
        .padding(.vertical, 9)
    }
}

struct EmptyPayloadView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing captured yet")
                    .font(.callout.weight(.semibold))
                Text("Select text, copy something, or choose Finder files when those capture sources are enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)
        }
        .padding(.vertical, 9)
    }
}

extension PasteboardSnapshot {
    var containsImageData: Bool {
        items.contains { item in
            item.types.contains { type in
                type.rawValue.localizedCaseInsensitiveContains("image")
                    || type.rawValue.localizedCaseInsensitiveContains("png")
                    || type.rawValue.localizedCaseInsensitiveContains("tiff")
            }
        }
    }
}
