import Foundation
import ServiceManagement

struct LaunchAtLoginController {
    private let diagnostics: any DiagnosticRecording

    init(diagnostics: any DiagnosticRecording = UnifiedLogSink()) {
        self.diagnostics = diagnostics
    }

    var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
    }

    var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    @discardableResult
    func setEnabled(_ isEnabled: Bool) -> Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        if isEnabled == isRegistered { return true }

        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            diagnostics.record(
                DiagnosticEvent(
                    capability: .app,
                    severity: .error,
                    audience: .developers,
                    outcome: .failed,
                    code: "launch-at-login-update-failed",
                    metadata: .init(
                        errorCategory: String(describing: type(of: error)),
                        privateSystemDetail: error.localizedDescription
                    )
                )
            )
            return false
        }
    }
}
