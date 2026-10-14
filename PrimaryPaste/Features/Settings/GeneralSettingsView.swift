import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var appState: AppState
    let previewCaptureToast: () -> Void
    let previewLimitToast: () -> Void
    @State private var isIconOptionsExpanded = false
    @State private var isAdvancedExpanded = false

    private var availabilityDetail: String {
        preferences.isEnabled
            ? "Selection capture and paste triggers can run when their permissions are ready."
            : "Capture and paste triggers are paused until Primary Paste is enabled again."
    }

    private var startupPresenceStatusText: String {
        if preferences.launchAtLogin && preferences.showDockIcon {
            return "Login + Dock"
        }
        if preferences.launchAtLogin {
            return "Login"
        }
        if preferences.showDockIcon {
            return "Dock"
        }
        return "Menu Bar"
    }

    var body: some View {
        SettingsPage(
            title: "Primary Paste",
            subtitle: "Startup, visibility, and capture feedback."
        ) {
            SettingsSectionLabel(
                title: "App",
                detail: "Control when Primary Paste runs."
            )

            SettingsCard {
                SettingsCardHeader(
                    title: "Availability",
                    detail: availabilityDetail,
                    systemImage: preferences.isEnabled ? "power.circle.fill" : "power.circle",
                    tint: preferences.isEnabled ? Color.accentColor : Color.orange
                ) {
                    Spacer()
                    StatusBadge(
                        isComplete: preferences.isEnabled,
                        text: preferences.isEnabled ? "Running" : "Paused",
                        tone: preferences.isEnabled ? .progress : .warning
                    )
                }

                Divider()

                Toggle("Enable Primary Paste", isOn: $preferences.isEnabled)
            }

            SettingsCard {
                SettingsCardHeader(
                    title: "Startup & Presence",
                    detail: "Choose where Primary Paste appears and whether it starts automatically.",
                    systemImage: "menubar.rectangle",
                    tint: Color.accentColor
                ) {
                    Spacer()
                    StatusBadge(
                        isComplete: true,
                        text: startupPresenceStatusText,
                        tone: .neutral
                    )
                }

                Divider()

                Toggle("Launch at Login", isOn: $preferences.launchAtLogin)
                if let error = appState.startupError {
                    Text(error).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Show Setup on Launch", isOn: $preferences.showSetupOnLaunch)
                Toggle("Show Dock Icon", isOn: $preferences.showDockIcon)
            }

            SettingsDisclosureCard(
                title: "Customize Icons",
                detail: "Choose what Primary Paste looks like in the two places macOS keeps it visible.",
                systemImage: "menubar.rectangle",
                isExpanded: $isIconOptionsExpanded
            ) {
                IconRoutesControl(
                    menuSelection: $preferences.menuBarIconVariant,
                    appSelection: $preferences.appIconVariant,
                    showStatusText: $preferences.showMenuBarStatusText
                )
            }

            SettingsSectionLabel(
                title: "Feedback",
                detail: "Configure capture confirmations and warnings."
            )

            SettingsCard {
                SettingsCardHeader(
                    title: "Capture Feedback",
                    detail: "Preview and tune the one-line capture confirmation.",
                    systemImage: "bell.badge",
                    tint: preferences.showCaptureToasts ? Color.accentColor : Color.secondary
                ) {
                    Spacer()
                    StatusBadge(
                        isComplete: preferences.showCaptureToasts,
                        text: preferences.showCaptureToasts ? "On" : "Off",
                        tone: preferences.showCaptureToasts ? .progress : .neutral
                    )
                }

                Divider()

                Toggle("Show capture toasts", isOn: $preferences.showCaptureToasts)

                if preferences.showCaptureToasts {
                    Toggle("Show source label in toasts", isOn: $preferences.showToastSourceLabel)

                    ToastSizeSettingRow(selection: $preferences.captureToastSize)

                    DoubleSliderSettingRow(
                        title: "Show For",
                        value: $preferences.captureToastDisplaySeconds,
                        range: PreferencesStore.captureToastDisplaySecondsRange,
                        step: 0.1,
                        suffix: "s"
                    )

                    FeedbackPreviewActions(
                        previewCaptureToast: previewCaptureToast,
                        previewLimitToast: previewLimitToast
                    )
                }
            }

            SettingsDisclosureCard(
                title: "Advanced",
                detail: "Add troubleshooting and activity tools to Settings.",
                systemImage: "wrench.and.screwdriver",
                isExpanded: $isAdvancedExpanded
            ) {
                Toggle("Show Support", isOn: $preferences.showSupport)
                Text("Use Support to run health checks, inspect activity, and test capture or paste behavior.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

}

struct IconRoutesControl: View {
    @Binding var menuSelection: PrimaryPasteIconVariant
    @Binding var appSelection: PrimaryPasteIconVariant
    @Binding var showStatusText: Bool
    @State private var isMarkPickerExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                IconDestinationSummaryCard(
                    destination: .menuBar,
                    variant: menuSelection,
                    supportingText: showStatusText ? "Icon plus words when needed" : "Icon only in every state"
                )

                IconDestinationSummaryCard(
                    destination: .dock,
                    variant: appSelection,
                    supportingText: "Shown when the Dock icon is enabled"
                )

                IconStatusWordsCard(isOn: $showStatusText)
            }

            Divider()

            SettingsDisclosureButton(isExpanded: $isMarkPickerExpanded, minHeight: 42) {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Choose a Different Mark")
                            .font(.callout.weight(.semibold))
                        Text("Menu Bar and Dock can use different marks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(isMarkPickerExpanded ? "Hide" : "Show")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if isMarkPickerExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text("Choose where each mark appears.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        IconRouteLegendItem(title: "Menu Bar", tint: .accentColor, systemImage: "menubar.rectangle")
                        IconRouteLegendItem(title: "Dock", tint: .purple, systemImage: "dock.rectangle")
                    }

                    IconVariantDualChooser(
                        menuSelection: $menuSelection,
                        appSelection: $appSelection
                    )
                }
                .padding(.top, 8)
            }
        }
    }
}

