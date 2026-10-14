import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SettingsCardHeader<Actions: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.12))
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actions
        }
    }
}

struct DiagnosticsSignalGrid: View {
    @ObservedObject var diagnostics: InteractionDiagnostics
    @ObservedObject var permissions: PermissionsCoordinator
    let showsFinderDiagnostics: Bool
    let clipboardProbeIsHealthy: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 170), spacing: 8, alignment: .top)
    ]

    private var selectionValue: String {
        diagnostics.selectionCaptureSourceSummary == "None yet"
            ? "No captures"
            : diagnostics.selectionCaptureSourceSummary
    }

    private var pasteValue: String {
        diagnostics.middleClickCount == 0
            ? "No clicks"
            : "\(diagnostics.middleClickCount) clicks"
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            DiagnosticsSignalTile(
                title: "Selection",
                value: selectionValue,
                detail: diagnostics.lastSelectionDecision,
                systemImage: "selection.pin.in.out",
                tint: diagnostics.selectionCaptureSourceSummary == "None yet" ? Color.secondary : Color.green
            )

            DiagnosticsSignalTile(
                title: "Clipboard",
                value: clipboardProbeIsHealthy ? "Ready" : "Run check",
                detail: diagnostics.lastClipboardDecision,
                systemImage: "clipboard",
                tint: clipboardProbeIsHealthy ? Color.green : Color.accentColor
            )

            DiagnosticsSignalTile(
                title: "Privacy",
                value: diagnostics.privacyProbePassed ? "Self-test passed" : "Not run",
                detail: diagnostics.lastPrivacyProbe,
                systemImage: "lock.shield",
                tint: diagnostics.privacyProbePassed ? Color.green : Color.secondary
            )

            DiagnosticsSignalTile(
                title: "Paste",
                value: pasteValue,
                detail: diagnostics.lastPasteDecision,
                systemImage: "cursorarrow.click",
                tint: diagnostics.middleClickCount == 0 ? Color.secondary : Color.accentColor
            )

            if showsFinderDiagnostics {
                DiagnosticsSignalTile(
                    title: "Finder",
                    value: permissions.isFinderAutomationTrusted ? "Allowed" : "Not allowed",
                    detail: diagnostics.lastFileSelectionDecision,
                    systemImage: "folder",
                    tint: permissions.isFinderAutomationTrusted ? Color.green : Color.orange
                )
            }
        }
    }
}

struct DiagnosticsSignalTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(minHeight: 78, alignment: .topLeading)
    }
}

struct ReadinessSummaryTile: View {
    let title: String
    let detail: String
    let systemImage: String
    let isComplete: Bool

    private var tint: Color {
        isComplete ? Color.green : Color.orange
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: isComplete ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(minHeight: 64)
    }
}

struct ReadinessProofGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
    }
}

struct ManualVerificationFocusStrip: View {
    let openCheckCount: Int
    let evidenceReadyCount: Int
    let evidenceBackedCount: Int
    let missingTargetCount: Int
    let nextUnprovenTitle: String

    var body: some View {
        HStack(spacing: 0) {
            ManualVerificationFocusColumn(
                title: "Open",
                value: openCheckCount.formatted(),
                detail: "checks",
                systemImage: "checklist.unchecked",
                isComplete: openCheckCount == 0
            )

            VerticalDivider()

            ManualVerificationFocusColumn(
                title: "Seen",
                value: "\(evidenceReadyCount)/\(evidenceBackedCount)",
                detail: "ready",
                systemImage: "waveform.path.ecg",
                isComplete: evidenceReadyCount == evidenceBackedCount
            )

            VerticalDivider()

            ManualVerificationFocusColumn(
                title: "Targets",
                value: missingTargetCount.formatted(),
                detail: "left to cover",
                systemImage: "scope",
                isComplete: missingTargetCount == 0
            )

            VerticalDivider()

            ManualVerificationFocusColumn(
                title: "Next",
                value: nextUnprovenTitle,
                detail: "guided below",
                systemImage: openCheckCount == 0 ? "checkmark.seal" : "arrow.forward.circle",
                isComplete: openCheckCount == 0 && missingTargetCount == 0
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.24))
        )
    }
}

