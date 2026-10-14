import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SliderSettingRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let suffix: String

    private var doubleValue: Binding<Double> {
        Binding<Double>(
            get: { Double(value) },
            set: { newValue in
                value = Int(newValue)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(value)\(suffix)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: doubleValue,
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            .accessibilityLabel(title)
            .accessibilityValue("\(value)\(suffix)")
        }
    }
}

struct DoubleSliderSettingRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String

    private var formattedValue: String {
        "\(String(format: "%.1f", value))\(suffix)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(formattedValue)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: $value,
                in: range,
                step: step
            )
            .accessibilityLabel(title)
            .accessibilityValue(formattedValue)
        }
    }
}

struct SetupStatusRow: View {
    let title: String
    let detail: String
    let isComplete: Bool
    let completeText: String
    let incompleteText: String
    let primaryActionTitle: String
    let primaryAction: () -> Void
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?

    private var statusTone: StatusBadgeTone {
        if isComplete {
            return .success
        }
        if incompleteText == "Paused" {
            return .paused
        }
        return .warning
    }

    private var iconName: String {
        if isComplete {
            return "checkmark.circle.fill"
        }
        if incompleteText == "Paused" {
            return "pause.circle.fill"
        }
        return "exclamationmark.circle.fill"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(statusTone.color.opacity(0.12))
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(statusTone.color)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                    StatusBadge(
                        isComplete: isComplete,
                        text: isComplete ? completeText : incompleteText,
                        tone: statusTone
                    )
                }
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 8) {
                Button(primaryActionTitle, action: primaryAction)
                    .controlSize(.small)
                if let secondaryActionTitle, let secondaryAction {
                    Button(secondaryActionTitle, action: secondaryAction)
                        .buttonStyle(.link)
                        .controlSize(.small)
                }
            }
        }
    }
}

struct StatusBadge: View {
    let isComplete: Bool
    let text: String
    var tone: StatusBadgeTone?

    private var resolvedTone: StatusBadgeTone {
        tone ?? (isComplete ? .success : .warning)
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(resolvedTone.color)
                .frame(width: 4.5, height: 4.5)
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(resolvedTone.textColor)
        .background(
            Capsule()
                .fill(resolvedTone.color.opacity(0.08))
        )
        .overlay(
            Capsule()
                .strokeBorder(resolvedTone.color.opacity(0.10))
        )
    }
}

enum StatusBadgeTone: Equatable {
    case success
    case warning
    case progress
    case paused
    case neutral

    var color: Color {
        switch self {
        case .success:
            return Color.green
        case .warning:
            return Color.orange
        case .progress:
            return Color.accentColor
        case .paused:
            return Color.indigo
        case .neutral:
            return Color.secondary
        }
    }

    var textColor: Color {
        switch self {
        case .neutral:
            return Color.secondary
        case .success, .warning, .progress, .paused:
            return color
        }
    }
}

struct ProofBadge: View {
    let kind: ManualVerificationProofKind

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.systemImage)
                .font(.caption2.weight(.semibold))
            Text(kind.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(kind.tint)
        .background(
            Capsule()
                .fill(kind.tint.opacity(0.08))
        )
        .overlay(
            Capsule()
                .strokeBorder(kind.tint.opacity(0.10))
        )
    }
}

struct SettingsPage<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 26, weight: .semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, 2)

                content
            }
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 18)
        }
    }
}

extension Color {
    static func settingsAdaptiveSurface(lightOpacity: Double, darkOpacity: Double) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return (isDark ? NSColor.white : NSColor.black)
                    .withAlphaComponent(isDark ? darkOpacity : lightOpacity)
            })
    }

    static func settingsReviewSurface(isExpanded: Bool) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                if isDark {
                    return NSColor(calibratedWhite: isExpanded ? 0.16 : 0.13, alpha: 1)
                }
                return NSColor(calibratedWhite: isExpanded ? 0.91 : 0.93, alpha: 1)
            })
    }

    static func settingsOverviewSurface() -> Color {
        settingsAdaptiveSurface(lightOpacity: 0.06, darkOpacity: 0.08)
    }

    static func settingsCardSurface() -> Color {
        settingsAdaptiveSurface(lightOpacity: 0.065, darkOpacity: 0.085)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsSurface(Color.settingsCardSurface())
    }
}

struct SettingsSectionLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
        .padding(.horizontal, 2)
    }
}

struct SettingsDisclosureCard<Content: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsDisclosureButton(isExpanded: $isExpanded, minHeight: 54) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
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
                .padding(.top, 4)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsSurface(Color.settingsCardSurface())
    }
}

struct SettingsDisclosureButton<Label: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isExpanded: Bool
    var minHeight: CGFloat = 32
    @ViewBuilder let label: Label

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12)

                label
            }
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Collapse section" : "Expand section")
    }
}

struct SettingsSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let surface: Color
    var material: Material = .thin
    var materialOpacity: Double = 0.16
    var strokeOpacity: Double = 0.18
    var shadowOpacity: Double = 0
    var shadowRadius: CGFloat = 0
    var shadowY: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(material)
                        .opacity(reduceTransparency ? 0 : materialOpacity)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(surface)
                }
            )
            .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(strokeOpacity))
            )
    }
}

extension View {
    func settingsSurface(
        _ surface: Color,
        material: Material = .thin,
        materialOpacity: Double = 0.16,
        strokeOpacity: Double = 0.18,
        shadowOpacity: Double = 0,
        shadowRadius: CGFloat = 0,
        shadowY: CGFloat = 0
    ) -> some View {
        modifier(
            SettingsSurfaceModifier(
                surface: surface,
                material: material,
                materialOpacity: materialOpacity,
                strokeOpacity: strokeOpacity,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }
}