enum IconRouteDestination {
    case menuBar
    case dock

    var title: String {
        switch self {
        case .menuBar: return "Menu Bar"
        case .dock: return "Dock"
        }
    }

    var systemImage: String {
        switch self {
        case .menuBar: return "menubar.rectangle"
        case .dock: return "dock.rectangle"
        }
    }

    var tint: Color {
        switch self {
        case .menuBar: return .accentColor
        case .dock: return .purple
        }
    }

    var imageStyle: PrimaryPasteIconImageStyle {
        switch self {
        case .menuBar: return .markPreview
        case .dock: return .appIcon
        }
    }

    var previewSize: CGFloat {
        switch self {
        case .menuBar: return 28
        case .dock: return 38
        }
    }
}

struct IconDestinationSummaryCard: View {
    let destination: IconRouteDestination
    let variant: PrimaryPasteIconVariant
    let supportingText: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(destination.tint.opacity(0.10))
                Image(
                    nsImage: PrimaryPasteIconRenderer.image(
                        for: variant,
                        size: destination.previewSize,
                        style: destination.imageStyle
                    )
                )
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: destination.previewSize, height: destination.previewSize)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: destination.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(destination.tint)
                    Text(destination.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(variant.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(supportingText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(destination.tint.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(destination.tint.opacity(0.16))
        )
    }
}

struct IconStatusWordsCard: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                Image(systemName: "textformat.abc")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.secondary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("Status Words")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(isOn ? "Private, Paused, Setup" : "Icon only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.settingsAdaptiveSurface(lightOpacity: 0.045, darkOpacity: 0.065))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.18))
        )
    }
}

struct IconRouteLegendItem: View {
    let title: String
    let tint: Color
    let systemImage: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
    }
}

struct IconVariantDualChooser: View {
    @Binding var menuSelection: PrimaryPasteIconVariant
    @Binding var appSelection: PrimaryPasteIconVariant