struct ManualVerificationFocusColumn: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(isComplete ? Color.green : Color.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isComplete ? Color.green : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ManualVerificationGapStrip: View {
    let openCheckCount: Int
    let evidenceReadyCount: Int
    let evidenceBackedCount: Int
    let evidenceGapCount: Int
    let missingTargetCount: Int
    let nextUnprovenTitle: String

    private var isComplete: Bool {
        openCheckCount == 0 && evidenceGapCount == 0 && missingTargetCount == 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Still To Check")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                ManualVerificationGapColumn(
                    systemImage: "checklist.unchecked",
                    title: "Open Checks",
                    value: openCheckCount.formatted(),
                    isComplete: openCheckCount == 0
                )

                VerticalDivider()

                ManualVerificationGapColumn(
                    systemImage: "waveform.path.ecg",
                    title: "Seen & Ready",
                    value: "\(evidenceReadyCount)/\(evidenceBackedCount)",
                    isComplete: evidenceGapCount == 0
                )

                VerticalDivider()

                ManualVerificationGapColumn(
                    systemImage: "scope",
                    title: "Target Gaps",
                    value: missingTargetCount.formatted(),
                    isComplete: missingTargetCount == 0
                )

                VerticalDivider()

                ManualVerificationGapColumn(
                    systemImage: isComplete ? "checkmark.seal" : "arrow.forward.circle",
                    title: "Next Unproven",
                    value: nextUnprovenTitle,
                    isComplete: isComplete
                )
            }
            .padding(.vertical, 2)
        }
    }
}

struct ManualVerificationGapColumn: View {
    let systemImage: String
    let title: String
    let value: String
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(isComplete ? Color.green : Color.orange)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isComplete ? Color.green : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

struct ManualVerificationProofStrip: View {
    let appProbeCount: Int
    let runtimeEvidenceCount: Int
    let settingsAndHumanCount: Int
    let humanCheckCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Check Types")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                ManualVerificationProofColumn(
                    systemImage: "terminal",
                    title: "Scripted",
                    value: "preflight + smoke",
                    tint: Color.green
                )

                VerticalDivider()

                ManualVerificationProofColumn(
                    systemImage: ManualVerificationProofKind.appProbe.systemImage,
                    title: ManualVerificationProofKind.appProbe.title,
                    value: "\(appProbeCount) checks",
                    tint: ManualVerificationProofKind.appProbe.tint
                )

                VerticalDivider()

                ManualVerificationProofColumn(
                    systemImage: ManualVerificationProofKind.runtimeEvidence.systemImage,
                    title: "Seen",
                    value: "\(runtimeEvidenceCount) checks",
                    tint: ManualVerificationProofKind.runtimeEvidence.tint
                )

                VerticalDivider()

                ManualVerificationProofColumn(
                    systemImage: ManualVerificationProofKind.humanCheck.systemImage,
                    title: "Hands-on",
                    value: "\(humanCheckCount + settingsAndHumanCount) checks",
                    tint: ManualVerificationProofKind.humanCheck.tint
                )
            }
            .padding(.vertical, 2)
        }
    }
}

struct ManualVerificationProofColumn: View {
    let systemImage: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

struct ManualVerificationSignalStrip: View {
    let runStartedText: String
    let sourceAppCount: Int
    let pasteTargetCount: Int
    let passThroughAppCount: Int
    let clipboardProbeReady: Bool
    let nativeDefaultProbeReady: Bool
    let privacyProbeReady: Bool

