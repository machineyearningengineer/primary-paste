import AppKit
import Combine
import SwiftUI

struct CaptureToastNotice {
    let sourceAppName: String
    let sourceBundleIdentifier: String?
    let sourceLabel: String
    let preview: String
    let badge: String
}

enum CaptureToastPresentationPhase {
    case hidden
    case visible
    case releasing
    case disappearing
}

final class CaptureToastContentModel: ObservableObject {
    @Published var icon = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) ?? NSImage()
    @Published var sourceName = ""
    @Published var sourceLabel = ""
    @Published var preview = ""
    @Published var isClipboardCopy = false
    @Published var selectionBadge = ""
    @Published var growthBadge = ""
    @Published var isWarning = false
    @Published var isContinuationUpdate = false
    @Published var updateToken = 0
    @Published var presentationPhase: CaptureToastPresentationPhase = .hidden

    func update(
        icon: NSImage,
        sourceName: String,
        sourceLabel: String,
        preview: String,
        isClipboardCopy: Bool,
        selectionBadge: String,
        growthBadge: String,
        isWarning: Bool,
        isContinuationUpdate: Bool
    ) {
        self.icon = icon
        self.sourceName = sourceName
        self.sourceLabel = sourceLabel
        self.preview = preview
        self.isClipboardCopy = isClipboardCopy
        self.selectionBadge = selectionBadge
        self.growthBadge = growthBadge
        self.isWarning = isWarning
        self.isContinuationUpdate = isContinuationUpdate
        updateToken += 1
    }

    func setPresentationPhase(_ phase: CaptureToastPresentationPhase) {
        guard presentationPhase != phase else { return }
        presentationPhase = phase
    }
}

final class CaptureToastPresenter {
    private let preferences: PreferencesStore
    private let contentModel = CaptureToastContentModel()
    private var panel: NSPanel?
    private var hostingController: NSHostingController<CaptureToastView>?
    private var dismissWorkItem: DispatchWorkItem?
    private var lastItem: SelectionItem?
    private var lastShownAt = Date.distantPast
    private var lastHiddenAt = Date.distantPast
    private var presentationGeneration = 0
    private var scheduledPresentationID = UUID()

    init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    func show(item: SelectionItem) {
        let requestID = UUID()
        scheduledPresentationID = requestID
        DispatchQueue.main.async { [weak self] in
            guard let self, self.scheduledPresentationID == requestID else { return }
            let icon = self.icon(for: item.sourceBundleIdentifier)
            let isContinuation = self.isContinuation(item)
            let metrics = self.toastMetrics(for: item, isContinuation: isContinuation)

            self.present(
                icon: icon,
                sourceName: item.sourceAppName,
                sourceLabel: item.isClipboardCopy
                    ? "Copied from \(item.sourceAppName)" : "Selected from \(item.sourceAppName)",
                preview: item.preview,
                isClipboardCopy: item.isClipboardCopy,
                selectionBadge: metrics.selectionBadge,
                growthBadge: metrics.growthBadge,
                isWarning: false,
                isContinuationUpdate: isContinuation,
                representedItem: item
            )
        }
    }

    func show(notice: CaptureToastNotice) {
        let requestID = UUID()
        scheduledPresentationID = requestID
        DispatchQueue.main.async { [weak self] in
            guard let self, self.scheduledPresentationID == requestID else { return }
            self.present(
                icon: self.icon(for: notice.sourceBundleIdentifier),
                sourceName: notice.sourceAppName,
                sourceLabel: notice.sourceLabel,
                preview: notice.preview,
                isClipboardCopy: false,
                selectionBadge: notice.badge,
                growthBadge: "",
                isWarning: true,
                isContinuationUpdate: false,
                representedItem: nil
            )
        }
    }

