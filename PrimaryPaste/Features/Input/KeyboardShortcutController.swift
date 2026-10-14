import Carbon.HIToolbox
import Combine
import Foundation

final class KeyboardShortcutController {
    static let shortcutDisplayName = "Control-Option-Command-V"

    private static let hotKeySignature: OSType = 0x50505354  // PPST
    private static let hotKeyIdentifier: UInt32 = 1

    private let preferences: PreferencesStore
    private let diagnostics: InteractionDiagnostics
    private let action: () -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var cancellables: Set<AnyCancellable> = []

    init(
        preferences: PreferencesStore,
        diagnostics: InteractionDiagnostics,
        action: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.diagnostics = diagnostics
        self.action = action
    }

    func start() {
        installEventHandlerIfNeeded()
        observePreferences()
        refreshRegistration()
    }

    func stop() {
        unregisterHotKey()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        cancellables.removeAll()
    }

    private func observePreferences() {
        guard cancellables.isEmpty else { return }

        preferences.$keyboardShortcutTriggerEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshRegistration()
            }
            .store(in: &cancellables)

        preferences.$isEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshRegistration()
            }
            .store(in: &cancellables)
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let owner = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<KeyboardShortcutController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                controller.handleHotKeyPressed()
                return noErr
            },
            1,
            &eventType,
            owner,
            &eventHandler
        )

        if status != noErr {
            diagnostics.recordPasteDecision("Shortcut trigger unavailable: hotkey handler failed (\(status))")
        }
    }

    private func refreshRegistration() {
        guard preferences.isEnabled, preferences.keyboardShortcutTriggerEnabled else {
            unregisterHotKey()
            return
        }
        registerHotKeyIfNeeded()
    }

    private func registerHotKeyIfNeeded() {
        guard hotKeyRef == nil else { return }

        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.hotKeyIdentifier
        )
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            hotKeyRef = nil
            diagnostics.recordPasteDecision(
                "Shortcut trigger unavailable: \(Self.shortcutDisplayName) could not register (\(status))")
        }
    }

    private func unregisterHotKey() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    private func handleHotKeyPressed() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard preferences.isEnabled, preferences.keyboardShortcutTriggerEnabled else { return }
            action()
        }
    }
}
