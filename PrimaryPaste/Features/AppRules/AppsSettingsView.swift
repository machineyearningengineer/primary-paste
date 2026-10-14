import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct AppsSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var blockedBundleIdentifier = ""
    @State private var passThroughBundleIdentifier = ""
    @State private var compatibilityBundleIdentifier = ""
    @State private var compatibilityDisplayName = ""
    @State private var compatibilityMode: AppTextIntegrationMode = .compatibilityPasteOnly
    @State private var isBlockedRulesExpanded = false
    @State private var isPassThroughRulesExpanded = false
    @State private var isCompatibilityRulesExpanded = true

    private var currentRuleTarget: AppRuleTarget? {
        appState.appRules.frontmostRuleTarget ?? appState.appRules.recentlyFocusedApp
    }

    private var isShowingRememberedTarget: Bool {
        appState.appRules.frontmostRuleTarget == nil && currentRuleTarget != nil
    }

    private var currentTargetTitle: String {
        guard let currentRuleTarget else {
            return appState.appRules.frontmostAppName
        }
        return currentRuleTarget.displayName
    }

    private var currentTargetDetail: String {
        isShowingRememberedTarget
            ? "The last app you used before opening these settings."
            : "Rules apply to the app shown here."
    }

    private var currentCompatibilityRule: AppCompatibilityRule? {
        guard let currentRuleTarget else { return nil }
        return appState.appRules.compatibilityRule(for: currentRuleTarget)
    }

    private var currentCompatibilityMode: AppTextIntegrationMode {
        currentCompatibilityRule?.integrationMode ?? .strictAXOnly
    }

    private var frontmostIsPrimaryPaste: Bool {
        guard let bundleIdentifier = appState.appRules.frontmostBundleIdentifier else { return false }
        return appState.appRules.isSelfBundleIdentifier(bundleIdentifier)
    }

    private var currentTargetIsBlocked: Bool {
        guard let currentRuleTarget else { return false }
        return appState.preferences.blockedBundleIdentifiers.contains(currentRuleTarget.bundleIdentifier)
    }

    private var currentTargetIsPassThrough: Bool {
        guard let currentRuleTarget else { return false }
        return appState.preferences.passThroughBundleIdentifiers.contains(currentRuleTarget.bundleIdentifier)
    }

    private var frontmostRuleStatus: String {
        if currentRuleTarget == nil {
            return frontmostIsPrimaryPaste ? "Settings" : "Unknown"
        }
        if currentTargetIsBlocked {
            return "Blocked"
        }
        if currentTargetIsPassThrough {
            return "Pass-through"
        }
        if currentCompatibilityMode != .strictAXOnly {
            return "Compatibility"
        }
        return "Standard"
    }

    private var frontmostRuleTone: StatusBadgeTone {
        if currentTargetIsBlocked {
            return .paused
        }
        if currentTargetIsPassThrough {
            return .success
        }
        if currentCompatibilityMode != .strictAXOnly {
            return .progress
        }
        return .neutral
    }

    private var currentRuleExplanation: String {
        if currentTargetIsBlocked && currentTargetIsPassThrough {
            return
                "Selection capture is blocked and middle-click stays native in this app. Use the actions above to change either behavior."
        }
        if currentTargetIsBlocked {
            return "Selection capture is blocked in this app. Paste behavior still follows the setting below."
        }
        if currentTargetIsPassThrough {
            return "Middle-click stays fully native in this app. Editor fallback is off while this rule is active."
        }
        if currentCompatibilityMode != .strictAXOnly {
            return
                "Editor fallback is active for this app because its text fields are not fully visible to macOS Accessibility."
        }
        return "This app uses the standard capture and editable-field safety rules."
    }

    private var compatibilityModeBinding: Binding<AppTextIntegrationMode> {
        Binding(
            get: { currentCompatibilityMode },
            set: { mode in
                guard let currentRuleTarget else { return }
                appState.appRules.setCompatibilityMode(mode, for: currentRuleTarget)
            }
        )
    }

    var body: some View {
        SettingsPage(
            title: "Apps",
            subtitle: "Set capture and middle-click behavior for individual apps."
        ) {
            SettingsSectionLabel(
                title: "Current App",
                detail: "Configure the app you used before opening Settings."
            )

            SettingsCard {
                SettingsCardHeader(
                    title: currentTargetTitle,
                    detail: currentTargetDetail,
                    systemImage: "app.badge",
                    tint: Color.accentColor
                ) {
                    Spacer()
                    if isShowingRememberedTarget {
                        Label("Remembered", systemImage: "clock.arrow.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    StatusBadge(
                        isComplete: currentTargetIsBlocked || currentTargetIsPassThrough,
                        text: frontmostRuleStatus,
                        tone: frontmostRuleTone
                    )
                }

                Divider()

                if let currentRuleTarget {
                    let bundleIdentifier = currentRuleTarget.bundleIdentifier

                    if isShowingRememberedTarget {
                        Text(
                            "Rules below apply to this remembered app. Existing settings are selected here so you can adjust them without switching away."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }

                    HStack {
                        if currentTargetIsBlocked {
                            Button {
                                appState.appRules.removeBlockedBundleIdentifier(bundleIdentifier)
                            } label: {
                                Label("Allow Capture", systemImage: "checkmark.shield")
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button {
                                appState.appRules.addBlockedBundleIdentifier(bundleIdentifier)
                            } label: {
                                Label("Block Capture", systemImage: "shield.slash")
                            }
                            .buttonStyle(.bordered)
                        }

                        if currentTargetIsPassThrough {
                            Button {
                                appState.appRules.removePassThroughBundleIdentifier(bundleIdentifier)
                            } label: {
                                Label("Use Paste Settings", systemImage: "arrow.uturn.backward.circle")
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button {
                                appState.appRules.addPassThroughBundleIdentifier(bundleIdentifier)
                            } label: {
                                Label("Keep Middle-Click Native", systemImage: "cursorarrow.click")
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        CompatibilityModeMenu(
                            title: "Editor Fallback",
                            selection: compatibilityModeBinding,
                            modes: AppTextIntegrationMode.allCases
                        )

                        Text(currentCompatibilityMode.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        if currentCompatibilityMode != .strictAXOnly {
                            Label(
                                "Fallback cannot prove the pointer is inside an editable field. Only use it for apps you trust.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        } else if currentTargetIsPassThrough {
                            Label(
                                "Choosing an editor fallback will turn off Keep Middle-Click Native for this app.",
                                systemImage: "info.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 8)

                    Text(currentRuleExplanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
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
                    .padding(.top, 2)
                } else if frontmostIsPrimaryPaste {
                    Text(
                        "Primary Paste is in front while Settings is open. Switch to another app once and this section will remember it here."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            SettingsSectionLabel(
                title: "Saved Rules",
                detail:
                    "Blocked apps ignore selection capture. Pass-through apps keep all middle-clicks native. Compatibility apps use keyboard fallbacks when macOS cannot see their editor."
            )

            SettingsDisclosureCard(
                title: "Blocked Apps",
                detail:
                    "\(appState.preferences.blockedBundleIdentifiers.count) saved. Selection capture is ignored for these apps.",
                systemImage: "shield.slash",
                isExpanded: $isBlockedRulesExpanded
            ) {
                RuleListView(
                    emptySystemImage: "shield.slash",
                    placeholder: "com.example.App",
                    emptyText: "No blocked apps yet.",
                    emptyDetail:
                        "Switch to an app above and use Block Capture when you want Primary to ignore its selections.",
                    bundleIdentifiers: appState.preferences.blockedBundleIdentifiers,
                    draft: $blockedBundleIdentifier,
                    add: { appState.appRules.addBlockedBundleIdentifier($0) },
                    choose: { appState.appRules.addBlockedBundleIdentifier($0) },
                    remove: { appState.appRules.removeBlockedBundleIdentifier($0) }
                )
            }

            SettingsDisclosureCard(
                title: "Pass-Through Apps",
                detail:
                    "\(appState.preferences.passThroughBundleIdentifiers.count) saved. Middle-clicks stay native for these apps.",
                systemImage: "cursorarrow.click",
                isExpanded: $isPassThroughRulesExpanded
            ) {
                RuleListView(
                    emptySystemImage: "cursorarrow.click",
                    placeholder: "com.example.Browser",
                    emptyText: "No pass-through apps yet.",
                    emptyDetail:
                        "Switch to a browser or tool above and choose Keep Middle-Click Native when Primary should never intercept it.",
                    bundleIdentifiers: appState.preferences.passThroughBundleIdentifiers,
                    draft: $passThroughBundleIdentifier,
                    add: { appState.appRules.addPassThroughBundleIdentifier($0) },
                    choose: { appState.appRules.addPassThroughBundleIdentifier($0) },
                    remove: { appState.appRules.removePassThroughBundleIdentifier($0) }
                )
            }

            SettingsDisclosureCard(
                title: "Compatibility Apps",
                detail:
                    "\(appState.preferences.appCompatibilityRules.count) saved. Uses keyboard fallbacks for trusted apps.",
                systemImage: "keyboard.badge.eye",
                isExpanded: $isCompatibilityRulesExpanded
            ) {
                CompatibilityRuleListView(
                    rules: appState.preferences.appCompatibilityRules,
                    draftBundleIdentifier: $compatibilityBundleIdentifier,
                    draftDisplayName: $compatibilityDisplayName,
                    draftMode: $compatibilityMode,
                    add: { appState.appRules.setCompatibilityRule($0) },
                    remove: { appState.appRules.removeCompatibilityRule($0) }
                )
            }
        }
    }
}
