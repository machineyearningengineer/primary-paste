import Combine
import Foundation

enum PrimaryPayload {
    case text(String)
    case pasteboard(PasteboardSnapshot)
}

enum PasteTransport {
    case clipboardFreeText(String)
    case pasteboard(PasteboardSnapshot)
}

struct SelectionItem: Identifiable {
    let id = UUID()
    let payload: PrimaryPayload
    let preview: String
    let sourceAppName: String
    let sourceBundleIdentifier: String?
    let capturedAt: Date
    let isClipboardCopy: Bool

    var wordCount: Int {
        preview.split(whereSeparator: \.isWhitespace).count
    }

    var pasteTransport: PasteTransport {
        switch payload {
        case .text(let text):
            return .clipboardFreeText(text)
        case .pasteboard(let snapshot):
            if let text = snapshot.clipboardFreePasteText {
                return .clipboardFreeText(text)
            }
            return .pasteboard(snapshot)
        }
    }
}

final class PrimarySelectionStore: ObservableObject {
    struct StateSnapshot {
        let current: SelectionItem?
        let queue: [SelectionItem]
        let cycleIndex: Int
    }

    @Published private(set) var current: SelectionItem?
    @Published private(set) var queue: [SelectionItem] = []

    private let preferences: PreferencesStore
    @Published private var cycleIndex = 0
    private var cancellables: Set<AnyCancellable> = []

    init(preferences: PreferencesStore) {
        self.preferences = preferences
        preferences.$queueSize.removeDuplicates().sink { [weak self] limit in
            self?.trimQueue(to: limit)
        }.store(in: &cancellables)
    }

    var onRecord: ((SelectionItem) -> Void)?

    func record(
        _ text: String,
        sourceAppName: String,
        sourceBundleIdentifier: String?,
        isClipboardCopy: Bool = false
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if case .text(let currentText) = current?.payload, currentText == text,
            current?.sourceBundleIdentifier == sourceBundleIdentifier,
            current?.isClipboardCopy == isClipboardCopy
        {
            return
        }

        let item = SelectionItem(
            payload: .text(text),
            preview: text.oneLinePreview(),
            sourceAppName: sourceAppName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            capturedAt: Date(),
            isClipboardCopy: isClipboardCopy
        )

        record(item)
    }

    func record(
        _ snapshot: PasteboardSnapshot,
        sourceAppName: String,
        sourceBundleIdentifier: String?,
        isClipboardCopy: Bool = true
    ) {
        guard !snapshot.isEmpty else { return }

        let preview = snapshot.previewText
        guard !preview.isEmpty else { return }
        if case .pasteboard(let currentSnapshot) = current?.payload,
            currentSnapshot.hasSamePayload(as: snapshot),
            current?.sourceBundleIdentifier == sourceBundleIdentifier,
            current?.isClipboardCopy == isClipboardCopy
        {
            return
        }

        let item = SelectionItem(
            payload: .pasteboard(snapshot),
            preview: preview.oneLinePreview(),
            sourceAppName: sourceAppName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            capturedAt: Date(),
            isClipboardCopy: isClipboardCopy
        )

        record(item)
    }

    private func record(_ item: SelectionItem) {
        current = item
        queue.append(item)
        trimQueue(to: preferences.queueSize)
        onRecord?(item)
    }

    private func trimQueue(to limit: Int) {
        let safeLimit = min(
            max(limit, PreferencesStore.queueSizeRange.lowerBound), PreferencesStore.queueSizeRange.upperBound)
        if queue.count > safeLimit {
            let removed = queue.count - safeLimit
            queue.removeFirst(removed)
            cycleIndex = max(0, cycleIndex - removed)
        }
        if cycleIndex >= queue.count { cycleIndex = 0 }
    }

    func peekItem() -> SelectionItem? {
        switch preferences.pasteMode {
        case .latest: return current
        case .queue: return queue.first
        case .stack: return queue.last
        case .cycle: return queue.isEmpty ? nil : queue[min(cycleIndex, queue.count - 1)]
        }
    }

    func didPaste(_ item: SelectionItem, mode: PasteMode? = nil, clearAfterPaste: Bool? = nil) {
        let shouldClear = clearAfterPaste ?? preferences.clearAfterPaste
        switch mode ?? preferences.pasteMode {
        case .latest:
            if shouldClear, current?.id == item.id { clear() }
        case .queue, .stack:
            if shouldClear {
                queue.removeAll { $0.id == item.id }
                if current?.id == item.id { current = queue.last }
                if cycleIndex >= queue.count { cycleIndex = 0 }
            }
        case .cycle:
            if let index = queue.firstIndex(where: { $0.id == item.id }) {
                cycleIndex = (index + 1) % queue.count
            }
        }
    }

    func consumeItem() -> SelectionItem? {
        guard let item = peekItem() else { return nil }
        didPaste(item)
        return item
    }

    func remove(_ item: SelectionItem) {
        queue.removeAll { $0.id == item.id }
        if current?.id == item.id { current = queue.last }
        if cycleIndex >= queue.count { cycleIndex = 0 }
    }

    func clear() {
        current = nil
        queue.removeAll()
        cycleIndex = 0
    }

    func stateSnapshot() -> StateSnapshot {
        StateSnapshot(current: current, queue: queue, cycleIndex: cycleIndex)
    }

    func restore(_ snapshot: StateSnapshot) {
        current = snapshot.current
        queue = snapshot.queue
        cycleIndex = min(max(snapshot.cycleIndex, 0), max(queue.count - 1, 0))
        trimQueue(to: preferences.queueSize)
    }
}
