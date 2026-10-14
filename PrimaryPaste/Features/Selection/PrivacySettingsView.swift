import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct PrivacySettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var permissions: PermissionsCoordinator
    @State private var isResetToolsExpanded = false

    private var showsAutomationResetAction: Bool {
        preferences.captureFileSelections || permissions.isFinderAutomationTrusted
    }

    var body: some View {
        SettingsPage(
            title: "Privacy",
            subtitle: "Manage capture protection, Private Mode, and permission cleanup."
        ) {
            SettingsSectionLabel(
                title: "Guards",
                detail: "Pause capture or filter sensitive text."
            )

            SettingsCard {
                SettingsCardHeader(
                    title: "Privacy Controls",
                    detail: "Sensitive-looking selections are refused; Private Mode pauses capture entirely.",
                    systemImage: "lock.shield",
                    tint: preferences.isPrivateModeEnabled ? Color.orange : Color.accentColor
                ) {
                    Spacer()
                    StatusBadge(
                        isComplete: !preferences.isPrivateModeEnabled,
                        text: preferences.isPrivateModeEnabled ? "Private" : "Normal",
                        tone: preferences.isPrivateModeEnabled ? .warning : .progress
                    )
                }

                Divider()

                Toggle("Sensitive text filtering", isOn: $preferences.sensitiveTextFiltering)
                Toggle("Private Mode", isOn: $preferences.isPrivateModeEnabled)
            }

            SettingsSectionLabel(
                title: "Local Guarantees",
                detail: "Current privacy behavior for enabled features."
            )

            SettingsCard {
                SettingsCardHeader(
                    title: "What Stays Private",
                    detail: "How Primary Paste handles protected fields, clipboard data, and visibility.",
                    systemImage: "checkmark.shield",
                    tint: Color.green
                ) {
                    Spacer()
                    StatusBadge(isComplete: true, text: "Local", tone: .success)
                }

                Divider()

                PrivacyPromiseGrid(
                    preferences: preferences,
                    permissions: permissions
                )
            }

            SettingsSectionLabel(
                title: "Reset",
                detail: "Open macOS privacy panes or clear Primary Paste's local state."
            )

            SettingsDisclosureCard(
                title: "Reset & Revoke",
                detail: "macOS permissions are revoked in System Settings; local settings can be reset here.",
                systemImage: "arrow.counterclockwise",
                isExpanded: $isResetToolsExpanded
            ) {
                PrivacyActionRow(
                    title: "Accessibility",
                    detail:
                        "Review or revoke the permission that lets Primary Paste read selected text and inspect editable fields.",
                    systemImage: "accessibility",
                    tint: Color.accentColor,
                    actionTitle: "Open",
                    actionSystemImage: "arrow.up.right.square",
                    action: permissions.openAccessibilitySettings
                )

                Divider()

                PrivacyActionRow(
                    title: "Input Monitoring",
                    detail:
                        "Review or revoke the permission used for global middle-click and optional keyboard triggers.",
                    systemImage: "keyboard.badge.eye",
                    tint: Color.accentColor,
                    actionTitle: "Open",
                    actionSystemImage: "arrow.up.right.square",
                    action: permissions.openInputMonitoringSettings
                )

                if showsAutomationResetAction {
                    Divider()

                    PrivacyActionRow(
                        title: "Finder Automation",
                        detail:
                            "Review or revoke Finder access used only when Finder file selection capture is enabled.",
                        systemImage: "folder.badge.gearshape",
                        tint: Color.accentColor,
                        actionTitle: "Open",
                        actionSystemImage: "arrow.up.right.square",
                        action: permissions.openAutomationSettings
                    )
                }

                Divider()

                PrivacyActionRow(
                    title: "Local App State",
                    detail:
                        "Reset Primary Paste preferences and clear Current Primary. macOS privacy permissions are left to System Settings.",
                    systemImage: "trash",
                    tint: Color.red,
                    actionTitle: "Reset",
                    actionSystemImage: "trash",
                    role: .destructive
                ) {
                    preferences.resetToDefaults()
                    appState.primaryStore.clear()
                    permissions.refreshFastStatus()
                }
            }
        }
    }
}