    private let columns = [
        GridItem(.adaptive(minimum: 132, maximum: 148), spacing: 10, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(PrimaryPasteIconVariant.allCases) { variant in
                IconVariantChoiceCard(
                    variant: variant,
                    isMenuSelection: menuSelection == variant,
                    isAppSelection: appSelection == variant,
                    setMenuSelection: { menuSelection = variant },
                    setAppSelection: { appSelection = variant }
                )
            }
        }
    }
}

struct IconVariantChoiceCard: View {
    let variant: PrimaryPasteIconVariant
    let isMenuSelection: Bool
    let isAppSelection: Bool
    let setMenuSelection: () -> Void
    let setAppSelection: () -> Void

    private var isSelected: Bool {
        isMenuSelection || isAppSelection
    }

    private var borderColor: Color {
        if isMenuSelection && isAppSelection {
            return Color.primary.opacity(0.26)
        }
        if isMenuSelection {
            return Color.accentColor
        }
        if isAppSelection {
            return Color.purple
        }
        return Color(nsColor: .separatorColor).opacity(0.18)
    }

    private var assignmentText: String {
        if isMenuSelection && isAppSelection {
            return "Menu + Dock"
        }
        if isMenuSelection {
            return "Menu Bar"
        }
        if isAppSelection {
            return "Dock"
        }
        return "Available"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            IconPreviewPair(variant: variant)

            Text(variant.title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 7) {
                Text(assignmentText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                IconAssignmentButton(
                    systemImage: "menubar.rectangle",
                    tint: .accentColor,
                    isSelected: isMenuSelection,
                    action: setMenuSelection,
                    accessibilityLabel: "Use \(variant.title) in the menu bar"
                )

                IconAssignmentButton(
                    systemImage: "dock.rectangle",
                    tint: .purple,
                    isSelected: isAppSelection,
                    action: setAppSelection,
                    accessibilityLabel: "Use \(variant.title) as the Dock icon"
                )
            }
        }
        .padding(9)
        .frame(minHeight: 116, alignment: .topLeading)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    isSelected
                        ? borderColor.opacity(0.10)
                        : Color.settingsAdaptiveSurface(lightOpacity: 0.035, darkOpacity: 0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1)
        )
    }
}

struct IconPreviewPair: View {
    let variant: PrimaryPasteIconVariant

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.78))
                Image(
                    nsImage: PrimaryPasteIconRenderer.image(
                        for: variant,
                        size: 28,
                        style: .markPreview
                    )
                )
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 28, height: 28)
            }
            .frame(width: 42, height: 46)

            Image(
                nsImage: PrimaryPasteIconRenderer.image(
                    for: variant,
                    size: 46,
                    style: .appIcon
                )
            )
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 46, height: 46)
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.70))
        )
    }
}

struct IconAssignmentButton: View {
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void
    let accessibilityLabel: String

    @ViewBuilder
    private var iconLabel: some View {
        switch systemImage {
        case "menubar.rectangle":
            Label("Menu", systemImage: "menubar.rectangle")
        case "dock.rectangle":
            Label("Dock", systemImage: "dock.rectangle")
        default:
            Label(accessibilityLabel, systemImage: systemImage)
        }
    }

    var body: some View {
        Button(action: action) {
            iconLabel
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 24, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.white : tint)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? tint : tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(tint.opacity(isSelected ? 0 : 0.18))
        )
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

struct ToastSizeSettingRow: View {
    @Binding var selection: CaptureToastSize

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Toast Size")
                    .font(.callout.weight(.semibold))
                Text(selection.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Picker("Toast Size", selection: $selection) {
                ForEach(CaptureToastSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 296)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
    }
}

struct FeedbackPreviewActions: View {
    let previewCaptureToast: () -> Void
    let previewLimitToast: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Preview Toasts")
                    .font(.callout.weight(.semibold))
                Text("Try success and warning states without changing Primary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(action: previewCaptureToast) {
                Label("Capture", systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)

            Button(action: previewLimitToast) {
                Label("Limit", systemImage: "exclamationmark.triangle")
            }
            .buttonStyle(.bordered)
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