    func dismiss() {
        scheduledPresentationID = UUID()
        presentationGeneration += 1
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)
        contentModel.setPresentationPhase(.hidden)
        contentModel.preview = ""
        contentModel.sourceName = ""
        contentModel.sourceLabel = ""
        lastItem = nil
        lastShownAt = .distantPast
    }

    private func present(
        icon: NSImage,
        sourceName: String,
        sourceLabel: String,
        preview: String,
        isClipboardCopy: Bool,
        selectionBadge: String,
        growthBadge: String,
        isWarning: Bool,
        isContinuationUpdate: Bool,
        representedItem: SelectionItem?
    ) {
        dismissWorkItem?.cancel()
        presentationGeneration += 1
        let generation = presentationGeneration

        contentModel.update(
            icon: icon,
            sourceName: sourceName,
            sourceLabel: sourceLabel,
            preview: preview,
            isClipboardCopy: isClipboardCopy,
            selectionBadge: selectionBadge,
            growthBadge: growthBadge,
            isWarning: isWarning,
            isContinuationUpdate: isContinuationUpdate
        )

        let panel = self.panel ?? makePanel()
        if hostingController == nil {
            let view = CaptureToastView(
                model: contentModel,
                preferences: preferences
            )
            let hostingController = NSHostingController(rootView: view)
            self.hostingController = hostingController
            panel.contentViewController = hostingController
        }
        self.panel = panel

        let targetFrame = targetFrame()
        let wasVisible = panel.isVisible && panel.alphaValue > 0.05
        if let representedItem {
            lastItem = representedItem
            lastShownAt = Date()
        }

        panel.setFrame(targetFrame, display: true)
        panel.alphaValue = 1

        if wasVisible {
            contentModel.setPresentationPhase(.visible)
        } else {
            contentModel.setPresentationPhase(.hidden)
            panel.orderFrontRegardless()

            DispatchQueue.main.async { [weak self, weak panel] in
                guard
                    let self,
                    let panel,
                    panel.isVisible,
                    self.presentationGeneration == generation
                else {
                    return
                }

                self.contentModel.setPresentationPhase(.visible)
            }
        }

        let workItem = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.animateOut(panel, generation: generation)
        }

        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + preferences.captureToastDisplaySeconds, execute: workItem)
    }

    private func makePanel() -> NSPanel {
        let metrics = CaptureToastMetrics(
            size: preferences.captureToastSize,
            showsSourceLabel: preferences.showToastSourceLabel
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: metrics.width, height: metrics.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        return panel
    }

    private func targetFrame() -> NSRect {
        let metrics = CaptureToastMetrics(
            size: preferences.captureToastSize,
            showsSourceLabel: preferences.showToastSourceLabel
        )
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: metrics.width, height: metrics.height)
        }
        let frame = screen.frame
        let width = min(metrics.width, max(260, frame.width - 40))
        let height = metrics.height
        let x = frame.midX - width / 2
        let y = frame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func animateOut(_ panel: NSPanel, generation: Int) {
        guard presentationGeneration == generation else { return }

        contentModel.setPresentationPhase(.releasing)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self, weak panel] in
            guard
                let self,
                let panel,
                panel.isVisible,
                self.presentationGeneration == generation
            else {
                return
            }

            self.contentModel.setPresentationPhase(.disappearing)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.29) { [weak self, weak panel] in
            guard
                let self,
                let panel,
                self.presentationGeneration == generation
            else {
                return
            }

            panel.orderOut(nil)
            self.contentModel.setPresentationPhase(.hidden)
            self.lastHiddenAt = Date()
            if self.panel === panel {
                self.panel = panel
            }
        }
    }

    private func isContinuation(_ item: SelectionItem) -> Bool {
        guard
            !item.isClipboardCopy,
            let lastItem,
            !lastItem.isClipboardCopy,
            item.sourceBundleIdentifier == lastItem.sourceBundleIdentifier
        else {
            return false
        }

        if Date().timeIntervalSince(lastShownAt) < 1.4 {
            return true
        }

        if let currentText = textPayload(for: item),
            let previousText = textPayload(for: lastItem)
        {
            return currentText.hasPrefix(previousText) || previousText.hasPrefix(currentText)
        }

        if let currentFileSignature = fileSelectionSignature(for: item),
            let previousFileSignature = fileSelectionSignature(for: lastItem)
        {
            return currentFileSignature.hasPrefix(previousFileSignature)
                || previousFileSignature.hasPrefix(currentFileSignature)
        }

        return false
    }

    private func toastMetrics(for item: SelectionItem, isContinuation: Bool) -> (
        selectionBadge: String, growthBadge: String
    ) {
        if case .pasteboard(let snapshot) = item.payload, !snapshot.fileURLs.isEmpty {
            return (snapshot.fileSelectionBadgeText, "")
        }

        guard
            !item.isClipboardCopy,
            let text = textPayload(for: item)
        else {
            return ("", "")
        }

        let metrics = ToastTextMetrics(text: text)

        let selectionBadge = selectionBadge(for: metrics)

        let growthBadge = growthBadge(
            for: item,
            currentMetrics: metrics,
            isContinuation: isContinuation
        )
        return (selectionBadge, growthBadge)
    }

    private func selectionBadge(for metrics: ToastTextMetrics) -> String {
        if metrics.lineCount > 1 {
            return countBadge(metrics.lineCount, singular: "line", plural: "lines")
        }

        if metrics.wordCount >= 8, metrics.collapsedCharacterCount >= 42 {
            return countBadge(metrics.wordCount, singular: "word", plural: "words")
        }

        if metrics.wordCount <= 2, metrics.collapsedCharacterCount >= 38 {
            return countBadge(metrics.collapsedCharacterCount, singular: "char", plural: "chars")
        }

        if metrics.collapsedCharacterCount >= 58 {
            if metrics.wordCount > 1 {
                return countBadge(metrics.wordCount, singular: "word", plural: "words")
            }
            return countBadge(metrics.collapsedCharacterCount, singular: "char", plural: "chars")
        }

        return ""
    }

    private func growthBadge(
        for item: SelectionItem,
        currentMetrics: ToastTextMetrics,
        isContinuation: Bool
    ) -> String {
        guard
            isContinuation,
            let lastItem,
            let previousText = textPayload(for: lastItem),
            currentMetrics.text.count > previousText.count,
            currentMetrics.text.hasPrefix(previousText)
        else {
            return ""
        }

        let previousMetrics = ToastTextMetrics(text: previousText)

        let lineDelta = currentMetrics.lineCount - previousMetrics.lineCount
        if lineDelta > 0, currentMetrics.lineCount > 1 {
            return plusBadge(lineDelta, singular: "line", plural: "lines")
        }

        let wordDelta = currentMetrics.wordCount - previousMetrics.wordCount
        if wordDelta >= 2 || (wordDelta == 1 && currentMetrics.isPreviewUnderPressure) {
            return plusBadge(wordDelta, singular: "word", plural: "words")
        }

        let characterDelta = currentMetrics.collapsedCharacterCount - previousMetrics.collapsedCharacterCount
        if characterDelta > 0 && wordDelta == 0 && currentMetrics.isPreviewUnderPressure {
            return plusBadge(characterDelta, singular: "char", plural: "chars")
        }

        if characterDelta >= 14 {
            return plusBadge(characterDelta, singular: "char", plural: "chars")
        }

        return ""
    }

    private func countBadge(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    private func plusBadge(_ count: Int, singular: String, plural: String) -> String {
        "+\(count) \(count == 1 ? singular : plural)"
    }

    private func textPayload(for item: SelectionItem) -> String? {
        switch item.payload {
        case .text(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .pasteboard(let snapshot):
            guard snapshot.fileURLs.isEmpty else { return nil }
            for pasteboardItem in snapshot.items {
                if let text = pasteboardItem.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !text.isEmpty
                {
                    return text
                }
            }
            return nil
        }
    }

    private func fileSelectionSignature(for item: SelectionItem) -> String? {
        guard case .pasteboard(let snapshot) = item.payload, !snapshot.fileURLs.isEmpty else { return nil }
        return snapshot.fileURLs
            .map { $0.standardizedFileURL.path }
            .joined(separator: "\n")
    }

    private func icon(for bundleIdentifier: String?) -> NSImage {
        guard
            let bundleIdentifier,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            return NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) ?? NSImage()
        }

        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct CaptureToastMetrics {
    let size: CaptureToastSize
    let showsSourceLabel: Bool

    var width: CGFloat {
        switch size {
        case .tiny: 390
        case .compact: 430
        case .medium: 468
        case .large: 520
        }
    }

    var height: CGFloat {
        if showsSourceLabel {
            switch size {
            case .tiny: 58
            case .compact: 64
            case .medium: 70
            case .large: 82
            }
        } else {
            switch size {
            case .tiny: 48
            case .compact: 54
            case .medium: 60
            case .large: 70
            }
        }
    }

    var horizontalPadding: CGFloat {
        switch size {
        case .tiny: 16
        case .compact: 18
        case .medium: 20
        case .large: 24
        }
    }

    var contentSpacing: CGFloat {
        switch size {
        case .tiny: 9
        case .compact: 10
        case .medium: 12
        case .large: 14
        }
    }

    var iconSize: CGFloat {
        switch size {
        case .tiny: 24
        case .compact: 26
        case .medium: 28
        case .large: 32
        }
    }

    var iconCornerRadius: CGFloat {
        switch size {
        case .tiny: 6.5
        case .compact: 7
        case .medium: 7.5
        case .large: 8
        }
    }

    var previewFontSize: CGFloat {
        switch size {
        case .tiny: 14
        case .compact: 15
        case .medium: 16
        case .large: 18
        }
    }

    var sourceLabelFontSize: CGFloat {
        switch size {
        case .tiny: 10
        case .compact: 10.5
        case .medium: 11
        case .large: 12
        }
    }

    var badgeFontSize: CGFloat {
        switch size {
        case .tiny: 9.5
        case .compact: 10
        case .medium: 10.5
        case .large: 11
        }
    }

    var badgeHorizontalPadding: CGFloat {
        switch size {
        case .tiny: 5.5
        case .compact: 6
        case .medium: 6.5
        case .large: 7
        }
    }

    var badgeVerticalPadding: CGFloat {
        switch size {
        case .tiny: 2.5
        case .compact: 3
        case .medium: 3.5
        case .large: 4
        }
    }

    var warningBadgeSize: CGFloat {
        switch size {
        case .tiny: 9
        case .compact: 10
        case .medium: 11
        case .large: 12
        }
    }

    var warningIconFontSize: CGFloat {
        switch size {
        case .tiny: 5.5
        case .compact: 6
        case .medium: 6.5
        case .large: 7
        }
    }

    var progressWidth: CGFloat {
        switch size {
        case .tiny: 100
        case .compact: 112
        case .medium: 128
        case .large: 148
        }
    }

    var progressLeading: CGFloat {
        horizontalPadding + iconSize + contentSpacing
    }

    var progressBottom: CGFloat {
        switch size {
        case .tiny: 7
        case .compact: 8
        case .medium: 9
        case .large: 10
        }
    }

    var cornerRadius: CGFloat {
        switch size {
        case .tiny: 14
        case .compact: 16
        case .medium: 18
        case .large: 20
        }
    }
}

private struct ToastTextMetrics {
    let text: String
    let collapsedCharacterCount: Int
    let wordCount: Int
    let lineCount: Int

    init(text: String) {
        self.text = text
        let collapsed = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        collapsedCharacterCount = collapsed.count
        wordCount = text.split(whereSeparator: \.isWhitespace).count
        lineCount =
            text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    var isPreviewUnderPressure: Bool {
        lineCount > 1
            || collapsedCharacterCount >= 48
            || (wordCount >= 8 && collapsedCharacterCount >= 42)
            || (wordCount <= 2 && collapsedCharacterCount >= 38)
    }
}

private struct CaptureToastView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: CaptureToastContentModel
    @ObservedObject var preferences: PreferencesStore
    @State private var selectionPulse: CGFloat = 0

    private var metrics: CaptureToastMetrics {
        CaptureToastMetrics(
            size: preferences.captureToastSize,
            showsSourceLabel: preferences.showToastSourceLabel
        )
    }

    private var capHeight: CGFloat {
        min(14, max(9, metrics.height * 0.24))
    }

    private var capCornerRadius: CGFloat {
        min(metrics.cornerRadius, capHeight * 0.55)
    }

    private var capScaleX: CGFloat {
        switch model.presentationPhase {
        case .hidden:
            return 0.92
        case .visible:
            return 1
        case .releasing:
            return 1.012
        case .disappearing:
            return 0.88
        }
    }

    private var capScaleY: CGFloat {
        switch model.presentationPhase {
        case .hidden:
            return 0.78
        case .visible:
            return 1
        case .releasing:
            return 1.08
        case .disappearing:
            return 0.58
        }
    }

    private var capOpacity: Double {
        switch model.presentationPhase {
        case .hidden:
            return 0
        case .visible:
            return 1
        case .releasing:
            return 0.92
        case .disappearing:
            return 0
        }
    }

    private var shellScaleX: CGFloat {
        switch model.presentationPhase {
        case .hidden:
            return 0.88
        case .visible:
            return 1
        case .releasing:
            return 1.006
        case .disappearing:
            return 0.92
        }
    }

    private var shellScaleY: CGFloat {
        switch model.presentationPhase {
        case .hidden:
            return 0.24
        case .visible:
            return 1
        case .releasing:
            return 1.018
        case .disappearing:
            return 0.12
        }
    }

    private var shellOpacity: Double {
        switch model.presentationPhase {
        case .hidden:
            return 0
        case .visible:
            return 1
        case .releasing:
            return 0.96
        case .disappearing:
            return 0.06
        }
    }

    private var contentOpacity: Double {
        switch model.presentationPhase {
        case .hidden:
            return 0
        case .visible:
            return 1
        case .releasing:
            return 0.74
        case .disappearing:
            return 0
        }
    }

    private var contentOffsetY: CGFloat {
        switch model.presentationPhase {
        case .hidden:
            return -3
        case .visible:
            return 0
        case .releasing:
            return -1
        case .disappearing:
            return -3
        }
    }

    private var contentBlur: CGFloat {
        switch model.presentationPhase {
        case .hidden:
            return 2.5
        case .visible:
            return 0
        case .releasing:
            return 0.55
        case .disappearing:
            return 1.9
        }
    }

    private var capAnimation: Animation {
        switch model.presentationPhase {
        case .hidden:
            return .easeOut(duration: 0.04)
        case .visible:
            return .timingCurve(0.16, 0.9, 0.24, 1.0, duration: 0.11)
        case .releasing:
            return .timingCurve(0.18, 0.82, 0.26, 1.0, duration: 0.06)
        case .disappearing:
            return .easeOut(duration: 0.13)
        }
    }

    private var shellAnimation: Animation {
        switch model.presentationPhase {
        case .hidden:
            return .easeOut(duration: 0.06)
        case .visible:
            return .timingCurve(0.16, 0.9, 0.24, 1.0, duration: 0.20).delay(0.01)
        case .releasing:
            return .timingCurve(0.18, 0.82, 0.26, 1.0, duration: 0.06)
        case .disappearing:
            return .timingCurve(0.34, 0.0, 0.58, 1.0, duration: 0.21)
        }
    }

    private var contentAnimation: Animation {
        switch model.presentationPhase {
        case .hidden:
            return .easeOut(duration: 0.05)
        case .visible:
            return .easeOut(duration: 0.13).delay(0.065)
        case .releasing:
            return .easeOut(duration: 0.055)
        case .disappearing:
            return .easeOut(duration: 0.09)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: metrics.cornerRadius,
                bottomTrailingRadius: metrics.cornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(x: shellScaleX, y: shellScaleY, anchor: .top)
            .opacity(shellOpacity)
            .animation(reduceMotion ? nil : shellAnimation, value: model.presentationPhase)

            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: capCornerRadius,
                bottomTrailingRadius: capCornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color.black)
            .frame(height: capHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .scaleEffect(x: capScaleX, y: capScaleY, anchor: .top)
            .opacity(capOpacity)
            .animation(reduceMotion ? nil : capAnimation, value: model.presentationPhase)

            HStack(spacing: metrics.contentSpacing) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: model.icon)
                        .resizable()
                        .frame(width: metrics.iconSize, height: metrics.iconSize)
                        .clipShape(RoundedRectangle(cornerRadius: metrics.iconCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: metrics.iconCornerRadius + 1, style: .continuous)
                                .stroke(
                                    model.isWarning
                                        ? Color.orange.opacity(0.58)
                                        : Color.white.opacity(model.isContinuationUpdate ? 0.22 : 0.0),
                                    lineWidth: 1
                                )
                        )

                    if model.isWarning {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: metrics.warningBadgeSize, height: metrics.warningBadgeSize)
                            .overlay {
                                Image(systemName: "exclamationmark")
                                    .font(.system(size: metrics.warningIconFontSize, weight: .heavy))
                                    .foregroundStyle(Color.black.opacity(0.86))
                            }
                            .offset(x: 2, y: 2)
                    }
                }
                .frame(width: metrics.iconSize, height: metrics.iconSize)

                VStack(alignment: .leading, spacing: 2) {
                    if preferences.showToastSourceLabel {
                        Text(model.sourceLabel)
                            .font(.system(size: metrics.sourceLabelFontSize, weight: .semibold))
                            .foregroundStyle(model.isWarning ? Color.orange.opacity(0.82) : Color.white.opacity(0.58))
                            .lineLimit(1)
                            .transition(.opacity)
                    }

                    HStack(spacing: 8) {
                        Text(model.preview)
                            .font(.system(size: metrics.previewFontSize, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.86)
                            .allowsTightening(true)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: model.preview)

                        if !model.growthBadge.isEmpty {
                            ToastMetricBadge(text: model.growthBadge, style: .growth, metrics: metrics)
                                .transition(.scale(scale: 0.92).combined(with: .opacity))
                        } else if !model.selectionBadge.isEmpty {
                            ToastMetricBadge(
                                text: model.selectionBadge, style: model.isWarning ? .warning : .neutral,
                                metrics: metrics)
                        }
                    }
                    .lineLimit(1)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.82), value: model.growthBadge)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(contentOpacity)
            .offset(y: contentOffsetY)
            .blur(radius: contentBlur)
            .animation(reduceMotion ? nil : contentAnimation, value: model.presentationPhase)

            if model.isContinuationUpdate {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.0),
                                .white.opacity(0.30),
                                .white.opacity(0.08),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: metrics.progressWidth, height: 2)
                    .scaleEffect(x: selectionPulse, anchor: .leading)
                    .opacity((selectionPulse < 1 ? 0.8 : 0.34) * contentOpacity)
                    .padding(.leading, metrics.progressLeading)
                    .padding(.bottom, metrics.progressBottom)
                    .offset(y: contentOffsetY)
                    .blur(radius: contentBlur)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: selectionPulse
                    )
                    .animation(reduceMotion ? nil : contentAnimation, value: model.presentationPhase)
            }
        }
        .onChange(of: model.updateToken) { _, _ in
            guard model.isContinuationUpdate else {
                selectionPulse = 0
                return
            }
            selectionPulse = 0.28
            DispatchQueue.main.async {
                selectionPulse = 1
            }
        }
    }
}

private struct ToastMetricBadge: View {
    enum Style {
        case neutral
        case growth
        case warning
    }

    let text: String
    let style: Style
    let metrics: CaptureToastMetrics

    private var foregroundColor: Color {
        switch style {
        case .growth:
            return .white.opacity(0.88)
        case .warning:
            return .orange.opacity(0.9)
        case .neutral:
            return .white.opacity(0.68)
        }
    }

    private var fillColor: Color {
        switch style {
        case .growth:
            return .white.opacity(0.15)
        case .warning:
            return .orange.opacity(0.14)
        case .neutral:
            return .white.opacity(0.09)
        }
    }

    private var strokeColor: Color {
        switch style {
        case .growth:
            return .white.opacity(0.16)
        case .warning:
            return .orange.opacity(0.18)
        case .neutral:
            return .white.opacity(0.08)
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: metrics.badgeFontSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, metrics.badgeHorizontalPadding)
            .padding(.vertical, metrics.badgeVerticalPadding)
            .background(
                Capsule(style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .fixedSize()
    }
}