struct PrivacyActionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let actionTitle: String
    let actionSystemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.10))
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(role: role, action: action) {
                Label(actionTitle, systemImage: actionSystemImage)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

struct RuleListView: View {
    let emptySystemImage: String
    let placeholder: String
    let emptyText: String
    let emptyDetail: String
    let bundleIdentifiers: [String]
    @Binding var draft: String
    let add: (String) -> Void
    let choose: (String) -> Void
    let remove: (String) -> Void
    @State private var isManualAddExpanded = false

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddDraft: Bool {
        !trimmedDraft.isEmpty && !bundleIdentifiers.contains(trimmedDraft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    chooseApplication()
                } label: {
                    Label("Choose App", systemImage: "folder")
                }
                .controlSize(.small)

                Spacer()

                Button(isManualAddExpanded ? "Hide" : "Add Manually") {
                    withAnimation(.snappy(duration: 0.18)) {
                        isManualAddExpanded.toggle()
                    }
                }
                .controlSize(.small)
            }

            if isManualAddExpanded {
                HStack {
                    TextField(placeholder, text: $draft)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        guard canAddDraft else { return }
                        add(trimmedDraft)
                        draft = ""
                    }
                    .disabled(!canAddDraft)
                }

                Text(
                    "Use this only when Primary Paste cannot detect the app you want. The value should match the app's bundle identifier."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if bundleIdentifiers.isEmpty {
                EmptyRuleListView(
                    systemImage: emptySystemImage,
                    title: emptyText,
                    detail: emptyDetail
                )
            } else {
                ForEach(bundleIdentifiers, id: \.self) { bundleIdentifier in
                    AppRuleRow(
                        bundleIdentifier: bundleIdentifier,
                        remove: { remove(bundleIdentifier) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chooseApplication() {
        guard let app = AppPicker.chooseApplication(title: "Choose an app") else { return }
        guard !bundleIdentifiers.contains(app.bundleIdentifier) else { return }
        choose(app.bundleIdentifier)
    }
}

struct EmptyRuleListView: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)
        }
        .padding(.vertical, 8)
    }
}

struct AppRuleRow: View {
    let bundleIdentifier: String
    let remove: () -> Void

    private var display: AppRuleDisplay {
        AppRuleDisplay.resolve(bundleIdentifier)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: display.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(display.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                AppIdentifierText(bundleIdentifier: bundleIdentifier)
            }

            Spacer(minLength: 10)

            Button(role: .destructive, action: remove) {
                Label("Remove", systemImage: "minus.circle")
            }
            .accessibilityLabel("Remove rule for \(display.name)")
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 7)
    }
}

struct CompatibilityRuleListView: View {
    let rules: [AppCompatibilityRule]
    @Binding var draftBundleIdentifier: String
    @Binding var draftDisplayName: String
    @Binding var draftMode: AppTextIntegrationMode
    let add: (AppCompatibilityRule) -> Void
    let remove: (String) -> Void
    @State private var isManualAddExpanded = false

    private var trimmedBundleIdentifier: String {
        draftBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDisplayName: String {
        draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddDraft: Bool {
        !trimmedBundleIdentifier.isEmpty && draftMode != .strictAXOnly
            && !rules.contains { $0.bundleIdentifier == trimmedBundleIdentifier }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    chooseApplication()
                } label: {
                    Label("Choose App", systemImage: "folder")
                }
                .controlSize(.small)

                Spacer()

                StatusBadge(
                    isComplete: !rules.isEmpty,
                    text: "\(rules.count)",
                    tone: rules.isEmpty ? .neutral : .progress
                )
                Button(isManualAddExpanded ? "Hide" : "Add Manually") {
                    withAnimation(.snappy(duration: 0.18)) {
                        isManualAddExpanded.toggle()
                    }
                }
                .controlSize(.small)
            }

            if isManualAddExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("com.example.App", text: $draftBundleIdentifier)
                            .textFieldStyle(.roundedBorder)
                        TextField("Display name", text: $draftDisplayName)
                            .textFieldStyle(.roundedBorder)
                    }

                    CompatibilityModeMenu(
                        title: "Mode",
                        selection: $draftMode,
                        modes: AppTextIntegrationMode.allCases.filter { $0 != .strictAXOnly }
                    )

                    HStack {
                        Text(
                            "Use this for apps that hide their editor from macOS Accessibility. Known IDs here include com.t3tools.t3code and dev.openchamber.desktop."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 12)

                        Button {
                            guard canAddDraft else { return }
                            add(
                                AppCompatibilityRule(
                                    bundleIdentifier: trimmedBundleIdentifier,
                                    displayName: trimmedDisplayName.isEmpty
                                        ? trimmedBundleIdentifier : trimmedDisplayName,
                                    integrationMode: draftMode
                                )
                            )
                            draftBundleIdentifier = ""
                            draftDisplayName = ""
                            draftMode = .compatibilityPasteOnly
                        } label: {
                            Label("Add", systemImage: "plus.circle")
                        }
                        .disabled(!canAddDraft)
                    }
                }
            }

            if rules.isEmpty {
                EmptyRuleListView(
                    systemImage: "keyboard.badge.eye",
                    title: "No compatibility apps yet.",
                    detail:
                        "Switch to an app above and choose a compatibility mode when strict editable detection cannot see its editor."
                )
            } else {
                ForEach(rules) { rule in
                    CompatibilityRuleRow(
                        rule: rule,
                        update: { add($0) },
                        remove: { remove(rule.bundleIdentifier) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chooseApplication() {
        guard let app = AppPicker.chooseApplication(title: "Choose an app for Compatibility") else { return }

        draftBundleIdentifier = app.bundleIdentifier
        draftDisplayName = app.displayName
        if draftMode == .strictAXOnly {
            draftMode = .compatibilityPasteOnly
        }
        isManualAddExpanded = true
    }
}

struct PickedApplication {
    let bundleIdentifier: String
    let displayName: String
}

enum AppPicker {
    static func chooseApplication(title: String) -> PickedApplication? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let bundle = Bundle(url: url), let bundleIdentifier = bundle.bundleIdentifier else { return nil }

        let displayName =
            (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent

        return PickedApplication(bundleIdentifier: bundleIdentifier, displayName: displayName)
    }
}

struct CompatibilityRuleRow: View {
    let rule: AppCompatibilityRule
    let update: (AppCompatibilityRule) -> Void
    let remove: () -> Void
    @State private var isSettingsExpanded = false

    private var display: AppRuleDisplay {
        AppRuleDisplay.resolve(rule.bundleIdentifier)
    }

    private var modeBinding: Binding<AppTextIntegrationMode> {
        Binding(
            get: { rule.integrationMode },
            set: { mode in
                guard mode != .strictAXOnly else { return }
                var updatedRule = rule
                updatedRule.integrationMode = mode
                update(updatedRule)
            }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: display.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(rule.displayName.isEmpty ? display.name : rule.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(rule.integrationMode.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AppIdentifierText(bundleIdentifier: rule.bundleIdentifier)

                SettingsDisclosureButton(isExpanded: $isSettingsExpanded) {
                    Text(isSettingsExpanded ? "Hide Settings" : "Settings")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if isSettingsExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        CompatibilityModeMenu(
                            title: "Mode",
                            selection: modeBinding,
                            modes: AppTextIntegrationMode.allCases.filter { $0 != .strictAXOnly }
                        )
                        Text(rule.integrationMode.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
            }

            Spacer(minLength: 10)

            Button(role: .destructive, action: remove) {
                Label("Remove", systemImage: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 7)
    }
}

struct AppIdentifierText: View {
    let bundleIdentifier: String

    var body: some View {
        HStack(spacing: 5) {
            Text("App ID")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(bundleIdentifier)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

struct CompatibilityModeMenu: View {
    let title: String
    @Binding var selection: AppTextIntegrationMode
    let modes: [AppTextIntegrationMode]

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(title, selection: $selection) {
                ForEach(modes) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(maxWidth: 340, alignment: .leading)
        }
    }
}

struct AppRuleDisplay {
    let name: String
    let icon: NSImage

    static func resolve(_ bundleIdentifier: String) -> AppRuleDisplay {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let bundle = Bundle(url: url)
            let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            let fallbackName = url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 28, height: 28)
            return AppRuleDisplay(name: displayName ?? bundleName ?? fallbackName, icon: icon)
        }

        return AppRuleDisplay(
            name: fallbackName(for: bundleIdentifier),
            icon: NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
                ?? NSImage(size: NSSize(width: 28, height: 28))
        )
    }

    private static func fallbackName(for bundleIdentifier: String) -> String {
        bundleIdentifier
            .split(separator: ".")
            .last
            .map { String($0).replacingOccurrences(of: "-", with: " ").capitalized }
            ?? bundleIdentifier
    }
}

struct PrivacyPromiseGrid: View {
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var permissions: PermissionsCoordinator

    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 10, alignment: .top)
    ]

    private var finderFilesDetailText: String {
        if !preferences.captureFileSelections {
            return "Finder file selection capture is off by default."
        }
        if !permissions.isFinderAutomationTrusted {
            return "Finder capture is on but paused until Automation is allowed."
        }
        return "Finder selections can become Primary, but only while the Finder source is enabled."
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            PrivacyPromiseTile(
                title: "Secure Fields",
                detail: "Password and secure entry fields are never captured.",
                status: "Never",
                systemImage: "text.badge.checkmark",
                tone: .success
            )

            PrivacyPromiseTile(
                title: "Menu Bar",
                detail: "The menu keeps selected content hidden and shows only safe counts or source names.",
                status: "Hidden",
                systemImage: "menubar.rectangle",
                tone: .success
            )

            PrivacyPromiseTile(
                title: "Clipboard",
                detail: preferences.clipboardLinkMode == .separate
                    ? "Selections stay in Primary unless you explicitly send them to the normal clipboard."
                    : "Clipboard sharing is enabled by your Selection settings.",
                status: preferences.clipboardLinkMode == .separate ? "Separate" : "Linked",
                systemImage: "doc.on.clipboard",
                tone: preferences.clipboardLinkMode == .separate ? .success : .progress
            )

            PrivacyPromiseTile(
                title: "Finder Files",
                detail: finderFilesDetailText,
                status: preferences.captureFileSelections
                    ? (permissions.isFinderAutomationTrusted ? "On" : "Paused")
                    : "Off",
                systemImage: "folder.badge.gearshape",
                tone: preferences.captureFileSelections
                    ? (permissions.isFinderAutomationTrusted ? .progress : .warning)
                    : .success
            )

            PrivacyPromiseTile(
                title: "Sensitive Text",
                detail: preferences.sensitiveTextFiltering
                    ? "Key-like or secret-looking text is refused before replacing Primary."
                    : "Sensitive text filtering is off.",
                status: preferences.sensitiveTextFiltering ? "Filtered" : "Off",
                systemImage: "key.horizontal",
                tone: preferences.sensitiveTextFiltering ? .success : .warning
            )

            PrivacyPromiseTile(
                title: "Private Mode",
                detail: preferences.isPrivateModeEnabled
                    ? "Capture is paused until Private Mode is turned off."
                    : "Capture is available, with privacy filters still active.",
                status: preferences.isPrivateModeEnabled ? "Paused" : "Ready",
                systemImage: "moon.zzz",
                tone: preferences.isPrivateModeEnabled ? .warning : .success
            )
        }
    }
}

struct PrivacyPromiseTile: View {
    let title: String
    let detail: String
    let status: String
    let systemImage: String
    let tone: StatusBadgeTone

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tone.color.opacity(0.10))
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tone.color)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Spacer(minLength: 8)
                    StatusBadge(isComplete: tone != .warning, text: status, tone: tone)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.settingsAdaptiveSurface(lightOpacity: 0.045, darkOpacity: 0.065))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.18))
        )
    }
}