    private var passedProbeCount: Int {
        [clipboardProbeReady, nativeDefaultProbeReady, privacyProbeReady].filter { $0 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                ManualVerificationSignalColumn(
                    systemImage: "clock",
                    title: "Started",
                    value: runStartedText,
                    isActive: true
                )

                VerticalDivider()

                ManualVerificationSignalColumn(
                    systemImage: "selection.pin.in.out",
                    title: "Source Apps",
                    value: sourceAppCount.formatted(),
                    isActive: sourceAppCount > 0
                )

                VerticalDivider()

                ManualVerificationSignalColumn(
                    systemImage: "text.cursor",
                    title: "Paste Targets",
                    value: pasteTargetCount.formatted(),
                    isActive: pasteTargetCount > 0
                )

                VerticalDivider()

                ManualVerificationSignalColumn(
                    systemImage: "arrowshape.turn.up.right",
                    title: "Pass-Through",
                    value: passThroughAppCount.formatted(),
                    isActive: passThroughAppCount > 0
                )

                VerticalDivider()

                ManualVerificationSignalColumn(
                    systemImage: "checkmark.shield",
                    title: "Checks",
                    value: "\(passedProbeCount)/3",
                    isActive: passedProbeCount == 3
                )
            }
            .padding(.vertical, 2)
        }
    }
}

struct ManualVerificationSignalColumn: View {
    let systemImage: String
    let title: String
    let value: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

struct ManualVerificationCoverageStrip: View {
    let selectionCoverage: ManualVerificationTargetCoverage
    let pasteCoverage: ManualVerificationTargetCoverage
    let passThroughCoverage: ManualVerificationTargetCoverage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target Coverage")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                ManualVerificationCoverageColumn(
                    systemImage: "selection.pin.in.out",
                    title: "Selection",
                    coverage: selectionCoverage
                )

                VerticalDivider()

                ManualVerificationCoverageColumn(
                    systemImage: "text.cursor",
                    title: "Paste",
                    coverage: pasteCoverage
                )

                VerticalDivider()

                ManualVerificationCoverageColumn(
                    systemImage: "arrowshape.turn.up.right",
                    title: "Pass-through",
                    coverage: passThroughCoverage
                )
            }
            .padding(.vertical, 2)
        }
    }
}

struct ManualVerificationCoverageColumn: View {
    let systemImage: String
    let title: String
    let coverage: ManualVerificationTargetCoverage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(
                    coverage.isComplete ? Color.green : (coverage.hasEvidence ? Color.accentColor : Color.secondary)
                )
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(coverage.badgeText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        coverage.isComplete ? Color.green : (coverage.hasEvidence ? Color.primary : Color.secondary))
                Text(coverage.nextTargetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

struct VerticalDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.18))
            .frame(width: 1, height: 34)
            .padding(.horizontal, 12)
    }
}

struct ManualVerificationTarget {
    let title: String
    let tokens: [String]
}

struct ManualVerificationTargetCoverage {
    let covered: [String]
    let missing: [String]

    var isComplete: Bool {
        missing.isEmpty
    }

    var hasEvidence: Bool {
        !covered.isEmpty
    }

    var badgeText: String {
        let total = covered.count + missing.count
        return "\(covered.count)/\(total) targets"
    }

    var detailText: String {
        let coveredText = covered.isEmpty ? "Covered: none yet" : "Covered: \(covered.joined(separator: ", "))"
        guard !missing.isEmpty else { return "\(coveredText). All target classes covered." }
        return "\(coveredText). Missing: \(missing.joined(separator: ", ")). \(nextTargetText)"
    }

    var nextTargetText: String {
        guard let nextTarget = nextMissingTargetTitle else { return "All target classes covered." }
        return "Next: test \(nextTarget)."
    }

    var nextMissingTargetTitle: String? {
        missing.first
    }
}

struct ManualVerificationEvidence {
    let text: String
    let isPositive: Bool
    let detail: String?

    init(text: String, isPositive: Bool, detail: String? = nil) {
        self.text = text
        self.isPositive = isPositive
        self.detail = detail
    }
}

