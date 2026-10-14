import Foundation

struct ClipboardSuppressionState {
    private var reason: String?
    private var expiresAt = Date.distantPast
    private var changeCountAtStart = 0
    private var remainingObservedChanges = 0

    mutating func suppressProgrammaticChanges(
        reason: String,
        duration: TimeInterval = 3.0,
        changeCountAtStart: Int,
        expectedObservedChanges: Int = 1,
        now: Date = Date()
    ) {
        self.reason = reason
        expiresAt = now.addingTimeInterval(duration)
        self.changeCountAtStart = changeCountAtStart
        remainingObservedChanges = max(expectedObservedChanges, 1)
    }

    mutating func clear() {
        reason = nil
        expiresAt = .distantPast
        changeCountAtStart = 0
        remainingObservedChanges = 0
    }

    mutating func suppressedProgrammaticClipboardReason(
        currentChangeCount: Int,
        now: Date = Date()
    ) -> String? {
        guard let reason else { return nil }
        guard now <= expiresAt else {
            clear()
            return nil
        }
        guard currentChangeCount > changeCountAtStart else { return nil }

        let observedChangeCount = currentChangeCount - changeCountAtStart
        guard observedChangeCount <= remainingObservedChanges else {
            clear()
            return nil
        }

        remainingObservedChanges -= 1
        changeCountAtStart = currentChangeCount
        if remainingObservedChanges <= 0 {
            clear()
        }
        return reason
    }
}
