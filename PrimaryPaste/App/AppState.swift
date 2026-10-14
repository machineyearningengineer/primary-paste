import AppKit
import Combine
import Foundation

final class AppState: ObservableObject {
    let preferences: PreferencesStore
    let primaryStore: PrimarySelectionStore
    let appRules: AppRulesEngine
    let diagnostics: InteractionDiagnostics
    let licensing: LicenseController
    @Published var textCaptureIsRunning = false
    @Published var middleClickIsRunning = false
    @Published var fileCaptureIsRunning = false
    @Published var startupError: String?

    private var cancellables: Set<AnyCancellable> = []

    init(
        preferences: PreferencesStore,
        primaryStore: PrimarySelectionStore,
        appRules: AppRulesEngine,
        diagnostics: InteractionDiagnostics,
        licensing: LicenseController
    ) {
        self.preferences = preferences
        self.primaryStore = primaryStore
        self.appRules = appRules
        self.diagnostics = diagnostics
        self.licensing = licensing

        preferences.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        primaryStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        appRules.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        diagnostics.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        licensing.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }
}