struct ManualVerificationGuide {
    let detail: String
    let actionTitle: String?
    let action: (() -> Void)?

    let secondaryActionTitle: String?
    let secondaryAction: (() -> Void)?

    init(
        detail: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
    }
}

struct ManualVerificationGuideCard: View {
    let label: String
    let item: ManualVerificationItem
    let guide: ManualVerificationGuide
    let evidence: ManualVerificationEvidence?
    let isVerified: Bool
    let markVerified: () -> Void

    private var evidenceReady: Bool {
        evidence?.isPositive == true
    }

    private var actionTitle: String {
        if isVerified {
            return "Verified"
        }
        return evidenceReady ? "Mark Verified" : "Mark Manually"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(evidenceReady ? Color.green : Color.accentColor)
                .frame(width: 3)

            Image(systemName: item.group.systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                }
                ManualVerificationGuideMetaRow(
                    proofKind: item.proofKind,
                    evidence: evidence,
                    isVerified: isVerified,
                    evidenceReady: evidenceReady
                )
                Text(guide.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.proofKind.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = evidence?.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !isVerified {
                    Text("Primary has not seen this happen yet.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !isVerified && !evidenceReady {
                    Text("Use Mark Manually only after you have checked this yourself.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            if let actionTitle = guide.actionTitle, let action = guide.action {
                Button(actionTitle, action: action)
            }

            if let actionTitle = guide.secondaryActionTitle, let action = guide.secondaryAction {
                Button(actionTitle, action: action)
            }

            Button(actionTitle, action: markVerified)
                .disabled(isVerified)
        }
        .padding(12)
        .frame(minHeight: 58)
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

struct ManualVerificationGuideMetaRow: View {
    let proofKind: ManualVerificationProofKind
    let evidence: ManualVerificationEvidence?
    let isVerified: Bool
    let evidenceReady: Bool

    private var evidenceText: String {
        if let evidence {
            return evidence.text
        }
        return isVerified ? "Verified manually" : "Not seen yet"
    }

    private var evidenceTone: Color {
        if isVerified { return Color.green }
        if evidence?.isPositive == true { return Color.green }
        return Color.orange
    }

    private var statusText: String {
        if isVerified { return "Verified" }
        return evidenceReady ? "Ready" : "Needs check"
    }

    private var statusTone: Color {
        if isVerified || evidenceReady { return Color.green }
        return Color.secondary
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                metaItems
            }

            VStack(alignment: .leading, spacing: 3) {
                metaItems
            }
        }
    }

    @ViewBuilder
    private var metaItems: some View {
        InlineGuideMeta(
            systemImage: proofKind.systemImage,
            text: proofKind.title,
            tint: proofKind.tint
        )
        InlineGuideMeta(
            systemImage: evidence?.isPositive == true || isVerified ? "checkmark.circle.fill" : "circle",
            text: evidenceText,
            tint: evidenceTone
        )
        InlineGuideMeta(
            systemImage: isVerified || evidenceReady ? "checkmark.seal.fill" : "clock",
            text: statusText,
            tint: statusTone
        )
    }
}

struct InlineGuideMeta: View {
    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct ManualVerificationGroupSection: View {
    let group: ManualVerificationGroup
    let items: [ManualVerificationItem]
    let completedCount: Int
    let selectedGuideID: String?
    let isComplete: (String) -> Bool
    let setComplete: (String, Bool) -> Void
    let evidence: (ManualVerificationItem) -> ManualVerificationEvidence?
    let selectGuide: (String) -> Void

    private var isGroupComplete: Bool {
        !items.isEmpty && completedCount == items.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: group.systemImage)
                    .foregroundStyle(isGroupComplete ? Color.green : Color.secondary)
                    .frame(width: 18)
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                StatusBadge(
                    isComplete: isGroupComplete,
                    text: "\(completedCount)/\(items.count)"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    ManualVerificationRow(
                        item: item,
                        evidence: evidence(item),
                        isGuided: selectedGuideID == item.id,
                        selectGuide: { selectGuide(item.id) },
                        isComplete: Binding(
                            get: { isComplete(item.id) },
                            set: { setComplete(item.id, $0) }
                        )
                    )
                }
            }
            .padding(.leading, 26)
        }
    }
}

struct ManualVerificationRow: View {
    let item: ManualVerificationItem
    let evidence: ManualVerificationEvidence?
    let isGuided: Bool
    let selectGuide: () -> Void
    @Binding var isComplete: Bool

    private var evidenceReady: Bool {
        evidence?.isPositive == true
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(isOn: $isComplete) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                        ProofBadge(kind: item.proofKind)
                        if let evidence {
                            StatusBadge(isComplete: evidence.isPositive, text: evidence.text)
                        } else if !isComplete {
                            StatusBadge(isComplete: false, text: "Not seen yet")
                        }
                        if isComplete && !evidenceReady {
                            StatusBadge(isComplete: false, text: "Manual")
                        }
                        if isGuided {
                            StatusBadge(isComplete: true, text: "Guided")
                        }
                    }
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.proofKind.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = evidence?.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !isComplete {
                        Text("Primary has not seen this happen yet.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .toggleStyle(.checkbox)

            Spacer(minLength: 8)

            Button("Guide", action: selectGuide)
                .disabled(isGuided)
        }
    }
}

struct ReadinessCheckRow: View {
    let title: String
    let detail: String
    let isComplete: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? Color.green : Color.secondary)
                .frame(width: 18)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 16)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct PassThroughProbeView: View {
    let decision: String

    private var isComplete: Bool {
        PastePassThroughEvidence.confirmsTargetSafety(decision)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isComplete ? "arrow.forward.circle.fill" : "arrow.forward.circle")
                .foregroundStyle(isComplete ? Color.green : Color.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Native Middle-Click")
                    .font(.subheadline.weight(.semibold))
                Text(isComplete ? decision : "Middle-click this panel to check native pass-through")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            StatusBadge(
                isComplete: isComplete,
                text: isComplete ? "Passed" : "Ready"
            )
        }
        .padding(12)
        .frame(minHeight: 70)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isComplete ? Color.green.opacity(0.25) : Color.secondary.opacity(0.18))
        )
    }
}

struct ClipboardLinkProbeView: View {
    let modeTitle: String
    let guardDecision: String
    let modeDecision: String
    let nativeDefaultDecision: String
    let isGuardHealthy: Bool
    let isModeHealthy: Bool
    let isNativeDefaultHealthy: Bool
    let runProbe: () -> Void

    private var needsNativeDefaultProof: Bool {
        modeTitle == ClipboardLinkMode.separate.title
    }

    private var isHealthy: Bool {
        isGuardHealthy && isModeHealthy && (!needsNativeDefaultProof || isNativeDefaultHealthy)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isHealthy ? "checkmark.shield.fill" : "shield")
                .foregroundStyle(isHealthy ? Color.green : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text("Clipboard Link Check")
                    .font(.subheadline.weight(.semibold))
                Text(
                    isHealthy
                        ? modeDecision
                        : "Runs a temporary clipboard write, checks \(modeTitle), and restores the previous clipboard."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                Text(isGuardHealthy ? guardDecision : "Self-capture guard not confirmed yet.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                if needsNativeDefaultProof {
                    Text(isNativeDefaultHealthy ? nativeDefaultDecision : "Native clipboard default not confirmed yet.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            StatusBadge(isComplete: true, text: modeTitle)

            Button("Check") {
                runProbe()
            }
        }
        .padding(12)
        .frame(minHeight: 54)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isHealthy ? Color.green.opacity(0.25) : Color.secondary.opacity(0.18))
        )
    }
}
